import Foundation

enum TabletKeyboardSize: Int, Codable, CaseIterable {
    case small = 420, standard = 520, large = 620
    var label: String {
        switch self { case .small: "小さめ"; case .standard: "標準"; case .large: "大きめ" }
    }
}

enum TabletKeyboardPosition: String, Codable, CaseIterable {
    case left, center, right
    var label: String {
        switch self { case .left: "左寄せ"; case .center: "中央"; case .right: "右寄せ" }
    }
}
