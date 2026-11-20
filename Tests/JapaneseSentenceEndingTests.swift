import Foundation
@main struct JapaneseSentenceEndingTests {
    static func main() {
        for text in ["GitHubに保存します", "明日は午後3時です", "そこは直してよ", "これはできない", "丸がつかないね", "2回成功してるね", "今はできないよね", "着いたね", "駅に着いた", "今日は歩いたよ", "そこまで泳いだね", "話せたね", "全部終わったね", "保存した", "ちゃんと見られたよ", "さっき読んだ", "できたね"] {
            precondition(JapaneseSentenceEnding.complete(text) == text + "。")
        }
        for text in ["来られる？", "保存します。", "やった！", "GitHub", "https://github.com", "a.b", "それは", "ほら", "直してほしいけど", "「保存します」", ""] {
            precondition(JapaneseSentenceEnding.complete(text) == text)
        }
        print("PASS: completed sentence endings, existing punctuation, fragments and identifiers")
    }
}
