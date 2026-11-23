import Foundation
import NaturalLanguage

struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case vocabulary }
    var id = UUID()
    var heard: String
    var written: String
    var kind: Kind? = nil
    var isVocabulary: Bool { kind == .vocabulary }
}

/// Registers one correction made while looking at a recognition result.
enum DictionaryCorrection {
    enum Outcome: Equatable { case addedHint, addedReplacement, updatedReplacement, duplicate, invalid }

    /// An empty `heard` (or one equal to `written`) registers a recognition hint.
    /// Otherwise it registers a replacement; an existing replacement for the same `heard` is updated.
    static func apply(heard: String, written: String, to entries: inout [DictionaryEntry]) -> Outcome {
        let heard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let written = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty, written.count <= 4096, heard.count <= 1024 else { return .invalid }
        if heard.isEmpty || heard == written {
            guard !entries.contains(where: { $0.isVocabulary && $0.written.lowercased() == written.lowercased() }) else { return .duplicate }
            entries.append(DictionaryEntry(heard: "", written: written, kind: .vocabulary))
            return .addedHint
        }
        if let index = entries.firstIndex(where: { !$0.isVocabulary && $0.heard == heard }) {
            guard entries[index].written != written else { return .duplicate }
            entries[index].written = written
            return .updatedReplacement
        }
        entries.append(DictionaryEntry(heard: heard, written: written))
        return .addedReplacement
    }

    /// A file both the Mac and iPhone apps can import through "CSV / TSV / JSON".
    static func exportData(_ entries: [DictionaryEntry]) throws -> Data {
        let rows = entries.map { entry -> [String: String] in
            entry.isVocabulary ? ["heard": "", "written": entry.written, "kind": "vocabulary"]
                               : ["heard": entry.heard, "written": entry.written]
        }
        return try JSONSerialization.data(withJSONObject: ["entries": rows], options: [.prettyPrinted, .sortedKeys])
    }
}

