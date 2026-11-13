import SwiftUI
import AppKit
import Speech
import FoundationModels

@main struct VoiceSeedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    init() {
        // Remove only temporary recordings created by this app, never imported user files.
        let temporary = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil) {
            for file in files where file.lastPathComponent.hasPrefix("voice-seed-") && file.pathExtension == "caf" {
                let components = file.lastPathComponent.split(separator: "-")
                if components.count > 3, let pid = Int32(components[2]), kill(pid, 0) == -1, errno == ESRCH {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    var body: some Scene {
        Window("こえのたね", id: "main") {
            MainView(model: model)
                .onAppear { delegate.connect(model) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) {
                Button("こえのたねについて") { model.selectedTab = "アプリについて"; model.showWindow() }
            }
            CommandGroup(after: .appInfo) {
                Button("こえのたねの設定") { model.selectedTab = "設定"; model.showWindow() }.keyboardShortcut(",")
                UpdateMenuItem(model: model, updater: model.updater)
            }
        }
        MenuBarExtra("こえのたね", systemImage: model.phase == .recording ? "mic.fill" : "waveform") {
            Text(model.phase == .idle ? "こえのたね" : model.phase.title)
            Button(model.phase == .recording ? "録音を終了" : "録音を開始") { model.toggle(fromShortcut: true) }
                .disabled(model.busy && model.phase != .recording)
            if model.phase == .recording { Button("録音をキャンセル") { model.cancel() } }
            Divider()
            Button("入力画面を開く") { model.selectedTab = "入力"; model.showWindow() }
            Button("設定") { model.selectedTab = "設定"; model.showWindow() }
            Button("こえのたねについて") { model.selectedTab = "アプリについて"; model.showWindow() }
            UpdateMenuItem(model: model, updater: model.updater)
            Divider()
            Button("終了") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var hotkey: GlobalHotkey?
    private var activity: NSObjectProtocol?
    private var commandMode = false
    private var permissionTimer: Timer?
    private var sleepObserver: NSObjectProtocol?

    func connect(_ model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        model.updater.start()
        model.publicInfo.start()
        let hotkey = GlobalHotkey()
        hotkey.onPress = { [weak model] in model?.toggle(fromShortcut: true) }
        self.hotkey = hotkey
        model.hotkey = hotkey
        model.hotkeyStatus = hotkey.register(choice: model.shortcut) ? "" : "ショートカットを登録できません。設定から別のキーを選んでください。"
        model.hud = RecordingHUD(model: model)
        let fn = FnKeyMonitor()
        fn.onPress = { [weak model] in model?.fnPressed() }
        fn.onRelease = { [weak model] in model?.fnReleased() }
        fn.onInterrupted = { [weak model] in model?.fnInterrupted() }
        model.fnMonitor = fn
        model.refreshInputPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak model] _ in
            Task { @MainActor in model?.refreshInputPermissions() }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak model] _ in
            MainActor.assumeIsolated { model?.fnInterrupted() }
        }
        // Avoid App Nap while processing, without preventing ordinary system sleep.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "音声入力の待機")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if arguments.contains("--diagnose") || arguments.contains("--transcribe-file") || arguments.contains("--install-model") || arguments.contains("--refine-text") || arguments.contains("--benchmark-stream") {
            commandMode = true
            NSApp.setActivationPolicy(.prohibited)
            Task {
                var result: [String: Any] = [:]
                var exitCode: Int32 = 0
                do {
                    if arguments.contains("--install-model") {
                        try await SpeechService.install()
                        result["installation"] = "complete"
                    }
                    if let index = arguments.firstIndex(of: "--transcribe-file"), arguments.count > index + 1 {
                        result["text"] = try await SpeechService.transcribe(file: URL(fileURLWithPath: arguments[index + 1]), vocabulary: [])
                    }
                    if let index = arguments.firstIndex(of: "--refine-text"), arguments.count > index + 1 {
                        result["text"] = try await SpeechService.refine(arguments[index + 1])
                    }
                    if let index = arguments.firstIndex(of: "--benchmark-stream"), arguments.count > index + 1 {
                        result = try await StreamingSpeechSession.benchmark(file: URL(fileURLWithPath: arguments[index + 1]))
                    }
                    result["speech"] = await SpeechService.status()
                    result["llm"] = SpeechService.refinementStatus
                    result["speechAvailable"] = String(SpeechTranscriber.isAvailable)
                } catch { result["error"] = error.localizedDescription; exitCode = 1 }
                result["version"] = AppMetadata.version
                result["build"] = AppMetadata.build
                if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), let string = String(data: data, encoding: .utf8) { print(string) }
                fflush(stdout)
                exit(exitCode)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model?.showWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
        model?.fnMonitor?.stop()
        permissionTimer?.invalidate()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        hotkey?.unregister()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }
}
