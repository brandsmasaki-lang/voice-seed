import Foundation
import FoundationModels

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
        print("PASS: \(checks) AppModel fresh-install integration checks (synthetic assets; no microphone recording)")
    }
}
