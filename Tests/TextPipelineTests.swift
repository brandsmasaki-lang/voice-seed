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
        var list: [DictionaryEntry] = []
        precondition(DictionaryCorrection.apply(heard: "", written: "Aqua Voice", to: &list) == .addedHint && list[0].isVocabulary)
        precondition(DictionaryCorrection.apply(heard: " ", written: "aqua voice", to: &list) == .duplicate && list.count == 1, "Hints are not duplicated")
        precondition(DictionaryCorrection.apply(heard: "アクアボイスト", written: "Aqua Voiceと", to: &list) == .addedReplacement)
        precondition(TextPipeline.applyDictionary("アクアボイストの差", entries: list) == "Aqua Voiceとの差", "A registered correction fixes the same mistake next time")
        precondition(DictionaryCorrection.apply(heard: "アクアボイスト", written: "AquaVoiceと", to: &list) == .updatedReplacement && list.count == 2, "Re-registering a mistake updates it")
        precondition(DictionaryCorrection.apply(heard: "アクアボイスト", written: "AquaVoiceと", to: &list) == .duplicate)
        precondition(DictionaryCorrection.apply(heard: "何か", written: "  ", to: &list) == .invalid && list.count == 2)
        let exported = try! JSONSerialization.jsonObject(with: DictionaryCorrection.exportData(list)) as! [String: [[String: String]]]
        precondition(exported["entries"]!.count == 2 && exported["entries"]!.contains { $0["kind"] == "vocabulary" && $0["written"] == "Aqua Voice" }, "Export keeps hints and replacements apart")
        print("PASS: 16 text pipeline checks")
    }
}
