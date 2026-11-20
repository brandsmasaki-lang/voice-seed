import XCTest
@testable import VoiceSeedCore

final class JapaneseSentenceEndingTests: XCTestCase {
    func testReportedConversationalEndings() {
        for text in ["GitHubに保存します", "丸がつかないね", "成功してるね", "着いたね", "駅に着いた", "全部終わったね", "できたね", "今日は歩いたよ", "読んだ", "直してよ"] {
            XCTAssertEqual(JapaneseSentenceEnding.complete(text), text + "。")
        }
    }
    func testPreservePunctuationAndIncompleteText() {
        for text in ["来られる？", "来られますか？", "保存します。", "やった！", "GitHub", "https://github.com", "それは", "ほら", "直してほしいけど", "「保存します」", ""] {
            XCTAssertEqual(JapaneseSentenceEnding.complete(text), text)
        }
    }
}
