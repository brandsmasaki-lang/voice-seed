import Foundation

struct BenchmarkPhrase: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var text: String
    var label: String
    static let corpus: [Self] = [
        .init(id: "basic", text: "明日の打ち合わせは午後3時からです。", label: "短文・数字"),
        .init(id: "negative", text: "この資料は送らず、来週まで待ってください。", label: "否定・依頼"),
        .init(id: "amount", text: "見積金額は税込12,800円、数量は3個です。", label: "金額・数量"),
        .init(id: "products", text: "こえのたねとPromptBankを使って、毎日の作業を進めます。", label: "製品名・辞書"),
        .init(id: "homophone", text: "口座への入金と、講座への申し込みを確認してください。", label: "同音異義語"),
        .init(id: "long", text: "先ほど共有した資料の2ページ目を確認して、修正した内容を明日の午前10時までに教えてください。", label: "長文・期限"),
        .init(id: "quote", text: "「えっと」と書いてある部分は、そのまま残してください。", label: "引用の保護"),
        .init(id: "filler", text: "明日の会議は15時です。資料は3部用意してください。", label: "冒頭に「えー、えっと、」を加えて読む")
    ]
}

struct BenchmarkResult: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var phraseID: String
    var reference: String
    var recognized: String
    var finalText: String
    var rawCharacterErrorRate: Double
    var finalCharacterErrorRate: Double
    var metrics: DictationMetrics
    var date: Date
}

enum TextAccuracy {
    static func characterErrorRate(reference: String, candidate: String) -> Double {
        func normalized(_ value: String) -> [Character] {
            Array(value.precomposedStringWithCanonicalMapping.filter { !$0.isWhitespace })
        }
        let expected = normalized(reference), actual = normalized(candidate)
        guard !expected.isEmpty else { return actual.isEmpty ? 0 : 1 }
        var previous = Array(0...actual.count)
        for (i, character) in expected.enumerated() {
            var row = [i + 1]
            for (j, other) in actual.enumerated() {
                row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (character == other ? 0 : 1)))
            }
            previous = row
        }
        return Double(previous.last!) / Double(expected.count)
    }
}
