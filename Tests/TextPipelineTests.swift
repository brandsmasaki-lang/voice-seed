import Foundation

@main struct TextPipelineTests {
    static func main() {
        let entries = [DictionaryEntry(heard: "たね", written: "種"), DictionaryEntry(heard: "AIのたね", written: "AIのたね本部"), DictionaryEntry(heard: "種", written: "SEED")]
        precondition(TextPipeline.applyDictionary(" AIのたねとたね ", entries: entries) == "AIのたね本部と種", "Prefer longest matches and do not cascade replacements")
        precondition(TextPipeline.applyDictionary("ぷろんぷとばんくを使います", entries: [.init(heard: "ぷろんぷとばんく", written: "PromptBank")]) == "PromptBankを使います")
        precondition(TextPipeline.applyDictionary("👩‍💻音声入力", entries: [.init(heard: "", written: "無効")]) == "👩‍💻音声入力", "Empty entries must not loop; preserve graphemes")
        precondition(TextPipeline.acceptsRefinement(original: "明日は15時に3名で伺います", candidate: "明日は15時に、3名で伺います。"))
        precondition(!TextPipeline.acceptsRefinement(original: "明日は15時に3名で伺います", candidate: "明日は16時に、3名で伺います。"), "Do not silently alter numbers")
        precondition(!TextPipeline.acceptsRefinement(original: "長い話も省略せずにそのまま文章として残してください。", candidate: "了解です"), "Reject obvious truncation")
        precondition(!TextPipeline.acceptsRefinement(original: "こんにちは", candidate: ""))
        precondition(!TextPipeline.acceptsRefinement(original: "気温は15度です", candidate: "気温は-15度です。"), "Preserve numeric signs")
        print("PASS: 8 text pipeline checks")
    }
}
