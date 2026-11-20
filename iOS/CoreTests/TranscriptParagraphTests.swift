import XCTest
@testable import VoiceSeedCore

final class TranscriptParagraphTests: XCTestCase {
    func testLongPauseAfterQuestionCreatesParagraphWithoutChangingWords() {
        var buffer = TranscriptBuffer(paragraphPause: 1.2)
        buffer.update(start: 0, end: 1, text: "明日来られますか？", isFinal: true)
        buffer.update(start: 2.3, end: 4, text: "午後3時に待っています。", isFinal: true)
        XCTAssertEqual(buffer.finalText, "明日来られますか？\n午後3時に待っています。")
    }
    func testShortPauseAndMidSentencePauseDoNotBreak() {
        var buffer = TranscriptBuffer(paragraphPause: 1.2)
        buffer.update(start: 0, end: 1, text: "今日は、", isFinal: true)
        buffer.update(start: 3, end: 4, text: "晴れです。", isFinal: true)
        buffer.update(start: 4.5, end: 6, text: "散歩します。", isFinal: true)
        XCTAssertEqual(buffer.finalText, "今日は、晴れです。散歩します。")
    }
    func testRecognitionRevisionAndExistingNewlineArePreserved() {
        var buffer = TranscriptBuffer(paragraphPause: 1.2)
        buffer.update(start: 0, end: 1, text: "本当？", isFinal: true)
        buffer.update(start: 3, end: 4, text: "そうです", isFinal: false)
        XCTAssertEqual(buffer.preview, "本当？\nそうです")
        XCTAssertEqual(buffer.finalText, "本当？")
        buffer.update(start: 0, end: 4, text: "本当？\nそうです。", isFinal: true)
        XCTAssertEqual(buffer.finalText, "本当？\nそうです。")
    }
    func testDefaultDoesNotChangeMacFormatting() {
        var buffer = TranscriptBuffer()
        buffer.update(start: 0, end: 1, text: "はい。", isFinal: true)
        buffer.update(start: 3, end: 4, text: "承知しました。", isFinal: true)
        XCTAssertEqual(buffer.finalText, "はい。承知しました。")
    }
}
