import AVFoundation
import Speech
import CoreMedia

/// All conversion runs on one queue. The render callback's buffer is copied before return.
final class IOSAudioStreamPump: @unchecked Sendable {
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

    private func yield(_ buffer: AVAudioPCMBuffer) throws {
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

