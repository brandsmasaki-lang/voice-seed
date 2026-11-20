import XCTest
@testable import VoiceSeedCore

final class DictationQuestionsTests: XCTestCase {
    // Compare pitch contours with the same words and volume. Include pauses, noise and
    // multiple sample rates so that loudness, unvoiced sounds and stale pitch cannot vote.
    func testSyntheticContours() {
        for rate in [16_000.0, 44_100.0, 48_000.0] {
            for (change, expected) in [(0.0, EndingIntonation.levelOrFalling),
                                       (-6.0, .levelOrFalling), (6.0, .rising)] {
                var track = EndingPitchTrack(), phase = 0.0, frame = 0
                let n = Int(rate * 0.4)
                while frame < n {
                    let size = min(517, n - frame)
                    track.append(frames: size, sampleRate: rate) { index in
                        let t = Double(frame + index) / rate
                        let hz = 180 * pow(2, change * min(1, max(0, (t - 0.16) / 0.22)) / 12)
                        phase += 2 * .pi * hz / rate
                        return sin(phase) * (0.12 + 0.1 * t)
                    }
                    frame += size
                }
                XCTAssertEqual(track.ending(from: 0, to: 0.4), expected)
                XCTAssertEqual(track.ending(from: 0.38, to: 0.4), .unknown)
                track.append(frames: Int(rate / 2), sampleRate: rate) { _ in 0 }
                XCTAssertEqual(track.ending(from: 0, to: 0.9), .unknown)
            }
        }
    }

    func testApplyOnlySupportedSentenceEndings() {
        XCTAssertEqual(DictationQuestions.punctuate("App Storeに並びました？", intonation: .levelOrFalling), "App Storeに並びました。")
        XCTAssertEqual(DictationQuestions.punctuate("来られる。", intonation: .rising), "来られる？")
        XCTAssertEqual(DictationQuestions.punctuate("違う", intonation: .rising, isUtteranceEnd: true), "違う？")
        XCTAssertEqual(DictationQuestions.punctuate("違う", intonation: .rising), "違う")
        for text in ["来られますか？", "どこに行きました？", "「違う？」", "https://example.org/?"] {
            XCTAssertEqual(DictationQuestions.punctuate(text, intonation: .levelOrFalling), text)
        }
        XCTAssertEqual(DictationQuestions.punctuate("並びました？", intonation: .unknown), "並びました？")
        XCTAssertEqual(DictationQuestions.punctuate(" 来られる？ ", intonation: .levelOrFalling), " 来られる。 ")
    }

    func testConversationalStatementUsesStopUnlessTheEndingClearlyRises() {
        for tone in [EndingIntonation.levelOrFalling, .unknown] {
            XCTAssertEqual(DictationQuestions.punctuate("いつもそうだよね？", intonation: tone), "いつもそうだよね。")
            XCTAssertEqual(DictationQuestions.punctuate("だよね?", intonation: tone), "だよね。")
            XCTAssertEqual(DictationQuestions.punctuate("「だよね」", intonation: tone), "「だよね」")
        }
        XCTAssertEqual(DictationQuestions.punctuate("そうだよね？", intonation: .rising), "そうだよね？")
        XCTAssertEqual(DictationQuestions.punctuate("ダメだなと思う？", intonation: .levelOrFalling), "ダメだなと思う。")
        XCTAssertEqual(DictationQuestions.punctuate("どう思う？", intonation: .levelOrFalling), "どう思う？")
    }

    func testEarlierAccentWithFlatFinalSyllableIsNotARisingEnding() {
        var track = EndingPitchTrack(), phase = 0.0
        track.append(frames: 6400, sampleRate: 16000) { i in
            let t = Double(i) / 16000
            let rise = min(1, max(0, (t - 0.19) / 0.06))
            phase += 2 * .pi * 180 * pow(2, rise / 2) / 16000
            return 0.25 * sin(phase)
        }
        XCTAssertNotEqual(track.ending(from: 0, to: 0.4), .rising)
    }

    func testUnvoicedNoiseCannotSupplyAnEnding() {
        var track = EndingPitchTrack(), seed: UInt64 = 1
        track.append(frames: 8_000, sampleRate: 16_000) { _ in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return (Double(seed >> 32) / Double(UInt32.max) - 0.5) * 0.2
        }
        XCTAssertEqual(track.ending(from: 0, to: 0.5), .unknown)
    }

    func testTextRefinementCannotAddRemoveOrRelocateQuestions() {
        XCTAssertFalse(DictationQuestions.preservesQuestions("App Storeに並びました？", from: "App Storeに並びました。"))
        XCTAssertFalse(DictationQuestions.preservesQuestions("来られる。", from: "来られる？"))
        XCTAssertFalse(DictationQuestions.preservesQuestions("来られる。着いた？", from: "来られる？着いた。"))
        XCTAssertTrue(DictationQuestions.preservesQuestions("予定です。来られる?", from: "予定です 来られる？"))
    }
}
