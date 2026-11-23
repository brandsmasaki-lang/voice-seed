import UIKit

extension UIFont {
    static func dictationPreview(compatibleWith traits: UITraitCollection) -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 19), compatibleWith: traits)
    }
}

/// Keep the arrowhead the same width while the shaft adapts to the preview height.
private final class SwipeDownHint: UIView {
    override func draw(_ rect: CGRect) {
        let halfLength = min(bounds.height * 0.3, 30)
        let wing = min(5.5, halfLength)
        let tip = CGPoint(x: bounds.midX, y: bounds.midY + halfLength)
        let arrow = UIBezierPath()
        arrow.move(to: CGPoint(x: tip.x, y: bounds.midY - halfLength))
        arrow.addLine(to: tip)
        arrow.move(to: CGPoint(x: tip.x - wing, y: tip.y - wing))
        arrow.addLine(to: tip)
        arrow.addLine(to: CGPoint(x: tip.x + wing, y: tip.y - wing))
        arrow.lineWidth = 1.75
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        KeyboardPalette.secondaryInk.setStroke()
        arrow.stroke()
    }
}

/// A label in a scroll view has no text-selection/caret scroll position to
/// inherit when a long recognition result is replaced by a short instruction.
final class DictationPreviewView: UIScrollView, UIScrollViewDelegate {
    private let label = UILabel()
    private let swipeHint = SwipeDownHint()
    private let swipeHintWidth: CGFloat = 15
    private var showingPreview = false
    private var followsTail = true
    private var pendingTail = false
    private var pendingTop = true
    private var dragStartedAtTop = false
    var onSwipeDownFromTop: (() -> Void)? {
        didSet {
            alwaysBounceVertical = onSwipeDownFromTop != nil
            label.accessibilityHint = alwaysBounceVertical ? "先頭から下にスワイプするとキーボードをしまえます" : nil
            setNeedsLayout()
        }
    }

    var text: String {
        get { label.text ?? "" }
        set { display(newValue, isPreview: false) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentInsetAdjustmentBehavior = .never
        contentInset = .zero
        // This pane sits below the keyboard toolbar; it does not extend under
        // any bar. The system's hard scroll-edge effect can mask the first line
        // inside an input extension even when contentOffset is zero.
        topEdgeEffect.isHidden = true
        bottomEdgeEffect.isHidden = true
        leftEdgeEffect.isHidden = true
        rightEdgeEffect.isHidden = true
        panGestureRecognizer.addTarget(self, action: #selector(handlePreviewDrag(_:)))
        showsHorizontalScrollIndicator = false
        delegate = self
        backgroundColor = KeyboardPalette.paper
        layer.cornerRadius = 8
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        label.adjustsFontForContentSizeCategory = true
        addSubview(label)
        swipeHint.isOpaque = false
        swipeHint.contentMode = .redraw
        swipeHint.isAccessibilityElement = false
        swipeHint.isUserInteractionEnabled = false
        swipeHint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swipeHint)
        NSLayoutConstraint.activate([
            swipeHint.widthAnchor.constraint(equalToConstant: swipeHintWidth),
            swipeHint.trailingAnchor.constraint(equalTo: frameLayoutGuide.trailingAnchor, constant: -5),
            swipeHint.topAnchor.constraint(equalTo: frameLayoutGuide.topAnchor),
            swipeHint.bottomAnchor.constraint(equalTo: frameLayoutGuide.bottomAnchor)
        ])
        accessibilityIdentifier = "dictation-preview"
        label.accessibilityLabel = "認識プレビュー"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func display(_ value: String, isPreview: Bool) {
        guard value != text || showingPreview != isPreview else { return }
        let startsPreview = isPreview && !showingPreview
        showingPreview = isPreview
        label.text = value
        label.font = isPreview ? .dictationPreview(compatibleWith: traitCollection) : .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        label.textColor = isPreview ? KeyboardPalette.ink : KeyboardPalette.secondaryInk
        label.accessibilityValue = value
        if !isPreview || startsPreview { followsTail = true }
        pendingTop = !isPreview
        pendingTail = isPreview && followsTail
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        swipeHint.isHidden = traitCollection.userInterfaceIdiom != .pad || onSwipeDownFromTop == nil
        let width = bounds.width - 16 - (swipeHint.isHidden ? 0 : swipeHintWidth)
        guard width > 0, bounds.height > 0 else { return }
        let height = ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        label.frame = CGRect(x: 8, y: 8, width: width, height: height)
        let size = CGSize(width: bounds.width, height: height + 16)
        if contentSize != size { contentSize = size }
        guard !isDragging, !isDecelerating else { return }
        let bottom = max(0, size.height - bounds.height)
        let y = pendingTop ? 0 : pendingTail ? bottom : min(bottom, max(0, contentOffset.y))
        pendingTop = false; pendingTail = false
        if abs(contentOffset.y - y) > 0.5 || contentOffset.x != 0 {
            setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }
    }

    @objc private func handlePreviewDrag(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            dragStartedAtTop = contentOffset.y <= -adjustedContentInset.top + 1
        case .ended:
            let delta = pan.translation(in: superview)
            if dragStartedAtTop && delta.y >= 40 && delta.y > 1.5 * abs(delta.x) {
                onSwipeDownFromTop?()
            }
            dragStartedAtTop = false
        case .cancelled, .failed:
            dragStartedAtTop = false
        default:
            break
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        followsTail = false; pendingTail = false; pendingTop = false
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishReadingScroll() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { finishReadingScroll() }

    private func finishReadingScroll() {
        followsTail = contentOffset.y >= max(0, contentSize.height - bounds.height) - 12
    }
}
