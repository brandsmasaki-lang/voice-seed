import AVFoundation
import Speech

/// Synthetic samples only. No microphone, files, recognition model, or network.
@main struct AudioStreamPumpTests {
    static func main() async throws {
        // AnalyzerInput requires supported PCM; the actual Japanese model selects Int16.
        // Float output traps inside Speech on macOS 27, before the ownership assertions.
        for (sourceType, rate) in [(AVAudioCommonFormat.pcmFormatFloat32, 48_000.0),
                                   (.pcmFormatFloat32, 16_000.0), (.pcmFormatInt16, 48_000.0)] {
            let sourceFormat = AVAudioFormat(commonFormat: sourceType, sampleRate: 48_000, channels: 1, interleaved: false)!
            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: false)!
            let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream()
            let pump = IOSAudioStreamPump(target: targetFormat, continuation: continuation)
            for _ in 0..<4 {
                let source = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 4_800)!
                source.frameLength = 4_800
                for i in 0..<4_800 {
                    let sample = Float(sin(Double(i) * 0.1)) * 0.25
                    if let samples = source.floatChannelData { samples[0][i] = sample }
                    else { source.int16ChannelData![0][i] = Int16(sample * 32767) }
                }
                pump.enqueue(source)
                // Audio taps recycle buffers immediately. The queued work must own a copy.
                if let samples = source.floatChannelData { samples[0].update(repeating: 0, count: 4_800) }
                else { source.int16ChannelData![0].update(repeating: 0, count: 4_800) }
            }
            pump.finish()
            var maximum: Float = 0
            var frames = 0
            for try await input in stream {
                let buffer = input.buffer
                precondition(buffer.format == targetFormat)
                frames += Int(buffer.frameLength)
                for i in 0..<Int(buffer.frameLength) {
                    maximum = max(maximum, abs(Float(buffer.int16ChannelData![0][i]) / 32768))
                }
            }
            precondition(maximum > 0.2 && maximum < 0.3, "Samples were lost or corrupted")
            precondition(abs(frames - Int(0.4 * rate)) < 64, "Sample rate conversion lost audio")
            let diagnostics = await pump.inputDiagnostics()
            precondition(diagnostics.buffers == 4 && diagnostics.frames == 19_200)
            precondition(diagnostics.peakLevel > 0.7)
        }
        for interleaved in [false, true] {
            let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: interleaved)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
            buffer.frameLength = 512
            var levels: [Double] = []
            for volume: Int16 in [0, 320, 16000, 0] {
                for frame in 0..<512 {
                    buffer.int16ChannelData![0][frame * buffer.stride] = 0
                    buffer.int16ChannelData![1][frame * buffer.stride] = volume
                }
                levels.append(MicrophoneLevel.measure(buffer))
            }
            precondition(levels[0] == 0 && levels[1] > 0 && levels[2] > levels[1] && levels[3] == 0)
        }
        print("PASS: microphone meter follows silence, soft and loud PCM, including stereo and integer input")
        try await testQuestionTiming()
        print("PASS: audio buffer ownership and 48kHz/16kHz conversion; synthetic samples only")
    }

    @MainActor private static func testQuestionTiming() async throws {
        let rate = 16_000.0
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: false)!
        let (stream, continuation) = AsyncThrowingStream<AnalyzerInput, Error>.makeStream()
        let pump = IOSAudioStreamPump(target: format, continuation: continuation)
        var phase = 0.0
        for index in 0..<20 {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 640)!
            buffer.frameLength = 640
            for i in 0..<640 {
                let seconds = Double(index * 640 + i) / rate
                let rise = min(1, max(0, (seconds - 0.56) / 0.22))
                phase += 2 * .pi * 180 * pow(2, rise / 2) / rate
                buffer.int16ChannelData![0][i] = Int16(6000 * sin(phase))
            }
            pump.enqueue(buffer)
        }
        pump.finish()
        for try await _ in stream { }
        let duration = CMTime(value: 6400, timescale: 16000)
        var statement = AttributedString("App Storeに並びました？")
        statement.audioTimeRange = CMTimeRange(start: .zero, duration: duration)
        var question = AttributedString("来られる。")
        question.audioTimeRange = CMTimeRange(start: duration, duration: duration)
        statement.append(question)
        let text = OnDeviceCapture.punctuated(statement, start: 0, end: 0.8, pitches: await pump.endingPitches())
        precondition(text == "App Storeに並びました。来られる？", "Each sentence must use its own audio time range")
        let pitches = await pump.endingPitches()
        precondition(OnDeviceCapture.punctuated(AttributedString("ね？"), start: 0.32, end: 0.4,
            pitches: pitches, preceding: "そうだよ") == "ね。")
        precondition(OnDeviceCapture.punctuated(AttributedString("？"), start: 0.80, end: 0.80,
            pitches: pitches, preceding: "そうだよね") == "？")
        print("PASS: level and rising endings in the same synthetic recognition result")
    }
}
