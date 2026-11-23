import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

@MainActor final class JapaneseComposer {
    private lazy var converter = KanaKanjiConverter.withDefaultDictionary()
    private(set) var reading = ""
    private(set) var candidates: [String] = []
    var convertsReading = true
    var dictionary: [DictionaryEntry] = []
    var isEmpty: Bool { reading.isEmpty }

    func append(_ text: String) { reading += text; refresh() }
    func replaceLast(_ text: String) {
        if !reading.isEmpty { reading.removeLast() }
        reading += text; refresh()
    }
    func removeLast(_ count: Int) { reading = String(reading.dropLast(min(count, reading.count))); refresh() }
    func delete() { if !reading.isEmpty { reading.removeLast() }; refresh() }
    func alternateLast() {
        guard let last = reading.last else { return }
        reading.removeLast(); reading.append(KanaLayout.alternate(last)); refresh()
    }
    func clear() { reading = ""; candidates = [] }
    private func refresh() {
        candidates = convertsReading ? conversions(for: reading) : []
    }

    func conversions(for reading: String) -> [String] {
        guard !reading.isEmpty else { return [] }
        guard reading.count <= 80 else { return [reading] }
        var input = ComposingText()
        input.insertAtCursorPosition(reading, inputStyle: .direct)
        let temporary = FileManager.default.temporaryDirectory
        let result = converter.requestCandidates(input, options: .init(
            N_best: 8, requireJapanesePrediction: false, requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP, englishCandidateInRoman2KanaInput: false,
            fullWidthRomanCandidate: false, halfWidthKanaCandidate: false,
            learningType: .nothing, maxMemoryCount: 0, shouldResetMemory: false,
            memoryDirectoryURL: temporary, sharedContainerURL: temporary,
            textReplacer: .withDefaultEmojiDictionary(),
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            metadata: .init(versionString: "オトナの音声入力 こえのたね")))
        let personal = dictionary.filter { !$0.isVocabulary && $0.heard == reading }.map(\.written)
        var seen = Set<String>()
        return (personal + result.mainResults.map(\.text) + [reading, reading.applyingTransform(.hiraganaToKatakana, reverse: false) ?? reading])
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
