import ApplicationServices
import Foundation

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
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion == 27 && version.minorVersion < 3 {
            return "デバイスの制御とデータへのアクセス"
        }
        if version.majorVersion >= 27 { return "システム設定での自動貼り付け" }
        return "アクセシビリティ"
    }

    static var listenPermissionName: String {
        AppDistribution.isAppStore ? "入力監視" : "アクセシビリティまたは入力監視"
    }
}
