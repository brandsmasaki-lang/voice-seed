import Foundation

/// Display and release metadata come from the bundle; version strings are never duplicated in views.
enum AppMetadata {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "こえのたね"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "開発版"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    static let versionDescription = "バージョン \(version)（ビルド \(build)）"

    static func bundledText(_ name: String, extension ext: String = "md") -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "公開準備中です。" }
        return text
    }
}
