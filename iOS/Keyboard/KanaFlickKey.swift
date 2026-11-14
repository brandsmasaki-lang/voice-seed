import UIKit

@MainActor final class KanaFlickKey: UIControl {
    private let values: [String]
    private let label = UILabel()
    private let hint = UILabel()
    private var origin = CGPoint.zero
    private var selectedIndex = 0
    var onInput: (([String], Int) -> Void)?

    init(values: [String]) {
        self.values = values; super.init(frame: .zero)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 7
        label.text = values[0]; label.font = .systemFont(ofSize: 24, weight: .medium)
        label.textAlignment = .center; label.textColor = .label
        hint.text = values.count == 5 ? values.dropFirst().joined(separator: " ") : ""
        hint.font = .systemFont(ofSize: 8); hint.textAlignment = .center; hint.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [label, hint]); stack.axis = .vertical; stack.spacing = 0
        stack.isUserInteractionEnabled = false; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor), stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -4)])
        accessibilityLabel = values[0] + (values.count > 1 ? "、連打またはフリックで" + values.dropFirst().joined(separator: "、") : "")
        accessibilityTraits = .keyboardKey
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        origin = touch.location(in: self); selectedIndex = 0
        backgroundColor = .systemGray3; return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        selectedIndex = values.count > 1 ? KanaLayout.index(dx: point.x - origin.x, dy: point.y - origin.y) : 0
        label.text = values[selectedIndex]; hint.text = selectedIndex == 0 && values.count == 5 ? values.dropFirst().joined(separator: " ") : ""
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        onInput?(values, selectedIndex); reset()
    }
    override func cancelTracking(with event: UIEvent?) { reset() }
    override func accessibilityActivate() -> Bool { onInput?(values, 0); return true }
    private func reset() {
        label.text = values[0]; hint.text = values.count == 5 ? values.dropFirst().joined(separator: " ") : ""
        backgroundColor = .secondarySystemGroupedBackground
    }
}
