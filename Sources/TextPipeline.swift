import Foundation

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
    private static let fillerPattern = try! NSRegularExpression(pattern:
        #"(?:え[ー〜～]+っ?と|えっと)(?:(?:ですね|ね|さ|な)?(?=$|[\s、，,。．.])[ \t]*(?:[、，,。．.][ \t]*)?)?"#
        + #"|(?:ええっ?と|え[ー〜～]+|あの[ー〜～]+|ん[ー〜～]+|う[ー〜～]+ん)(?:ですね|ね)?(?=$|[\s、，,。．.])[ \t]*(?:[、，,。．.][ \t]*)?"#
        + #"|(?<![^\s、，,。．.])(?:あ[ー〜～]+|その[ー〜～]+|ま[ー〜～]+)(?:ですね|ね)?(?=$|[\s、，,。．.])[ \t]*(?:[、，,。．.][ \t]*)?"#
        + #"|(?<![^\s、，,。．.])あの(?=[ \t]*[、，,])[ \t]*[、，,][ \t]*"#
        + #"|(?<=[。．.！？!?][ \t\n]{0,2})ええ[。．.][ \t]*"#)

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

    // A single pass prevents one replacement from being replaced again by another entry.
    static func applyDictionary(_ text: String, entries: [DictionaryEntry]) -> String {
        let entries = entries.filter { !$0.isVocabulary && !$0.heard.isEmpty && !$0.written.isEmpty }
            .sorted { $0.heard.count > $1.heard.count }
        let byFirstCharacter = Dictionary(grouping: entries, by: { $0.heard.first! })
        var result = ""
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if let entry = byFirstCharacter[text[cursor]]?.first(where: { text[cursor...].hasPrefix($0.heard) }) {
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
    static func acceptsRefinement(original: String, candidate: String) -> Bool {
        let candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate.count >= max(1, original.count / 2),
              candidate.count <= max(30, original.count * 2) else { return false }
        let regex = try! NSRegularExpression(pattern: "[+＋−-]?[0-9０-９]+(?:[.,．，][0-9０-９]+)*")
        func numbers(_ string: String) -> [String] {
            regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
                .compactMap { Range($0.range, in: string).map { String(string[$0]) } }.sorted()
        }
        return numbers(original) == numbers(candidate)
    }
}
