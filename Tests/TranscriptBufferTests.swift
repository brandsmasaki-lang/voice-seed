import Foundation

@main struct TranscriptBufferTests {
    static func main() {
        var transcript = TranscriptBuffer()
        transcript.update(start: 0, end: 1, text: "こん", isFinal: false)
        precondition(transcript.preview == "こん" && transcript.finalText.isEmpty)
        transcript.update(start: 0, end: 2, text: "こんにちは。", isFinal: false)
        precondition(transcript.preview == "こんにちは。", "A hypothesis replaces rather than appends")
        transcript.update(start: 0, end: 2, text: "こんにちは。", isFinal: true)
        precondition(transcript.finalText == "こんにちは。")
        transcript.update(start: 0, end: 2, text: "誤った仮説", isFinal: false)
        precondition(transcript.finalText == "こんにちは。" && transcript.preview == "こんにちは。", "Do not undo finalized text")
        transcript.update(start: 2, end: 3, text: "今日は", isFinal: false)
        precondition(transcript.preview == "こんにちは。今日は" && transcript.finalText == "こんにちは。")
        transcript.update(start: 2, end: 4, text: "今日は金曜日。", isFinal: true)
        precondition(transcript.finalText == "こんにちは。今日は金曜日。")
        transcript.update(start: 0, end: 2, text: "こんにちは。", isFinal: true)
        precondition(transcript.finalText == "こんにちは。今日は金曜日。", "Duplicate finals must not repeat words")
        transcript.update(start: 0, end: 4, text: "こんにちは、今日は金曜日。", isFinal: true)
        precondition(transcript.finalText == "こんにちは、今日は金曜日。", "A consolidated final replaces overlapping ranges")
        transcript.update(start: .nan, end: 5, text: "無効", isFinal: true)
        precondition(transcript.finalText == "こんにちは、今日は金曜日。")
        print("PASS: 9 progressive transcript integrity checks")
    }
}
