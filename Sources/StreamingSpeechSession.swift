import AVFoundation
import Speech
import CoreMedia

/// All conversion runs on one queue. The render callback's buffer is copied before return.
private final class AudioStreamPump: @unchecked Sendable {
    private let queue = DispatchQueue(label: "jp.ainotane.voice-seed.audio", qos: .userInitiated)
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?
    private var closed = false
    private var conversionError: Error?
    var onLevel: (@Sendable (Double) -> Void)?

    init(target: AVAudioFormat, continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation) {
        self.target = target; self.continuation = continuation
    }

    func enqueue(_ source: AVAudioPCMBuffer) {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return }
        copy.frameLength = source.frameLength
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let outputs = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (input, output) in zip(inputs, outputs) {
            if let src = input.mData, let dst = output.mData { memcpy(dst, src, Int(min(input.mDataByteSize, output.mDataByteSize))) }
        }
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
                conversionError = error; closed = true; continuation.finish(throwing: error)
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
            } catch { conversionError = error; continuation.finish(throwing: error) }
        }
    }
}

@MainActor final class StreamingSpeechSession {
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private var engine: AVAudioEngine?
    private var tapped = false
    private var pump: AudioStreamPump?
    private var reader: Task<String, Error>?
    private var interruptedObserver: NSObjectProtocol?
    private var started = false
    private(set) var firstPreviewAt: Date?
    var onPreview: ((String) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onFailure: ((Error) -> Void)?

    private init(transcriber: SpeechTranscriber, analyzer: SpeechAnalyzer, format: AVAudioFormat) {
        self.transcriber = transcriber; self.analyzer = analyzer; self.format = format
    }

    static func prepare(vocabulary: [String]) async throws -> StreamingSpeechSession {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP")) else {
            throw VoiceError.message("日本語の端末内音声認識を利用できません。")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else { throw VoiceError.message("日本語モデルを準備してください。") }
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: .init(priority: .userInitiated, modelRetention: .processLifetime))
        let context = AnalysisContext()
        context.contextualStrings[.general] = Array(Set(vocabulary.filter { !$0.isEmpty }))
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
            var transcript = TranscriptBuffer()
            do {
                for try await result in transcriber.results {
                    transcript.update(start: result.range.start.seconds, end: result.range.end.seconds,
                                      text: String(result.text.characters), isFinal: result.isFinal)
                    if !transcript.preview.isEmpty {
                        if self?.firstPreviewAt == nil { self?.firstPreviewAt = Date() }
                        self?.onPreview?(transcript.preview)
                    }
                }
                return transcript.finalText
            } catch {
                if !(error is CancellationError) { self?.onFailure?(error) }
                throw error
            }
        }
        try await analyzer.start(inputSequence: stream)
        try Task.checkCancellation()
    }

    func startMicrophone() async throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else { throw VoiceError.message("マイクの入力デバイスを確認してください。") }
        self.engine = engine
        try await startStream()
        try Task.checkCancellation()
        guard let pump else { throw VoiceError.message("音声ストリームを開始できません。") }
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [pump] buffer, _ in pump.enqueue(buffer) }
        tapped = true
        interruptedObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.onFailure?(VoiceError.message("マイクの接続または音声設定が変更されました。もう一度音声入力してください。")) }
        }
        engine.prepare()
        try engine.start()
    }

    private func stopMicrophone() {
        if let interruptedObserver { NotificationCenter.default.removeObserver(interruptedObserver); self.interruptedObserver = nil }
        engine?.stop()
        if tapped { engine?.inputNode.removeTap(onBus: 0); tapped = false }
        engine = nil
    }

    func endAudio() {
        stopMicrophone()
        pump?.finish()
    }

    func finish() async throws -> String {
        do {
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
        stopMicrophone(); pump?.finish(cancelled: true); reader?.cancel()
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
            session.endAudio()
            let text = try await session.finish()
            return ["preparationSeconds": prepared.timeIntervalSince(start),
                    "audioSeconds": Double(audio.length) / audio.processingFormat.sampleRate,
                    "releaseToTextSeconds": Date().timeIntervalSince(released),
                    "firstPreviewSeconds": session.firstPreviewAt?.timeIntervalSince(feedingStarted) ?? -1,
                    "text": text]
        } catch { session.cancel(); throw error }
    }
}
