import AppIntents

/// Public App Intents API; no responder-chain selectors or host-app URL guessing.
struct ActivateDictationIntent: AppIntent {
    @Parameter(title: "入力欄") var documentID: String
    init() { documentID = "" }
    init(documentID: String) { self.documentID = documentID }
    static var title: LocalizedStringResource = "こえのたねのマイクを有効にする"
    static var description = IntentDescription("本体アプリを開き、端末内音声入力のマイクを準備します。")
    static var supportedModes: IntentModes { .foreground(.immediate) }
    #if compiler(>=6.4)
    // Xcode 27 SDK: a keyboard must not execute the host's foreground work.
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @MainActor func perform() async throws -> some IntentResult {
        let launch = documentID.isEmpty ? nil : KeyboardLaunch(documentID: documentID, createdAt: Date())
        try AppGroupContainer.open().enqueue(.init(kind: .activate, keyboardLaunch: launch))
        return .result()
    }
}

struct OpenVoiceSeedSettingsIntent: AppIntent {
    static var title: LocalizedStringResource = "こえのたねの設定を開く"
    static var supportedModes: IntentModes { .foreground(.immediate) }
    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif
    @MainActor func perform() async throws -> some IntentResult {
        try AppGroupContainer.open().enqueue(.init(kind: .showSettings))
        return .result()
    }
}
