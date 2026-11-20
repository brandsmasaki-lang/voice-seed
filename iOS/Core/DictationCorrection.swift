import Foundation

/// Coordinates are Character offsets within the last delivered text, never the host document.
struct DictationCorrection {
    struct Word {
        let start: Int
        let text: String
        let reading: String
        var range: Range<Int> { start..<(start + text.count) }
    }
    struct Edit: Equatable {
        let start: Int
        let from: String
        let to: String
        var inverse: Self { .init(start: start, from: to, to: from) }
    }

    private(set) var text: String
    private(set) var caret: Int
    private(set) var undo: Edit?
    let document: String
    let focus: UUID
    private static let contextLimit = 24
    private let prefix: String
    private let suffix: String

    init(text: String, before: String?, after: String?, document: String, focus: UUID) {
        self.text = text
        caret = text.count
        prefix = String((before ?? "").suffix(Self.contextLimit))
        suffix = String((after ?? "").prefix(Self.contextLimit))
        self.document = document
        self.focus = focus
    }

    func matches(before: String?, after: String?, at offset: Int) -> Bool {
        let left = prefix + text.prefix(offset)
        let right = String(text.dropFirst(offset)) + suffix
        let actualLeft = before ?? "", actualRight = after ?? ""
        let leftMatches = prefix.count < Self.contextLimit ? actualLeft == left : actualLeft.hasSuffix(left)
        let rightMatches = suffix.count < Self.contextLimit ? actualRight == right : actualRight.hasPrefix(right)
        return leftMatches && rightMatches
    }

    /// Compare everything the host exposes at a cursor position. A window alone
    /// never proves the whole utterance; the keyboard also checks both boundaries.
    func agreesWithWindow(before: String?, after: String?, at offset: Int) -> Bool {
        let left = prefix + text.prefix(offset)
        let right = String(text.dropFirst(offset)) + suffix
        let actualLeft = before ?? "", actualRight = after ?? ""
        guard !(actualLeft.isEmpty && actualRight.isEmpty) else { return false }
        func agrees(_ actual: String, _ expected: String, fromEnd: Bool) -> Bool {
            if expected.isEmpty || actual.isEmpty { return expected.isEmpty && actual.isEmpty }
            return fromEnd ? (actual.hasSuffix(expected) || expected.hasSuffix(actual))
                           : (actual.hasPrefix(expected) || expected.hasPrefix(actual))
        }
        if offset == 0 {
            guard prefix.count < Self.contextLimit ? actualLeft == prefix : actualLeft.hasSuffix(prefix) else { return false }
        }
        if offset == text.count {
            guard suffix.count < Self.contextLimit ? actualRight == suffix : actualRight.hasPrefix(suffix) else { return false }
        }
        return agrees(actualLeft, left, fromEnd: true) && agrees(actualRight, right, fromEnd: false)
    }

    var words: [Word] {
        let ns = text as NSString
        let tokenizer = CFStringTokenizerCreate(nil, text as CFString, CFRangeMake(0, ns.length),
            kCFStringTokenizerUnitWord, Locale(identifier: "ja_JP") as CFLocale)
        guard let tokenizer else { return [] }
        var words: [Word] = []
        var cursor = text.startIndex
        var offset = 0
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard let range = Range(NSRange(location: r.location, length: r.length), in: text) else { continue }
            offset += text.distance(from: cursor, to: range.lowerBound)
            let word = String(text[range])
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            let reading = latin?.applyingTransform(StringTransform("Latin-Hiragana"), reverse: false) ?? word
            words.append(Word(start: offset, text: word, reading: reading))
            offset += word.count
            cursor = range.upperBound
        }
        return words
    }

    /// Both taps include the touched character, even when the user selects backwards.
    func selection(from first: Int, through last: Int) -> Word? {
        let lower = min(first, last), upper = max(first, last)
        guard lower >= 0, upper < text.count else { return nil }
        let source = String(text.dropFirst(lower).prefix(upper - lower + 1))
        return Word(start: lower, text: source, reading: source)
    }

    enum SelectionPart: Int { case end, start, whole }

    func adjusting(_ range: Range<Int>, part: SelectionPart, by delta: Int) -> Word? {
        guard delta == -1 || delta == 1, !range.isEmpty, range.lowerBound >= 0, range.upperBound <= text.count else { return nil }
        let first = range.lowerBound + (part == .end ? 0 : delta)
        let last = range.upperBound - 1 + (part == .start ? 0 : delta)
        guard first <= last else { return nil }
        return selection(from: first, through: last)
    }

    func atEndOfUtterance() -> Self {
        var result = self
        result.caret = text.count
        return result
    }

    func applying(_ edit: Edit, isUndo: Bool) -> Self? {
        guard edit.start >= 0, edit.start <= text.count,
              (isUndo ? edit == undo : !edit.from.isEmpty), text.dropFirst(edit.start).hasPrefix(edit.from) else { return nil }
        var revised = self
        revised.text = text.prefix(edit.start) + edit.to + text.dropFirst(edit.start + edit.from.count)
        revised.caret = edit.start + edit.to.count
        revised.undo = isUndo ? nil : edit.inverse
        return revised
    }
}
