import Foundation

// Keep decoding the layout preference saved by earlier builds.
enum PhoneKeyboardLayout: String, Codable, Sendable { case standard, keypad }

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
