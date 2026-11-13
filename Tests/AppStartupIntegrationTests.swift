import Foundation

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
        let model = AppModel(speechModel: service)
        defer { model.shutdown() }
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        await model.refresh()
        check(!model.modelReady && model.modelStatus == missing.status, "Fresh installation exposes the actual missing model")
        model.fnPressed()
        check(model.selectedTab == "入力", "Regression: Fn with a missing model must not navigate to settings")
        check(model.notice.contains("日本語モデルを準備"), "The same screen names an actionable button")
        check(model.phase == .idle, "Missing assets never open the microphone")
        model.fnReleased(); model.fnPressed(); model.fnReleased()
        check(model.selectedTab == "入力" && model.phase == .idle, "Repeated press/release does not create a settings loop")
        model.toggle()
        check(model.selectedTab == "入力" && model.phase == .idle, "Button recording uses the same model preparation screen")
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
        print("PASS: \(checks) AppModel fresh-install integration checks (synthetic assets; no microphone recording)")
    }
}
