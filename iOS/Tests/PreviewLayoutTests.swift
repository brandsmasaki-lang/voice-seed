import UIKit

@main final class PreviewTestApp: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Preview tests", sessionRole: session.role)
        configuration.delegateClass = PreviewTestScene.self
        return configuration
    }
}
final class PreviewTestScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = PreviewTestController()
        self.window = window; window.makeKeyAndVisible()
    }
}
final class PreviewTestController: UIViewController {
    private var failures: [String] = []
    private let instruction = "マイクを押すと、こえのたねが一度開きます。戻ると聞き取りが始まります。"
    private let long = (1...30).map { "\($0)行目：これは長文プレビューの表示確認です。" }.joined(separator: "\n")
    private func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
    private func layout(_ preview: DictationPreviewView) { preview.setNeedsLayout(); preview.layoutIfNeeded() }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        view.backgroundColor = .systemBackground
        for width: CGFloat in [280, 304, 414, 688, 760] {
            for height: CGFloat in [46, 80] {
                let preview = DictationPreviewView(frame: CGRect(x: 0, y: 0, width: width, height: height))
                view.addSubview(preview)
                preview.text = instruction; layout(preview)
                check(preview.contentOffset.y == 0, "initial instruction must start at top")
                check(preview.adjustedContentInset == .zero, "no inherited safe-area inset")
                preview.display(long, isPreview: true); layout(preview)
                check(preview.contentOffset.y > 0, "long preview must scroll")
                check(abs(preview.contentOffset.y - (preview.contentSize.height - height)) < 1, "long preview follows tail")
                preview.scrollViewWillBeginDragging(preview)
                preview.contentOffset.y = 20
                preview.scrollViewDidEndDragging(preview, willDecelerate: false)
                preview.display(long + "\n追加した文章です。", isPreview: true); layout(preview)
                check(abs(preview.contentOffset.y - 20) < 1, "new recognition must preserve reading position")
                preview.scrollViewWillBeginDragging(preview)
                preview.contentOffset.y = preview.contentSize.height - height
                preview.scrollViewDidEndDragging(preview, willDecelerate: false)
                preview.display(long + "\nさらに追加した文章です。\n最後の行です。", isPreview: true); layout(preview)
                check(abs(preview.contentOffset.y - (preview.contentSize.height - height)) < 1, "returning to bottom resumes follow")
                preview.text = instruction; layout(preview)
                check(preview.contentOffset.y == 0, "long to instruction must reset to top")
                preview.display("短い認識結果です。", isPreview: true); layout(preview)
                check(preview.contentOffset.y == 0, "short preview must remain at top")
                preview.removeFromSuperview()
            }
        }
        let titles = ["初期表示：先頭から読める", "長文から案内へ戻る：位置をリセット", "長文：上下にスクロールして読み返す"]
        for index in 0..<3 {
            let title = UILabel(frame: CGRect(x: 18, y: 100 + index * 180, width: Int(view.bounds.width) - 36, height: 32))
            title.text = titles[index]; title.font = .systemFont(ofSize: 17); view.addSubview(title)
            let preview = DictationPreviewView(frame: CGRect(x: 18, y: 140 + index * 180, width: Int(view.bounds.width) - 36, height: 80))
            view.addSubview(preview)
            if index > 0 { preview.display(long, isPreview: true); layout(preview) }
            if index < 2 { preview.text = instruction }
            layout(preview)
        }
        let result: [String: Any] = ["passed": failures.isEmpty, "failures": failures, "cases": 80,
                                   "syntheticOnly": true, "realMicrophoneTested": false]
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("preview-results.json")
        try! JSONSerialization.data(withJSONObject: result, options: .prettyPrinted).write(to: url)
    }
}
