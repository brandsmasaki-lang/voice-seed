import XCTest
@testable import VoiceSeedCore

final class KanaTapCycleTests: XCTestCase {
    func testReverseAfterFlickOrRepeatedTapAndWrapWithinTheKey() {
        let key = KanaLayout.rows[0][0]
        var cycle = KanaTapCycle()
        XCTAssertNil(cycle.reverse(currentLast: nil, at: 0))
        _ = cycle.resolve(values: key, selectedIndex: 2, at: 0, currentLast: nil)
        XCTAssertEqual(cycle.reverse(currentLast: "う", at: 3)?.text, "い")
        XCTAssertEqual(cycle.reverse(currentLast: "い", at: 4)?.text, "あ")
        XCTAssertEqual(cycle.reverse(currentLast: "あ", at: 5)?.text, "お")
        XCTAssertEqual(cycle.resolve(values: key, selectedIndex: 0, at: 5.1, currentLast: "お"),
                       .init(text: "あ", replacesLast: true))
        _ = cycle.resolve(values: key, selectedIndex: 0, at: 5.2, currentLast: "あ")
        _ = cycle.resolve(values: key, selectedIndex: 0, at: 5.3, currentLast: "い")
        XCTAssertEqual(cycle.reverse(currentLast: "う", at: 5.4), .init(text: "い", replacesLast: true))
        cycle.reset()
        XCTAssertNil(cycle.reverse(currentLast: "い", at: 6))
    }

    func testFourPunctuationTapsProduceOneExclamationMark() {
        var cycle = KanaTapCycle(), reading = ""
        let values = KanaLayout.rows[3][2]
        for tap in 0..<4 {
            let edit = cycle.resolve(values: values, selectedIndex: 0, at: Double(tap) * 0.1,
                                     currentLast: reading.last.map(String.init))
            if edit.replacesLast { reading.removeLast() }
            reading += edit.text
        }
        XCTAssertEqual(reading, "！")
    }

    func testKanaCyclesAndDifferentKeyStartsANewCharacter() {
        var cycle = KanaTapCycle(), reading = ""
        for (time, values) in [(0.0, KanaLayout.rows[0][0]), (0.1, KanaLayout.rows[0][0]),
                               (0.2, KanaLayout.rows[0][1]), (0.3, KanaLayout.rows[0][0])] {
            let edit = cycle.resolve(values: values, selectedIndex: 0, at: time, currentLast: reading.last.map(String.init))
            if edit.replacesLast { reading.removeLast() }; reading += edit.text
        }
        XCTAssertEqual(reading, "いかあ")
    }

    func testPauseCommitOrCursorMovePreventsReplacement() {
        let values = KanaLayout.rows[0][0]
        var cycle = KanaTapCycle()
        _ = cycle.resolve(values: values, selectedIndex: 0, at: 0, currentLast: nil)
        XCTAssertEqual(cycle.resolve(values: values, selectedIndex: 0, at: 1, currentLast: "あ"), .init(text: "あ", replacesLast: false))
        cycle.reset()
        XCTAssertFalse(cycle.resolve(values: values, selectedIndex: 0, at: 1.1, currentLast: "あ").replacesLast)
        XCTAssertFalse(cycle.resolve(values: values, selectedIndex: 0, at: 1.2, currentLast: nil).replacesLast)
    }

    func testRepeatedFlicksAppendAndDoNotJoinATapCycle() {
        let values = KanaLayout.rows[0][0]
        var cycle = KanaTapCycle()
        _ = cycle.resolve(values: values, selectedIndex: 0, at: 0, currentLast: nil)
        XCTAssertEqual(cycle.resolve(values: values, selectedIndex: 1, at: 0.1, currentLast: "あ"), .init(text: "い", replacesLast: false))
        XCTAssertEqual(cycle.resolve(values: values, selectedIndex: 1, at: 0.2, currentLast: "い"), .init(text: "い", replacesLast: false))
        XCTAssertEqual(cycle.resolve(values: values, selectedIndex: 0, at: 0.3, currentLast: "い"), .init(text: "あ", replacesLast: false))
    }
}
