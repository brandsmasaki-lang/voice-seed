import AVFoundation

/// Normalized RMS of the captured PCM, using the active channel with the strongest signal.
enum MicrophoneLevel {
    static func measure(_ buffer: AVAudioPCMBuffer) -> Double {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        func rms<Sample>(_ channels: UnsafePointer<UnsafeMutablePointer<Sample>>,
                         asDouble: (Sample) -> Double) -> Double {
            var strongest: Double = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                var sum: Double = 0
                let samples = channels[channel]
                for frame in 0..<frames {
                    let sample = asDouble(samples[frame * buffer.stride])
                    sum += sample * sample
                }
                strongest = max(strongest, sqrt(sum / Double(frames)))
            }
            return strongest
        }
        let amplitude: Double
        if let channels = buffer.floatChannelData {
            amplitude = rms(channels, asDouble: Double.init)
        } else if let channels = buffer.int16ChannelData {
            amplitude = rms(channels) { Double($0) / 32768 }
        } else if let channels = buffer.int32ChannelData {
            amplitude = rms(channels) { Double($0) / 2147483648 }
        } else { return 0 }
        // The shelf below -60 dBFS leaves the meter at rest in silence.
        return max(0, min(1, (20 * log10(max(0.000001, amplitude)) + 60) / 60))
    }
}
