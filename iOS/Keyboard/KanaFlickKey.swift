import UIKit

@MainActor final class KanaFlickKey: UIControl {
    private let values: [String]
    private let legend: String
    private let detail: String
    private let label = UILabel()
    private let hint = UILabel()
    private var origin = CGPoint.zero
    private var selectedIndex = 0
    var onInput: (([String], Int) -> Void)?

    init(values: [String], legend: String? = nil, detail: String? = nil) {
        precondition((1...5).contains(values.count))
        self.values = values
        self.legend = legend ?? values[0]
        self.detail = detail ?? values.dropFirst().joined(separator: " ")
        super.init(frame: .zero)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 7
        label.text = self.legend; label.font = .systemFont(ofSize: self.legend.count > 3 ? 18 : 24, weight: .medium)
        label.textAlignment = .center; label.textColor = .label
        hint.text = self.detail
        hint.font = .systemFont(ofSize: detail == nil ? 8 : 11); hint.textAlignment = .center; hint.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [label, hint]); stack.axis = .vertical; stack.spacing = 0
        stack.isUserInteractionEnabled = false; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor), stack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -4)])
        accessibilityLabel = values[0] + (values.count > 1 ? "、連打またはフリックで" + values.dropFirst().joined(separator: "、") : "")
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        origin = touch.location(in: self); selectedIndex = 0
        backgroundColor = .systemGray3; return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        selectedIndex = index(at: touch.location(in: self))
        label.text = selectedIndex == 0 ? legend : values[selectedIndex]; hint.text = selectedIndex == 0 ? detail : ""
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        if let touch { selectedIndex = index(at: touch.location(in: self)) }
        onInput?(values, selectedIndex); reset()
    }
    override func cancelTracking(with event: UIEvent?) { reset() }
    override func accessibilityActivate() -> Bool { onInput?(values, 0); return true }
    private func index(at point: CGPoint) -> Int {
        let direction = KanaLayout.index(dx: point.x - origin.x, dy: point.y - origin.y)
        return values.indices.contains(direction) ? direction : 0
    }
    private func reset() {
        label.text = legend; hint.text = detail
        backgroundColor = .secondarySystemGroupedBackground
    }
}
