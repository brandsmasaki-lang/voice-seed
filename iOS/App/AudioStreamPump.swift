import AVFoundation
import Speech
import CoreMedia

struct IOSAudioInputDiagnostics: Sendable {
    var buffers = 0
    var frames: UInt64 = 0
    var peakLevel: Double = 0
    var sourceMaximum: Float = 0
    var copiedMaximum: Float = 0
}

/// All conversion runs on one queue. The render callback's buffer is copied before return.
final class IOSAudioStreamPump: @unchecked Sendable {
    private let queue = DispatchQueue(label: "jp.ainotane.voice-seed.audio", qos: .userInitiated)
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private let target: AVAudioFormat
    private var converter: AVAudioConverter?
    private var closed = false
    private var conversionError: Error?
    private var diagnostics = IOSAudioInputDiagnostics()
    private var pitches = EndingPitchTrack()
    var onLevel: (@Sendable (Double) -> Void)?

    init(target: AVAudioFormat, continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation) {
        self.target = target; self.continuation = continuation
    }

    func enqueue(_ source: AVAudioPCMBuffer) {
        // Compare amplitudes before and after the render callback's buffer copy.
        // Only aggregate numbers are retained; audio is never written to disk.
        #if DEBUG
        let sourceMaximum = Self.maximumAmplitude(source)
        #endif
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return }
        copy.frameLength = source.frameLength
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let outputs = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (input, output) in zip(inputs, outputs) {
            if let src = input.mData, let dst = output.mData { memcpy(dst, src, Int(min(input.mDataByteSize, output.mDataByteSize))) }
        }
        queue.async { [self] in
            guard !closed else { return }
            diagnostics.buffers += 1
            diagnostics.frames += UInt64(copy.frameLength)
            #if DEBUG
            diagnostics.sourceMaximum = max(diagnostics.sourceMaximum, sourceMaximum)
            diagnostics.copiedMaximum = max(diagnostics.copiedMaximum, Self.maximumAmplitude(copy))
            if diagnostics.buffers == 1 {
                IOSPreparationTrace.step("audio.format=" + String(copy.format.commonFormat.rawValue) + ".channels=" + String(copy.format.channelCount) + ".rate=" + String(copy.format.sampleRate))
            }
            #endif
            do {
                let level = MicrophoneLevel.measure(copy)
                diagnostics.peakLevel = max(diagnostics.peakLevel, level)
                onLevel?(level)
                if copy.format == target { try yield(copy); return }
                if converter == nil {
                    converter = AVAudioConverter(from: copy.format, to: target)
                    converter?.primeMethod = .none
                }
                guard let converter else { throw DictationFailure.message("マイクの音声形式を認識用に変換できません。") }
                let capacity = AVAudioFrameCount(ceil(Double(copy.frameLength) * target.sampleRate / copy.format.sampleRate)) + 64
                guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw DictationFailure.message("音声バッファを作成できません。") }
                var supplied = false
                var error: NSError?
                let status = converter.convert(to: output, error: &error) { _, status in
                    if supplied { status.pointee = .noDataNow; return nil }
                    supplied = true; status.pointee = .haveData; return copy
                }
                if let error { throw error }
                guard status != .error else { throw DictationFailure.message("音声変換でエラーが発生しました。") }
                if output.frameLength > 0 { try yield(output) }
            } catch {
                conversionError = error; closed = true; continuation.finish(throwing: error)
            }
        }
    }

    #if DEBUG
    private static func maximumAmplitude(_ buffer: AVAudioPCMBuffer) -> Float {
        var maximum: Float = 0
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.isInterleaved ? 1 : buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) * (buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1) {
                    maximum = max(maximum, abs(channels[channel][frame]))
                }
            }
        } else if let channels = buffer.int16ChannelData {
            for channel in 0..<Int(buffer.format.isInterleaved ? 1 : buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) * (buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1) {
                    maximum = max(maximum, abs(Float(channels[channel][frame])) / 32768)
                }
            }
        }
        return maximum
    }
    #endif

    func inputDiagnostics() async -> IOSAudioInputDiagnostics {
        await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: diagnostics) }
        }
    }

    func endingPitches() async -> EndingPitchTrack {
        await withCheckedContinuation { callback in queue.async { [self] in callback.resume(returning: pitches) } }
    }

    private func yield(_ buffer: AVAudioPCMBuffer) throws {
        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        if let data = buffer.int16ChannelData?[0] {
            pitches.append(frames: Int(buffer.frameLength), sampleRate: buffer.format.sampleRate) { Double(data[$0 * stride]) / 32768 }
        } else if let data = buffer.floatChannelData?[0] {
            pitches.append(frames: Int(buffer.frameLength), sampleRate: buffer.format.sampleRate) { Double(data[$0 * stride]) }
        }
        if case .dropped = continuation.yield(AnalyzerInput(buffer: buffer)) {
            throw DictationFailure.message("音声認識が追いつかないため音声入力を中止しました。ほかの重い処理を止めてお試しください。")
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

