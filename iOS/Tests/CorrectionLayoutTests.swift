import UIKit

@main final class CorrectionTestApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = CorrectionTestScene.self
        return config
    }
}

final class CorrectionTestScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = CorrectionTestController()
        self.window = window
        window.makeKeyAndVisible()
    }
}

final class CorrectionTestController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.backgroundColor = .systemBackground
        let text = "斎藤の洗濯をまた確認します。"
        let state = DictationCorrection(text: text, before: nil, after: nil, document: "test", focus: UUID())
        let word = state.words.first { $0.text == "洗濯" }!
        let preview = CorrectionStrip()
        let panel = CorrectionChoices(frame: .zero)
        view.addSubview(preview)
        view.addSubview(panel)
        var failures: [String] = []
        for width: CGFloat in [280, 320, 375, min(700, view.bounds.width - 24)] {
            for size: CGFloat in [20, 24, 30] {
                let x = (view.bounds.width - width) / 2
                preview.frame = CGRect(x: x, y: view.safeAreaInsets.top + 24, width: width, height: 88)
                preview.show(text, words: state.words, selected: word.range)
                let textFont = preview.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
                let basePt = UIFont.preferredFont(forTextStyle: .body, compatibleWith: preview.traitCollection).pointSize
                let previewPt = textFont?.pointSize ?? 0
                if previewPt <= basePt || previewPt > basePt * 1.20 { failures.append("プレビューの文字サイズ") }
                panel.frame = CGRect(x: x, y: preview.frame.maxY + 8, width: width, height: 220)
                panel.reset()
                panel.pointSize = size
                panel.row([("選択", {}), ("洗濯", {}), ("せんたく", {})])
                let long = "ことばの研究をしている架空の会社名"
                panel.row([(long, {})])
                panel.row([("前の語", {}), ("次の語", {})])
                panel.row([("この語を消す", {}), ("元に戻す", {})])
                panel.setNeedsLayout()
                panel.layoutIfNeeded()
                func checkButtons(_ element: UIView) {
                    if let button = element as? UIButton, let label = button.titleLabel {
                        let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
                        if button.bounds.height < 43.9 || label.frame.height + 1 < needed.height ||
                            label.adjustsFontSizeToFitWidth || button.frame.maxX > width + 1 {
                            failures.append("\(width)pt / \(size)pt / \(label.text ?? "")")
                        }
                    }
                    element.subviews.forEach(checkButtons)
                }
                checkButtons(panel)
                if panel.contentSize.width > width + 1 { failures.append("横方向にはみ出した") }
            }
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("correction-results.json")
        let results: [String: Any] = ["passed": failures.isEmpty, "cases": 12, "failures": failures]
        try! JSONSerialization.data(withJSONObject: results).write(to: url)
    }
}
