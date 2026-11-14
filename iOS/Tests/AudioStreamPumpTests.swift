import AVFoundation
import Speech

/// Synthetic samples only. No microphone, files, recognition model, or network.
@main struct AudioStreamPumpTests {
    static func main() async throws {
        for rate in [48_000.0, 16_000.0] {
            let sourceFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let targetFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
            let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream()
            let pump = IOSAudioStreamPump(target: targetFormat, continuation: continuation)
            for _ in 0..<4 {
                let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 4_800)!
                source.frameLength = 4_800
                for i in 0..<4_800 { source.floatChannelData![0][i] = Float(sin(Double(i) * 0.1)) * 0.25 }
                pump.enqueue(source)
                // Audio taps recycle buffers immediately. The queued work must own a copy.
                source.floatChannelData![0].update(repeating: 0, count: 4_800)
            }
            pump.finish()
            var maximum: Float = 0
            var frames = 0
            for try await input in stream {
                precondition(input.buffer.format == targetFormat)
                frames += Int(input.buffer.frameLength)
                for i in 0..<Int(input.buffer.frameLength) {
                    maximum = max(maximum, abs(input.buffer.floatChannelData![0][i]))
                }
            }
            precondition(maximum > 0.2 && maximum < 0.3, "Samples were lost or corrupted")
            precondition(abs(frames - Int(0.4 * rate)) < 64, "Sample rate conversion lost audio")
            let diagnostics = await pump.inputDiagnostics()
            precondition(diagnostics.buffers == 4 && diagnostics.frames == 19_200)
            precondition(diagnostics.peakLevel > 0.7)
        }
        print("PASS: audio buffer ownership and 48kHz/16kHz conversion; synthetic samples only")
    }
}
