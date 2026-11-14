import Foundation
import SwiftUI
import UIKit

@MainActor final class DictationModel: ObservableObject {
    @Published private(set) var state = SessionSnapshot()
    @Published private(set) var modelReady = false
    @Published private(set) var downloading = false
    @Published var errorMessage = ""
    @Published var selectedTab = 0
    @Published var showSetup = false
    @Published var showKeyboardReturn = false
    private var store: SharedSessionStore?
    private let microphone = MicrophoneSession()
    private var prepared: OnDeviceCapture?
    private var active: OnDeviceCapture?
    private var processingCapture: OnDeviceCapture?
    private var poller: Task<Void, Never>?
    private var finishing: Task<Void, Never>?
    private var generation = UUID()
    private var heartbeatAt = Date.distantPast
    private var publishingPreviewAt = Date.distantPast
    private var activating = false
    private let synthetic: Bool
    private let syntheticUI: Bool
    private var lastDeliveryTrace = ""

    init() {
        #if DEBUG
        syntheticUI = ProcessInfo.processInfo.arguments.contains("--synthetic-ui")
        synthetic = syntheticUI || ProcessInfo.processInfo.arguments.contains("--synthetic-dictation")
        #else
        synthetic = false
        syntheticUI = false
        #endif
        microphone.onInterruption = { [weak self] in self?.disconnect(message: "通話や音声経路の変更によりマイクを終了しました。") }
    }

