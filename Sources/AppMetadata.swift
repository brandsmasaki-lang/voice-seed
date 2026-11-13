import Foundation

/// Display and release metadata come from the bundle; version strings are never duplicated in views.
enum AppMetadata {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "こえのたね"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "開発版"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    static let versionDescription = "バージョン \(version)（ビルド \(build)）"

    static let links: [AppLink] = {
        guard let url = Bundle.main.url(forResource: "AppLinks", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let values = try? PropertyListDecoder().decode([String: String].self, from: data) else { return [] }
        return [
            AppLink(id: "Website", title: "ブランズバンク", detail: "運営元の公式サイト", symbol: "building.2", value: values["Website"]),
            AppLink(id: "X", title: "服部雅樹のX", detail: "AI活用・開発の発信", symbol: "at", value: values["X"]),
            AppLink(id: "LINE", title: "AI導入・開発相談LINE", detail: "AIの導入やアプリ開発を相談する", symbol: "bubble.left.and.bubble.right", value: values["LINE"]),
            AppLink(id: "GitHub", title: "GitHub", detail: "ソースコード・最新版・不具合報告", symbol: "chevron.left.forwardslash.chevron.right", value: values["GitHub"])
        ]
    }()

    static func bundledText(_ name: String, extension ext: String = "md") -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "公開準備中です。" }
        return text
    }
}

struct AppLink: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let url: URL?

    init(id: String, title: String, detail: String, symbol: String, value: String?) {
        self.id = id; self.title = title; self.detail = detail; self.symbol = symbol
        if let value, let url = URL(string: value), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil {
            self.url = url
        } else { self.url = nil }
    }
}
