import UIKit
import SwiftUI

private struct ActivateKeyboardButton: View {
    var destination: URL?
    var body: some View {
        Link(destination: destination ?? URL(string: "koenotane://settings")!) {
            Label("タップして話す", systemImage: "mic").font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
        }.disabled(destination == nil).buttonStyle(.plain).foregroundStyle(.white).background(.black.opacity(0.8), in: Capsule())
    }
}
private struct KeyboardSettingsButton: View {
    var body: some View {
        Link(destination: URL(string: "koenotane://settings")!) { Image(systemName: "slider.horizontal.3").font(.system(size: 18)).padding(8) }
            .buttonStyle(.plain).foregroundStyle(.primary)
    }
}

final class KeyboardViewController: UIInputViewController {
    private enum Mode: Equatable { case kana, abc, numbers, emoji }
    private var mode: Mode = .kana
    private let root = UIStackView()
    private let toolbar = UIStackView()
    private let candidates = UIStackView()
    private let candidateScroll = UIScrollView()
    private let bodyStack = UIStackView()
    private let speechButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let notice = UILabel()
    private let globe = UIButton(type: .system)
    private let composer = JapaneseComposer()
    private var tapCycle = KanaTapCycle()
    private var store: SharedSessionStore?
    private var snapshot = SessionSnapshot()
    private var timer: Timer?
    private var pending: CaptureRequest?
    private var activationTicket: KeyboardLaunch?
    private let keyboardID = UUID()
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
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 344),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
        ])
        toolbar.axis = .horizontal; toolbar.spacing = 8; toolbar.alignment = .center
        cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        cancelButton.accessibilityLabel = "音声入力をキャンセル"
        cancelButton.addAction(UIAction { [weak self] _ in self?.cancelPending() }, for: .touchUpInside)
        cancelButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        toolbar.addArrangedSubview(cancelButton)
        let settings = UIHostingController(rootView: KeyboardSettingsButton()); settingsHost = settings
        mount(settings, in: toolbar); settings.view.widthAnchor.constraint(equalToConstant: 36).isActive = true
        let activation = UIHostingController(rootView: ActivateKeyboardButton()); activationHost = activation
        mount(activation, in: toolbar)
        speechButton.layer.cornerRadius = 17
        speechButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        speechButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        speechButton.addAction(UIAction { [weak self] _ in self?.speechAction() }, for: .touchUpInside)
        toolbar.addArrangedSubview(speechButton)
        toolbar.addArrangedSubview(UIView())
        let hide = UIButton(type: .system); hide.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        hide.accessibilityLabel = "キーボードを閉じる"
        hide.addAction(UIAction { [weak self] _ in self?.commit(); self?.cancelPending(); self?.dismissKeyboard() }, for: .touchUpInside)
        toolbar.addArrangedSubview(hide)
        toolbar.heightAnchor.constraint(equalToConstant: 36).isActive = true
        root.addArrangedSubview(toolbar)
        notice.font = .systemFont(ofSize: 11); notice.textColor = .secondaryLabel; notice.numberOfLines = 2
        notice.heightAnchor.constraint(equalToConstant: 32).isActive = true
        root.addArrangedSubview(notice)
        candidates.axis = .horizontal; candidates.spacing = 8
        candidateScroll.addSubview(candidates); candidates.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            candidates.leadingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.leadingAnchor),
            candidates.trailingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.trailingAnchor),
            candidates.topAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.topAnchor),
            candidates.bottomAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.bottomAnchor),
            candidates.heightAnchor.constraint(equalTo: candidateScroll.frameLayoutGuide.heightAnchor),
            candidateScroll.heightAnchor.constraint(equalToConstant: 28)
        ])
        root.addArrangedSubview(candidateScroll)
        bodyStack.axis = .vertical; bodyStack.spacing = 5
        root.addArrangedSubview(bodyStack)
        let bottom = UIStackView(); bottom.axis = .horizontal; bottom.alignment = .center
        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.accessibilityLabel = "別のキーボード"
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        globe.widthAnchor.constraint(equalToConstant: 40).isActive = true
        bottom.addArrangedSubview(globe); bottom.addArrangedSubview(UIView())
        let brand = UILabel(); brand.text = "こえのたね"; brand.font = .systemFont(ofSize: 10); brand.textColor = .secondaryLabel
        bottom.addArrangedSubview(brand)
        bottom.heightAnchor.constraint(equalToConstant: 24).isActive = true
        root.addArrangedSubview(bottom)
        buildKeys()
    }

    private func mount<T: View>(_ host: UIHostingController<T>, in stack: UIStackView) {
        addChild(host); host.view.backgroundColor = .clear; stack.addArrangedSubview(host.view); host.didMove(toParent: self)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        focusID = UUID(); currentDocument = textDocumentProxy.documentIdentifier.uuidString; pending = nil; tapCycle.reset()
        activationTicket = nil
        do { store = try AppGroupContainer.open() } catch { notice.text = error.localizedDescription }
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        isVisible = false
        commit(); cancelPending(); focusID = UUID()
        timer?.invalidate(); timer = nil
        super.viewWillDisappear(animated)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isVisible = true
        focusSettlesAt = ProcessInfo.processInfo.systemUptime + 0.2
        refresh()
    }
    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        guard !inserting else { return }
        let document = textDocumentProxy.documentIdentifier.uuidString
        if document != currentDocument {
            focusSettlesAt = ProcessInfo.processInfo.systemUptime + 0.2
            cancelPending(); tapCycle.reset(); composer.clear(); updateCandidates(); focusID = UUID(); currentDocument = document
            activationTicket = nil
        }
    }
    override func selectionDidChange(_ textInput: (any UITextInput)?) {
        super.selectionDidChange(textInput)
        if !inserting { tapCycle.reset(); focusSettlesAt = ProcessInfo.processInfo.systemUptime + 0.2 }
        if !inserting, pending != nil { cancelPending() }
    }

    private func refresh() {
        globe.isHidden = !needsInputModeSwitchKey
        guard hasFullAccess else {
            speechButton.isHidden = true; activationHost?.view.isHidden = false
            notice.text = "設定で「こえのたね」のフルアクセスを許可してください。音声は送信しません。"
            return
        }
        if store == nil { store = try? AppGroupContainer.open() }
        do {
            if let store { snapshot = try store.read() }
            if let store, activationTicket == nil || Date().timeIntervalSince(activationTicket!.createdAt) > 30 {
                let ticket = KeyboardLaunch(documentID: textDocumentProxy.documentIdentifier.uuidString, createdAt: Date(), keyboardID: keyboardID)
                try store.update { $0.keyboardActivationTicket = ticket }
                activationTicket = ticket
                activationHost?.rootView = ActivateKeyboardButton(destination: VoiceSeedLink.dictationURL(ticket: ticket.id))
            }
            if isVisible, ProcessInfo.processInfo.systemUptime >= focusSettlesAt,
               pending == nil, snapshot.keyboardLaunch != nil, snapshot.phase == .ready, let store {
                let document = textDocumentProxy.documentIdentifier.uuidString
                // Resume only in the initiating keyboard after the app leaves
                // the foreground; bind delivery to the current proxy and focus.
                let request: CaptureRequest? = try store.update { state in
                    guard state.commands.count < 16,
                          state.claimKeyboardLaunch(documentID: document, keyboardID: keyboardID, at: Date()),
                          let sessionID = state.sessionID else { return nil }
                    let request = CaptureRequest(id: UUID(), sessionID: sessionID, focusID: focusID,
                        documentID: document, startedAt: Date())
                    state.commands.append(.init(kind: .start, request: request))
                    return request
                }
                if let request { commit(); pending = request }
            }
            composer.dictionary = snapshot.settings.dictionary
            let live = snapshot.isLive(at: Date())
            activationHost?.view.isHidden = live
            speechButton.isHidden = !live
            cancelButton.isHidden = pending == nil
            settingsHost?.view.isHidden = pending != nil
            let label: String
            switch snapshot.phase {
            case .listening: label = "▎聞き取り中…タップで終了 ▎"
            case .processing: label = "確定中…タップでキャンセル"
            case .ready: label = "🎙 タップして話す"
            default: label = snapshot.phase.label
            }
            speechButton.setTitle(label, for: .normal)
            speechButton.backgroundColor = snapshot.phase == .listening ? .systemGreen : .label
            speechButton.setTitleColor(.systemBackground, for: .normal)
            speechButton.isEnabled = [.ready, .listening, .processing].contains(snapshot.phase)
                && !(snapshot.phase == .ready && pending != nil)
            notice.text = !snapshot.preview.isEmpty ? snapshot.preview : snapshot.keyboardGuidance(at: Date())
            if let pending, let store {
                guard pending.sessionID == snapshot.sessionID else { self.pending = nil; return }
                let document = textDocumentProxy.documentIdentifier.uuidString
                if document != pending.documentID { cancelPending(); return }
                let delivery = try store.update { state in
                    state.claimDelivery(requestID: pending.id, focusID: focusID, documentID: document, now: Date())
                }
                if let delivery {
                    // No suspension between rechecking focus and the single insertion attempt.
                    guard textDocumentProxy.documentIdentifier.uuidString == pending.documentID, focusID == pending.focusID else {
                        try store.update { $0.delivery?.status = .focusChanged }; self.pending = nil; return
                    }
                    self.pending = nil; inserting = true
                    textDocumentProxy.insertText(delivery.text)
                    inserting = false
                    let latency = pending.stoppedAt.map { max(0, Date().timeIntervalSince($0) * 1000) }
                        ?? delivery.request.stoppedAt.map { max(0, Date().timeIntervalSince($0) * 1000) }
                    try store.update { state in
                        guard state.delivery?.id == delivery.id else { return }
                        state.delivery?.status = .inserted; state.delivery?.metrics.insertionMilliseconds = latency
                        if let index = state.history.firstIndex(where: { $0.id == delivery.id }) {
                            state.history[index].metrics.insertionMilliseconds = latency
                        }
                    }
                } else if snapshot.finishedRequestID == pending.id {
                    // Silence/cancellation has no text to deliver. Release the
                    // request so the next utterance can start normally.
                    self.pending = nil
                }
            }
        } catch SharedStoreError.busy { }
        catch { notice.text = error.localizedDescription }
    }

    private func speechAction() {
        if snapshot.phase == .processing { cancelPending(); return }
        guard let store else { return }
        do {
            if snapshot.phase == .listening, var request = pending {
                request.stoppedAt = Date(); pending = request
                try store.enqueue(.init(kind: .stop, request: request)); return
            }
            // The host polls asynchronously. Keep the first request until it is
            // accepted/delivered rather than replacing it on a rapid second tap.
            guard pending == nil, snapshot.phase == .ready, snapshot.isLive(at: Date()), let sessionID = snapshot.sessionID else { return }
            commit()
            let request = CaptureRequest(id: UUID(), sessionID: sessionID, focusID: focusID,
                documentID: textDocumentProxy.documentIdentifier.uuidString, startedAt: Date())
            try store.enqueue(.init(kind: .start, request: request)); pending = request
            speechButton.isEnabled = false
        } catch { notice.text = error.localizedDescription }
    }
    private func cancelPending() {
        guard let request = pending else { return }
        pending = nil; try? store?.enqueue(.init(kind: .cancel, request: request))
    }

    private func key(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal); button.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
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
        switch mode {
        case .kana:
            let left = UIStackView(arrangedSubviews: [
                key("←") { [weak self] in self?.moveCursor(-1) },
                key("→") { [weak self] in self?.moveCursor(1) },
                key("ABC") { [weak self] in self?.switchMode(.abc) },
                key("😊") { [weak self] in self?.switchMode(.emoji) }
            ]); left.axis = .vertical; left.spacing = 5; left.distribution = .fillEqually
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
            let right = UIStackView(arrangedSubviews: [
                deleteKey(), space,
                key("改行") { [weak self] in self?.enter() }
            ]); right.axis = .vertical; right.spacing = 5
            right.arrangedSubviews[0].heightAnchor.constraint(equalToConstant: 45).isActive = true
            right.arrangedSubviews[1].heightAnchor.constraint(equalToConstant: 45).isActive = true
            let body = UIStackView(arrangedSubviews: [left, middle, right]); body.axis = .horizontal; body.spacing = 6
            left.widthAnchor.constraint(equalTo: body.widthAnchor, multiplier: 0.18).isActive = true
            right.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
            bodyStack.addArrangedSubview(body)
        case .abc:
            for letters in ["qwertyuiop", "asdfghjkl", "zxcvbnm"] {
                bodyStack.addArrangedSubview(row(letters.map { character in
                    let value = uppercase ? String(character).uppercased() : String(character)
                    return key(value) { [weak self] in self?.typeDirect(value) }
                }))
            }
            bodyStack.addArrangedSubview(row([
                key("あ") { [weak self] in self?.switchMode(.kana) },
                key("⇧") { [weak self] in self?.uppercase.toggle(); self?.buildKeys() },
                key("123") { [weak self] in self?.switchMode(.numbers) },
                spaceButton("space"),
                deleteKey(),
                key("改行") { [weak self] in self?.enter() }
            ]))
            bodyStack.distribution = .fillEqually
        case .numbers, .emoji:
            let rows = mode == .numbers ? ["1234567890", "-/:;()¥&@\"", ".,?!'％+＝〜"] : ["😊😂🥰😅👍", "🙏🙇🎉✨❤️", "👀💡✅📩🌱"]
            for letters in rows {
                bodyStack.addArrangedSubview(row(letters.map { character in
                    key(String(character)) { [weak self] in self?.typeDirect(String(character)) }
                }))
            }
            bodyStack.addArrangedSubview(row([
                key("あ") { [weak self] in self?.switchMode(.kana) },
                key("ABC") { [weak self] in self?.switchMode(.abc) }, spaceButton("空白"),
                deleteKey(), key("改行") { [weak self] in self?.enter() }
            ])); bodyStack.distribution = .fillEqually
        }
    }
    private func switchMode(_ next: Mode) { commit(); mode = next; buildKeys() }
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
    private func alternate() { cancelPending(); tapCycle.reset(); composer.alternateLast(); setMarked(); updateCandidates() }
    private func setMarked() {
        inserting = true
        textDocumentProxy.setMarkedText(composer.reading, selectedRange: NSRange(location: composer.reading.utf16.count, length: 0))
        inserting = false
    }
    private func commit(_ candidate: String? = nil) {
        tapCycle.reset()
        guard !composer.isEmpty else { return }
        inserting = true
        textDocumentProxy.setMarkedText(candidate ?? composer.reading, selectedRange: NSRange(location: (candidate ?? composer.reading).utf16.count, length: 0))
        textDocumentProxy.unmarkText(); inserting = false
        composer.clear(); updateCandidates()
    }
    private func typeDirect(_ value: String) {
        cancelPending(); commit(); inserting = true; textDocumentProxy.insertText(value); inserting = false
    }
    private func delete() {
        cancelPending(); tapCycle.reset()
        if !composer.isEmpty { composer.delete(); setMarked(); updateCandidates(); if composer.isEmpty { textDocumentProxy.unmarkText() } }
        else { inserting = true; textDocumentProxy.deleteBackward(); inserting = false }
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
            if composer.isEmpty { textDocumentProxy.unmarkText() }
        } else {
            let count = textDocumentProxy.selectedText?.isEmpty == false ? 1
                : BunsetsuDeletion.characterCount(beforeCursor: textDocumentProxy.documentContextBeforeInput ?? "")
            inserting = true
            for _ in 0..<count { textDocumentProxy.deleteBackward() }
            inserting = false
        }
    }
    private func enter() { cancelPending(); if !composer.isEmpty { commit(composer.candidates.first) } else { typeDirect("\n") } }
    private func moveCursor(_ delta: Int) { cancelPending(); commit(); textDocumentProxy.adjustTextPosition(byCharacterOffset: delta) }
    private func spaceButton(_ title: String) -> UIButton {
        let button = key(title) { [weak self] in
            guard let self else { return }; self.cancelPending()
            if !self.composer.isEmpty { self.commit(self.composer.candidates.first) } else { self.typeDirect(" ") }
        }
        button.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(spaceTrackpad(_:))))
        return button
    }
    @objc private func spaceTrackpad(_ gesture: UILongPressGestureRecognizer) {
        let x = gesture.location(in: view).x
        if gesture.state == .began { cancelPending(); commit(); spaceOrigin = x; spaceOffset = 0 }
        if gesture.state == .changed {
            let next = Int((x - spaceOrigin) / 12), delta = next - spaceOffset
            if delta != 0 { textDocumentProxy.adjustTextPosition(byCharacterOffset: delta); spaceOffset = next }
        }
    }
    private func updateCandidates() {
        let signature = composer.candidates.joined(separator: "\u{0}")
        guard signature != lastCandidateText else { return }; lastCandidateText = signature
        clearStack(candidates)
        for text in composer.candidates.prefix(12) {
            let button = key(text) { [weak self] in self?.commit(text) }
            button.contentEdgeInsets = UIEdgeInsets(top: 3, left: 12, bottom: 3, right: 12)
            button.titleLabel?.font = .systemFont(ofSize: 15); candidates.addArrangedSubview(button)
        }
    }
}
