import Foundation

@main struct FillerCleanupTests {
    static func main() {
        let cases: [(String, String)] = [
            ("えー、えっと、明日は15時に3名で伺います。", "明日は15時に3名で伺います。"),
            ("あのー、資料を送ってください。", "資料を送ってください。"),
            ("ええと、資料を送ってください。", "資料を送ってください。"),
            ("明日は、えーっと、15時です。", "明日は、15時です。"),
            ("あの、あの店で会いましょう。", "あの店で会いましょう。"),
            ("あの店で、その案を相談します。", "あの店で、その案を相談します。"),
            ("ええ、賛成です。", "ええ、賛成です。"),
            ("えー！本当ですか？", "えー！本当ですか？"),
            ("はい、そうですね。ちょっと考えます。", "はい、そうですね。ちょっと考えます。"),
            ("来年のえと、教えてください。", "来年のえと、教えてください。"),
            ("「えっと、明日です」と言いました。", "「えっと、明日です」と言いました。"),
            ("えー、「あのー、えっと、」が口癖です。", "「あのー、えっと、」が口癖です。"),
            ("『「えー、」を除く』という文です。", "『「えー、」を除く』という文です。"),
            ("えっと、\"えー、\"と書いてください。", "\"えー、\"と書いてください。"),
            ("えー、\n明日は延期しません。", "明日は延期しません。"),
            ("うーん、反対です。んー、やめましょう。", "反対です。やめましょう。"),
            ("えっと。今日は金曜日です。", "今日は金曜日です。"),
            ("えー、", ""),
            ("👩‍💻えー、仕事をします。", "👩‍💻仕事をします。"),
            ("「えー、閉じない引用", "「えー、閉じない引用")
        ]
        for (input, expected) in cases {
            let output = TextPipeline.removeFillers(input)
            precondition(output == expected, "\(input) -> \(output), expected \(expected)")
        }
        precondition(TextPipeline.process("えー、明日", entries: [], removeFillers: false) == "えー、明日", "Raw mode is preserved")
        precondition(TextPipeline.process("えっと、明日", entries: [.init(heard: "えっと", written: "ETTO")], removeFillers: true) == "ETTO、明日", "Explicit user dictionary entries have priority")
        precondition(TextPipeline.process("えー、ぷろんぷとばんくを使います", entries: [.init(heard: "ぷろんぷとばんく", written: "PromptBank")], removeFillers: true) == "PromptBankを使います")
        let sample = String(repeating: "えー、えっと、明日は15時に3名で伺います。「あのー」は引用です。", count: 10)
        _ = TextPipeline.removeFillers(sample)
        let start = Date()
        for _ in 0..<100 { _ = TextPipeline.removeFillers(sample) }
        print("PASS: 23 filler cleanup and meaning-preservation checks")
        print(String(format: "Filler cleanup: %.3f ms per %d-character sample (100 iterations)", Date().timeIntervalSince(start) * 10, sample.count))
    }
}