enum TextPipeline {
    // 1. えーっと / えっと are never content, so they go even without punctuation after them
    //    ("えーっとこの件"), together with a trailing ね / ですね / さ / な when punctuation follows.
    // 2. Other drawn-out sounds need punctuation, a space or the end after them, so that
    //    "えー！" and "ええ、賛成です" stay.
    // 3. あー / そのー / まー also need a boundary before them, so "じゃあー、" stays.
    // 4. A bare あの counts only as "あの、" at the start of a phrase.
    // 5. "ええ。" standing alone between sentences is a drawn-out "えー" as the recognizer writes it.
    //    At the very start, or as "ええ、…", it is an answer and stays.
    // 6. A single "え" at the start of a phrase, glued to katakana, kanji or Latin letters
    //    ("えファンクション"), is a hesitation. "え？", "え、" and words such as "えび" stay.
    private static let fillerPattern = try! NSRegularExpression(pattern:
        #"(?:え[ー〜～]+っ?と|えっと)(?:(?:ですね|ね|さ|な)?(?=$|[\s、，,。．.])[ \t]*(?:[、，,。．.][ \t]*)?)?"#
        + #"|(?:ええっ?と|え[ー〜～]+|あの[ー〜～]+|ん[ー〜～]+|う[ー〜～]+ん)(?:ですね|ね)?(?=$|[\s、，,。．.])[ \t]*(?:[、，,。．.][ \t]*)?"#
        + #"|(?<![^\s、，,。．.])(?:あ[ー〜～]+|その[ー〜～]+|ま[ー〜～]+)(?:ですね|ね)?(?=$|[\s、，,。．.])[ \t]*(?:[、，,。．.][ \t]*)?"#
        + #"|(?<![^\s、，,。．.])あの(?=[ \t]*[、，,])[ \t]*[、，,][ \t]*"#
        + #"|(?<=[。．.！？!?][ \t\n]{0,2})ええ[。．.][ \t]*"#
        + #"|(?<![^\s、，,。．.！？!?])え(?=[\p{Katakana}\p{Han}A-Za-zＡ-Ｚａ-ｚ])"#)

    /// Conservative, local cleanup. Quoted words, affirmations and meaningful modifiers stay.
    static func removeFillers(_ text: String, preserving terms: Set<String> = []) -> String {
        let quotePairs: [Character: Character] = ["「": "」", "『": "』", "“": "”", "\"": "\""]
        var output = "", plain = "", quoted = ""
        var closers: [Character] = []
        func clean(_ fragment: String) -> String {
            var result = fragment
            let range = NSRange(fragment.startIndex..., in: fragment)
            for match in fillerPattern.matches(in: fragment, range: range).reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let word = String(result[range]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "、，,。．.")))
                if !terms.contains(word) { result.removeSubrange(range) }
            }
            return result
        }
        for character in text {
            if closers.isEmpty {
                if let closer = quotePairs[character] {
                    output += clean(plain); plain = ""
                    quoted.append(character); closers.append(closer)
                } else { plain.append(character) }
            } else {
                quoted.append(character)
                if character == closers.last {
                    closers.removeLast()
                    if closers.isEmpty { output += quoted; quoted = "" }
                } else if let closer = quotePairs[character] { closers.append(closer) }
            }
        }
        return (output + quoted + clean(plain)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func process(_ text: String, entries: [DictionaryEntry], removeFillers: Bool) -> String {
        let protected = Set(entries.flatMap { [$0.heard, $0.written] }.filter { !$0.isEmpty })
        let cleaned = removeFillers ? Self.removeFillers(text, preserving: protected) : text
        return applyDictionary(cleaned, entries: entries)
    }

    private static func isIdeograph(_ character: Character?) -> Bool {
        character?.unicodeScalars.first?.properties.isIdeographic == true
    }

    private static func needsWordBoundary(_ reading: String) -> Bool {
        if reading.count == 1 && isIdeograph(reading.first) { return true }
        return !reading.isEmpty && reading.count <= 2 && reading.unicodeScalars.allSatisfy {
            (0x3041...0x3096).contains($0.value) || (0x30A1...0x30FA).contains($0.value) || $0.value == 0x30FC
        }
    }

    private static func isDaiShortcut(_ entry: DictionaryEntry) -> Bool {
        !entry.isVocabulary && entry.written == "DAI" && ["だい", "ダイ", "大"].contains(entry.heard)
    }

    // A short abbreviation is useful as a written correction, but biasing the
    // acoustic model with its spelling can turn an unrelated word into that name.
    static func recognitionVocabulary(_ entries: [DictionaryEntry], includingReadings: Bool = false) -> [String] {
        var hints = Set<String>()
        for entry in entries where entry.isVocabulary || !needsWordBoundary(entry.heard) {
            hints.insert(entry.written)
            if includingReadings { hints.insert(entry.heard) }
        }
        hints.remove("")
        return hints.sorted()
    }

    // Restrict sound-alike corrections to the reported mixed-script phrases.
    private static let editionPair = try! NSRegularExpression(
        pattern: #"(?i)(?<![a-z0-9_])(?:(?:Appマン|アップマン|App版|アップ版)と(?:ゲット|ギット|Git)版|Appバンドギフトバン(?=は(?:一緒|同じ)))"#)
    private static let taisetsu = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_])(?:DAI|だい|ダイ)切(?=$|[\s、。！？!?」』]|[なにさでだ])"#)

    // Match against the original text so the output of a correction is never replaced again.
    static func applyDictionary(_ text: String, entries: [DictionaryEntry]) -> String {
        let entries = entries.filter { !$0.isVocabulary && !$0.heard.isEmpty && !$0.written.isEmpty }
            .sorted { $0.heard.count > $1.heard.count }
        var repairs: [String.Index: (end: String.Index, written: String)] = [:]
        func collect(_ expression: NSRegularExpression, replacement: String) {
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text), text[range] != replacement {
                    repairs[range.lowerBound] = (range.upperBound, replacement)
                }
            }
        }
        if text.contains("版") || text.contains("ギフトバン") { collect(editionPair, replacement: "App版とGit版") }
        if text.contains("切"), entries.contains(where: isDaiShortcut) {
            collect(taisetsu, replacement: "大切")
        }
        var boundaries: Set<String.Index>?
        func isWordRange(_ range: Range<String.Index>) -> Bool {
            if boundaries == nil {
                let tokenizer = NLTokenizer(unit: .word)
                tokenizer.setLanguage(.japanese)
                tokenizer.string = text
                var edges: Set<String.Index> = [text.startIndex, text.endIndex]
                tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { token, _ in
                    edges.insert(token.lowerBound)
                    edges.insert(token.upperBound)
                    return true
                }
                boundaries = edges
            }
            return boundaries!.contains(range.lowerBound) && boundaries!.contains(range.upperBound)
        }
        let byFirstCharacter = Dictionary(grouping: entries, by: { $0.heard.first! })
        var result = ""
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let entry = byFirstCharacter[text[cursor]]?.first(where: { entry in
                guard text[cursor...].hasPrefix(entry.heard) else { return false }
                guard needsWordBoundary(entry.heard) else { return true }
                let end = text.index(cursor, offsetBy: entry.heard.count)
                // A tokenizer can split a kanji prefix or suffix within one compound.
                if entry.heard.count == 1, isIdeograph(entry.heard.first),
                   isIdeograph(text[..<cursor].last) || isIdeograph(text[end...].first) { return false }
                // Japanese tokenizers may split a misheard "だいせつ" into "だい" and "せつ".
                if ["だい", "ダイ"].contains(entry.heard) && entry.written == "DAI" && (text[end...].hasPrefix("せつ") || text[end...].hasPrefix("セツ")) { return false }
                return isWordRange(cursor..<end)
            })
            if let repair = repairs[cursor], entry.map({ text.index(cursor, offsetBy: $0.heard.count) >= repair.end }) != true {
                result += repair.written
                cursor = repair.end
            } else if let entry {
                result += entry.written
                cursor = text.index(cursor, offsetBy: entry.heard.count)
            } else {
                result.append(text[cursor])
                cursor = text.index(after: cursor)
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Reject conspicuous truncation, expansion, or altered numeric facts after LLM editing.
    // This is a guard, not a guarantee of semantic equivalence; the original stays visible.
    static func acceptsRefinement(original: String, candidate: String, dictionary: [DictionaryEntry] = []) -> Bool {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate.count >= max(1, original.count / 2),
              candidate.count <= max(30, original.count * 2) else { return false }
        let regex = try! NSRegularExpression(pattern: "[+＋−-]?[0-9０-９]+(?:[.,．，][0-9０-９]+)*")
        func numbers(_ string: String) -> [String] {
            regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
                .compactMap { Range($0.range, in: string).map { String(string[$0]) } }.sorted()
        }
        guard numbers(original) == numbers(candidate) else { return false }

        // The original already contains the one-pass dictionary replacements. Reapplying
        // them to the model output would allow chained replacements and miss paraphrases.
        var protected = Set(dictionary.map(\.written))
        protected.insert("App版とGit版")
        if dictionary.contains(where: isDaiShortcut) {
            protected.insert("大切")
        }
        for term in protected where !term.isEmpty && original.contains(term) {
            if original.ranges(of: term).count != candidate.ranges(of: term).count { return false }
        }
        return true
    }
}
