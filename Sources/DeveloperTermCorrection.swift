import Foundation

/// Resolve the reported GitHub confusion only next to explicit repository operations.
/// Do not rewrite the musical instrument or ambiguous words such as コード.
enum DeveloperTermCorrection {
    private static let pattern = try! NSRegularExpression(pattern:
        #"(?:ギター部|ギターブ|ギター|きっとハブ|リットハブ|LitHub)(?=(?:に|へ)(?:保存|コミット|プッシュ|アップロード)|(?:の|で)(?:リポジトリ|プルリクエスト|コミット|プッシュ))"#)
    static func apply(_ text: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "GitHub")
    }
}
