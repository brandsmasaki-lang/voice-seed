import AppKit
import AVFoundation
import Speech
import SwiftUI
import ApplicationServices
import Carbon
import CoreAudio
import IOKit.hid
import UniformTypeIdentifiers

enum RecordingPhase: String {
    case idle, preparing, recording, transcribing, refining
    var title: String {
        switch self {
        case .idle: return "話すだけで、ことばになる。"
        case .preparing: return "マイクを準備しています"
        case .recording: return "聞き取り中"
        case .transcribing: return "ことばに変えています"
        case .refining: return "文章を整えています"
        }
    }
}

@MainActor final class AppModel: NSObject, ObservableObject {
    let publicInfo = PublicInfoStore()
    let updater = AppUpdateController()
    @Published var phase: RecordingPhase = .idle
    @Published var output = ""
    @Published var original = ""
    @Published var notice = ""
    @Published var backgroundNotice = ""
    @Published var confirmingHistoryDeletion = false
    @Published var confirmingUsageReset = false
    @Published private(set) var activity: LocalActivitySnapshot
    @Published var modelStatus = "日本語モデルを確認中…"
    @Published var level: Double = 0
    @Published var seconds = 0
    @Published var selectedTab = "入力"
    @Published var installing = false
    @Published var modelReady = false
    @Published var llmStatus = SpeechService.refinementStatus
    @Published var hotkeyStatus = ""
    @Published var fnEnabled = UserDefaults.standard.object(forKey: "fnEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(fnEnabled, forKey: "fnEnabled"); refreshInputPermissions() }
    }
    @Published var fnReady = false
    @Published var pasteReady = false
    /// True when a permission granted to an earlier build no longer applies to this one.
    /// System Settings still shows the switch as on in that state, which users cannot diagnose.
    @Published var permissionsNeedRedo = false
    private static let grantedBuildKey = "permissionGrantedBuild"
    private static let currentBuild: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let path = Bundle.main.executablePath ?? ""
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(version)-\(attributes?[.size] as? Int ?? 0)-\(Int(modified))"
    }()
    @Published var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var fnLastEvent = "Fnキーを押して離すと、ここで検出を確認できます。"
    @Published var recordingFromFn = false
    @Published var pendingDictionaryImport: DictionaryImportPreview?
    @Published var readingDictionary = false
    @Published var livePreview = ""
    @Published private(set) var playbackMuteFailed = false
    @Published var lastFinalizeSeconds: Double?
    var fnMonitor: FnKeyMonitor?
    private var holdRecording = HoldRecordingState()
    @Published var dictionary: [DictionaryEntry] = [] {
        didSet { saveDictionary(); warmTask?.cancel(); warmTask = nil; prewarm() }
    }
    @Published var refineText: Bool = UserDefaults.standard.bool(forKey: "refineText") {
        didSet { UserDefaults.standard.set(refineText, forKey: "refineText") }
    }
    @Published var removeFillers = UserDefaults.standard.object(forKey: "removeFillers") as? Bool ?? true {
        didSet { UserDefaults.standard.set(removeFillers, forKey: "removeFillers") }
    }
    @Published var autoPaste: Bool = UserDefaults.standard.object(forKey: "autoPaste") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoPaste, forKey: "autoPaste") }
    }
    @Published var shortcut: Int = UserDefaults.standard.integer(forKey: "shortcut") {
        didSet {
            UserDefaults.standard.set(shortcut, forKey: "shortcut")
            hotkeyStatus = hotkey?.register(choice: shortcut) == true ? "" : (shortcut == 3 ? "Control＋Commandには\(InputAccess.listenPermissionName)の許可が必要です。" : "ショートカットを登録できません。別の組み合わせを選んでください。")
        }
    }
    var hotkey: GlobalHotkey?
    var hud: RecordingHUD?
    private var capture: MicrophoneCapture?
    private var outputMute: RecordingOutputMute?
    private var analysisTask: Task<StreamingSpeechSession, Error>?
    private var liveSession: StreamingSpeechSession?
    private var warmTask: Task<StreamingSpeechSession, Error>?
    private var activeEntries: [DictionaryEntry] = []
    private var timer: Timer?
    private var target: NSRunningApplication?
    private var pasteThisRecording = false
    private var displayOnlyReason = ""
    private var work: Task<Void, Never>?
    private var startedAt = Date()
    private var sessionID = UUID()
    private let speechModel: SpeechModelAccess
    private let activityStore: LocalActivityStore
    private let windowPresenter: (() -> Void)?
    private var resultPresentation = RecordingPresentation.mainWindow
    private(set) var lastResultPresentation: RecordingPresentation?
    private var inputRequestedAt = Date()

    var busy: Bool { phase != .idle || updater.sessionInProgress }
    var displayedOutput: String { busy && !livePreview.isEmpty ? livePreview : output }
    var duration: String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    var shortcutLabel: String { ["⌃ ⌥ Space", "⌘ ⇧ Space", "⌃ ⇧ Space", "⌃ ⌘"][min(max(shortcut, 0), 3)] }
    var needsInputSetup: Bool {
        !modelReady || microphoneStatus != .authorized || (fnEnabled && !fnReady) || (autoPaste && !pasteReady)
    }
    var canAutomaticallyPaste: Bool { autoPaste && pasteReady }

    #if APP_STORE
    private var waitingForPasteSettings = false
    private var visitedPasteSettings = false

    // A process which requested PostEvent can keep its old permission until
    // relaunched. On the first setup visit, refresh the app once on return.
    private func finishFirstPasteSetup(granted: Bool) {
        guard waitingForPasteSettings else { return }
        if granted {
            waitingForPasteSettings = false
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication else { return }
        if front.bundleIdentifier == "com.apple.systempreferences" {
            visitedPasteSettings = true
            return
        }
        guard visitedPasteSettings, front.activationPolicy == .regular,
              !busy, !installing, !readingDictionary, pendingDictionaryImport == nil,
              output.isEmpty, original.isEmpty, microphoneStatus != .notDetermined else { return }
        waitingForPasteSettings = false
        relaunch(activate: front.processIdentifier == ProcessInfo.processInfo.processIdentifier)
    }
    #endif

    func refreshInputPermissions() {
        if shortcut == 3, let hotkey {
            hotkeyStatus = hotkey.refreshModifierShortcut(choice: shortcut) ? "" : "Control＋Commandには\(InputAccess.listenPermissionName)の許可が必要です。"
        }
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        if microphoneStatus != microphone { microphoneStatus = microphone }
        let canPaste = InputAccess.canPaste
        if pasteReady != canPaste { pasteReady = canPaste }
        let defaults = UserDefaults.standard
        if canPaste && defaults.string(forKey: Self.grantedBuildKey) != Self.currentBuild {
            defaults.set(Self.currentBuild, forKey: Self.grantedBuildKey)
        }
        let redo = RecordingPresentation.permissionNeedsRedo(granted: canPaste,
            grantedBuild: defaults.string(forKey: Self.grantedBuildKey), currentBuild: Self.currentBuild)
        if permissionsNeedRedo != redo { permissionsNeedRedo = redo }
        let canDetectFn: Bool
        if fnEnabled { canDetectFn = fnMonitor?.start() ?? false }
        else { fnMonitor?.stop(); canDetectFn = false }
        if fnReady != canDetectFn { fnReady = canDetectFn }
        #if APP_STORE
        finishFirstPasteSetup(granted: canPaste)
        #endif
    }

    func requestFnPermission() {
        // CGRequestListenEventAccess alone can leave the app missing from the Input Monitoring list;
        // the IOHID request registers it there reliably.
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        _ = CGRequestListenEventAccess()
        openInputPrivacySettings("Privacy_ListenEvent")
        refreshInputPermissions()
    }

    private func openInputPrivacySettings(_ pane: String) {
        let modern = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)")!
        if !NSWorkspace.shared.open(modern) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        }
    }

    /// Removes this app's stale Accessibility and Input Monitoring records, then asks again.
    /// Without this the user must know to delete the entry with "−" and add it back by hand.
    func redoPermissions() {
        #if APP_STORE
        if autoPaste { requestAccessibility() } else { requestFnPermission() }
        #else
        let bundleID = Bundle.main.bundleIdentifier ?? "jp.ainotane.voice-seed"
        for service in ["Accessibility", "ListenEvent"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, bundleID]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            do { try process.run(); process.waitUntilExit() } catch { continue }
        }
        fnMonitor?.stop()
        UserDefaults.standard.removeObject(forKey: Self.grantedBuildKey)
        permissionsNeedRedo = false
        requestAccessibility()
        #endif
    }

    func relaunch(activate: Bool = true) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = activate
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { newApp, _ in
            guard let newApp, newApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    func fnPressed() {
        fnLastEvent = "Fn を押しています。"
        let ownSettingsFrontmost = ["設定", "アプリについて"].contains(selectedTab)
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        switch FnStartPolicy.action(enabled: fnEnabled, busy: busy, installing: installing,
                                    ownSettingsFrontmost: ownSettingsFrontmost, modelReady: modelReady,
                                    pasteAllowed: pasteReady, autoPasteEnabled: autoPaste) {
        case .ignore: return
        case .prepareSpeechModel:
            resultPresentation = .nonactivatingNotice
            notice = "まだ音声入力を開始できません。入力画面の「日本語モデルを準備」を押してください。"
            selectedTab = "入力"; presentRecordingResult(); return
        case .record:
            break
        }
        guard holdRecording.begin(canStart: true) else { return }
        recordingFromFn = true
        toggle(fromShortcut: true)
    }

    func fnReleased() {
        fnLastEvent = "Fn を離しました。検出できています。"
        switch holdRecording.release(recordingStarted: phase == .recording) {
        case .stop: stop()
        case .cancelPreparation: cancel()
        case nil: break
        }
    }

    func fnInterrupted() {
        guard holdRecording.active else { return }
        cancel()
        fnLastEvent = "Fnキーの検知が中断されたため、音声入力をキャンセルしました。"
    }

    func fnUsedWithAnotherKey() {
        if holdRecording.active { cancel(silently: true) }
        notice = ""; backgroundNotice = ""; hud?.hide()
        fnLastEvent = "Fnとの組み合わせ操作のため、音声入力は行いません。"
    }

    override convenience init() {
        self.init(speechModel: .live)
    }

    init(speechModel: SpeechModelAccess, activityStore: LocalActivityStore = LocalActivityStore(), windowPresenter: (() -> Void)? = nil) {
        self.speechModel = speechModel
        self.activityStore = activityStore
        self.activity = activityStore.snapshot
        self.windowPresenter = windowPresenter
        super.init()
        if let data = UserDefaults.standard.data(forKey: "dictionary"),
           let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            dictionary = entries
        }
    }

    func refresh() async {
        let readiness = await speechModel.read()
        modelStatus = readiness.status
        modelReady = readiness.ready
        llmStatus = SpeechService.refinementStatus
        prewarm()
    }

    private func prewarm() {
        guard modelReady, !busy, warmTask == nil else { return }
        let vocabulary = TextPipeline.recognitionVocabulary(dictionary)
        warmTask = Task { try await StreamingSpeechSession.prepare(vocabulary: vocabulary) }
    }

    func installModel() {
        guard !installing, !busy else { return }
        installing = true
        notice = "日本語モデルをAppleからダウンロードします。音声は送信しません。"
        work = Task {
            do { try await speechModel.install(); notice = "日本語モデルの準備ができました。入力画面で試せます。" }
            catch { notice = "モデルを準備できませんでした: \(error.localizedDescription)" }
            installing = false
            await refresh()
        }
    }

    func toggle(fromShortcut: Bool = false) {
        if phase == .recording { stop(); return }
        guard !busy, !installing else { return }
        resultPresentation = .forRecording(startedFromGlobalKey: fromShortcut)
        guard modelReady else { selectedTab = "入力"; notice = "入力画面の「日本語モデルを準備」を押してください。"; presentRecordingResult(); return }
        target = fromShortcut ? NSWorkspace.shared.frontmostApplication : nil
        let externalInput = fromShortcut && target?.processIdentifier != ProcessInfo.processInfo.processIdentifier
        pasteThisRecording = externalInput && canAutomaticallyPaste
        displayOnlyReason = externalInput && autoPaste && !pasteReady
            ? "文字起こしができました。自動貼り付けの許可がないため、ここに表示しています。コピーして入力先へ貼り付けるか、「貼り付けを許可する」を押してください。"
            : "文字起こしができました。内容を確認してコピーできます。"
        phase = .preparing
        inputRequestedAt = Date()
        backgroundNotice = ""
        if fromShortcut { hud?.show() } else { hud?.hide() }
        notice = ""
        livePreview = ""
        lastFinalizeSeconds = nil
        activeEntries = dictionary
        let id = UUID()
        sessionID = id
        work = Task {
            guard !Task.isCancelled, sessionID == id else { return }
            if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                let allowed = await AVCaptureDevice.requestAccess(for: .audio)
                guard !Task.isCancelled, sessionID == id else { return }
                refreshInputPermissions()
                guard allowed else {
                    fail(VoiceError.message("マイクが許可されていません。「システム設定 → プライバシーとセキュリティ → マイク」でこえのたねを許可してください。"))
                    return
                }
            }
            work = nil
            beginCapture(id: id)
        }
    }

    private func beginCapture(id: UUID) {
        outputMute = RecordingOutputMute.begin { [weak self] in
            self?.captureInterrupted(id: id, error: VoiceError.message("音声の出力先が変わりました。もう一度音声入力してください。"))
        }
        playbackMuteFailed = outputMute == nil
        let capture = MicrophoneCapture()
        self.capture = capture
        do {
            try capture.start { [weak self] error in
                self?.captureInterrupted(id: id, error: error)
            }
        } catch {
            fail(error)
            return
        }

        seconds = 0
        startedAt = Date()
        phase = .recording
        hud?.show()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.seconds = Int(Date().timeIntervalSince(self.startedAt))
                if self.seconds >= 300 { self.stop() }
            }
        }

        let pending = warmTask
        warmTask = nil
        let vocabulary = TextPipeline.recognitionVocabulary(activeEntries)
        analysisTask = Task { [self] in
            do {
                let session: StreamingSpeechSession
                if let pending { session = try await pending.value }
                else { session = try await StreamingSpeechSession.prepare(vocabulary: vocabulary) }
                guard !Task.isCancelled, sessionID == id else {
                    session.cancel()
                    throw CancellationError()
                }
                liveSession = session
                session.onPreview = { [weak self] text in
                    guard let self, self.sessionID == id, self.busy else { return }
                    self.livePreview = text
                }
                session.onLevel = { [weak self] level in
                    guard let self, self.sessionID == id, self.phase == .recording else { return }
                    self.level = level
                }
                session.onFailure = { [weak self] error in
                    guard let self, self.sessionID == id, self.phase == .recording else { return }
                    self.fail(error)
                }
                try await session.start(buffers: capture.buffers)
                return session
            } catch {
                if sessionID == id {
                    if phase == .recording { fail(error) }
                    else { liveSession?.cancel() }
                }
                throw error
            }
        }
    }

    private func endCapture(cancelled: Bool = false) {
        capture?.end(cancelled: cancelled)
        capture = nil
        outputMute?.restore()
        outputMute = nil
        playbackMuteFailed = false
    }

    private func captureInterrupted(id: UUID, error: Error) {
        guard sessionID == id else { return }
        if phase == .recording { fail(error) }
        else if phase == .transcribing { endCapture() }
    }

    func prepareForSleep() {
        if phase == .transcribing { endCapture() }
        else { cancel() }
    }

    func stop() {
        guard phase == .recording, let analysisTask, let capture else { return }
        let released = Date()
        capture.markRelease(at: AudioGetCurrentHostTime())
        timer?.invalidate(); timer = nil
        level = 0
        phase = .transcribing
        holdRecording.reset(); recordingFromFn = false
        let entries = activeEntries
        let useLLM = refineText
        let cleanFillers = removeFillers
        let shouldPaste = pasteThisRecording && autoPaste
        let destination = target
        let requestStarted = inputRequestedAt
        work = Task {
            var completedText: String?
            defer {
                if let completedText { recordActivity(text: completedText, application: destination?.localizedName ?? "こえのたね", inputSeconds: Date().timeIntervalSince(requestStarted)) }
                self.analysisTask = nil; liveSession = nil; livePreview = ""; phase = .idle; hud?.hideRecording(); work = nil; prewarm()
            }
            do {
                await capture.waitForTail()
                try Task.checkCancellation()
                endCapture()
                let session = try await analysisTask.value
                let recognized = try await session.finish()
                lastFinalizeSeconds = Date().timeIntervalSince(released)
                try Task.checkCancellation()
                original = recognized
                output = TextPipeline.process(recognized, entries: entries, removeFillers: cleanFillers)
                if output.isEmpty {
                    notice = "フィラーだけだったため、貼り付ける文章はありません。元の認識結果は確認できます。"
                    presentRecordingResult()
                    return
                }
                if useLLM {
                    phase = .refining
                    do { output = try await SpeechService.refine(output, dictionary: entries) }
                    catch { notice = "文章整形: \(error.localizedDescription) 認識結果を確認してください。" }
                }
                try Task.checkCancellation()
                completedText = output
                if shouldPaste && notice.isEmpty {
                    await paste(into: destination)
                } else {
                    if notice.isEmpty { notice = displayOnlyReason }
                    selectedTab = "入力"
                    presentRecordingResult()
                }
            } catch VoiceError.noSpeech { clearEmptyInputNotice() }
            catch is CancellationError { notice = "音声入力をキャンセルしました。" }
            catch { notice = error.localizedDescription; presentRecordingResult() }
        }
    }

    func cancel(silently: Bool = false) {
        guard phase == .recording || phase == .preparing else { return }
        discardCapture()
        livePreview = ""; phase = .idle; level = 0; hud?.hide()
        holdRecording.reset(); recordingFromFn = false
        notice = silently ? "" : "音声入力をキャンセルしました。"
        backgroundNotice = ""
        prewarm()
    }

    private func discardCapture() {
        sessionID = UUID()
        work?.cancel(); work = nil
        analysisTask?.cancel(); analysisTask = nil
        timer?.invalidate(); timer = nil
        endCapture(cancelled: true)
        liveSession?.cancel(); liveSession = nil
    }

    func fail(_ error: Error) {
        discardCapture()
        livePreview = ""; phase = .idle; level = 0; hud?.hide()
        holdRecording.reset(); recordingFromFn = false
        if let voiceError = error as? VoiceError, case .noSpeech = voiceError { clearEmptyInputNotice(); prewarm(); return }
        notice = error.localizedDescription
        selectedTab = "入力"
        presentRecordingResult()
        prewarm()
    }

    private func clearEmptyInputNotice() {
        notice = ""; backgroundNotice = ""; hud?.hide()
    }

    func shutdown() {
        warmTask?.cancel()
        discardCapture()
    }

    func copy() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        notice = "コピーしました。入力先で ⌘V を押して貼り付けてください。"
    }

    private func paste(into destination: NSRunningApplication?) async {
        guard let destination, !destination.isTerminated else {
            notice = "入力先が見つかりません。結果はアプリ内に残しています。"; presentRecordingResult(); return
        }
        guard InputAccess.canPaste else {
            notice = "自動貼り付けには\(InputAccess.pastePermissionName)の許可が必要です。結果はアプリ内に残しています。"; presentRecordingResult(); return
        }
        guard RecordingPresentation.canPaste(startingApplication: destination.processIdentifier, currentApplication: NSWorkspace.shared.frontmostApplication?.processIdentifier) else {
            notice = "入力先が切り替わったため貼り付けませんでした。結果はアプリ内に残しています。"; presentRecordingResult(); return
        }
        // Many apps (Electron, browsers, web views) do not report a focused element, or hand out
        // a new element for the same field on every query. Requiring the same element as at the
        // start therefore blocked legitimate pastes. The frontmost-app check above is the guard;
        // the focused element is only used, when available, to keep password fields untouched.
        #if APP_STORE
        // Sandbox cannot inspect another app's focused AX element. Fail closed whenever
        // macOS reports secure event input; retain the transcript for manual recovery.
        guard !IsSecureEventInputEnabled() else {
            notice = "保護された入力が有効なため貼り付けません。結果はアプリ内に残しています。"; presentRecordingResult(); return
        }
        #else
        var subrole: CFTypeRef?
        if let current = Self.focusedElement(in: destination) {
            AXUIElementCopyAttributeValue(current, kAXSubroleAttribute as CFString, &subrole)
        }
        guard RecordingPresentation.canPaste(focusedSubrole: subrole as? String) else {
            notice = "パスワード欄には自動で貼り付けません。"; presentRecordingResult(); return
        }
        #endif
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            notice = "貼り付け操作を作成できませんでした。結果はアプリ内に残しています。"; presentRecordingResult(); return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        notice = "\(destination.localizedName ?? "入力先")へ貼り付け操作を送りました。入力先でご確認ください。"
    }

    func requestAccessibility() {
        #if APP_STORE
        waitingForPasteSettings = !InputAccess.canPaste
        visitedPasteSettings = false
        _ = IOHIDRequestAccess(kIOHIDRequestTypePostEvent)
        _ = CGRequestPostEventAccess()
        // PostEvent is sandbox-compatible and appears under Accessibility in System Settings.
        // A previously dismissed TCC prompt is not shown again, so always provide the settings route.
        openInputPrivacySettings("Privacy_Accessibility")
        #else
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        #endif
        refreshInputPermissions()
    }

    func requestMicrophonePermission() {
        guard !busy else { return }
        if microphoneStatus == .denied || microphoneStatus == .restricted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            return
        }
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            refreshInputPermissions()
        }
    }

    #if !APP_STORE
    private static func focusedElement(in app: NSRunningApplication) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    #endif

    func showWindow() {
        if let windowPresenter { windowPresenter(); return }
        guard let application = NSApp else { return }
        application.activate(ignoringOtherApps: true)
        application.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "こえのたね" })?.makeKeyAndOrderFront(nil)
    }

    /// Global dictation must not activate either this app or a previous input app.
    func presentRecordingResult() {
        lastResultPresentation = resultPresentation
        if resultPresentation == .nonactivatingNotice {
            backgroundNotice = notice
            hud?.showNotice()
        } else { showWindow() }
    }

    func recordActivity(text: String, application: String, inputSeconds: Double?) {
        activityStore.record(text: text, application: application, inputSeconds: inputSeconds)
        activity = activityStore.snapshot
    }
    func setHistoryEnabled(_ enabled: Bool) { activityStore.setHistoryEnabled(enabled); activity = activityStore.snapshot }
    func setUsageEnabled(_ enabled: Bool) { activityStore.setUsageEnabled(enabled); activity = activityStore.snapshot }
    func setTypingSpeed(_ speed: Int) { activityStore.setTypingSpeed(speed); activity = activityStore.snapshot }
    func clearHistory() { activityStore.clearHistory(); activity = activityStore.snapshot }
    func clearUsage() { activityStore.clearUsage(); activity = activityStore.snapshot }
    func copyHistory(_ entry: RecentInput) {
        NSPasteboard.general.clearContents()
        let written = NSPasteboard.general.setString(entry.text, forType: .string)
        notice = written && NSPasteboard.general.string(forType: .string) == entry.text
            ? "履歴をコピーしました。入力先で ⌘V を押して貼り付けてください。"
            : "コピーできませんでした。履歴の文章を選択してコピーしてください。"
    }

    func importAudio() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "こえのたね" }) else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.transcribeImportedAudio(url) }
        }
    }

    private func transcribeImportedAudio(_ url: URL) {
        guard !busy else { return }
        phase = .transcribing; notice = ""
        let entries = dictionary
        work = Task {
            defer { phase = .idle; work = nil }
            do {
                let recognized = try await SpeechService.transcribe(file: url, vocabulary: TextPipeline.recognitionVocabulary(entries))
                original = recognized
                output = TextPipeline.process(recognized, entries: entries, removeFillers: removeFillers)
                notice = "音声ファイルを文字起こししました。"
                if refineText {
                    phase = .refining
                    do { output = try await SpeechService.refine(output, dictionary: entries) }
                    catch { notice = "文章整形: \(error.localizedDescription)" }
                }
                recordActivity(text: output, application: "音声ファイル", inputSeconds: nil)
            } catch VoiceError.noSpeech { clearEmptyInputNotice() }
            catch { notice = error.localizedDescription }
        }
    }

    /// Registers a correction from the result area and fixes the text on screen right away.
    func addCorrection(heard: String, written: String) {
        var entries = dictionary
        let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let written = written.trimmingCharacters(in: .whitespacesAndNewlines)
        switch DictionaryCorrection.apply(heard: heard, written: written, to: &entries) {
        case .addedHint: notice = "「\(written)」を認識ヒントに登録しました。次回から、この表記で認識されやすくなります。"
        case .addedReplacement: notice = "登録しました。次回から「\(heard)」は「\(written)」に置き換えます。"
        case .updatedReplacement: notice = "更新しました。次回から「\(heard)」は「\(written)」に置き換えます。"
        case .duplicate: notice = "すでに登録されています。"; return
        case .invalid: notice = "正しい表記を入力してください。"; return
        }
        dictionary = entries
        if !heard.isEmpty, heard != written, !busy { output = output.replacingOccurrences(of: heard, with: written) }
    }

    func exportDictionary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "こえのたね辞書.json"
        panel.allowedContentTypes = [.json]
        panel.message = "iPhone版では「辞書」の取り込みで「CSV / TSV / JSON」を選び、このファイルを読み込みます。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try DictionaryCorrection.exportData(dictionary).write(to: url, options: .atomic); notice = "辞書を書き出しました（\(dictionary.count)件）。" }
        catch { notice = "辞書の書き出し: \(error.localizedDescription)" }
    }

    private func saveDictionary() {
        if let data = try? JSONEncoder().encode(dictionary) { UserDefaults.standard.set(data, forKey: "dictionary") }
    }

    func importSystemDictionary() {
        let replacements = NSSpellChecker.shared.userReplacementsDictionary
        var merged = dictionary
        do {
            notice = try DictionaryImporter.importSystemReplacements(replacements.map { ($0.key, $0.value) }, into: &merged)
            if merged.count != dictionary.count { dictionary = merged }
        } catch { notice = error.localizedDescription }
    }

    func chooseDictionary(source: DictionaryImportSource) {
        guard !busy, !readingDictionary else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = source == .apple ? [.propertyList] : [.plainText, .commaSeparatedText, .tabSeparatedText, .json, .text]
        panel.allowsMultipleSelection = false
        panel.message = "\(source.rawValue)から書き出したファイルを選んでください。確認画面ではまだ登録されません。"
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "こえのたね" }) else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.loadDictionary(url: url, source: source) }
        }
    }

    private func loadDictionary(url: URL, source: DictionaryImportSource) {
        readingDictionary = true
        let existing = dictionary
        Task {
            defer { readingDictionary = false }
            do {
                // Parsing a large ATOK dictionary must not freeze the recording/UI actor.
                let preview = try await Task.detached(priority: .userInitiated) {
                    try DictionaryImporter.read(url: url, source: source, existing: existing)
                }.value
                pendingDictionaryImport = preview
            } catch { notice = "辞書の取り込み: \(error.localizedDescription)" }
        }
    }

    func confirmDictionaryImport() {
        guard let preview = pendingDictionaryImport else { return }
        let plan = DictionaryImporter.plan(candidates: preview.candidates, existing: dictionary)
        dictionary.append(contentsOf: plan.additions)
        notice = "辞書を\(plan.additions.count)件追加しました。重複は\(plan.duplicates)件除外しました。既存の単語は変更していません。"
        pendingDictionaryImport = nil
    }
}
