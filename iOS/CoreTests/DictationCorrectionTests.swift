import XCTest
@testable import VoiceSeedCore

final class DictationCorrectionTests: XCTestCase {
    func testReconversionAndUndoTargetOnlyChosenOccurrence() throws {
        let text = "😊来週の洗濯と今日の洗濯について相談します。"
        let original = DictationCorrection(text: text, before: "予定：", after: "次の文", document: "memo", focus: UUID())
        let selected = try XCTUnwrap(original.words.last { $0.text == "洗濯" })
        XCTAssertEqual(selected.reading, "せんたく")
        let revised = try XCTUnwrap(original.applying(.init(start: selected.start, from: selected.text, to: "せんたく"), isUndo: false))
        XCTAssertEqual(revised.text, "😊来週の洗濯と今日のせんたくについて相談します。")
        XCTAssertTrue(revised.matches(before: "予定：😊来週の洗濯と今日のせんたく", after: "について相談します。次の文", at: revised.caret))
        let undone = try XCTUnwrap(revised.applying(try XCTUnwrap(revised.undo), isUndo: true))
        XCTAssertEqual(undone.text, text)
        XCTAssertNil(undone.undo)
    }

    func testChangedOrUnobservableContextRejectsReplacement() {
        let text = "来週の洗濯について相談します。"
        let state = DictationCorrection(text: text, before: "予定：", after: nil, document: "memo", focus: UUID())
        XCTAssertTrue(state.matches(before: "予定：" + text, after: nil, at: state.caret))
        XCTAssertFalse(state.matches(before: "変更：" + text, after: nil, at: state.caret))
        XCTAssertFalse(state.matches(before: "予定：" + text, after: "追記", at: state.caret))
        XCTAssertFalse(state.matches(before: nil, after: nil, at: state.caret))
        XCTAssertFalse(state.matches(before: "予定：来週の", after: "洗濯について相談します。", at: state.caret))
        XCTAssertFalse(state.matches(before: "変更。予定：" + text, after: nil, at: state.caret))
        XCTAssertFalse(state.agreesWithWindow(before: "変更。予定：", after: text, at: 0))
        let bounded = DictationCorrection(text: text, before: "", after: "以上", document: "memo", focus: UUID())
        XCTAssertFalse(bounded.matches(before: text, after: "以上です", at: bounded.caret))
        XCTAssertFalse(bounded.agreesWithWindow(before: text, after: "以上です", at: bounded.caret))
    }
    func testDeletionUndoAndConsecutiveUtterances() throws {
        let first = "斎藤の洗濯をまた確認します。"
        let second = "明日の予定です。"
        let a = DictationCorrection(text: first, before: nil, after: nil, document: "a", focus: UUID())
        let word = try XCTUnwrap(a.words.first { $0.text == "また" })
        let removed = try XCTUnwrap(a.applying(.init(start: word.start, from: word.text, to: ""), isUndo: false))
        XCTAssertEqual(removed.text, "斎藤の洗濯を確認します。")
        XCTAssertNil(removed.applying(.init(start: 0, from: "", to: "別の語"), isUndo: true))
        XCTAssertEqual(removed.applying(try XCTUnwrap(removed.undo), isUndo: true)?.text, first)
        let b = DictationCorrection(text: second, before: first, after: "", document: "a", focus: UUID())
        XCTAssertTrue(b.matches(before: first + second, after: "", at: second.count))
        XCTAssertFalse(a.matches(before: first + second, after: "", at: first.count))
    }

    func testLongTextRequiresObservableContextBeforeWriting() throws {
        let long = String(repeating: "長い文章です。", count: 90) + "洗濯。"
        let s = DictationCorrection(text: long, before: "", after: "", document: "abc", focus: UUID())
        XCTAssertTrue(s.matches(before: long, after: "", at: long.count))
        XCTAssertFalse(s.matches(before: String(long.suffix(64)), after: "", at: long.count))
        XCTAssertTrue(s.agreesWithWindow(before: String(long.suffix(42)), after: "", at: long.count))
        XCTAssertFalse(s.agreesWithWindow(before: "異なる末尾の文章です。", after: "", at: long.count))
        XCTAssertFalse(s.agreesWithWindow(before: "", after: "", at: long.count))
        let word = try XCTUnwrap(s.words.last { $0.text == "洗濯" })
        XCTAssertEqual(s.applying(.init(start: word.start, from: word.text, to: "選択"), isUndo: false)?.text,
                       String(long.dropLast(3)) + "選択。")
    }

    func testPreferredCandidatesMigrateWithoutChangingAutomaticReplacement() throws {
        let old = LocalSettings()
        var settings = try JSONDecoder().decode(LocalSettings.self, from: JSONEncoder().encode(old))
        XCTAssertNil(settings.preferredCandidates)
        let entry = DictionaryEntry(heard: "さいとう", written: "齋藤")
        settings.prefer(entry)
        settings.prefer(DictionaryEntry(heard: "さいとう", written: "齋藤"))
        XCTAssertEqual(settings.preferredCandidates?.count, 1)
        XCTAssertEqual(TextPipeline.applyDictionary("さいとうと斎藤", entries: settings.dictionary), "さいとうと斎藤")
        var changed = try XCTUnwrap(settings.preferredCandidates?.first)
        changed.written = "齊藤"
        settings.prefer(changed)
        XCTAssertEqual(settings.preferredCandidates, [changed])
    }
}

extension DictationCorrectionTests {
    func testArrowsAdjustOneGraphemeAndStopAtBoundaries() throws {
        let draft = DictationCorrection(text: "👩🏽‍💻番号の種", before: nil, after: nil, document: "", focus: UUID())
        let range = 1..<3
        XCTAssertEqual(draft.adjusting(range, part: .end, by: -1)?.text, "番")
        XCTAssertEqual(draft.adjusting(range, part: .end, by: 1)?.text, "番号の")
        XCTAssertEqual(draft.adjusting(range, part: .start, by: 1)?.text, "号")
        XCTAssertEqual(draft.adjusting(range, part: .start, by: -1)?.text, "👩🏽‍💻番号")
        XCTAssertEqual(draft.adjusting(range, part: .whole, by: 1)?.text, "号の")
        XCTAssertNil(draft.adjusting(0..<1, part: .end, by: -1))
        XCTAssertNil(draft.adjusting(0..<1, part: .whole, by: -1))
        XCTAssertNil(draft.adjusting(4..<5, part: .end, by: 1))
    }

    func testRangeSpansWordsPunctuationAndGraphemesInBothDirections() throws {
        let text = "👩🏽‍💻iPhone番号の種がApp Storeに並びました。"
        let draft = DictationCorrection(text: text, before: nil, after: nil, document: "", focus: UUID())
        let part = try XCTUnwrap(draft.selection(from: 10, through: 7))
        XCTAssertEqual(part.text, "番号の種")
        XCTAssertEqual(draft.selection(from: 8, through: 9)?.text, "号の")
        XCTAssertEqual(draft.selection(from: 7, through: 10)?.range, part.range)
        XCTAssertEqual(draft.selection(from: 0, through: 0)?.text, "👩🏽‍💻")
        XCTAssertNil(draft.selection(from: 1, through: text.count))
        let revised = try XCTUnwrap(draft.applying(.init(start: part.start, from: part.text, to: "版、こえのたね"), isUndo: false))
        XCTAssertEqual(revised.text, "👩🏽‍💻iPhone版、こえのたねがApp Storeに並びました。")
        XCTAssertEqual(revised.applying(try XCTUnwrap(revised.undo), isUndo: true)?.text, text)
    }
}
