import AppKit

@MainActor enum ApplicationInstallCoordinator {
    /// Returns true only for the installed app. Otherwise this process ends after installation or cancellation.
    static func prepare(source: URL = Bundle.main.bundleURL, service: ApplicationInstallService = ApplicationInstallService(), ready: @escaping () -> Void) {
        if service.isInstalled(source) { ready(); return }
        NSApp.activate(ignoringOtherApps: true)
        do {
            if let installed = try service.verifiedExistingApplication() {
                let alert = NSAlert()
                alert.messageText = "インストール済みのこえのたねを開きます"
                alert.informativeText = "アプリケーションフォルダに、すでにこえのたねがあります。そちらを開きます。更新は、開いたアプリの「更新する」から行えます。辞書・履歴・設定はそのまま引き継ぎます。"
                alert.addButton(withTitle: "インストール済みのアプリを開く")
                alert.addButton(withTitle: "終了")
                if alert.runModal() == .alertFirstButtonReturn { openInstalled(installed) }
                else { NSApp.terminate(nil) }
                return
            }
            let alert = NSAlert()
            alert.messageText = "アプリケーションにインストール"
            alert.informativeText = "こえのたねをアプリケーションフォルダにコピーして、そこから開きます。今後の更新も同じ場所に入ります。ダウンロード元のファイルは残ります。"
            alert.addButton(withTitle: "インストールして開く")
            alert.addButton(withTitle: "終了")
            guard alert.runModal() == .alertFirstButtonReturn else { NSApp.terminate(nil); return }
            openInstalled(try service.install(from: source))
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "アプリケーションへの配置が必要です"
            alert.informativeText = error.localizedDescription + "\n\n管理者の許可が必要なMacでは、Finderでこえのたねを「アプリケーション」へドラッグし、macOSの認証に従ってください。配置後、そのアプリを開いてください。"
            alert.addButton(withTitle: "Finderで配置する")
            alert.addButton(withTitle: "終了")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([source])
                NSWorkspace.shared.open(service.destination.deletingLastPathComponent())
            }
            NSApp.terminate(nil)
        }
    }

    private static func openInstalled(_ application: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // An app launched from Downloads must not substitute itself for the installed copy.
        configuration.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.openApplication(at: application, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    let alert = NSAlert()
                    alert.messageText = "アプリケーションから開いてください"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "アプリを表示")
                    alert.runModal()
                    NSWorkspace.shared.activateFileViewerSelecting([application])
                }
                NSApp.terminate(nil)
            }
        }
    }
}
