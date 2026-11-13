import Foundation
import XCTest
import KanaKanjiConverterModuleWithDefaultDictionary
@testable import VoiceSeedCore

final class JapaneseConversionTests: XCTestCase {
    @MainActor func testBundledOfflineDictionaryProvidesCommonKanji() async {
        let converter = KanaKanjiConverter.withDefaultDictionary()
        for (reading, expected) in [("とうきょう", "東京"), ("しりょう", "資料"), ("ぎんこう", "銀行")] {
            var input = ComposingText(); input.insertAtCursorPosition(reading, inputStyle: .direct)
            let directory = FileManager.default.temporaryDirectory
            let result = converter.requestCandidates(input, options: .init(
                N_best: 10, requireJapanesePrediction: false, requireEnglishPrediction: false,
                keyboardLanguage: .ja_JP, englishCandidateInRoman2KanaInput: false,
                fullWidthRomanCandidate: false, halfWidthKanaCandidate: false,
                learningType: .nothing, maxMemoryCount: 0, shouldResetMemory: false,
                memoryDirectoryURL: directory, sharedContainerURL: directory,
                textReplacer: .withDefaultEmojiDictionary(),
                specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
                metadata: .init(versionString: "VoiceSeed synthetic test")))
            XCTAssertTrue(result.mainResults.contains { $0.text == expected }, reading)
        }
    }
    func testFlickDirectionsAndCorrectionKeys() {
        XCTAssertEqual(KanaLayout.index(dx: 0, dy: 0), 0)
        XCTAssertEqual(KanaLayout.index(dx: -20, dy: 0), 1)
        XCTAssertEqual(KanaLayout.index(dx: 0, dy: -20), 2)
        XCTAssertEqual(KanaLayout.index(dx: 20, dy: 0), 3)
        XCTAssertEqual(KanaLayout.index(dx: 0, dy: 20), 4)
        XCTAssertEqual(KanaLayout.alternate("は"), "ば")
        XCTAssertEqual(KanaLayout.alternate("ば"), "ぱ")
        XCTAssertEqual(KanaLayout.alternate("ぱ"), "は")
        XCTAssertEqual(KanaLayout.alternate("つ"), "っ")
        XCTAssertEqual(KanaLayout.alternate("ゃ"), "や")
    }
}
