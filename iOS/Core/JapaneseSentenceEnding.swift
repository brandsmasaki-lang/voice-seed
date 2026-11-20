import Foundation

/// Complete an unpunctuated Japanese sentence; never infer a question from text alone.
enum JapaneseSentenceEnding {
    static func complete(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 3,
              value.range(of: #"(?:です|ます|でした|ました|ません|ください|なんだ|して|だった|でしょう|だろう|している|してる|していた|できる|ない|欲しい|ほしい|嬉しい|うれしい|[いえきけしせちてにねひへびべみめりれ]た|いだ|った|んだ|来た|だ)(?:よね|よ|ね)?$"#, options: .regularExpression) != nil else { return text }
        return value + "。"
    }
}