    func initialize() async {
        guard store == nil else { return }
        do {
            if syntheticUI {
                store = try SharedSessionStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("VoiceSeed-UI-" + UUID().uuidString))
            } else { store = try AppGroupContainer.open() }
            IOSPreparationTrace.step(synthetic ? "mode.synthetic" : "mode.realMicrophone")
            try store?.update { $0.disconnect() }
            try reload()
            if let delivery = state.delivery {
                lastDeliveryTrace = delivery.id.uuidString + delivery.status.rawValue
            }
            if synthetic { modelReady = true }
            else { modelReady = await JapaneseSpeechModel.ready() }
            poller = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.poll()
                    try? await Task.sleep(for: .milliseconds(80))
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func reload() throws { if let store { state = try store.read() } }
    private func update(_ body: (inout SessionSnapshot) throws -> Void) throws {
        guard let store else { throw SharedStoreError.unavailable }
        try store.update(body); try reload()
    }

    private func poll() async {
        guard let store else { return }
        do {
            if state.sessionID != nil, state.phase != .listening, state.phase != .processing,
               let end = state.expiresAt, Date() >= end {
                disconnect(message: "マイクの待機時間が終了しました。必要なときに再開できます。")
            }
            if state.sessionID != nil, Date().timeIntervalSince(heartbeatAt) >= 0.4 {
                heartbeatAt = Date(); try update { $0.refreshHeartbeat(at: heartbeatAt) }
            }
            if let command = try store.nextCommand(at: Date()) {
                IOSPreparationTrace.step("command." + command.kind.rawValue)
                switch command.kind {
                case .activate:
                    selectedTab = 0
                    showKeyboardReturn = command.keyboardLaunch != nil
                    await activate()
                    if state.phase == .ready, let launch = command.keyboardLaunch {
                        try update { $0.keyboardLaunch = launch }
                    }
                case .start:
                    if let request = command.request { start(request) }
                case .stop:
                    if let request = command.request, state.request?.id == request.id { finish() }
                case .cancel:
                    if let request = command.request, state.request?.id == request.id { await cancel() }
                case .disconnect: disconnect()
                case .showSettings: selectedTab = 4
                }
            }
            try reload()
            if let delivery = state.delivery {
                let key = delivery.id.uuidString + delivery.status.rawValue
                if key != lastDeliveryTrace {
                    lastDeliveryTrace = key
                    IOSPreparationTrace.step("delivery." + delivery.status.rawValue + ".characters=" + String(delivery.text.count))
                }
            }
        } catch SharedStoreError.busy { }
        catch { errorMessage = error.localizedDescription }
    }

    func installModel() async {
        guard !downloading else { return }; downloading = true
        defer { downloading = false }
        do { try await JapaneseSpeechModel.install(); modelReady = await JapaneseSpeechModel.ready() }
        catch { errorMessage = error.localizedDescription }
    }

    func activate() async {
        guard !activating else { return }
        if state.isLive(at: Date()), state.phase != .failed { return }
        guard modelReady else { errorMessage = "先に日本語モデルを準備してください。"; return }
        activating = true; defer { activating = false }
        let token = UUID(); generation = token
        do {
            try update { $0.activate(at: Date()) }
            // A real device still needs the ordinary microphone standby session
            // while the host app is in the background. Synthetic dictation drops
            // those buffers and exercises only the keyboard delivery path.
            if !syntheticUI { try await microphone.activate() }
            if !synthetic {
                let capture = try await makePrepared()
                guard generation == token else { capture.cancel(); return }
                prepared = capture
            }
            guard generation == token else { return }
            try update { $0.phase = .ready; $0.heartbeat = Date() }
        } catch { disconnect(); errorMessage = error.localizedDescription }
    }

    private func makePrepared() async throws -> OnDeviceCapture {
        try await OnDeviceCapture.prepare(vocabulary: state.settings.dictionary.flatMap { [$0.heard, $0.written] })
    }

    func startLocal(benchmark: BenchmarkPhrase? = nil) {
        guard let sessionID = state.sessionID else { return }
        let request = CaptureRequest(id: UUID(), sessionID: sessionID, focusID: UUID(),
                                     documentID: "local-app", startedAt: Date(), benchmarkID: benchmark?.id)
        start(request)
    }

    private func start(_ request: CaptureRequest) {
        do {
            var accepted = false
            try update { accepted = $0.begin(request, at: Date()) }
            IOSPreparationTrace.step(accepted ? "capture.accepted" : "capture.rejected")
            guard accepted else {
                if state.request?.id != request.id { try update { $0.finishWithoutDelivery(request.id) } }
                return
            }
            showKeyboardReturn = false
            if synthetic { try update { $0.preview = "明日の打ち合わせは午後3時からです。" }; return }
            guard let capture = prepared else {
                try update { $0.finishWithoutDelivery(request.id); $0.phase = .preparing }
                Task { await rewarm() }; return
            }
            prepared = nil; active = capture
            capture.onPreview = { [weak self] text in
                guard let self, self.state.request?.id == request.id else { return }
                if Date().timeIntervalSince(self.publishingPreviewAt) >= 0.12 {
                    self.publishingPreviewAt = Date()
                    try? self.update { $0.preview = text }
                }
            }
            capture.onLevel = { [weak self] level in
                guard let self, self.state.request?.id == request.id else { return }
                if abs(level - self.state.level) > 0.08 { try? self.update { $0.level = level } }
            }
            capture.onFailure = { [weak self] _ in
                guard let self, self.state.request?.id == request.id, self.state.phase == .listening else { return }
                self.disconnect(message: "マイクの接続を確認し、もう一度有効にしてください。")
            }
            capture.start(); microphone.attach(capture)
        } catch { errorMessage = error.localizedDescription }
    }

    func finish() {
        guard var request = state.request, state.phase == .listening else { return }
        request.stoppedAt = Date()
        microphone.attach(nil)
        let capture = active; active = nil
        processingCapture = capture
        let token = generation
        do { try update { $0.request = request; $0.phase = .processing; $0.level = 0 } }
        catch { errorMessage = error.localizedDescription; return }
        finishing = Task { [weak self, capture] in
            guard let self else { return }
            defer { if self.generation == token { self.finishing = nil; self.processingCapture = nil } }
            do {
                let raw: String
                if self.synthetic { raw = "明日の打ち合わせは午後3時からです。" }
                else { raw = try await capture?.finish() ?? "" }
                IOSPreparationTrace.step("recognition.finished.characters=" + String(raw.count))
                let finalized = Date()
                guard !Task.isCancelled, self.generation == token, self.state.request?.id == request.id else { return }
                var text = TextPipeline.process(raw, entries: self.state.settings.dictionary, removeFillers: self.state.settings.removeFillers)
                let refinementStart = Date()
                var refined = false
                if self.state.settings.refineWithAppleIntelligence, OnDeviceRefiner.available, !text.isEmpty {
                    let candidate = (try? await OnDeviceRefiner.refine(text)) ?? text
                    guard !Task.isCancelled, self.state.request?.id == request.id else { return }
                    text = TextPipeline.applyDictionary(candidate, entries: self.state.settings.dictionary); refined = true
                }
                let finished = Date()
                let metrics = DictationMetrics(speechSeconds: max(0, request.stoppedAt!.timeIntervalSince(request.startedAt)),
                    finalizationMilliseconds: max(0, finalized.timeIntervalSince(request.stoppedAt!) * 1000),
                    refinementMilliseconds: refined ? finished.timeIntervalSince(refinementStart) * 1000 : 0,
                    firstPreviewMilliseconds: capture?.previewMilliseconds, refinementApplied: refined)
                guard self.generation == token, self.state.request?.id == request.id else { return }
                try self.update { value in
                    if text.isEmpty { value.finishWithoutDelivery(request.id) }
                    else {
                        let delivery = TextDelivery(request: request, text: text, metrics: metrics, createdAt: finished)
                        guard value.publish(delivery) else { return }
                        if let phrase = BenchmarkPhrase.corpus.first(where: { $0.id == request.benchmarkID }) {
                            value.benchmarks.insert(.init(id: request.id, phraseID: phrase.id, reference: phrase.text,
                                recognized: raw, finalText: text,
                                rawCharacterErrorRate: TextAccuracy.characterErrorRate(reference: phrase.text, candidate: raw),
                                finalCharacterErrorRate: TextAccuracy.characterErrorRate(reference: phrase.text, candidate: text),
                                metrics: metrics, date: finished), at: 0)
                            value.benchmarks = Array(value.benchmarks.prefix(50))
                        }
                    }
                }
                await self.rewarm(token: token)
            } catch {
                guard self.generation == token, self.state.request?.id == request.id else { return }
                if !(error is CancellationError), !(error is DictationFailure) { self.errorMessage = error.localizedDescription }
                try? self.update { $0.finishWithoutDelivery(request.id) }
                await self.rewarm(token: token)
            }
        }
    }

    func cancel() async {
        finishing?.cancel(); finishing = nil; microphone.attach(nil); active?.cancel(); active = nil
        processingCapture?.cancel(); processingCapture = nil
        let token = UUID(); generation = token
        try? update {
            if let id = $0.request?.id { $0.finishWithoutDelivery(id) }
            $0.phase = .preparing; $0.level = 0
        }
        await rewarm(token: token)
    }

    private func rewarm(token: UUID? = nil) async {
        let token = token ?? generation
        guard state.sessionID != nil else { return }
        do {
            if !synthetic {
                let capture = try await makePrepared()
                guard generation == token, state.sessionID != nil else { capture.cancel(); return }
                prepared?.cancel(); prepared = capture
            }
            guard generation == token, state.sessionID != nil else { return }
            try update { $0.phase = .ready; $0.heartbeat = Date() }
        } catch { disconnect(); errorMessage = error.localizedDescription }
    }

    func disconnect(message: String = "") {
        showKeyboardReturn = false
        generation = UUID(); finishing?.cancel(); finishing = nil
        microphone.attach(nil); active?.cancel(); prepared?.cancel(); active = nil; prepared = nil
        processingCapture?.cancel(); processingCapture = nil
        microphone.deactivate()
        try? update { $0.disconnect(message: message) }
    }

    func updateSettings(_ change: (inout LocalSettings) -> Void) {
        do {
            try update { change(&$0.settings) }
            if state.phase == .ready {
                try update { $0.phase = .preparing }
                Task { await rewarm() }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func clearHistory() { do { try update { $0.history = [] } } catch { errorMessage = error.localizedDescription } }
    func clearBenchmarks() { do { try update { $0.benchmarks = [] } } catch { errorMessage = error.localizedDescription } }
    func exportBenchmarkReport() -> String {
        struct Report: Encodable {
            var appVersion: String; var osVersion: String; var scope: String; var results: [BenchmarkResult]
        }
        let report = Report(appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            osVersion: UIDevice.current.systemVersion,
            scope: "本体内で読んだ指定文の認識精度・確定時間。認識結果を含みます。実際の他アプリへの入力時間は入力履歴の数値で別に確認します。",
            results: state.benchmarks)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return (try? String(decoding: encoder.encode(report), as: UTF8.self)) ?? ""
    }
}
