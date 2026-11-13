import Foundation
import CoreFoundation

@main struct DictionaryImporterTests {
    static func main() throws {
        func parse(_ text: String, _ file: String = "test.txt", _ source: DictionaryImportSource = .atok, _ encoding: String.Encoding = .utf8) throws -> DictionaryImportPreview {
            try DictionaryImporter.parse(data: text.data(using: encoding)!, fileName: file, source: source, existing: [])
        }
        let atok = try parse("!!ATOK_TANGO_TEXT_HEADER_1\nよみ\t単語\t品詞\nぷろんぷとばんく\tPromptBank\t名詞\nえーあい\tAI\t名詞\n")
        precondition(atok.additions.count == 2 && atok.additions[0].heard == "ぷろんぷとばんく")
        let unicode = try parse("かいぎ\t会議\t名詞", "unicode.txt", .atok, .utf16)
        precondition(unicode.additions[0].written == "会議" && unicode.encoding == "UTF-16")
        let cp932 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
        let sjis = try parse("えーあい\t人工知能\t名詞", "sjis.txt", .atok, cp932)
        precondition(sjis.additions[0].written == "人工知能")
        let old = try parse("!!DICUT10\nまさしげ、正成、固有人名\nかいしゃ、ジャストシステム、固有組織")
        precondition(old.additions.count == 2 && old.additions[0].heard == "まさしげ")
        let words = try parse("[\"PromptBank\",\"Hacker News\",\"#general\"]", "words.json", .aquaWords)
        precondition(words.additions.count == 3 && words.additions.allSatisfy(\.isVocabulary))
        let root = try parse("{\"dictionary\":[\"PromptBank\"],\"replacements\":[{\"from\":\"ぷろんぷと\",\"to\":\"PromptBank\"}]}", "all.json", .generic)
        precondition(root.additions.count == 2 && root.additions.filter(\.isVocabulary).count == 1)
        let pairs = try parse("[{\"from\":\"ぷろんぷと\",\"to\":\"PromptBank\"}]", "pairs.json", .aquaReplacements)
        precondition(pairs.additions[0].written == "PromptBank" && !pairs.additions[0].isVocabulary)
        let csv = try parse("from,to\r\n\"えーしーえむいー\",\"ACME, Inc.\"\r\n\"しょめい\",\"一行目\n\n# 二行目\"", "pairs.csv", .aquaReplacements)
        precondition(csv.additions.count == 2 && csv.additions[0].written == "ACME, Inc." && csv.additions[1].written == "一行目\n\n# 二行目")
        let quotes = try parse("from,to\n\"くおーと\",\"He said \"\"Hello\"\"\"", "quote.csv", .generic)
        precondition(quotes.additions[0].written == "He said \"Hello\"")
        let plainWords = try parse("# 説明\nPromptBank\nACME, Inc.\n#general\n[TODO]", "words.txt", .aquaWords)
        precondition(plainWords.additions.map(\.written) == ["PromptBank", "ACME, Inc.", "#general", "[TODO]"])
        let columnWords = try parse("word\n\"ACME, Inc.\"\nPromptBank", "words.csv", .aquaWords)
        precondition(columnWords.additions.count == 2 && columnWords.additions[0].written == "ACME, Inc.")
        let tsv = try parse("from\tto\nぷろんぷと\tPromptBank", "pairs.tsv", .aquaReplacements)
        precondition(tsv.additions.count == 1 && tsv.additions[0].heard == "ぷろんぷと")
        let dup = try parse("a\tA\na\tA")
        precondition(dup.additions.count == 1 && dup.duplicates == 1)
        let ambiguous = try parse("はし\t橋\nはし\t箸")
        precondition(ambiguous.additions.count == 2 && ambiguous.additions.allSatisfy(\.isVocabulary) && ambiguous.conflicts == 2)
        let existing = DictionaryEntry(heard: "はし", written: "橋")
        let conflict = DictionaryImporter.plan(candidates: [DictionaryEntry(heard: "はし", written: "箸")], existing: [existing])
        precondition(conflict.additions[0].isVocabulary && conflict.conflicts == 1 && existing.written == "橋")
        let vocabDups = try parse("[\"PromptBank\",\"promptbank\"]", "words.json", .aquaWords)
        precondition(vocabDups.additions.count == 1 && vocabDups.duplicates == 1)
        let noCascade = TextPipeline.applyDictionary("PromptBank", entries: words.additions)
        precondition(noCascade == "PromptBank", "Vocabulary is recognition context, never an automatic replacement")
        let original = [DictionaryEntry(heard: "たね", written: "種")]
        let oldJSON = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([DictionaryEntry].self, from: oldJSON)
        precondition(decoded[0].kind == nil && decoded[0].heard == "たね", "Existing saved dictionaries keep working")
        let bom = try parse("\u{FEFF}えーあい\tAI")
        precondition(bom.additions[0].heard == "えーあい")
        let noBom = try parse("かいぎ\t会議", "no-bom.txt", .atok, .utf16LittleEndian)
        precondition(noBom.additions[0].written == "会議")
        func mustReject(_ label: String, _ body: () throws -> Void) {
            do { try body(); fatalError("Expected rejection: \(label)") } catch { }
        }
        mustReject("invalid JSON") { _ = try parse("{invalid", "broken.json", .generic) }
        mustReject("unclosed quote") { _ = try parse("from,to\na,\"unclosed", "broken.csv", .generic) }
        mustReject("empty dictionary") { _ = try parse("# comment only\n!!HEADER") }
        mustReject("size limit") { _ = try DictionaryImporter.parse(data: Data(repeating: 65, count: DictionaryImporter.maximumBytes + 1), fileName: "large.txt", source: .generic, existing: []) }
        mustReject("entry limit") { _ = try parse((0...DictionaryImporter.maximumEntries).map { "word\($0)" }.joined(separator: "\n"), "large.txt", .aquaWords) }
        print("PASS: 25 dictionary import format, encoding, merge and validation checks")
    }
}
