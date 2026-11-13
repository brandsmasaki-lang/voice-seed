import AppIntents

/// Public App Intents API; no responder-chain selectors or host-app URL guessing.
struct ActivateDictationIntent: AppIntent {
    static var title: LocalizedStringResource = "こえのたねのマイクを有効にする"
    static var description = IntentDescription("本体アプリを開き、端末内音声入力のマイクを準備します。")
    static var openAppWhenRun: Bool = true

    @MainActor func perform() async throws -> some IntentResult {
        try AppGroupContainer.open().enqueue(.init(kind: .activate))
        return .result()
    }
}

struct OpenVoiceSeedSettingsIntent: AppIntent {
    static var title: LocalizedStringResource = "こえのたねの設定を開く"
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult {
        try AppGroupContainer.open().enqueue(.init(kind: .showSettings))
        return .result()
    }
}
