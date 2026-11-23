import Foundation

enum PhoneKeyboardLayout: String, Codable, CaseIterable, Sendable {
    case standard, keypad

    var label: String { self == .standard ? "標準" : "テンキー" }
}

enum PhoneKeypad {
    // Tap, then flick left, up, right or down. Short groups omit unused directions.
    static let latinRows = [
        ["@#/&_", "abc", "def"],
        ["ghi", "jkl", "mno"],
        ["pqrs", "tuv", "wxyz"],
        ["*-+=", "'\"()", ".,?!"]
    ]
    static let numberRows = [
        ["1☆♪→", "2¥$€", "3%°#"],
        ["4○*・", "5+×÷", "6<=>"],
        ["7「」:", "8〒々〆", "9^|\\"],
        ["()[]", "0〜…", ".,-/"]
    ]
}
