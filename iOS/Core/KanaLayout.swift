import Foundation

enum KanaLayout {
    // Center, left, up, right, down.
    static let rows: [[[String]]] = [
        [["あ", "い", "う", "え", "お"], ["か", "き", "く", "け", "こ"], ["さ", "し", "す", "せ", "そ"]],
        [["た", "ち", "つ", "て", "と"], ["な", "に", "ぬ", "ね", "の"], ["は", "ひ", "ふ", "へ", "ほ"]],
        [["ま", "み", "む", "め", "も"], ["や", "（", "ゆ", "）", "よ"], ["ら", "り", "る", "れ", "ろ"]],
        [["゛゜小"], ["わ", "を", "ん", "ー", "〜"], ["、", "。", "？", "！", "…"]]
    ]
    static func index(dx: Double, dy: Double, threshold: Double = 14) -> Int {
        guard max(abs(dx), abs(dy)) >= threshold else { return 0 }
        if abs(dx) > abs(dy) { return dx < 0 ? 1 : 3 }
        return dy < 0 ? 2 : 4
    }
    static func alternate(_ character: Character) -> Character {
        let groups = ["あぁ", "いぃ", "うぅゔ", "えぇ", "おぉ", "かが", "きぎ", "くぐ", "けげ", "こご",
                      "さざ", "しじ", "すず", "せぜ", "そぞ", "ただ", "ちぢ", "つっづ", "てで", "とど",
                      "はばぱ", "ひびぴ", "ふぶぷ", "へべぺ", "ほぼぽ", "やゃ", "ゆゅ", "よょ", "わゎ"]
        for group in groups {
            let values = Array(group)
            if let i = values.firstIndex(of: character) { return values[(i + 1) % values.count] }
        }
        return character
    }
}
