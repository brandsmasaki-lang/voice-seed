import UIKit

@MainActor final class DeleteKey: UIControl {
    var onDelete: (() -> Void)?
    var onDeleteBunsetsu: (() -> Void)?
    private var timer: Timer?
    private var origin = CGPoint.zero
    private var gesture = DeleteKeyGesture()
    private let icon = UIImageView(image: UIImage(systemName: "delete.left"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGray3; layer.cornerRadius = 7
        icon.tintColor = .label; icon.contentMode = .scaleAspectFit; icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([icon.centerXAnchor.constraint(equalTo: centerXAnchor), icon.centerYAnchor.constraint(equalTo: centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 22)])
        isAccessibilityElement = true; accessibilityTraits = .keyboardKey
        accessibilityLabel = "削除"; accessibilityHint = "長押しで連続削除、左フリックで1文節を削除"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        stop(); gesture = DeleteKeyGesture(); origin = touch.location(in: self)
        timer = Timer(timeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.perform(self.gesture.repeatTick())
                self.timer = Timer(timeInterval: 0.075, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { guard let self else { return }; self.perform(self.gesture.repeatTick()) }
                }
                if let timer = self.timer { RunLoop.main.add(timer, forMode: .common) }
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        gesture.move(dx: point.x - origin.x, dy: point.y - origin.y)
        icon.image = UIImage(systemName: gesture.isLeftFlick ? "arrow.left.to.line" : "delete.left")
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { perform(gesture.end()); stop() }
    override func cancelTracking(with event: UIEvent?) { stop() }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { stop() } }
    override func accessibilityActivate() -> Bool { onDelete?(); return true }
    private func perform(_ action: DeleteKeyGesture.Action) {
        switch action { case .none: break; case .character: onDelete?(); case .bunsetsu: onDeleteBunsetsu?() }
    }
    private func stop() { timer?.invalidate(); timer = nil; icon.image = UIImage(systemName: "delete.left") }
}
