import UIKit

/// The last utterance keeps the host's original punctuation and line breaks.
/// TextKit maps a tap to a word even when that word wraps to the next line.
@MainActor final class CorrectionStrip: UITextView {
    private var targets: [(NSRange, DictationCorrection.Word)] = []
    var onWord: ((DictationCorrection.Word) -> Void)?
    var onCharacter: ((Int) -> Void)?

    init() {
        super.init(frame: .zero, textContainer: nil)
        isEditable = false
        isSelectable = false
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 8
        textContainerInset = .init(top: 5, left: 4, bottom: 5, right: 4)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pickWord)))
        accessibilityLabel = "直前に音声入力した文。直す語をタップ"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ text: String, words: [DictationCorrection.Word], selected: Range<Int>?) {
        let changed = self.text != text
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.dictationPreview(compatibleWith: traitCollection),
            .foregroundColor: UIColor.label
        ])
        var index = text.startIndex
        var previousStart = 0
        targets = words.map { word in
            index = text.index(index, offsetBy: word.start - previousStart)
            previousStart = word.start
            let range = NSRange(index..<text.index(index, offsetBy: word.text.count), in: text)
            return (range, word)
        }
        let highlighted = selected.map { offsets in
            let start = text.index(text.startIndex, offsetBy: offsets.lowerBound)
            let end = text.index(start, offsetBy: offsets.count)
            return NSRange(start..<end, in: text)
        }
        if let highlighted {
            result.addAttributes([.backgroundColor: UIColor.systemYellow, .foregroundColor: UIColor.black], range: highlighted)
        }
        let offset = contentOffset
        attributedText = result
        accessibilityValue = text
        if onCharacter != nil {
            accessibilityCustomActions = text.enumerated().map { offset, character in
                UIAccessibilityCustomAction(name: "\(offset + 1)文字目の\(character)") { [weak self] _ in self?.onCharacter?(offset); return true }
            }
        } else {
            accessibilityCustomActions = words.map { word in
                UIAccessibilityCustomAction(name: word.text + "を直す") { [weak self] _ in self?.onWord?(word); return true }
            }
        }
        if let highlighted {
            scrollRangeToVisible(highlighted)
        } else { setContentOffset(changed ? .zero : offset, animated: false) }
    }

    @objc private func pickWord(_ tap: UITapGestureRecognizer) {
        var point = tap.location(in: self)
        point.x -= textContainerInset.left
        point.y -= textContainerInset.top
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        guard glyph < layoutManager.numberOfGlyphs,
              layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
                .insetBy(dx: -1, dy: -1).contains(point) else { return }
        let position = layoutManager.characterIndexForGlyph(at: glyph)
        if let onCharacter, position < (text as NSString).length {
            let composed = (text as NSString).rangeOfComposedCharacterSequence(at: position)
            if let range = Range(composed, in: text) {
                onCharacter(text.distance(from: text.startIndex, to: range.lowerBound))
            }
            return
        }
        if let word = targets.first(where: { NSLocationInRange(position, $0.0) })?.1 { onWord?(word) }
    }
}

/// Scroll vertically when a long candidate or larger type needs extra lines.
@MainActor final class CorrectionChoices: UIScrollView {
    private let stack = UIStackView()
    var pointSize: CGFloat = 22

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .vertical
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func reset() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        setContentOffset(.zero, animated: false)
    }

    func row(_ actions: [(String, () -> Void)]) {
        let line = UIStackView()
        line.spacing = 5
        line.distribution = .fillEqually
        for (title, action) in actions {
            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = .secondarySystemGroupedBackground
            config.baseForegroundColor = .label
            config.attributedTitle = AttributedString(title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: pointSize, weight: .semibold)]))
            config.titleLineBreakMode = .byCharWrapping
            config.contentInsets = .init(top: 5, leading: 4, bottom: 5, trailing: 4)
            let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
            button.titleLabel?.numberOfLines = 0
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            line.addArrangedSubview(button)
        }
        stack.addArrangedSubview(line)
    }

    func message(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: pointSize, weight: .semibold)
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
    }
}
