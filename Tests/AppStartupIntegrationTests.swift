import Foundation
import FoundationModels
import CoreGraphics

@main struct AppStartupIntegrationTests {
    @MainActor static func main() async {
        var installed = false
        var installs = 0
        var failInstallation = false
        let missing = SpeechModelReadiness(ready: false, status: "日本語モデルの初回ダウンロードが必要です")
        let ready = SpeechModelReadiness(ready: true, status: "日本語モデルの準備完了")
        let service = SpeechModelAccess(read: { installed ? ready : missing }, install: {
            installs += 1
            if failInstallation { throw VoiceError.message("テスト用の通信失敗") }
            installed = true
        })
        var windowPresentations = 0
        let model = AppModel(speechModel: service, windowPresenter: { windowPresentations += 1 })
        defer { model.shutdown() }
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        let draft = "明日は15時に3名で伺います。"
        do {
            let refused = try await SpeechService.refine(draft, using: { _ in
                throw LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "Synthetic refusal"))
            })
            check(refused == draft, "A model guardrail preserves the input and does not block automatic paste")
            let failed = try await SpeechService.refine(draft, using: { _ in throw VoiceError.message("Synthetic failure") })
            check(failed == draft, "Optional formatting failure preserves the input")
            let altered = try await SpeechService.refine(draft, using: { _ in "明日は16時に3名で伺います。" })
            check(altered == draft, "Rejected formatting preserves numbers")
            let formatted = try await SpeechService.refine(draft, using: { _ in "明日は15時に、3名で伺います。" })
            check(formatted == "明日は15時に、3名で伺います。", "Valid formatting is used")
            let entries = [DictionaryEntry(heard: "声の種", written: "こえのたね")]
            let corrected = TextPipeline.process("今日は声の種を使います", entries: entries, removeFillers: true)
            let demoResult = try await SpeechService.refine(corrected, dictionary: entries) { _ in "今日は音紋を使います。" }
            check(demoResult == "今日はこえのたねを使います", "A paraphrase cannot overwrite a dictionary correction")
            let punctuated = try await SpeechService.refine(corrected, dictionary: entries) { _ in "今日は、こえのたねを使います。" }
            check(punctuated == "今日は、こえのたねを使います。", "Preserving dictionary spellings still allows formatting")
            let hint = [DictionaryEntry(heard: "", written: "こえのたね", kind: .vocabulary)]
            let repeated = "こえのたねで、こえのたねを紹介します。"
            let partialLoss = try await SpeechService.refine(repeated, dictionary: hint) { _ in "こえのたねで、音紋を紹介します。" }
            check(partialLoss == repeated, "Every occurrence of a recognized vocabulary hint is protected")
            let unrelated = try await SpeechService.refine("今日は花の種をまきます", dictionary: hint) { _ in "今日は、花の種をまきます。" }
            check(unrelated == "今日は、花の種をまきます。", "An unused hint is not inserted into unrelated text")
            do {
                _ = try await SpeechService.refine(draft, using: { _ in throw CancellationError() })
                check(false, "Cancellation must propagate")
            } catch is CancellationError { check(true, "Cancellation propagates") }
        } catch { preconditionFailure("Unexpected refinement failure: \(error)") }
        await model.refresh()
        check(!model.modelReady && model.modelStatus == missing.status, "Fresh installation exposes the actual missing model")
        model.fnPressed()
        check(model.selectedTab == "入力", "Regression: Fn with a missing model must not navigate to settings")
        check(model.notice.contains("日本語モデルを準備"), "The same screen names an actionable button")
        check(model.phase == .idle, "Missing assets never open the microphone")
        check(windowPresentations == 0 && model.lastResultPresentation == .nonactivatingNotice, "Fn setup failure cannot activate the app")
        for reason in ["貼り付け許可なし", "入力先が変わった", "文章整形の失敗", "入力する文字なし"] {
            model.notice = reason; model.presentRecordingResult()
            check(windowPresentations == 0 && model.backgroundNotice == reason, "Background failure retains a notice without activating the app")
        }
        model.fnReleased(); model.fnPressed(); model.fnReleased()
        check(model.selectedTab == "入力" && model.phase == .idle, "Repeated press/release does not create a settings loop")
        model.toggle()
        check(model.selectedTab == "入力" && model.phase == .idle, "Button recording uses the same model preparation screen")
        check(windowPresentations == 1 && model.lastResultPresentation == .mainWindow, "Only explicit in-app recording may request the window")
        check(RecordingPhase.recording.title == "聞き取り中", "Requested listening label")
        model.installModel()
        let deadline = Date().addingTimeInterval(5)
        while model.installing && Date() < deadline { await Task.yield() }
        check(!model.installing && installs == 1, "The actual model installation action completes once")
        check(model.modelReady && model.modelStatus == ready.status, "Completing setup refreshes readiness and its label together")
        check(model.selectedTab == "入力", "Completing model setup leaves the user on the input screen")
        installed = false
        await model.refresh()
        check(!model.modelReady, "A later missing model cannot leave stale ready=true")
        failInstallation = true
        model.installModel()
        let failureDeadline = Date().addingTimeInterval(5)
        while model.installing && Date() < failureDeadline { await Task.yield() }
        check(!model.installing && !model.modelReady && model.notice.contains("通信失敗"), "Download failure leaves a visible reason and a retryable idle state")
        check(model.selectedTab == "入力", "A download failure does not force a settings loop")
        let windowsBeforeEmptyInput = windowPresentations
        model.output = "保持する合成の文章"
        model.notice = "古い通知"; model.backgroundNotice = "古い通知"
        model.fail(VoiceError.noSpeech)
        check(model.notice.isEmpty && model.backgroundNotice.isEmpty, "No speech never presents an error popup")
        check(model.output == "保持する合成の文章" && model.phase == .idle, "No speech preserves the last result and returns to idle")
        check(windowPresentations == windowsBeforeEmptyInput, "No speech never activates the app")
        model.notice = "Fnの準備通知"; model.backgroundNotice = "Fnの準備通知"
        model.fnUsedWithAnotherKey()
        check(model.notice.isEmpty && model.backgroundNotice.isEmpty, "Fn keyboard chords dismiss notifications silently")
        check(windowPresentations == windowsBeforeEmptyInput, "Fn Delete cannot activate the main window")
        var protected = false
        let monitor = FnKeyMonitor(secureInputEnabled: { protected })
        var transitions: [Bool] = []
        var events: [String] = []
        monitor.onInputProtectionChanged = {
            transitions.append($0)
            model.fnInputProtectionChanged($0)
        }
        monitor.onPress = { events.append("press"); model.fnPressed() }
        monitor.onRelease = { events.append("release"); model.fnReleased() }
        monitor.onInterrupted = { events.append("interrupt"); model.fnInterrupted() }
        func fnEvent(down: Bool) {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: down)!
            event.flags = down ? [.maskSecondaryFn] : []
            monitor.receive(type: .flagsChanged, event: event)
        }
        model.modelReady = true
        model.microphoneStatus = .authorized
        model.fnReady = true
        model.pasteReady = true
        fnEvent(down: true)
        check(model.phase == .preparing && model.recordingFromFn, "An ordinary Fn press starts recording preparation")
        protected = true
        monitor.refreshInputProtection() // No key-up or any other event was delivered.
        monitor.refreshInputProtection()
        check(events == ["press", "interrupt"] && transitions == [true], "Entering protection without a release interrupts exactly once")
        check(model.fnPaused && model.fnProtectionMessage != nil, "Input protection has actionable status even when no key arrives")
        check(model.phase == .idle && !model.needsInputSetup, "A lost release ends preparation without requesting permissions again")
        fnEvent(down: false); fnEvent(down: true)
        check(events == ["press", "interrupt"], "Protected events never trigger recording or paste")
        model.toggle()
        check(model.phase == .preparing && !model.recordingFromFn, "The in-app microphone remains usable during protection")
        protected = false
        monitor.refreshInputProtection()
        fnEvent(down: false) // Release of a key held across the transition cannot paste.
        check(!model.fnPaused && model.fnProtection == .lifted && transitions == [true, false], "Recovery is automatic and leaves the reason visible")
        check(events == ["press", "interrupt"], "Recovery itself cannot start or finalize a recording")
        check(model.phase == .preparing, "Lifting protection leaves a manually started recording alone")
        model.cancel()
        fnEvent(down: true)
        check(model.phase == .preparing && model.recordingFromFn, "The first fresh press starts preparation again")
        fnEvent(down: false)
        check(model.fnProtectionMessage == nil && events.suffix(2) == ["press", "release"], "First fresh Fn works and clears the recovery message")
        #if APP_STORE
        events.removeAll()
        func poll(_ down: Bool) {
            monitor.sampleModifiers(readFlags: { down ? [.maskSecondaryFn] : [] }, readKeyDownCount: { 0 })
        }
        poll(false); poll(true)
        protected = true
        monitor.sampleModifiers(readFlags: { preconditionFailure("Protected modifiers must not be read") },
                                readKeyDownCount: { preconditionFailure("Protected keyboard activity must not be read") })
        protected = false
        poll(true); poll(false)
        check(events == ["press", "interrupt"], "Polling ignores the held Fn across protection")
        poll(true); poll(false)
        check(events == ["press", "interrupt", "press", "release"], "Polling recovers on the next fresh hold")
        #endif
        print("PASS: \(checks) AppModel integration checks (synthetic assets and Fn events; no microphone recording)")
    }
}
