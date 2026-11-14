import Foundation
import NaturalLanguage

enum BunsetsuDeletion {
    // NLTokenizer supplies Japanese word boundaries. Attach grammatical endings
    // to the preceding independent word to estimate the last bunsetsu locally.
    private static let endings: Set<String> = [
        "は", "が", "を", "に", "で", "と", "へ", "も", "や", "の", "から", "まで", "より",
        "だけ", "など", "には", "では", "とは", "にも", "ても", "ので", "のに", "けど",
        "です", "でし", "ます", "まし", "た", "だ", "だっ", "ない", "なかっ", "れる", "られる",
        "せる", "させる", "たい", "たく", "う", "よう", "ん", "し", "て"
    ]

    static func characterCount(beforeCursor context: String) -> Int {
        guard let last = context.last else { return 0 }
        if last.isNewline { return 1 }
        let line = String(context.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).last ?? "")
        if last.isWhitespace { return line.reversed().prefix(while: \.isWhitespace).count }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.japanese); tokenizer.string = line
        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { range, _ in ranges.append(range); return true }
        guard var index = ranges.indices.last else { return min(1, line.count) }
        while index > 0, endings.contains(String(line[ranges[index]])) { index -= 1 }
        return line[ranges[index].lowerBound...].count
    }
}
