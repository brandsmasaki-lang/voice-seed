import AppKit
import AVFoundation
import Speech
import SwiftUI
import ApplicationServices
import UniformTypeIdentifiers

enum RecordingPhase: String {
    case idle, preparing, recording, transcribing, refining
    var title: String {
        switch self {
        case .idle: return "話すだけで、ことばになる。"
        case .preparing: return "マイクを準備しています"
        case .recording: return "聞いています。"
        case .transcribing: return "ことばに変えています"
        case .refining: return "文章を整えています"
        }
    }
}

@MainActor final class AppModel: NSObject, ObservableObject {
    @Published var phase: RecordingPhase = .idle
    @Published var output = ""
    @Published var original = ""
    @Published var notice = ""
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
    @Published var fnLastEvent = "Fnキーを押して離すと、ここで検出を確認できます。"
    @Published var recordingFromFn = false
    @Published var pendingDictionaryImport: DictionaryImportPreview?
    @Published var readingDictionary = false
    @Published var livePreview = ""
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
            hotkeyStatus = hotkey?.register(choice: shortcut) == true ? "" : "ショートカットを登録できません。別の組み合わせを選んでください。"
        }
    }
    var hotkey: GlobalHotkey?
    var hud: RecordingHUD?
    private var liveSession: StreamingSpeechSession?
    private var warmTask: Task<StreamingSpeechSession, Error>?
    private var activeEntries: [DictionaryEntry] = []
    private var timer: Timer?
    private var target: NSRunningApplication?
    private var focusedAtStart: AXUIElement?
    private var pasteThisRecording = false
    private var work: Task<Void, Never>?
    private var startedAt = Date()
    private var sessionID = UUID()

    var busy: Bool { phase != .idle }
    var displayedOutput: String { busy && !livePreview.isEmpty ? livePreview : output }
    var duration: String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
    var shortcutLabel: String { ["⌃ ⌥ Space", "⌘ ⇧ Space", "⌃ ⇧ Space"][min(max(shortcut, 0), 2)] }

    func refreshInputPermissions() {
        let canPaste = AXIsProcessTrusted()
        if pasteReady != canPaste { pasteReady = canPaste }
        let canDetectFn: Bool
        if fnEnabled { canDetectFn = fnMonitor?.start() ?? false }
        else { fnMonitor?.stop(); canDetectFn = false }
        if fnReady != canDetectFn { fnReady = canDetectFn }
    }

    func requestFnPermission() {
        _ = CGRequestListenEventAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
        refreshInputPermissions()
    }

    func openKeyboardSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }

    func fnPressed() {
        fnLastEvent = "Fn を押しています。"
        // Settings and About never open the microphone while this app is frontmost.
        if ["設定", "アプリについて"].contains(selectedTab), NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        guard !busy, !installing else { return }
        guard modelReady, fnReady, pasteReady, autoPaste else {
            notice = !modelReady ? "日本語モデルを準備してください。" : "Fn入力の準備が必要です。①Fnキーの検知 ②自動貼り付けの許可を設定してください。"
            selectedTab = "設定"; showWindow(); return
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
        fnLastEvent = "Fnキーの検知が中断されたため、録音をキャンセルしました。"
    }

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "dictionary"),
           let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data) {
            dictionary = entries
        }
    }

    func refresh() async {
        modelStatus = await SpeechService.status()
        if let module = try? await SpeechService.module() {
            modelReady = await Speech.AssetInventory.status(forModules: [module]) == .installed
        }
        llmStatus = SpeechService.refinementStatus
        prewarm()
    }

    private func prewarm() {
        guard modelReady, !busy, warmTask == nil else { return }
        let vocabulary = dictionary.map(\.written)
        warmTask = Task { try await StreamingSpeechSession.prepare(vocabulary: vocabulary) }
    }

    func installModel() {
        guard !installing, !busy else { return }
        installing = true
        notice = "日本語モデルをAppleからダウンロードします。音声は送信しません。"
        work = Task {
            do { try await SpeechService.install(); notice = "日本語モデルの準備ができました。" }
            catch { notice = "モデルを準備できませんでした: \(error.localizedDescription)" }
            installing = false
            await refresh()
        }
    }

    func toggle(fromShortcut: Bool = false) {
        if phase == .recording { stop(); return }
        guard !busy, !installing else { return }
        guard modelReady else { selectedTab = "設定"; notice = "先に日本語モデルを準備してください。"; showWindow(); return }
        target = fromShortcut ? NSWorkspace.shared.frontmostApplication : nil
        focusedAtStart = target.flatMap { Self.focusedElement(in: $0) }
        pasteThisRecording = fromShortcut && target?.processIdentifier != ProcessInfo.processInfo.processIdentifier
        phase = .preparing
        notice = ""
        livePreview = ""
        lastFinalizeSeconds = nil
        activeEntries = dictionary
        let id = UUID()
        sessionID = id
        work = Task { [self] in
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled, sessionID == id else { return }
            guard allowed else {
                phase = .idle
                holdRecording.reset(); recordingFromFn = false
                notice = "マイクが許可されていません。「システム設定 → プライバシーとセキュリティ → マイク」でこえのたねを許可してください。"
                showWindow()
                return
            }
            do {
                let pending = warmTask
                warmTask = nil
                let session: StreamingSpeechSession
                if let pending { session = try await pending.value }
                else { session = try await StreamingSpeechSession.prepare(vocabulary: activeEntries.map(\.written)) }
                guard !Task.isCancelled, sessionID == id else { session.cancel(); return }
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
                try await session.startMicrophone()
                guard !Task.isCancelled, sessionID == id else { session.cancel(); return }
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
            } catch {
                guard sessionID == id, !Task.isCancelled else { return }
                fail(error)
            }
        }
    }

    func stop() {
        guard phase == .recording, let session = liveSession else { return }
        let released = Date()
        timer?.invalidate(); timer = nil
        level = 0
        phase = .transcribing
        session.endAudio()
        holdRecording.reset(); recordingFromFn = false
        let entries = activeEntries
        let useLLM = refineText
        let cleanFillers = removeFillers
        let shouldPaste = pasteThisRecording && autoPaste
        let destination = target
        work = Task {
            defer { liveSession = nil; livePreview = ""; phase = .idle; hud?.hide(); work = nil; prewarm() }
            do {
                let recognized = try await session.finish()
                lastFinalizeSeconds = Date().timeIntervalSince(released)
                try Task.checkCancellation()
                original = recognized
                output = TextPipeline.process(recognized, entries: entries, removeFillers: cleanFillers)
                if output.isEmpty {
                    notice = "フィラーだけだったため、貼り付ける文章はありません。元の認識結果は確認できます。"
                    showWindow()
                    return
                }
                if useLLM {
                    phase = .refining
                    do { output = try await SpeechService.refine(output) }
                    catch { notice = "文章整形: \(error.localizedDescription) 認識結果を確認してください。" }
                }
                try Task.checkCancellation()
                if shouldPaste && notice.isEmpty {
                    await paste(into: destination)
                } else {
                    if notice.isEmpty { notice = "文字起こしができました。内容を確認してコピーできます。" }
                    showWindow()
                }
            } catch is CancellationError { notice = "録音をキャンセルしました。" }
            catch { notice = error.localizedDescription; showWindow() }
        }
    }

    func cancel() {
        guard phase == .recording || phase == .preparing else { return }
        sessionID = UUID()
        work?.cancel(); work = nil
        timer?.invalidate(); timer = nil
        liveSession?.cancel(); liveSession = nil
        livePreview = ""; phase = .idle; level = 0; hud?.hide()
        holdRecording.reset(); recordingFromFn = false
        notice = "録音をキャンセルしました。"
        prewarm()
    }

    private func fail(_ error: Error) {
        timer?.invalidate(); timer = nil
        liveSession?.cancel(); liveSession = nil
        livePreview = ""; phase = .idle; hud?.hide()
        holdRecording.reset(); recordingFromFn = false
        notice = error.localizedDescription
        showWindow()
        prewarm()
    }

    func shutdown() {
        work?.cancel(); timer?.invalidate(); warmTask?.cancel(); liveSession?.cancel()
    }

    func copy() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        notice = "コピーしました。入力先で ⌘V を押して貼り付けてください。"
    }

    private func paste(into destination: NSRunningApplication?) async {
        guard let destination, !destination.isTerminated else {
            notice = "入力先が見つかりません。内容を確認してコピーしてください。"; showWindow(); return
        }
        guard AXIsProcessTrusted() else {
            notice = "自動貼り付けにはアクセシビリティの許可が必要です。「設定」から許可するか、コピーして貼り付けてください。"; showWindow(); return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != destination.processIdentifier {
            destination.activate()
            for _ in 0..<14 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier { break }
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier else {
            notice = "入力先を確認できませんでした。内容を確認してコピーしてください。"; showWindow(); return
        }
        guard let initial = focusedAtStart, let current = Self.focusedElement(in: destination), CFEqual(initial, current) else {
            notice = "録音開始時と同じ入力欄であることを確認できませんでした。内容を確認してコピーしてください。"; showWindow(); return
        }
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(current, kAXSubroleAttribute as CFString, &subrole)
        guard subrole as? String != kAXSecureTextFieldSubrole else {
            notice = "パスワード欄には自動で貼り付けません。"; showWindow(); return
        }
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            notice = "貼り付け操作を作成できませんでした。コピーして貼り付けてください。"; showWindow(); return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        notice = "\(destination.localizedName ?? "入力先")へ貼り付け操作を送りました。入力先でご確認ください。"
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        refreshInputPermissions()
    }

    private static func focusedElement(in app: NSRunningApplication) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "こえのたね" })?.makeKeyAndOrderFront(nil)
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
                let recognized = try await SpeechService.transcribe(file: url, vocabulary: entries.map(\.written))
                original = recognized
                output = TextPipeline.process(recognized, entries: entries, removeFillers: removeFillers)
                notice = "音声ファイルを文字起こししました。"
                if refineText {
                    phase = .refining
                    do { output = try await SpeechService.refine(output) }
                    catch { notice = "文章整形: \(error.localizedDescription)" }
                }
            } catch { notice = error.localizedDescription }
        }
    }

    private func saveDictionary() {
        if let data = try? JSONEncoder().encode(dictionary) { UserDefaults.standard.set(data, forKey: "dictionary") }
    }

    func chooseDictionary(source: DictionaryImportSource) {
        guard !busy, !readingDictionary else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .commaSeparatedText, .tabSeparatedText, .json, .text]
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
