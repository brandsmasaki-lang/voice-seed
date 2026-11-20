import AVFoundation
import Speech
import CoreMedia
import Synchronization

private final class CaptureBoundary: Sendable {
    let cutoff = Mutex<UInt64?>(nil)
}

/// Capture starts as soon as the microphone is requested. The bounded stream holds
/// the first words while the speech model is preparing and drains in capture order.
@MainActor final class MicrophoneCapture {
    let buffers: AsyncThrowingStream<AVAudioPCMBuffer, Error>
    private let continuation: AsyncThrowingStream<AVAudioPCMBuffer, Error>.Continuation
    private let engine = AVAudioEngine()
    private var tapped = false
    private var configurationObserver: NSObjectProtocol?
    private let boundary = CaptureBoundary()
    private let tailDelivered: AsyncStream<Void>
    private let tailSignal: AsyncStream<Void>.Continuation

    init() {
        (buffers, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingOldest(128))
        (tailDelivered, tailSignal) = AsyncStream.makeStream()
    }

    func start(onFailure: @escaping @MainActor @Sendable (Error) -> Void) throws {
        let input = engine.inputNode
        let hardware = input.inputFormat(forBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard hardware.channelCount > 0, hardware.sampleRate > 0, format.channelCount > 0, format.sampleRate > 0 else {
            throw VoiceError.message("マイクの入力デバイスを確認してください。")
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [continuation, boundary, tailSignal] buffer, when in
            guard buffer.frameLength > 0 else { return }
            var frames = buffer.frameLength
            var reachedEnd = false
            if let deadline = boundary.cutoff.withLock({ $0 }), when.isHostTimeValid {
                let earliest = min(deadline, when.hostTime)
                let difference = AVAudioTime.seconds(forHostTime: max(deadline, when.hostTime) - earliest)
                let slice = MicrophoneTail.slice(frames: Int(frames), sampleRate: buffer.format.sampleRate,
                    secondsBeforeCutoff: deadline >= when.hostTime ? difference : -difference)
                frames = AVAudioFrameCount(slice.count)
                reachedEnd = slice.reachedEnd
            }
            defer { if reachedEnd { tailSignal.finish() } }
            guard frames > 0 else { return }
            guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: frames) else {
                continuation.finish(throwing: VoiceError.message("マイクの音声を取り込めませんでした。"))
                tailSignal.finish()
                return
            }
            copy.frameLength = frames
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
            let outputs = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for (input, output) in zip(inputs, outputs) {
                if let src = input.mData, let dst = output.mData { memcpy(dst, src, Int(min(input.mDataByteSize, output.mDataByteSize))) }
            }
            if case .dropped = continuation.yield(copy) {
                continuation.finish(throwing: VoiceError.message("音声認識の準備に時間がかかり、録音を続けられませんでした。"))
                tailSignal.finish()
            }
        }
        tapped = true
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard self?.tapped == true else { return }
                onFailure(VoiceError.message("マイクの接続または音声設定が変更されました。もう一度音声入力してください。"))
            }
        }
        engine.prepare()
        try engine.start()
    }

    func markRelease(at hostTime: UInt64) {
        boundary.cutoff.withLock { $0 = hostTime + AVAudioTime.hostTime(forSeconds: MicrophoneTail.graceSeconds) }
    }

    func waitForTail() async {
        let timeout = Task { [tailSignal] in
            do { try await Task.sleep(for: .milliseconds(520)) }
            catch { return }
            tailSignal.finish()
        }
        defer { timeout.cancel() }
        for await _ in tailDelivered { }
    }

    func end(cancelled: Bool = false) {
        tailSignal.finish()
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        if tapped {
            tapped = false
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        continuation.finish(throwing: cancelled ? CancellationError() : nil)
    }
}

/// All conversion runs on one queue. Queued buffers are owned by the caller.
private final class AudioStreamPump: @unchecked Sendable {
    private let queue = DispatchQueue(label: "jp.ainotane.voice-seed.audio", qos: .userInitiated)
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?
    private var closed = false
    var onLevel: (@Sendable (Double) -> Void)?

    init(target: AVAudioFormat, continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation) {
        self.target = target; self.continuation = continuation
    }

    func enqueue(_ copy: AVAudioPCMBuffer) {
        queue.async { [self] in
            guard !closed else { return }
            do {
                if let samples = copy.floatChannelData?[0], copy.frameLength > 0 {
                    var sum: Float = 0
                    for i in 0..<Int(copy.frameLength) { sum += samples[i] * samples[i] }
                    let db = 20 * log10(max(0.000001, sqrt(Double(sum) / Double(copy.frameLength))))
                    onLevel?(max(0, min(1, (db + 60) / 60)))
                }
                if copy.format == target { try yield(copy); return }
                if converter == nil {
                    converter = AVAudioConverter(from: copy.format, to: target)
                    converter?.primeMethod = .none
                }
                guard let converter else { throw VoiceError.message("マイクの音声形式を認識用に変換できません。") }
                let capacity = AVAudioFrameCount(ceil(Double(copy.frameLength) * target.sampleRate / copy.format.sampleRate)) + 64
                guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw VoiceError.message("音声バッファを作成できません。") }
                var supplied = false
                var error: NSError?
                let status = converter.convert(to: output, error: &error) { _, status in
                    if supplied { status.pointee = .noDataNow; return nil }
                    supplied = true; status.pointee = .haveData; return copy
                }
                if let error { throw error }
                guard status != .error else { throw VoiceError.message("音声変換でエラーが発生しました。") }
                if output.frameLength > 0 { try yield(output) }
            } catch {
                closed = true; continuation.finish(throwing: error)
            }
        }
    }

    private func yield(_ buffer: AVAudioPCMBuffer) throws {
        if case .dropped = continuation.yield(AnalyzerInput(buffer: buffer)) {
            throw VoiceError.message("音声認識が追いつかないため音声入力を中止しました。ほかの重い処理を止めてお試しください。")
        }
    }

    func finish(cancelled: Bool = false) {
        queue.async { [self] in
            guard !closed else { return }
            defer { closed = true }
            if cancelled { continuation.finish(throwing: CancellationError()); return }
            do {
                if let converter {
                    // Flush the sample-rate converter so the final syllable isn't lost.
                    for _ in 0..<8 {
                        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 4096) else { break }
                        var error: NSError?
                        let status = converter.convert(to: output, error: &error) { _, status in status.pointee = .endOfStream; return nil }
                        if let error { throw error }
                        if output.frameLength > 0 { try yield(output) }
                        if status == .endOfStream || output.frameLength == 0 { break }
                    }
                }
                continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }
}

