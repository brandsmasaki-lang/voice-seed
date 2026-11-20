import Foundation
import CoreFoundation

enum DictionaryImportSource: String, CaseIterable, Identifiable, Sendable {
    case atok = "ATOK"
    case aquaWords = "Aqua Voiceの単語辞書"
    case aquaReplacements = "Aqua Voiceの置換辞書"
    case generic = "CSV / TSV / JSON"
    var id: String { rawValue }
}

struct DictionaryImportPreview: Identifiable, Sendable {
    let id = UUID()
    var fileName: String
    var encoding: String
    var candidates: [DictionaryEntry]
    var additions: [DictionaryEntry]
    var duplicates: Int
    var conflicts: Int
    var skipped: Int
    var warnings: [String]
}

enum DictionaryImportError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

enum DictionaryImporter {
    static let maximumBytes = 10 * 1024 * 1024
    static let maximumEntries = 50_000

    static func read(url: URL, source: DictionaryImportSource, existing: [DictionaryEntry]) throws -> DictionaryImportPreview {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumBytes else { throw DictionaryImportError.invalid("辞書ファイルは10MB以下にしてください。") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try parse(data: data, fileName: url.lastPathComponent, source: source, existing: existing)
    }

    static func parse(data: Data, fileName: String, source: DictionaryImportSource, existing: [DictionaryEntry]) throws -> DictionaryImportPreview {
        guard data.count <= maximumBytes else { throw DictionaryImportError.invalid("辞書ファイルは10MB以下にしてください。") }
        let (text, encoding) = try decode(data)
        var candidates: [DictionaryEntry] = []
        var skipped = 0
        var warnings: [String] = []
        func add(heard: String?, written: String?) {
            let written = written?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let heard = heard?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !written.isEmpty, written.count <= 4096,
                  heard == nil || (!(heard?.isEmpty ?? true) && heard!.count <= 1024) else { skipped += 1; return }
            candidates.append(DictionaryEntry(heard: heard ?? "", written: written, kind: heard == nil ? .vocabulary : nil))
        }

        if fileName.lowercased().hasSuffix(".json") {
            guard let utf8 = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: utf8) else {
                throw DictionaryImportError.invalid("JSONの形式を読み取れませんでした。書き出した辞書ファイルを選んでください。")
            }
            func readList(_ list: [Any], wordsOnly: Bool = false) {
                for item in list {
                    if let word = item as? String { add(heard: nil, written: word) }
                    else if let row = item as? [String: Any] {
                        if let from = row["from"] as? String, let to = row["to"] as? String, !wordsOnly { add(heard: from, written: to) }
                        else if let heard = row["heard"] as? String, let written = row["written"] as? String, !wordsOnly {
                            add(heard: (row["kind"] as? String) == "vocabulary" ? nil : heard, written: written)
                        } else if let word = (row["word"] ?? row["term"]) as? String { add(heard: nil, written: word) }
                        else { skipped += 1 }
                    } else { skipped += 1 }
                }
            }
            if let list = object as? [Any] { readList(list, wordsOnly: source == .aquaWords) }
            else if let root = object as? [String: Any] {
                var found = false
                if let words = (root["dictionary"] ?? root["words"]) as? [Any], source != .aquaReplacements {
                    found = true; readList(words, wordsOnly: true)
                }
                if let pairs = root["replacements"] as? [Any], source != .aquaWords {
                    found = true; readList(pairs)
                }
                if let list = root["entries"] as? [Any], source == .generic { found = true; readList(list) }
                guard found else { throw DictionaryImportError.invalid("単語または置換の配列が見つかりません。単語辞書はdictionary/words、置換辞書はreplacements、または配列形式に対応しています。") }
            } else { throw DictionaryImportError.invalid("このJSONは辞書形式ではありません。") }
        } else {
            let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            let contentLines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                .filter { line in
                    let line = line.trimmingCharacters(in: .whitespaces)
                    return !line.isEmpty && !line.hasPrefix("!!") && line != "#" && !line.hasPrefix("# ") && !line.hasPrefix("//")
                }
            let firstLine = contentLines.first ?? ""
            let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
            let delimiter: Character? = ext == "csv" ? "," : ext == "tsv" ? "\t" : firstLine.contains("\t") ? "\t" : firstLine.contains(",") ? "," : source == .atok && firstLine.contains("、") ? "、" : source == .atok && firstLine.contains("，") ? "，" : nil
            // Aqua word TXT is one term per physical line, even when a term contains a comma.
            let plainAquaWords = source == .aquaWords && fileName.lowercased().hasSuffix(".txt")
            let rows = try (plainAquaWords || delimiter == nil) ? contentLines.map { [$0] } : delimitedRows(normalized, delimiter: delimiter!)
            var firstDataRow = true
            for row in rows {
                let first = row.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let second = row.count > 1 ? row[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                if first.isEmpty && row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
                if first.hasPrefix("!!") || first == "#" || first.hasPrefix("# ") || first.hasPrefix("//") { continue }
                if firstDataRow {
                    firstDataRow = false
                    let headers = ["from", "heard", "reading", "読み", "よみ", "読みがな", "認識される言葉"]
                    let targets = ["to", "written", "word", "単語", "表記", "正しい表記"]
                    if row.count > 1 && headers.contains(first.lowercased()) && targets.contains(second.lowercased()) { continue }
                    if (source == .aquaWords || row.count == 1) && ["word", "words", "term", "単語"].contains(first.lowercased()) { continue }
                }
                if source == .aquaWords { add(heard: nil, written: first) }
                else if row.count >= 2 { add(heard: first, written: second) }
                else if source == .generic { add(heard: nil, written: first) }
                else { skipped += 1 }
            }
        }
        guard candidates.count <= maximumEntries else { throw DictionaryImportError.invalid("1回に取り込めるのは50,000件までです。ファイルを分けてください。") }
        guard !candidates.isEmpty else { throw DictionaryImportError.invalid("取り込める単語がありませんでした。ファイル形式と「読み・表記」の列を確認してください。") }
        if skipped > 0 { warnings.append("空欄や形式の合わない行を\(skipped)件除外しました。") }
        return plan(candidates: candidates, existing: existing, fileName: fileName, encoding: encoding, skipped: skipped, warnings: warnings)
    }

    static func plan(candidates: [DictionaryEntry], existing: [DictionaryEntry], fileName: String = "", encoding: String = "", skipped: Int = 0, warnings: [String] = []) -> DictionaryImportPreview {
        var duplicates = 0, conflicts = 0
        var warnings = warnings
        var additions: [DictionaryEntry] = []
        func canonical(_ value: String) -> String { value.precomposedStringWithCanonicalMapping }
        let groups = Dictionary(grouping: candidates.filter { !$0.isVocabulary }, by: { canonical($0.heard) })
        let ambiguous = Set(groups.filter { Set($0.value.map { canonical($0.written) }).count > 1 }.keys)
        var existingReadings: [String: String] = [:]
        var vocabulary = Set(existing.filter(\.isVocabulary).map { canonical($0.written).lowercased() })
        for entry in existing where !entry.isVocabulary { existingReadings[canonical(entry.heard)] = canonical(entry.written) }
        var exact = Set(existing.map { "\($0.isVocabulary ? "v" : "r")\u{0}\(canonical($0.heard))\u{0}\(canonical($0.written))" })
        for candidate in candidates {
            var entry = candidate
            let heard = canonical(entry.heard), written = canonical(entry.written)
            if !entry.isVocabulary && (ambiguous.contains(heard) || existingReadings[heard].map { $0 != written } == true) {
                conflicts += 1
                // Ambiguous ATOK readings still help recognition; never choose an arbitrary replacement.
                entry.heard = ""; entry.kind = .vocabulary
            }
            if entry.isVocabulary {
                guard vocabulary.insert(written.lowercased()).inserted else { duplicates += 1; continue }
            }
            let key = "\(entry.isVocabulary ? "v" : "r")\u{0}\(canonical(entry.heard))\u{0}\(written)"
            guard exact.insert(key).inserted else { duplicates += 1; continue }
            if !entry.isVocabulary { existingReadings[heard] = written }
            additions.append(entry)
        }
        if conflicts > 0 { warnings.append("同じ読みで表記が異なる\(conflicts)件は、置換せず認識ヒントとして扱います。既存の置換は変更しません。") }
        return DictionaryImportPreview(fileName: fileName, encoding: encoding, candidates: candidates, additions: additions,
                                       duplicates: duplicates, conflicts: conflicts, skipped: skipped, warnings: warnings)
    }

    private static func decode(_ data: Data) throws -> (String, String) {
        let bytes = Array(data.prefix(3))
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            if let text = String(data: data, encoding: .utf16) { return (text, "UTF-16") }
        }
        if let text = String(data: data, encoding: .utf8), !text.contains("\0") {
            return (text.replacingOccurrences(of: "\u{FEFF}", with: ""), "UTF-8")
        }
        // Some ATOK exports have UTF-16 without a BOM.
        if data.contains(0), let text = String(data: data, encoding: .utf16LittleEndian), !text.contains("\0") {
            return (text, "UTF-16 LE")
        }
        let cp932 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue))
        if let text = String(data: data, encoding: String.Encoding(rawValue: cp932)), !text.contains("\0") { return (text, "Shift JIS / CP932") }
        if let text = String(data: data, encoding: .shiftJIS), !text.contains("\0") { return (text, "Shift JIS") }
        throw DictionaryImportError.invalid("文字コードを読み取れません。UTF-8・UTF-16・Shift JISで書き出してください。バイナリの.dicファイルは使えません。")
    }

    /// CSV/TSV with quoted delimiters, doubled quotes, CRLF and embedded newlines.
    private static func delimitedRows(_ text: String, delimiter: Character) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = []
        var field = "", quoted = false, closedQuote = false
        var cursor = text.startIndex
        while cursor < text.endIndex {
            let char = text[cursor]
            let next = text.index(after: cursor)
            if quoted {
                if char == "\"" {
                    if next < text.endIndex, text[next] == "\"" { field.append("\""); cursor = text.index(after: next); continue }
                    quoted = false; closedQuote = true
                } else { field.append(char) }
            } else if char == delimiter { row.append(field); field = ""; closedQuote = false }
            else if char == "\n" { row.append(field); rows.append(row); row = []; field = ""; closedQuote = false }
            else if char == "\"", field.isEmpty, !closedQuote { quoted = true }
            else if closedQuote && char != " " { throw DictionaryImportError.invalid("CSVの引用符の後に不正な文字があります。書き出したファイルを確認してください。") }
            else if !closedQuote { field.append(char) }
            cursor = next
        }
        guard !quoted else { throw DictionaryImportError.invalid("CSVの引用符が閉じていません。書き出したファイルを確認してください。") }
        if !field.isEmpty || !row.isEmpty || closedQuote { row.append(field); rows.append(row) }
        return rows
    }
}
