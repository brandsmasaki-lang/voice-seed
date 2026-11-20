import ApplicationServices

enum AppDistribution {
    static var isAppStore: Bool {
        #if APP_STORE
        true
        #else
        false
        #endif
    }
}

enum InputAccess {
    static var canListen: Bool {
        #if APP_STORE
        CGPreflightListenEventAccess()
        #else
        CGPreflightListenEventAccess() || AXIsProcessTrusted()
        #endif
    }

    static var canPaste: Bool {
        #if APP_STORE
        CGPreflightPostEventAccess()
        #else
        AXIsProcessTrusted()
        #endif
    }

    static var pastePermissionName: String {
        AppDistribution.isAppStore ? "イベント送信" : "アクセシビリティ"
    }

    static var listenPermissionName: String {
        AppDistribution.isAppStore ? "入力監視" : "アクセシビリティまたは入力監視"
    }
}