@MainActor final class StreamingSpeechSession {
    private let transcriber: DictationTranscriber
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private var pump: AudioStreamPump?
    private var reader: Task<String, Error>?
    private var feeder: Task<Void, Error>?
    private var started = false
    private(set) var firstPreviewAt: Date?
    var onPreview: ((String) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onFailure: ((Error) -> Void)?

    private init(transcriber: DictationTranscriber, analyzer: SpeechAnalyzer, format: AVAudioFormat) {
        self.transcriber = transcriber; self.analyzer = analyzer; self.format = format
    }

    static func prepare(vocabulary: [String]) async throws -> StreamingSpeechSession {
        let transcriber = try await SpeechService.module(progressive: true)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else { throw VoiceError.message("日本語モデルを準備してください。") }
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .processLifetime))
        let context = AnalysisContext()
        context.contextualStrings[.general] = Array(Set(vocabulary.filter { !$0.isEmpty } + ["GitHub"]))
        try await analyzer.setContext(context)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw VoiceError.message("認識用の音声形式を取得できません。") }
        try await analyzer.prepareToAnalyze(in: format)
        try Task.checkCancellation()
        return StreamingSpeechSession(transcriber: transcriber, analyzer: analyzer, format: format)
    }

    private func startStream() async throws {
        guard !started else { throw VoiceError.message("音声認識セッションは開始済みです。") }
        started = true
        let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingOldest(512))
        let pump = AudioStreamPump(target: format, continuation: continuation)
        pump.onLevel = { [weak self] level in Task { @MainActor in self?.onLevel?(level) } }
        self.pump = pump
        reader = Task { [weak self, transcriber] in
            var transcript = TranscriptBuffer(paragraphPause: 1.2)
            do {
                for try await result in transcriber.results {
                    transcript.update(start: result.range.start.seconds, end: result.range.end.seconds,
                                      text: String(result.text.characters), isFinal: result.isFinal)
                    if !transcript.preview.isEmpty {
                        if self?.firstPreviewAt == nil { self?.firstPreviewAt = Date() }
                        self?.onPreview?(transcript.preview)
                    }
                }
                return JapaneseSentenceEnding.complete(DeveloperTermCorrection.apply(transcript.finalText))
            } catch {
                if !(error is CancellationError) { self?.onFailure?(error) }
                throw error
            }
        }
        try await analyzer.start(inputSequence: stream)
        try Task.checkCancellation()
    }

    func start(buffers: AsyncThrowingStream<AVAudioPCMBuffer, Error>) async throws {
        try await startStream()
        guard let pump else { throw VoiceError.message("音声ストリームを開始できません。") }
        feeder = Task { [weak self] in
            do {
                for try await buffer in buffers {
                    try Task.checkCancellation()
                    pump.enqueue(buffer)
                }
                pump.finish()
            } catch {
                pump.finish(cancelled: true)
                if !(error is CancellationError) { self?.onFailure?(error) }
                throw error
            }
        }
    }

    func finish() async throws -> String {
        do {
            try await feeder?.value
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            let text = try await reader?.value ?? ""
            guard !text.isEmpty else { throw VoiceError.noSpeech }
            return text
        } catch {
            reader?.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    func cancel() {
        onFailure = nil; onPreview = nil; onLevel = nil
        feeder?.cancel(); pump?.finish(cancelled: true); reader?.cancel()
        Task { await analyzer.cancelAndFinishNow() }
    }

    /// Replays only a specifically selected test file at real-time pace. Never opens the microphone.
    static func benchmark(file: URL) async throws -> [String: Any] {
        let start = Date()
        let session = try await prepare(vocabulary: [])
        let prepared = Date()
        try await session.startStream()
        let audio = try AVAudioFile(forReading: file)
        let chunk = AVAudioFrameCount(max(1, audio.processingFormat.sampleRate * 0.04))
        var frames: AVAudioFramePosition = 0
        let feedingStarted = Date()
        do {
            while audio.framePosition < audio.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: chunk) else { throw VoiceError.message("テスト音声を読み取れません。") }
                try audio.read(into: buffer)
                session.pump?.enqueue(buffer)
                frames += AVAudioFramePosition(buffer.frameLength)
                let due = Double(frames) / audio.processingFormat.sampleRate
                let remaining = due - Date().timeIntervalSince(feedingStarted)
                if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
            }
            let released = Date()
            session.pump?.finish()
            let text = try await session.finish()
            return ["preparationSeconds": prepared.timeIntervalSince(start),
                    "audioSeconds": Double(audio.length) / audio.processingFormat.sampleRate,
                    "releaseToTextSeconds": Date().timeIntervalSince(released),
                    "firstPreviewSeconds": session.firstPreviewAt?.timeIntervalSince(feedingStarted) ?? -1,
                    "text": text]
        } catch { session.cancel(); throw error }
    }
}
