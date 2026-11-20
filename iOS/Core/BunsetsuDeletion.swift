import Foundation

// Shared by committed text and the unconverted kana reading.
enum BunsetsuDeletion {
    static func characterCount(beforeCursor context: String) -> Int {
        guard let last = context.last else { return 0 }
        if last.isNewline { return 1 }
        let line = context.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last ?? ""
        return min(10, line.count)
    }
}
