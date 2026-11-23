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
        let singleKanji = [DictionaryEntry(heard: "大", written: "DAI")]
        for (raw, expected) in [("大切な予定です。", "大切な予定です。"), ("大切にします。", "大切にします。"),
                                ("拡大して大成功", "拡大して大成功"), ("大です", "DAIです"), ("大", "DAI"),
                                ("DAI切な予定", "大切な予定")] {
            precondition(TextPipeline.process(raw, entries: singleKanji, removeFillers: false) == expected, raw)
        }
        precondition(TextPipeline.recognitionVocabulary(singleKanji, includingReadings: true).isEmpty)
        precondition(!TextPipeline.acceptsRefinement(original: "大切です", candidate: "DAI切です", dictionary: singleKanji))
        let dai = DictionaryEntry(heard: "だい", written: "DAI")
        for (spoken, expected) in [
            ("だいです", "DAIです"), ("だい", "DAI"), ("だいぶ大切です", "だいぶ大切です"),
            ("だいこん", "だいこん"), ("たいせつ", "たいせつ"), ("だいせつ", "だいせつ"),
            ("DAI切な予定", "大切な予定"), ("だい切にします", "大切にします"),
            ("DAIを切る", "DAIを切る"), ("myDAI切", "myDAI切"), ("DAI切り替え", "DAI切り替え"),
            ("こえのたねのMacのキット版を使ってる人に更新のお知らせを出してよ。", "こえのたねのMacのGit版を使ってる人に更新のお知らせを出してよ。"),
            ("ギット版といっている", "Git版といっている"),
            ("App版とキット版は一緒？", "App版とGit版は一緒？"),
            ("模型のキット版を組み立てる", "模型のキット版を組み立てる"),
            ("アプリで工作キットを注文", "アプリで工作キットを注文"),
            ("Appマンとゲット版は一緒？", "App版とGit版は一緒？"),
            ("Appバンドギフトバンは一緒", "App版とGit版は一緒"),
            ("バックバンドBIGBANGは一緒ですか？", "バックバンドBIGBANGは一緒ですか？"),
            ("App版とギット版", "App版とGit版"), ("ゲットした", "ゲットした"),
            ("別のアプリとゲット版", "別のアプリとゲット版")
        ] {
            precondition(TextPipeline.process(spoken, entries: [dai], removeFillers: false) == expected, spoken)
        }
        precondition(TextPipeline.applyDictionary("DAI切", entries: []) == "DAI切")
        precondition(TextPipeline.applyDictionary("DAI切", entries: [dai, .init(heard: "DAI切", written: "登録表記")]) == "登録表記")
        precondition(TextPipeline.recognitionVocabulary([dai], includingReadings: true).isEmpty)
        precondition(TextPipeline.recognitionVocabulary([dai, .init(heard: "", written: "DAI", kind: .vocabulary)]) == ["DAI"])
        precondition(!TextPipeline.acceptsRefinement(original: "DAIです", candidate: "台です", dictionary: [dai]))
        precondition(!TextPipeline.acceptsRefinement(original: "大切です", candidate: "DAI切です", dictionary: [dai]))
        precondition(!TextPipeline.acceptsRefinement(original: "App版とGit版は一緒？", candidate: "Appマンとゲット版は一緒？"))
        print("PASS: dictionary matching, recognition hints, edition names and refinement")
    }
}
