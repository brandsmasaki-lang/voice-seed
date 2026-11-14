import Foundation

struct DictionaryEntry: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case vocabulary }
    var id = UUID()
    var heard: String
    var written: String
    var kind: Kind? = nil
    var isVocabulary: Bool { kind == .vocabulary }
}

enum TextPipeline {
    private static let fillerPattern = try! NSRegularExpression(pattern:
        #"(?:え(?:[ー〜～]+っ?と|っと)|ええっ?と|え[ー〜～]+|あの[ー〜～]+|ん[ー〜～]+|う[ー〜～]+ん)(?=$|[\s、，,。．.])[ \t]*(?:[、，,。．.][ \t]*)?|(?<![^\s、，,。．.])あの(?=[ \t]*[、，,])[ \t]*[、，,][ \t]*"#)

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
