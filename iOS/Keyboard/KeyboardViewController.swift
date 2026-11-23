import UIKit
import UniformTypeIdentifiers
import SwiftUI

private struct ActivateKeyboardButton: View {
    var destination: URL?
    var body: some View {
        Link(destination: destination ?? URL(string: "koenotane://settings")!) {
            Label("タップして話す", systemImage: "mic").font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .contentShape(Capsule())
        }.disabled(destination == nil).buttonStyle(.plain).foregroundStyle(.white).background(.black.opacity(0.8), in: Capsule())
    }
}
private struct KeyboardSettingsButton: View {
    let importDictionary: () -> Void
    var body: some View {
        Menu {
            Link("こえのたねの設定を開く", destination: URL(string: "koenotane://settings")!)
            Button("端末のユーザ辞書を取り込む", action: importDictionary)
        } label: {
            Image(systemName: "slider.horizontal.3").font(.system(size: 18)).padding(8).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.primary).accessibilityLabel("キーボード設定")
    }
}

final class KeyboardViewController: UIInputViewController {
    private enum Mode: Equatable { case kana, abc, numbers, emoji }
    private var mode: Mode = .kana
    private let root = UIStackView()
    private let toolbar = UIStackView()
    private let panes = UIStackView()
    private let previewColumn = UIStackView()
    private let keysColumn = UIStackView()
    private let hideButton = UIButton(type: .system)
    private var keysWidth: NSLayoutConstraint!
    private var toolbarLeading: NSLayoutConstraint!
    private var sideBySide = false
    private let candidates = UIStackView()
    private let candidateScroll = UIScrollView()
    private var activePhoneLayout: PhoneKeyboardLayout = .standard
    private let modeKeys = UIStackView()
    private let bodyStack = UIStackView()
    private let bottomBar = UIStackView()
    private var meterStep: Int?
    private var dictionaryImportNotice: (message: String, until: Date)?
    private let speechButton = UIButton(type: .system)
    private let reviewButton = UIButton(type: .system)
    private let pasteButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var discardMenuID: UUID?
    private var menuHasQueuedPaste = false
    private let notice = DictationPreviewView()
    private let correctionStrip = CorrectionStrip()
    private let reviewHint = UILabel()
    private let keyArea = UIStackView()
    private let choicesPanel = CorrectionChoices()
    private let undoButton = UIButton(type: .system)
    private let finishReplacement = UIButton(type: .system)
    private let selectionPart = UISegmentedControl(items: ["末尾", "先頭", "全体"])
    private enum RangeSelection { case first, last(Int), ready(DictationCorrection.Word) }
    private var rangeSelection: RangeSelection?
    // During a range edit, converted segments and direct keys stay in the preview until confirmed.
    private struct ManualReplacement {
        let target: DictationCorrection.Word
        var committed = ""
        var singleConversionReading: String?
    }
    private var manualEdit: ManualReplacement?
    private var selectedWord: DictationCorrection.Word?
    private var registration: DictionaryEntry?
    private var showingAllTypedCandidates = false
    private var correction: DictationCorrection?
    private var reviewedDraftID: UUID?
    private var expandedDraftID: UUID?
    private var reviewSize: CGFloat { CGFloat((snapshot.settings.reviewTextSize ?? .large).points) }
    private var copySuggestion: String?
    private var editingCorrection: Task<Void, Never>?
    private var noticeHeight: NSLayoutConstraint!
    private static let candidateRowHeight: CGFloat = 48
    private var keyboardHeight: NSLayoutConstraint!
    private let globe = UIButton(type: .system)
    private let layoutButton = UIButton(type: .system)
    private var rootMaximumWidth: NSLayoutConstraint!
    private var rootAlignment: NSLayoutConstraint!
    private var appliedTabletSize: TabletKeyboardSize?
    private var appliedTabletPosition: TabletKeyboardPosition?
    private var isTablet: Bool { traitCollection.userInterfaceIdiom == .pad }
    private let composer = JapaneseComposer()
    private weak var reverseButton: UIButton?
    private var tapCycle = KanaTapCycle()
    private var store: SharedSessionStore?
    private var snapshot = SessionSnapshot()
    private var timer: Timer?
    private var pending: CaptureRequest?
    private var activationTicket: KeyboardLaunch?
    // A ready draft gets a brief proxy-reconnection allowance. An explicitly
    // queued paste can wait for the entire finalization in the original field.
    private var draftInsertion: (id: UUID, document: String, focus: UUID, expires: Date?)?
    private var stoppedRequest: CaptureRequest? {
        guard let pending, pending.stoppedAt != nil, snapshot.request?.id == pending.id else { return nil }
        return pending
    }
    // UIKit recreates this controller and its document proxy when returning
    // from the containing app, even while the extension process stays alive.
    // Keep launch ownership for that process; still reject a different process
    // and bind each capture/delivery to the newly visible field and focus.
    private static let processKeyboardID = UUID()
    private let keyboardID = KeyboardViewController.processKeyboardID
    private var isVisible = false
    private var focusSettlesAt: TimeInterval = 0
    private var focusID = UUID()
    private var currentDocument = ""
    private var inserting = false
    private var activationHost: UIHostingController<ActivateKeyboardButton>?
    private var settingsHost: UIHostingController<KeyboardSettingsButton>?
    private var uppercase = false
    private var spaceOffset = 0
    private var spaceOrigin: CGFloat = 0
    private var lastCandidateText = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGray4
        root.axis = .vertical; root.spacing = 6; root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        keyboardHeight = view.heightAnchor.constraint(equalToConstant: 328)
        // Keep the familiar keys within reach on a wide iPad, while shrinking
        // naturally in narrow windows and floating keyboards.
        let preferredWidth = root.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -12)
        preferredWidth.priority = .defaultHigh
        rootMaximumWidth = root.widthAnchor.constraint(lessThanOrEqualToConstant: 520)
        rootAlignment = root.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        NSLayoutConstraint.activate([
            keyboardHeight,
            preferredWidth,
            rootAlignment,
            root.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 6),
            root.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -6),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
        ])
        rootMaximumWidth.isActive = isTablet
        toolbar.axis = .horizontal; toolbar.spacing = 8; toolbar.alignment = .center
        cancelButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        cancelButton.accessibilityLabel = "音声入力のその他の操作"
        cancelButton.showsMenuAsPrimaryAction = true
        cancelButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        toolbar.addArrangedSubview(cancelButton)
        let settings = UIHostingController(rootView: KeyboardSettingsButton { [weak self] in self?.importSystemDictionary() })
        settingsHost = settings
        mount(settings, in: toolbar); settings.view.widthAnchor.constraint(equalToConstant: 36).isActive = true
        let activation = UIHostingController(rootView: ActivateKeyboardButton()); activationHost = activation
        mount(activation, in: toolbar)
        speechButton.layer.cornerRadius = 17
        speechButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        speechButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        speechButton.addAction(UIAction { [weak self] _ in self?.speechAction() }, for: .touchUpInside)
        toolbar.addArrangedSubview(speechButton)
        reviewButton.setTitle("修正する", for: .normal)
        reviewButton.accessibilityHint = "話した文をプレビューで直します"
        reviewButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        reviewButton.addAction(UIAction { [weak self] _ in self?.reviewAction() }, for: .touchUpInside)
        reviewButton.isHidden = true
        var pasteStyle = UIButton.Configuration.filled()
        pasteStyle.title = "貼り付ける"
        pasteStyle.baseBackgroundColor = .systemGreen
        pasteStyle.baseForegroundColor = .black
        pasteStyle.cornerStyle = .capsule
        pasteButton.configuration = pasteStyle
        pasteButton.accessibilityHint = "プレビューの文を現在の入力欄に入れます"
        pasteButton.addAction(UIAction { [weak self] _ in self?.insertRetainedDraft() }, for: .touchUpInside)
        pasteButton.isHidden = true
        toolbar.addArrangedSubview(pasteButton)
        toolbar.addArrangedSubview(reviewButton)
        toolbar.addArrangedSubview(UIView())
        var hideStyle = UIButton.Configuration.tinted()
        hideStyle.title = "しまう"
        hideStyle.image = UIImage(systemName: "keyboard.chevron.compact.down")
        hideStyle.imagePadding = 5
        hideStyle.cornerStyle = .capsule
        hideStyle.contentInsets = .init(top: 4, leading: 8, bottom: 4, trailing: 8)
        hideStyle.baseForegroundColor = .label
        hideButton.configuration = hideStyle
        hideButton.accessibilityLabel = "キーボードをしまう"
        hideButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        hideButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            draftInsertion = nil
            endManualReading()
            commit()
            cancelPending()
            dismissKeyboard()
        }, for: .touchUpInside)
        toolbar.addArrangedSubview(hideButton)
        // Keep the dismiss action at the screen edge even when iPad keys are narrow or left-aligned.
        let toolbarRow = UIView()
        root.addArrangedSubview(toolbarRow)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)
        toolbarLeading = toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        NSLayoutConstraint.activate([
            toolbarRow.heightAnchor.constraint(equalToConstant: 44),
            toolbar.topAnchor.constraint(equalTo: toolbarRow.topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: toolbarRow.bottomAnchor),
            toolbarLeading,
            toolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -6),
            hideButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        panes.axis = .vertical; panes.spacing = 6
        previewColumn.axis = .vertical; previewColumn.spacing = 6
        keysColumn.axis = .vertical
        panes.addArrangedSubview(previewColumn)
        panes.addArrangedSubview(keysColumn)
        root.addArrangedSubview(panes)
        keysWidth = keysColumn.widthAnchor.constraint(equalToConstant: 520)
        reviewHint.font = .preferredFont(forTextStyle: .footnote)
        reviewHint.adjustsFontForContentSizeCategory = true
        reviewHint.textColor = .label
        reviewHint.setContentHuggingPriority(.required, for: .vertical)
        reviewHint.isHidden = true
        previewColumn.addArrangedSubview(reviewHint)
        let previewArea = UIView()
        for item: UIView in [notice, correctionStrip] {
            item.translatesAutoresizingMaskIntoConstraints = false
            previewArea.addSubview(item)
            NSLayoutConstraint.activate([
                item.leadingAnchor.constraint(equalTo: previewArea.leadingAnchor),
                item.trailingAnchor.constraint(equalTo: previewArea.trailingAnchor),
                item.topAnchor.constraint(equalTo: previewArea.topAnchor),
                item.bottomAnchor.constraint(equalTo: previewArea.bottomAnchor)
            ])
        }
        correctionStrip.isHidden = true
        // On phones the preview, hint and candidates share one fixed-height band.
        let sizedPreview = isTablet ? previewArea : previewColumn
        noticeHeight = sizedPreview.heightAnchor.constraint(equalToConstant: 46)
        noticeHeight.isActive = true
        notice.accessibilityIdentifier = "dictation-preview"
        notice.accessibilityLabel = "認識プレビュー"
        previewColumn.addArrangedSubview(previewArea)
        candidates.axis = .horizontal; candidates.spacing = 8
        candidateScroll.addSubview(candidates); candidates.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            candidates.leadingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.leadingAnchor),
            candidates.trailingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.trailingAnchor),
            candidates.topAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.topAnchor),
            candidates.bottomAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.bottomAnchor),
            candidates.heightAnchor.constraint(equalTo: candidateScroll.frameLayoutGuide.heightAnchor)
        ])
        let candidateHeight = candidateScroll.heightAnchor.constraint(equalToConstant: Self.candidateRowHeight)
        candidateHeight.priority = .defaultHigh; candidateHeight.isActive = true
        previewColumn.addArrangedSubview(candidateScroll)
        bodyStack.axis = .vertical; bodyStack.spacing = 5
        for button in [
            key("あ", fontSize: 24) { [weak self] in self?.switchMode(.kana) },
            key("ABC", fontSize: 20) { [weak self] in self?.switchMode(.abc) },
            key("123", fontSize: 22) { [weak self] in self?.switchMode(.numbers) },
            key("😊", fontSize: 24) { [weak self] in self?.switchMode(.emoji) }
        ] { modeKeys.addArrangedSubview(button) }
        modeKeys.axis = .vertical
        modeKeys.spacing = 5
        modeKeys.distribution = .fillEqually
        modeKeys.accessibilityIdentifier = "keyboard-mode-switches"
        let modeWidth = modeKeys.widthAnchor.constraint(equalToConstant: 68)
        modeWidth.priority = .defaultHigh
        modeWidth.isActive = true
        keyArea.addArrangedSubview(modeKeys)
        keyArea.addArrangedSubview(bodyStack)
        keyArea.axis = .horizontal
        keyArea.spacing = 6
        keysColumn.addArrangedSubview(keyArea)
        keysColumn.addArrangedSubview(choicesPanel)
        choicesPanel.isHidden = true
        correctionStrip.onWord = { [weak self] word in self?.showAlternatives(for: word) }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: KeyboardViewController, _) in
            self.showCorrectionWords()
        }
        bottomBar.axis = .horizontal; bottomBar.alignment = .center
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.accessibilityLabel = "別のキーボード"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globe.widthAnchor.constraint(equalToConstant: 40).isActive = true
        bottomBar.addArrangedSubview(globe)
        bottomBar.spacing = 5
        if isTablet {
            for (title, direction) in [("←", -1), ("→", 1)] {
                let arrow = key(title, fontSize: 24) { [weak self] in self?.moveCursor(direction) }
                arrow.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
                arrow.heightAnchor.constraint(equalToConstant: 44).isActive = true
                arrow.accessibilityHint = "選択中は黄色の範囲を、通常はカーソルを1文字動かします"
                bottomBar.addArrangedSubview(arrow)
            }
        }
        selectionPart.selectedSegmentIndex = 0
        selectionPart.accessibilityLabel = "矢印で動かす部分"
        selectionPart.isHidden = true
        bottomBar.addArrangedSubview(selectionPart)
        finishReplacement.configuration = .tinted()
        finishReplacement.setTitle("修正を確定", for: .normal)
        finishReplacement.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        finishReplacement.addAction(UIAction { [weak self] _ in self?.confirmReplacement() }, for: .touchUpInside)
        finishReplacement.isHidden = true
        bottomBar.addArrangedSubview(finishReplacement)
        undoButton.setTitle("元に戻す", for: .normal)
        undoButton.titleLabel?.font = .systemFont(ofSize: reviewSize, weight: .semibold)
        undoButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        undoButton.addAction(UIAction { [weak self] _ in
            guard let self, let undo = correction?.undo else { return }
            applyCorrection(undo, isUndo: true)
        }, for: .touchUpInside)
        bottomBar.addArrangedSubview(undoButton)
        undoButton.isHidden = true
        bottomBar.addArrangedSubview(UIView())
        layoutButton.setTitle("幅・位置", for: .normal)
        layoutButton.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        layoutButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        layoutButton.showsMenuAsPrimaryAction = true
        layoutButton.accessibilityLabel = "キーボードの幅と位置を変更"
        bottomBar.addArrangedSubview(layoutButton)
        let bottomHeight = bottomBar.heightAnchor.constraint(equalToConstant: 44)
        bottomHeight.priority = .defaultHigh; bottomHeight.isActive = true
        root.addArrangedSubview(bottomBar)
        buildKeys()
        updateLayoutPreferences()
        updatePreviewLayout()
    }

    private func mount<T: View>(_ host: UIHostingController<T>, in stack: UIStackView) {
        addChild(host); host.view.backgroundColor = .clear; stack.addArrangedSubview(host.view); host.didMove(toParent: self)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The host's text document is not connected yet during viewWillAppear.
        // Reading documentIdentifier here can raise an Objective-C exception
        // when switching back from another app and terminate the extension.
        isVisible = false
        cancelPending(); focusID = UUID(); currentDocument = ""; tapCycle.reset()
        activationTicket = nil
        do { store = try AppGroupContainer.open() } catch { notice.text = error.localizedDescription }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        // Preserve unfinished kana only while the original field still answers.
        // Never commit old composition through a disconnected/new document.
        endManualReading()
        if !composer.isEmpty, availableDocumentID() == currentDocument { commit() }
        isVisible = false
        draftInsertion = nil
        editingCorrection?.cancel()
        editingCorrection = nil
        // Keep the last utterance in memory. Its old focus can only yield a copy.
        resetChoices()
        showCorrectionWords()
        correctionStrip.isHidden = true
        timer?.invalidate(); timer = nil
        cancelPending(); composer.clear(); tapCycle.reset(); updateCandidates()
        focusID = UUID(); currentDocument = ""; activationTicket = nil
        super.viewWillDisappear(animated)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        if !isTablet && !hasFullAccess {
            let storedLayout = UserDefaults.standard.string(forKey: "phoneKeyboardLayout") ?? ""
            snapshot.settings.phoneKeyboardLayout = PhoneKeyboardLayout(rawValue: storedLayout)
            updateLayoutPreferences()
        }
        focusSettlesAt = ProcessInfo.processInfo.systemUptime + 0.2
        refresh()
    }
    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        guard isVisible, !inserting else { return }
        if draftInsertion?.expires == nil { draftInsertion = nil }
        // Reconcile the document in refresh after UIKit finishes reconnecting;
        // input callbacks can arrive while the host proxy is still changing.
        focusSettlesAt = ProcessInfo.processInfo.systemUptime + 0.2
    }
    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        guard isVisible, !inserting else { return }
        if draftInsertion?.expires == nil { draftInsertion = nil }
        tapCycle.reset(); focusSettlesAt = ProcessInfo.processInfo.systemUptime + 0.2
        if pending != nil { cancelPending() }
    }

    private func availableDocumentID() -> String? {
        guard isVisible, viewIfLoaded?.window != nil,
              ProcessInfo.processInfo.systemUptime >= focusSettlesAt else { return nil }
        // UIKit can briefly reject even a public property during reconnection.
        // Swift cannot catch NSException; the narrow bridge returns nil so the
        // next visible refresh retries without inventing a document identity.
        return VoiceSeedReadDocumentIdentifier(textDocumentProxy)?.uuidString
    }

    private func importSystemDictionary() {
        guard hasFullAccess else { refresh(); return }
        requestSupplementaryLexicon { [weak self] lexicon in
            let pairs = lexicon.entries.map { ($0.userInput, $0.documentText) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let message: String
                do {
                    let container = try AppGroupContainer.open()
                    message = try container.update { state in
                        try DictionaryImporter.importSystemReplacements(pairs, into: &state.settings.dictionary, limit: 2000)
                    }
                } catch { message = error.localizedDescription }
                self.dictionaryImportNotice = (message, Date().addingTimeInterval(7))
                self.refresh()
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }

    private func showMicrophoneLevel(_ level: Double?) {
        let step = level.map { Int((max(0, min(1, $0)) * 10).rounded()) }
        guard step != meterStep else { return }
        meterStep = step
        guard let step else {
            speechButton.setImage(nil, for: .normal)
            speechButton.accessibilityValue = nil
            return
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 18)).image { _ in
            UIColor.black.setFill()
            for index in 0..<5 {
                let peak = CGFloat(15 - 4 * abs(2 - index))
                let height = 2 + peak * CGFloat(step) / 10
                let bar = CGRect(x: CGFloat(index * 4), y: (18 - height) / 2, width: 2.5, height: height)
                UIBezierPath(roundedRect: bar, cornerRadius: 1.25).fill()
            }
        }
        speechButton.setImage(image.withRenderingMode(.alwaysOriginal), for: .normal)
        speechButton.accessibilityValue = "マイク入力レベル \(step * 10)パーセント"
    }

    private func refresh() {
        guard isVisible else { return }
        updatePreviewLayout()
        guard hasFullAccess else {
            speechButton.isHidden = true; activationHost?.view.isHidden = false
            reviewButton.isHidden = true; pasteButton.isHidden = true; reviewHint.isHidden = true
            correctionStrip.isHidden = true
            undoButton.isHidden = true
            resetChoices()
            notice.isHidden = false
            notice.text = "設定で「オトナの音声入力 こえのたね」のフルアクセスを許可してください。音声は送信しません。"
            return
        }
        guard let document = availableDocumentID() else {
            speechButton.isEnabled = false
            return
        }
        if document != currentDocument {
            draftInsertion = nil
            endManualReading(); resetChoices(); showCorrectionWords()
            cancelPending(); tapCycle.reset(); composer.clear(); updateCandidates()
            focusID = UUID(); currentDocument = document; activationTicket = nil
        }
        if store == nil { store = try? AppGroupContainer.open() }
        do {
            if let store { snapshot = try store.read() }
            updateLayoutPreferences()
            #if DEBUG
            if let launch = snapshot.keyboardLaunch, let store {
                let trace = "visible=\(isVisible).settled=\(ProcessInfo.processInfo.systemUptime >= focusSettlesAt).foreground=\(snapshot.hostIsForeground == true).owner=\(launch.keyboardID == keyboardID).document=\(launch.documentID == document).phase=\(snapshot.phase.rawValue).pending=\(pending != nil)"
                if trace != snapshot.keyboardHandoffTrace { try store.update { $0.keyboardHandoffTrace = trace } }
            }
            #endif
            if let store, activationTicket == nil || Date().timeIntervalSince(activationTicket!.createdAt) > 30 {
                let ticket = KeyboardLaunch(documentID: document, createdAt: Date(), keyboardID: keyboardID)
                try store.update { $0.keyboardActivationTicket = ticket }
                activationTicket = ticket
                activationHost?.rootView = ActivateKeyboardButton(destination: VoiceSeedLink.dictationURL(ticket: ticket.id))
            }
            if isVisible, ProcessInfo.processInfo.systemUptime >= focusSettlesAt,
               pending == nil, snapshot.retainedDraft == nil,
               snapshot.keyboardLaunch != nil, snapshot.phase == .ready, let store {
                // Resume only in the initiating keyboard after the app leaves
                // the foreground; bind delivery to the current proxy and focus.
                let request: CaptureRequest? = try store.update { state in
                    guard state.commands.count < 16,
                          state.claimKeyboardLaunch(documentID: document, keyboardID: keyboardID, at: Date()),
                          let sessionID = state.sessionID else { return nil }
                    let request = CaptureRequest(id: UUID(), sessionID: sessionID, focusID: focusID,
                        documentID: document, startedAt: Date(), reviewBeforeInsertion: true)
                    state.commands.append(.init(kind: .start, request: request))
                    return request
                }
                if let request { endManualReading(); resetChoices(); commit(); pending = request }
            }
            syncDraftForReview()
            deliverRequestedDraft(in: document)
            composer.dictionary = (snapshot.settings.preferredCandidates ?? []) + snapshot.settings.dictionary
            if undoButton.titleLabel?.font.pointSize != reviewSize {
                undoButton.titleLabel?.font = .systemFont(ofSize: reviewSize, weight: .semibold)
                showCorrectionWords()
                updateCandidates()
            }
            let live = snapshot.isLive(at: Date())
            let hasDraft = snapshot.retainedDraft != nil && snapshot.request == nil
            let finalizing = stoppedRequest != nil
            let queued = finalizing && draftInsertion?.id == stoppedRequest?.id
            activationHost?.view.isHidden = live || hasDraft || finalizing
            speechButton.isHidden = !live || hasDraft || finalizing
            pasteButton.isHidden = !hasDraft && !finalizing
            let pasteTitle = finalizing ? (queued ? "貼り付け待ち" : "確定後に貼り付け") : "貼り付ける"
            if pasteButton.configuration?.title != pasteTitle { pasteButton.configuration?.title = pasteTitle }
            pasteButton.isEnabled = !queued && (finalizing || (hasDraft && snapshot.retainedDraft?.text.isEmpty == false))
                && composer.isEmpty && manualEdit == nil && selectedWord == nil && rangeSelection == nil
            let reviewing = isTablet && hasDraft && (expandedDraftID == reviewedDraftID || selectedWord != nil || manualEdit != nil || rangeSelection != nil)
            reviewButton.isHidden = !isTablet || !hasDraft
            reviewButton.setTitle(reviewing ? "修正中" : "修正する", for: .normal)
            reviewButton.isEnabled = !reviewing && composer.isEmpty
            if reviewing, choicesPanel.isHidden, manualEdit == nil, composer.isEmpty {
                beginChoices()
                choicesPanel.message("語をタップすると候補が出ます。好きな範囲を書き直すときは「範囲を選ぶ」を押します。")
                addRangeSelectionButton()
                choicesPanel.row([("キーに戻る", { [weak self] in
                    self?.expandedDraftID = nil
                    self?.closeChoices()
                })])
            }
            let discardID = snapshot.retainedDraft?.id ?? pending?.id
            cancelButton.isHidden = discardID == nil
            if discardMenuID != discardID || menuHasQueuedPaste != queued {
                discardMenuID = discardID
                menuHasQueuedPaste = queued
                cancelButton.menu = discardID.map { id in
                    var actions: [UIAction] = []
                    if queued {
                        actions.append(UIAction(title: "貼り付けの予約を取り消す") { [weak self] _ in
                            guard let self, draftInsertion?.id == id else { return }
                            draftInsertion = nil
                            refresh()
                        })
                    }
                    actions.append(UIAction(title: "この文章を破棄", attributes: .destructive) { [weak self] _ in
                        self?.discardCurrentText(id)
                    })
                    return UIMenu(children: actions)
                }
            }
            settingsHost?.view.isHidden = pending != nil || hasDraft
            let label: String
            switch snapshot.phase {
            case .listening: label = isTablet ? "録音を終了" : "終了して貼り付け"
            case .processing: label = "文章を確定中"
            case .ready: label = "🎙 タップして話す"
            default: label = snapshot.phase.label
            }
            showMicrophoneLevel(snapshot.phase == .listening ? snapshot.level : nil)
            speechButton.setTitle(label, for: .normal)
            speechButton.backgroundColor = snapshot.phase == .listening ? .systemGreen : .label
            speechButton.setTitleColor(snapshot.phase == .listening ? .black : .systemBackground, for: .normal)
            speechButton.isEnabled = [.ready, .listening].contains(snapshot.phase)
                && !(snapshot.phase == .ready && pending != nil)
                && !(snapshot.phase == .listening && (pending == nil || pending?.stoppedAt != nil))
            let showingPreview = !snapshot.preview.isEmpty && !hasDraft
            let previewText = showingPreview ? snapshot.preview : (snapshot.retainedDraft?.text ?? snapshot.keyboardGuidance(at: Date()))
            if let manualEdit {
                notice.display(manualEdit.committed + composer.reading, isPreview: true)
                finishReplacement.isEnabled = !manualEdit.committed.isEmpty || !composer.isEmpty
            }
            else if let result = dictionaryImportNotice, result.until > Date(), !showingPreview,
                    !hasDraft, pending == nil, [.inactive, .ready, .failed].contains(snapshot.phase) {
                notice.display(result.message, isPreview: false)
            } else { notice.display(previewText, isPreview: showingPreview || hasDraft) }
            let capturing = !hasDraft && (pending != nil || snapshot.phase == .listening || snapshot.phase == .processing)
            correctionStrip.isHidden = correction == nil || showingPreview || capturing || !composer.isEmpty || manualEdit != nil
            notice.isHidden = !correctionStrip.isHidden
            selectionPart.isHidden = correctionStrip.isHidden || highlightedRange == nil
            undoButton.isHidden = correction?.undo == nil || correctionStrip.isHidden || copySuggestion != nil || !selectionPart.isHidden
            let hint: String?
            if let manualEdit { hint = "「" + manualEdit.target.text + "」の代わりに入れる文字" }
            else if let rangeSelection {
                switch rangeSelection {
                case .first: hint = "直したい最初の文字をタップ"
                case .last: hint = "最後の文字をタップ、または矢印で調整"
                case .ready: hint = "← →で黄色の範囲を1文字ずつ調整"
                }
            }
            else if selectedWord != nil { hint = "← →で黄色の範囲を1文字ずつ調整" }
            else if !correctionStrip.isHidden {
                hint = hasDraft ? "貼り付け前 · 直したい語をタップ" : "貼り付け済み · 直したい語をタップ"
            } else if snapshot.phase == .listening { hint = "聞き取り中" }
            else { hint = nil }
            reviewHint.text = hint
            reviewHint.isHidden = hint == nil
            if (capturing || showingPreview) && (!choicesPanel.isHidden || manualEdit != nil) {
                endManualReading(); resetChoices()
            }
            if let pending, pending.sessionID != snapshot.sessionID || snapshot.finishedRequestID == pending.id {
                self.pending = nil
            }
        } catch SharedStoreError.busy { }
        catch { notice.text = error.localizedDescription }
    }

    private func speechAction() {
        endManualReading(); resetChoices()
        guard let document = availableDocumentID(), document == currentDocument else { return }
        guard let store else { return }
        do {
            if snapshot.phase == .listening, var request = pending, request.stoppedAt == nil {
                request.stoppedAt = Date()
                try store.enqueue(.init(kind: .stop, request: request))
                pending = request
                if !isTablet {
                    draftInsertion = (request.id, document, focusID, nil)
                }
                speechButton.isEnabled = false
                refresh()
                return
            }
            // The host polls asynchronously. Keep the first request until it is
            // accepted/delivered rather than replacing it on a rapid second tap.
            guard pending == nil, snapshot.phase == .ready, snapshot.isLive(at: Date()), let sessionID = snapshot.sessionID else { return }
            commit()
            let request = CaptureRequest(id: UUID(), sessionID: sessionID, focusID: focusID,
                documentID: document, startedAt: Date(), reviewBeforeInsertion: true)
            try store.enqueue(.init(kind: .start, request: request)); pending = request
            speechButton.isEnabled = false
        } catch { notice.text = error.localizedDescription }
    }

    private func reviewAction() {
        guard let draft = snapshot.retainedDraft, draft.id == reviewedDraftID else { return }
        expandedDraftID = draft.id
        refresh()
        UIAccessibility.post(notification: .layoutChanged, argument: correctionStrip)
    }

    private func cancelPending(preservingPreview: Bool = true) {
        draftInsertion = nil
        guard let request = pending, let store else { return }
        // Leaving a field after Stop withdraws the paste, but lets the host
        // finish saving the complete draft even if refinement takes seconds.
        if preservingPreview && request.stoppedAt != nil {
            pending = nil
            return
        }
        do {
            try store.enqueue(.init(kind: .cancel, request: request, preservePreview: preservingPreview))
            pending = nil
        } catch {
            // Keep ownership if the store was temporarily locked. The next
            // visible reconciliation can retry instead of losing the request.
        }
    }

    private func discardCurrentText(_ id: UUID) {
        draftInsertion = nil
        if pending?.id == id { cancelPending(preservingPreview: false) }
        try? store?.update { _ = $0.takeRetainedDraft(id) }
        refresh()
    }

    private func insertRetainedDraft() {
        guard isVisible, !currentDocument.isEmpty,
              composer.isEmpty, manualEdit == nil, selectedWord == nil, rangeSelection == nil else { return }
        if let request = stoppedRequest, request.documentID == currentDocument, request.focusID == focusID {
            draftInsertion = (request.id, currentDocument, focusID, nil)
        } else if let draft = snapshot.retainedDraft, !draft.text.isEmpty {
            draftInsertion = (draft.id, currentDocument, focusID, Date().addingTimeInterval(1))
        } else { return }
        refresh()
    }

    private func deliverRequestedDraft(in document: String) {
        guard let request = draftInsertion else { return }
        guard request.expires.map({ $0 > Date() }) != false, request.document == document,
              request.focus == focusID, let store else { draftInsertion = nil; return }
        if request.expires == nil && stoppedRequest?.id == request.id { return }
        draftInsertion = nil
        guard snapshot.retainedDraft?.id == request.id else { return }
        let id = request.id
        let originalFocus = focusID
        do {
            guard let draft = try store.update({ state -> RetainedDraft? in
                let expectedText = isTablet ? correction?.text : snapshot.retainedDraft?.text
                guard state.retainedDraft?.text == expectedText, state.retainedDraft?.text.isEmpty == false,
                      request.expires != nil || state.retainedDraft?.isInterruptedPreview != true else { return nil }
                return state.takeRetainedDraft(id)
            }) else { return }
            guard availableDocumentID() == document, focusID == originalFocus else {
                try store.update { if $0.retainedDraft == nil { $0.retainedDraft = draft } }
                return
            }
            inserting = true
            insertDictation(draft.text, document: document)
            inserting = false
            snapshot.retainedDraft = nil
            pasteButton.isHidden = true
            notice.text = ""
            if snapshot.history.contains(where: { $0.id == id }) {
                let pastedAt = Date()
                try? store.update { state in
                    guard let index = state.history.firstIndex(where: { $0.id == id }) else { return }
                    let entry = state.history[index]
                    let reviewTime = max(0, pastedAt.timeIntervalSince(entry.date) * 1000)
                    state.history[index].metrics.insertionMilliseconds = entry.metrics.finalizationMilliseconds
                        + entry.metrics.refinementMilliseconds + reviewTime
                }
            }
        } catch SharedStoreError.busy {
            draftInsertion = request
        } catch { notice.text = error.localizedDescription }
    }

    private func insertDictation(_ text: String, document: String) {
        let state = isTablet ? DictationCorrection(text: text, before: textDocumentProxy.documentContextBeforeInput,
            after: textDocumentProxy.documentContextAfterInput, document: document, focus: focusID) : nil
        textDocumentProxy.insertText(text)
        editingCorrection?.cancel()
        editingCorrection = nil
        copySuggestion = nil
        reviewedDraftID = nil
        expandedDraftID = nil
        endManualReading()
        resetChoices()
        correction = state
        showCorrectionWords()
    }

    private func syncDraftForReview() {
        guard isTablet else { return }
        let draft = snapshot.retainedDraft
        guard draft?.id != reviewedDraftID || (draft != nil && draft?.text != correction?.text) else { return }
        editingCorrection?.cancel()
        editingCorrection = nil
        endManualReading()
        resetChoices()
        copySuggestion = nil
        reviewedDraftID = draft?.id
        correction = draft.map {
            DictationCorrection(text: $0.text, before: nil, after: nil, document: "", focus: focusID)
        }
        showCorrectionWords()
    }

    private func resetChoices() {
        rangeSelection = nil
        correctionStrip.onCharacter = nil
        selectedWord = nil
        selectionPart.selectedSegmentIndex = 0
        selectionPart.isHidden = true
        registration = nil
        showingAllTypedCandidates = false
        choicesPanel.reset()
        choicesPanel.isHidden = true
        keyArea.isHidden = false
    }

    private var highlightedRange: Range<Int>? {
        switch rangeSelection {
        case .first: return nil
        case .last(let start): return start..<(start + 1)
        case .ready(let selection): return selection.range
        case nil: return selectedWord?.range
        }
    }

    private func showCorrectionWords() {
        guard let correction else { return }
        correctionStrip.show(copySuggestion ?? correction.text, words: copySuggestion == nil ? correction.words : [],
                             selected: copySuggestion == nil ? highlightedRange : nil)
        undoButton.isHidden = correction.undo == nil || copySuggestion != nil
        if let copySuggestion {
            beginChoices()
            choicesPanel.message("入力先を確認できません。修正文をコピーできます。")
            choicesPanel.row([("修正文をコピー", { [weak self] in
                UIPasteboard.general.setItems([[UTType.plainText.identifier: copySuggestion]], options: [.localOnly: true])
                self?.closeChoices()
            }), ("閉じる", { [weak self] in self?.closeChoices() })])
        }
    }

    private func beginChoices() {
        choicesPanel.reset()
        choicesPanel.pointSize = reviewSize
        choicesPanel.isHidden = false
        keyArea.isHidden = true
    }

    private func closeChoices() {
        endManualReading()
        copySuggestion = nil
        resetChoices()
        showCorrectionWords()
    }

    private func addRangeSelectionButton() {
        choicesPanel.row([("範囲を選ぶ", { [weak self] in self?.startRangeSelection() })])
    }

    private func startRangeSelection() {
        guard correction != nil, copySuggestion == nil, editingCorrection == nil else { return }
        resetChoices()
        rangeSelection = .first
        correctionStrip.onCharacter = { [weak self] offset in self?.pickRangeEndpoint(offset) }
        beginChoices()
        choicesPanel.message("プレビューで最初の文字、次に最後の文字をタップします。")
        choicesPanel.row([("やめる", { [weak self] in self?.closeChoices() })])
        showCorrectionWords()
        refresh()
    }

    private func pickRangeEndpoint(_ offset: Int) {
        guard let rangeSelection, let correction else { return }
        switch rangeSelection {
        case .first, .ready:
            self.rangeSelection = .last(offset)
            beginChoices()
            choicesPanel.message("最後の文字をタップしてください。")
        case .last(let first):
            guard let part = correction.selection(from: first, through: offset) else { return }
            showRange(part)
            return
        }
        choicesPanel.row([("やめる", { [weak self] in self?.closeChoices() })])
        showCorrectionWords()
        refresh()
    }

    private func showRange(_ part: DictationCorrection.Word) {
        selectedWord = nil
        rangeSelection = .ready(part)
        correctionStrip.onCharacter = { [weak self] offset in self?.pickRangeEndpoint(offset) }
        beginChoices()
        choicesPanel.row([("書き直す", { [weak self] in self?.startManualReading(part) }),
                          ("選び直す", { [weak self] in self?.startRangeSelection() })])
        choicesPanel.row([("この範囲を消す", { [weak self] in
            self?.applyCorrection(.init(start: part.start, from: part.text, to: ""), isUndo: false)
        }), ("やめる", { [weak self] in self?.closeChoices() })])
        showCorrectionWords()
        refresh()
    }

    private func showAlternatives(for word: DictationCorrection.Word) {
        guard editingCorrection == nil else { return }
        selectedWord = word
        registration = nil
        let preferred = (snapshot.settings.preferredCandidates ?? []).filter { $0.heard == word.reading }.map(\.written)
        let spellings = ["斎藤", "齋藤", "斉藤", "齊藤"]
        let variants = spellings.contains(word.text) ? spellings : []
        var seen: Set<String> = [word.text, word.reading]
        let alternatives = (preferred + variants + composer.conversions(for: word.reading)).filter { seen.insert($0).inserted }
        let literal = word.reading == word.text ? [] : [word.reading]
        showCorrectionWords()
        showChoicePage(Array(alternatives.prefix(1)) + [word.text] + literal + Array(alternatives.dropFirst()), for: word, offset: 0)
    }

    private func showChoicePage(_ choices: [String], for word: DictationCorrection.Word, offset: Int) {
        beginChoices()
        let page = choices.dropFirst(offset).prefix(3)
        let actions: [(String, () -> Void)] = page.map { choice in
            (choice, { [weak self] in
                guard let self else { return }
                if choice == word.text { closeChoices(); return }
                applyCorrection(.init(start: word.start, from: word.text, to: choice), isUndo: false, reading: word.reading)
            })
        }
        let columnWidth = (root.bounds.width - CGFloat(max(0, page.count - 1)) * 5) / CGFloat(max(1, page.count))
        let font = UIFont.systemFont(ofSize: reviewSize, weight: .semibold)
        if page.contains(where: { ($0 as NSString).size(withAttributes: [.font: font]).width + 12 > columnWidth }) {
            for action in actions { choicesPanel.row([action]) }
        } else { choicesPanel.row(actions) }
        addRangeSelectionButton()
        var more: [(String, () -> Void)] = [("かなで直す", { [weak self] in self?.startManualReading(word) })]
        if choices.count > 3 {
            let next = offset + 3 < choices.count ? offset + 3 : 0
            more.append((next == 0 ? "最初の候補" : "ほかの候補", { [weak self] in
                self?.showChoicePage(choices, for: word, offset: next)
            }))
        }
        choicesPanel.row(more)
        if let words = correction?.words, let i = words.firstIndex(where: { $0.start == word.start }) {
            var navigation: [(String, () -> Void)] = []
            if i > 0 { navigation.append(("前の語", { [weak self] in self?.showAlternatives(for: words[i - 1]) })) }
            if i + 1 < words.count { navigation.append(("次の語", { [weak self] in self?.showAlternatives(for: words[i + 1]) })) }
            if !navigation.isEmpty { choicesPanel.row(navigation) }
        }
        choicesPanel.row([("この語を消す", { [weak self] in
            self?.applyCorrection(.init(start: word.start, from: word.text, to: ""), isUndo: false)
        }), ("閉じる", { [weak self] in self?.closeChoices() })])
    }

    private func startManualReading(_ word: DictationCorrection.Word) {
        resetChoices()
        manualEdit = ManualReplacement(target: word)
        finishReplacement.isHidden = false
        composer.clear()
        tapCycle.reset()
        mode = .kana
        buildKeys()
        lastCandidateText = ""
        updateCandidates()
        refresh()
    }

    private func endManualReading() {
        guard manualEdit != nil else { return }
        manualEdit = nil
        finishReplacement.isHidden = true
        composer.clear()
        tapCycle.reset()
        updateCandidates()
    }

    private func confirmReplacement() {
        guard let manualEdit else { return }
        let word = manualEdit.target
        let replacement = manualEdit.committed + composer.reading
        let reading = composer.isEmpty ? manualEdit.singleConversionReading : nil
        guard !replacement.isEmpty else { return }
        if replacement == word.text { closeChoices(); return }
        if reviewedDraftID == nil { endManualReading() }
        applyCorrection(.init(start: word.start, from: word.text, to: replacement), isUndo: false, reading: reading)
    }

    private func offerRegistration(reading: String, written: String) {
        let entry = DictionaryEntry(heard: reading, written: written)
        guard !(snapshot.settings.preferredCandidates ?? []).contains(where: { $0.heard == reading && $0.written == written }) else { return }
        registration = entry
        beginChoices()
        choicesPanel.message("「" + reading + "」の候補で「" + written + "」を優先しますか？")
        choicesPanel.row([("登録する", { [weak self] in
            guard let self, let store, let entry = registration else { return }
            do {
                snapshot = try store.update { state in state.settings.prefer(entry); return state }
                guard snapshot.settings.preferredCandidates?.contains(where: { $0.heard == entry.heard && $0.written == entry.written }) == true else {
                    choicesPanel.message("登録できません。辞書の件数と語の長さを確認してください。")
                    return
                }
                closeChoices()
            } catch { choicesPanel.message("登録できませんでした。もう一度お試しください。") }
        }), ("今回だけ", { [weak self] in self?.closeChoices() })])
    }

    private func sameCorrectionField(_ state: DictationCorrection) -> Bool {
        availableDocumentID() == state.document && focusID == state.focus && pending == nil
            && composer.isEmpty && snapshot.request == nil && textDocumentProxy.selectedText?.isEmpty != false
    }

    private func correctionMatches(_ state: DictationCorrection, at caret: Int) -> Bool {
        guard sameCorrectionField(state) else { return false }
        return state.matches(before: textDocumentProxy.documentContextBeforeInput,
                             after: textDocumentProxy.documentContextAfterInput, at: caret)
    }

    // The host text view applies proxy movements asynchronously. No deletion is issued
    // until both sides of the requested word boundary match in the originating field.
    private func awaitCaret(_ state: DictationCorrection, at caret: Int) async -> Bool {
        for _ in 0..<20 {
            if Task.isCancelled { return false }
            if correctionMatches(state, at: caret) { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return false
    }

    private func moveCaret(in text: String, from start: Int, to end: Int) {
        guard start != end else { return }
        let distance = text.prefix(end).utf16.count - text.prefix(start).utf16.count
        textDocumentProxy.adjustTextPosition(byCharacterOffset: distance)
    }

    private func visibleWindow(_ state: DictationCorrection, at offset: Int) async -> (left: Int, right: Int)? {
        for _ in 0..<16 {
            guard !Task.isCancelled, isVisible, focusID == state.focus, pending == nil else { return nil }
            if sameCorrectionField(state) {
                let before = textDocumentProxy.documentContextBeforeInput
                let after = textDocumentProxy.documentContextAfterInput
                if state.agreesWithWindow(before: before, after: after, at: offset) {
                    return (before?.count ?? 0, after?.count ?? 0)
                }
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    /// For hosts that expose just a few sentences, verify overlapping windows
    /// from the end back to the beginning, then return to the chosen word.
    private func verifyUtterance(_ state: DictationCorrection, at target: Int, deleting count: Int) async -> Bool {
        if await awaitCaret(state, at: target) { return true }
        guard let first = await visibleWindow(state, at: target), first.left >= count else { return false }
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        moveCaret(in: state.text, from: target, to: state.text.count)
        try? await Task.sleep(for: .milliseconds(80))
        var offset = state.text.count
        while let window = await visibleWindow(state, at: offset) {
            if offset == 0 {
                moveCaret(in: state.text, from: offset, to: target)
                try? await Task.sleep(for: .milliseconds(80))
                guard let final = await visibleWindow(state, at: target) else { return false }
                return final.left >= count
            }
            guard ProcessInfo.processInfo.systemUptime < deadline, window.left > 0 else { return false }
            // iOS often exposes more text before the caret than after it.
            // Both sides are checked at every boundary; never skip unread text.
            let next = max(0, offset - window.left)
            moveCaret(in: state.text, from: offset, to: next)
            offset = next
            try? await Task.sleep(for: .milliseconds(80))
        }
        return false
    }

    private func applyCorrection(_ edit: DictationCorrection.Edit, isUndo: Bool, reading: String? = nil) {
        guard editingCorrection == nil, let state = correction,
              let revised = state.applying(edit, isUndo: isUndo) else { return }
        if let id = reviewedDraftID {
            guard let store else { return }
            do {
                let saved = try store.update { $0.reviseDraft(id, replacing: state.text, with: revised.text) }
                guard saved else { refresh(); return }
                endManualReading()
                snapshot.retainedDraft?.text = revised.text
                correction = revised
                resetChoices()
                showCorrectionWords()
                if let reading { offerRegistration(reading: reading, written: edit.to) }
            } catch {
                UIAccessibility.post(notification: .announcement, argument: "修正を保存できませんでした")
                choicesPanel.message("修正を保存できませんでした。もう一度タップしてください。")
            }
            return
        }
        editingCorrection = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if !Task.isCancelled { editingCorrection = nil } }
            let end = edit.start + edit.from.count
            let windowMatches = sameCorrectionField(state) &&
                state.agreesWithWindow(before: textDocumentProxy.documentContextBeforeInput,
                                       after: textDocumentProxy.documentContextAfterInput, at: state.caret)
            let canLocateWord = windowMatches ? true : await awaitCaret(state, at: state.caret)
            if canLocateWord {
                moveCaret(in: state.text, from: state.caret, to: end)
                if await verifyUtterance(state, at: end, deleting: edit.from.count) {
                    inserting = true
                    for _ in edit.from { textDocumentProxy.deleteBackward() }
                    if !edit.to.isEmpty { textDocumentProxy.insertText(edit.to) }
                    inserting = false
                    if await verifyUtterance(revised, at: revised.caret, deleting: edit.to.count) {
                        // Restore the end of the utterance so the next dictation follows it.
                        // Some hosts return a shortened context once an interior caret settles.
                        var confirmed = revised
                        if revised.caret != revised.text.count {
                            moveCaret(in: revised.text, from: revised.caret, to: revised.text.count)
                            if await visibleWindow(revised, at: revised.text.count) != nil { confirmed = revised.atEndOfUtterance() }
                        }
                        guard !Task.isCancelled else { return }
                        resetChoices()
                        correction = confirmed
                        showCorrectionWords()
                        if let reading { offerRegistration(reading: reading, written: edit.to) }
                        return
                    }
                }
            }
            guard !Task.isCancelled else { return }
            resetChoices()
            copySuggestion = revised.text
            showCorrectionWords()
        }
    }

    private func key(_ title: String, fontSize: CGFloat = 17, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal); button.titleLabel?.font = .systemFont(ofSize: fontSize, weight: .medium)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.65
        button.contentEdgeInsets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        button.setTitleColor(.label, for: .normal); button.backgroundColor = .systemGray3; button.layer.cornerRadius = 7
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
    private func clearStack(_ stack: UIStackView) {
        for child in stack.arrangedSubviews { stack.removeArrangedSubview(child); child.removeFromSuperview() }
    }
    private func row(_ views: [UIView]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: views); row.axis = .horizontal; row.spacing = 5; row.distribution = .fillEqually
        return row
    }
    private func buildKeys() {
        clearStack(bodyStack)
        let keypad = !isTablet && activePhoneLayout == .keypad
        modeKeys.isHidden = keypad
        composer.convertsReading = !keypad || mode == .kana
        if keypad {
            buildPhoneKeypad()
            return
        }
        switch mode {
        case .kana:
            let middle = UIStackView(); middle.axis = .vertical; middle.spacing = 5; middle.distribution = .fillEqually
            for groups in KanaLayout.rows {
                middle.addArrangedSubview(row(groups.map { values in
                    let button = KanaFlickKey(values: values)
                    button.onInput = { [weak self] values, index in
                        if values[index] == "゛゜小" { self?.alternate() }
                        else { self?.typeKana(values: values, index: index) }
                    }; return button
                }))
            }
            let space = spaceButton("空白")
            let right = UIStackView(arrangedSubviews: [deleteKey(), space])
            right.axis = .vertical
            right.spacing = 5
            if isTablet {
                right.arrangedSubviews[0].heightAnchor.constraint(equalToConstant: 45).isActive = true
                space.heightAnchor.constraint(equalToConstant: 45).isActive = true
            } else {
                right.addArrangedSubview(previousCharacterKey())
                right.distribution = .fillEqually
            }
            right.addArrangedSubview(key("改行") { [weak self] in self?.enter() })
            let body = UIStackView(arrangedSubviews: [middle, right]); body.axis = .horizontal; body.spacing = 6
            right.widthAnchor.constraint(equalTo: body.widthAnchor, multiplier: 0.22).isActive = true
            bodyStack.addArrangedSubview(body)
        case .abc:
            for letters in ["qwertyuiop", "asdfghjkl", "zxcvbnm"] {
                bodyStack.addArrangedSubview(row(letters.map { character in
                    let value = uppercase ? String(character).uppercased() : String(character)
                    return key(value, fontSize: 30) { [weak self] in self?.typeDirect(value) }
                }))
            }
            bodyStack.addArrangedSubview(row([
                key("⇧") { [weak self] in self?.uppercase.toggle(); self?.buildKeys() },
                spaceButton("space"),
                deleteKey(),
                key("改行") { [weak self] in self?.enter() }
            ]))
            bodyStack.distribution = .fillEqually
        case .numbers, .emoji:
            let rows = mode == .numbers ? ["1234567890", "-/:;()¥&@\"", ".,?!'％+＝〜"] : ["😊😂🥰😅👍", "🙏🙇🎉✨❤️", "👀💡✅📩🌱"]
            for letters in rows {
                bodyStack.addArrangedSubview(row(letters.map { character in
                    key(String(character), fontSize: 30) { [weak self] in self?.typeDirect(String(character)) }
                }))
            }
            bodyStack.addArrangedSubview(row([
                spaceButton("空白"),
                deleteKey(), key("改行") { [weak self] in self?.enter() }
            ])); bodyStack.distribution = .fillEqually
        }
    }
    private func buildPhoneKeypad() {
        let left = UIStackView()
        let center = UIStackView()
        let right = UIStackView()
        for column in [left, center, right] {
            column.axis = .vertical
            column.spacing = 5
        }
        left.distribution = .fillEqually
        center.distribution = .fillEqually
        let back = key("←", fontSize: 23) { [weak self] in self?.moveCursor(-1) }
        back.accessibilityLabel = "カーソルを左へ"
        let reverse = previousCharacterKey()
        let modes: [(Mode, String)] = [(.kana, "かな"), (.abc, "英字"), (.numbers, "数字")]
        let modeKey = key("あA1", fontSize: 19) { [weak self] in
            guard let self else { return }
            switchMode(mode == .kana ? .abc : mode == .abc ? .numbers : .kana)
        }
        let selectedMode = modes.firstIndex { $0.0 == mode }
        let legend = NSMutableAttributedString(string: "あA1", attributes: [.foregroundColor: UIColor.secondaryLabel])
        if let selectedMode {
            legend.addAttributes([.foregroundColor: UIColor.label, .font: UIFont.boldSystemFont(ofSize: 23)],
                                 range: NSRange(location: selectedMode, length: 1))
        }
        modeKey.setAttributedTitle(legend, for: .normal)
        modeKey.accessibilityLabel = "文字種の切り替え"
        modeKey.accessibilityValue = selectedMode.map { modes[$0].1 } ?? "絵文字"
        modeKey.accessibilityHint = "かな、英字、数字の順に切り替えます"
        modeKey.menu = UIMenu(children: modes.map { option, title in
            UIAction(title: title, state: option == mode ? .on : .off) { [weak self] _ in self?.switchMode(option) }
        })
        for button in [back, reverse, modeKey] { left.addArrangedSubview(button) }

        let emoji = { [weak self] in self?.switchMode(.emoji) }
        switch mode {
        case .kana:
            left.addArrangedSubview(key("゛゜小") { [weak self] in self?.alternate() })
            for groups in KanaLayout.rows {
                var buttons: [UIView] = []
                for values in groups {
                    if values == ["゛゜小"] {
                        let smile = key("☺", fontSize: 26) { emoji() }
                        smile.accessibilityLabel = "絵文字"
                        buttons.append(smile)
                    } else {
                        let button = KanaFlickKey(values: values)
                        button.onInput = { [weak self] in self?.typeKana(values: $0, index: $1) }
                        buttons.append(button)
                    }
                }
                center.addArrangedSubview(row(buttons))
            }
        case .abc, .numbers:
            let latin = mode == .abc
            if latin {
                let shift = key(uppercase ? "A→a" : "a→A") { [weak self] in
                    self?.commit()
                    self?.uppercase.toggle()
                    self?.buildKeys()
                }
                shift.accessibilityLabel = uppercase ? "小文字に切り替え" : "大文字に切り替え"
                left.addArrangedSubview(shift)
            } else {
                left.addArrangedSubview(key("😊") { emoji() })
            }
            for groups in latin ? PhoneKeypad.latinRows : PhoneKeypad.numberRows {
                center.addArrangedSubview(row(groups.map { group in
                    let values = (latin && uppercase ? group.uppercased() : group).map(String.init)
                    let digit = !latin && group.first?.isNumber == true
                    let label = digit ? values[0] : group.uppercased()
                    let hint = digit ? values.dropFirst().joined(separator: " ") : ""
                    let button = KanaFlickKey(values: values, legend: label, detail: hint)
                    if digit {
                        button.accessibilityLabel = values[0] + "、フリックで" + values.dropFirst().joined(separator: "、")
                    }
                    button.onInput = { [weak self] values, index in
                        if digit { self?.typeDirect(values[index]) }
                        else { self?.typeKana(values: values, index: index) }
                    }
                    return button
                }))
            }
        case .emoji:
            left.addArrangedSubview(key("かな") { [weak self] in self?.switchMode(.kana) })
            for group in ["😊😂🥰😅👍", "🙏🙇🎉✨❤️", "👀💡✅📩🌱"] {
                center.addArrangedSubview(row(group.map { character in
                    key(String(character), fontSize: 23) { [weak self] in self?.typeDirect(String(character)) }
                }))
            }
        }
        let delete = deleteKey()
        let space = spaceButton("空白")
        let enter = key("改行") { [weak self] in self?.enter() }
        for item: UIView in [delete, space, enter] { right.addArrangedSubview(item) }
        let grid = UIStackView(arrangedSubviews: [left, center, right])
        grid.spacing = 5
        grid.accessibilityIdentifier = "phone-tenkey-grid"
        bodyStack.addArrangedSubview(grid)
        NSLayoutConstraint.activate([
            left.widthAnchor.constraint(equalTo: grid.widthAnchor, multiplier: 0.2, constant: -4),
            right.widthAnchor.constraint(equalTo: left.widthAnchor),
            delete.heightAnchor.constraint(equalTo: back.heightAnchor),
            space.heightAnchor.constraint(equalTo: back.heightAnchor)
        ])
    }
    private func switchMode(_ next: Mode) {
        guard mode != next else { return }
        commit()
        mode = next
        buildKeys()
    }
    private func typeKana(values: [String], index: Int) {
        cancelPending()
        let edit = tapCycle.resolve(values: values, selectedIndex: index,
            at: ProcessInfo.processInfo.systemUptime, currentLast: composer.reading.last.map(String.init))
        if edit.replacesLast { composer.replaceLast(edit.text) }
        else {
            if composer.reading.count >= 80 { commit() }
            composer.append(edit.text)
        }
        setMarked(); updateCandidates()
    }
    private func previousCharacterKey() -> UIButton {
        let button = key("") { [weak self] in self?.reverseKana() }
        let symbol = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        button.setImage(UIImage(systemName: "arrow.counterclockwise", withConfiguration: symbol), for: .normal)
        button.tintColor = .label
        button.accessibilityLabel = mode == .kana ? "前のかなに戻す" : "前の文字に戻す"
        button.accessibilityHint = mode == .kana ? "例えば「う」を「い」に戻します" : "同じキーの一つ前の文字に戻します"
        button.isEnabled = tapCycle.canReverse(composer.reading.last.map(String.init))
        reverseButton = button
        return button
    }

    private func reverseKana() {
        guard let edit = tapCycle.reverse(currentLast: composer.reading.last.map(String.init),
                                          at: ProcessInfo.processInfo.systemUptime) else { return }
        composer.replaceLast(edit.text)
        setMarked()
        updateCandidates()
    }
    private func alternate() { cancelPending(); tapCycle.reset(); composer.alternateLast(); setMarked(); updateCandidates() }
    private func setMarked() {
        guard manualEdit == nil else { return }
        inserting = true
        textDocumentProxy.setMarkedText(composer.reading, selectedRange: NSRange(location: composer.reading.utf16.count, length: 0))
        inserting = false
    }
    private func commit(_ candidate: String? = nil) {
        tapCycle.reset()
        guard !composer.isEmpty else { return }
        if var edit = manualEdit {
            let segment = candidate ?? composer.reading
            edit.singleConversionReading = edit.committed.isEmpty && segment != composer.reading ? composer.reading : nil
            edit.committed += segment
            manualEdit = edit
            composer.clear()
            updateCandidates()
            return
        }
        inserting = true
        textDocumentProxy.setMarkedText(candidate ?? composer.reading, selectedRange: NSRange(location: (candidate ?? composer.reading).utf16.count, length: 0))
        textDocumentProxy.unmarkText(); inserting = false
        composer.clear(); updateCandidates()
    }
    private func typeDirect(_ value: String) {
        if manualEdit != nil {
            commit()
            manualEdit?.committed.append(value)
            manualEdit?.singleConversionReading = nil
            refresh()
            return
        }
        cancelPending(); commit(); inserting = true; textDocumentProxy.insertText(value); inserting = false
    }
    private func delete() {
        cancelPending(); tapCycle.reset()
        if !composer.isEmpty { composer.delete(); setMarked(); updateCandidates(); if composer.isEmpty && manualEdit == nil { textDocumentProxy.unmarkText() } }
        else if manualEdit?.committed.isEmpty == false {
            manualEdit?.committed.removeLast()
            manualEdit?.singleConversionReading = nil
            refresh()
        }
        else if manualEdit == nil { inserting = true; textDocumentProxy.deleteBackward(); inserting = false }
    }
    private func deleteKey() -> DeleteKey {
        let key = DeleteKey(frame: .zero)
        key.onDelete = { [weak self] in self?.delete() }
        key.onDeleteBunsetsu = { [weak self] in self?.deleteBunsetsu() }
        return key
    }
    private func deleteBunsetsu() {
        cancelPending(); tapCycle.reset()
        if !composer.isEmpty {
            composer.removeLast(BunsetsuDeletion.characterCount(beforeCursor: composer.reading))
            setMarked(); updateCandidates()
            if composer.isEmpty && manualEdit == nil { textDocumentProxy.unmarkText() }
        } else if let prefix = manualEdit?.committed {
            manualEdit?.committed = String(prefix.dropLast(BunsetsuDeletion.characterCount(beforeCursor: prefix)))
            manualEdit?.singleConversionReading = nil
            refresh()
        } else if manualEdit == nil {
            let count = textDocumentProxy.selectedText?.isEmpty == false ? 1
                : BunsetsuDeletion.characterCount(beforeCursor: textDocumentProxy.documentContextBeforeInput ?? "")
            inserting = true
            for _ in 0..<count { textDocumentProxy.deleteBackward() }
            inserting = false
        }
    }
    private func enter() { cancelPending(); if composer.convertsReading && !composer.isEmpty { commit() } else { typeDirect("\n") } }
    private func moveCursor(_ delta: Int) {
        guard manualEdit == nil, editingCorrection == nil else { return }
        if let highlightedRange, let correction {
            guard let edge = DictationCorrection.SelectionPart(rawValue: selectionPart.selectedSegmentIndex),
                  let adjusted = correction.adjusting(highlightedRange, part: edge, by: delta) else { return }
            if let word = correction.words.first(where: { $0.range == adjusted.range }) {
                rangeSelection = nil
                correctionStrip.onCharacter = nil
                showAlternatives(for: word)
            } else { showRange(adjusted) }
            return
        }
        guard rangeSelection == nil else { return }
        cancelPending(); commit(); textDocumentProxy.adjustTextPosition(byCharacterOffset: delta)
    }
    private func spaceButton(_ title: String) -> UIButton {
        let button = key(title) { [weak self] in
            guard let self else { return }; self.cancelPending()
            if self.composer.convertsReading && !self.composer.isEmpty { self.commit(self.composer.candidates.first) } else { self.typeDirect(" ") }
        }
        button.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(spaceTrackpad(_:))))
        return button
    }
    @objc private func spaceTrackpad(_ gesture: UILongPressGestureRecognizer) {
        guard manualEdit == nil else { return }
        let x = gesture.location(in: view).x
        if gesture.state == .began { cancelPending(); commit(); spaceOrigin = x; spaceOffset = 0 }
        if gesture.state == .changed {
            let next = Int((x - spaceOrigin) / 12), delta = next - spaceOffset
            if delta != 0 { textDocumentProxy.adjustTextPosition(byCharacterOffset: delta); spaceOffset = next }
        }
    }
    private func updateCandidates() {
        reverseButton?.isEnabled = tapCycle.canReverse(composer.reading.last.map(String.init))
        // Keep the literal reading reachable even when conversion has many results.
        let displayed = composer.isEmpty || !composer.convertsReading ? [] : [composer.reading] + composer.candidates.filter { $0 != composer.reading }
        let signature = String(manualEdit != nil) + String(Int(reviewSize)) + displayed.joined(separator: "\u{0}")
        guard signature != lastCandidateText else { return }
        lastCandidateText = signature
        clearStack(candidates)
        func add(_ label: String, action: @escaping () -> Void) {
            let button = key(label, fontSize: reviewSize, action: action)
            button.titleLabel?.adjustsFontSizeToFitWidth = false
            button.contentEdgeInsets = .init(top: 3, left: 8, bottom: 3, right: 8)
            candidates.addArrangedSubview(button)
        }
        if manualEdit != nil { add("やめる") { [weak self] in self?.closeChoices() } }
        let hasMore = displayed.count > 3
        let longCandidate = displayed.prefix(3).contains { $0.count > 5 }
        func addList() {
            add("一覧") { [weak self] in self?.showTypedPage(displayed, offset: 0) }
        }
        if longCandidate { addList() }
        for text in displayed.prefix(3) { add(text) { [weak self] in self?.commit(text) } }
        if hasMore && !longCandidate { addList() }
        updatePreviewLayout()
    }

    private func showTypedPage(_ displayed: [String], offset: Int) {
        showingAllTypedCandidates = true
        beginChoices()
        for text in displayed.dropFirst(offset).prefix(3) {
            choicesPanel.row([(text, { [weak self] in self?.resetChoices(); self?.commit(text) })])
        }
        var actions: [(String, () -> Void)] = [("キーに戻る", { [weak self] in self?.resetChoices() })]
        if displayed.count > 3 {
            let next = offset + 3 < displayed.count ? offset + 3 : 0
            actions.append((next == 0 ? "最初の候補" : "ほかの候補", { [weak self] in self?.showTypedPage(displayed, offset: next) }))
        }
        choicesPanel.row(actions)
    }

    private func updatePreviewLayout() {
        // Give empty rows to the preview without making keys jump or shrink.
        // Face ID iPhones already have the system globe outside this view.
        candidateScroll.isHidden = !composer.convertsReading || (composer.isEmpty && manualEdit == nil) || showingAllTypedCandidates
        globe.isHidden = !needsInputModeSwitchKey
        updateLandscapeLayout()
        if sideBySide {
            // One toolbar and four full-size key rows. Preview and candidates share their height.
            let keyRows: CGFloat = 4 * 44 + 3 * 5
            keyboardHeight.constant = 10 + 44 + root.spacing + keyRows
            return
        }
        if !isTablet {
            // Reserve the same space before, during and after composition. Resizing the
            // extension animates the key under a finger even if its final frame is unchanged.
            let line = ceil(UIFont.dictationPreview(compatibleWith: traitCollection).lineHeight)
            noticeHeight.constant = Self.candidateRowHeight + 2 * previewColumn.spacing
                + ceil(reviewHint.font.lineHeight) + line + 16
            keyboardHeight.constant = 306 + noticeHeight.constant
            return
        }
        let extraRows: CGFloat = (candidateScroll.isHidden ? 0 : 54) + 50
        let expanded = reviewedDraftID != nil && reviewedDraftID == expandedDraftID && manualEdit == nil
        noticeHeight.constant = expanded ? 120 : 80
        keyboardHeight.constant = 256 + noticeHeight.constant + extraRows + (reviewHint.isHidden ? 0 : ceil(reviewHint.font.lineHeight) + 6)
    }

    private func updateLandscapeLayout() {
        guard isTablet else { return }
        let width = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right - 12
        let landscape = view.window?.windowScene?.effectiveGeometry.interfaceOrientation.isLandscape == true
        let wide = landscape && width >= 680
        if wide != sideBySide {
            sideBySide = wide
            panes.axis = wide ? .horizontal : .vertical
            panes.spacing = wide ? 10 : 6
            noticeHeight.isActive = !wide
            keysWidth.isActive = wide
            bottomBar.removeFromSuperview()
            toolbarLeading.isActive = false
            if wide {
                toolbar.insertArrangedSubview(bottomBar, at: toolbar.arrangedSubviews.count - 1)
                toolbarLeading = toolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 6)
            } else {
                root.addArrangedSubview(bottomBar)
                toolbarLeading = toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor)
            }
            toolbarLeading.isActive = true
        }
        let preferred = CGFloat((snapshot.settings.tabletKeyboardSize ?? .standard).rawValue)
        if wide {
            let keys = min(preferred, (width - panes.spacing) * 0.68)
            keysWidth.constant = keys
            rootMaximumWidth.constant = min(width, keys + panes.spacing + 280)
        } else {
            rootMaximumWidth.constant = preferred
        }
        let keysFirst = wide && snapshot.settings.tabletKeyboardPosition == .left
        if (panes.arrangedSubviews.first === keysColumn) != keysFirst {
            panes.removeArrangedSubview(keysColumn)
            panes.insertArrangedSubview(keysColumn, at: keysFirst ? 0 : panes.arrangedSubviews.count)
        }
    }

    private func updateLayoutPreferences() {
        if !isTablet {
            let selected = snapshot.settings.phoneKeyboardLayout ?? .standard
            if activePhoneLayout != selected {
                commit()
                activePhoneLayout = selected
                buildKeys()
            } else if layoutButton.menu != nil { return }
            layoutButton.setTitle("配列", for: .normal)
            layoutButton.accessibilityLabel = "キー配列"
            layoutButton.menu = UIMenu(children: PhoneKeyboardLayout.allCases.map { layout in
                UIAction(title: layout.label, state: selected == layout ? .on : .off) { [weak self] _ in
                    guard let self else { return }
                    if hasFullAccess {
                        saveLayoutPreferences { $0.phoneKeyboardLayout = layout }
                    } else {
                        UserDefaults.standard.set(layout.rawValue, forKey: "phoneKeyboardLayout")
                        snapshot.settings.phoneKeyboardLayout = layout
                        updateLayoutPreferences()
                    }
                }
            })
            return
        }
        let size = snapshot.settings.tabletKeyboardSize ?? .standard
        let position = snapshot.settings.tabletKeyboardPosition ?? .center
        guard appliedTabletSize != size || appliedTabletPosition != position else { return }
        appliedTabletSize = size; appliedTabletPosition = position
        rootAlignment.isActive = false
        switch position {
        case .left: rootAlignment = root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6)
        case .center: rootAlignment = root.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        case .right: rootAlignment = root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6)
        }
        rootAlignment.isActive = true
        updateLandscapeLayout()
        layoutButton.menu = UIMenu(children: [
            UIMenu(title: "幅", options: .displayInline, children: TabletKeyboardSize.allCases.map { option in
                UIAction(title: option.label, state: option == size ? .on : .off) { [weak self] _ in
                    self?.saveLayoutPreferences { $0.tabletKeyboardSize = option }
                }
            }),
            UIMenu(title: "位置", options: .displayInline, children: TabletKeyboardPosition.allCases.map { option in
                UIAction(title: option.label, state: option == position ? .on : .off) { [weak self] _ in
                    self?.saveLayoutPreferences { $0.tabletKeyboardPosition = option }
                }
            })
        ])
    }

    private func saveLayoutPreferences(_ change: (inout LocalSettings) -> Void) {
        do {
            let store = try store ?? AppGroupContainer.open()
            snapshot = try store.update { state in change(&state.settings); return state }
            updateLayoutPreferences()
        } catch { notice.text = error.localizedDescription }
    }
}
