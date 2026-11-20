/// A tap can deliver a buffer after the user releases Fn. Keep the end of the
/// utterance and trim the buffer where the allowed recording time ends.
struct MicrophoneTail {
    static let graceSeconds = 0.12

    static func slice(frames: Int, sampleRate: Double, secondsBeforeCutoff: Double) -> (count: Int, reachedEnd: Bool) {
        let framesBeforeCutoff = (sampleRate * secondsBeforeCutoff).rounded(.down)
        if framesBeforeCutoff <= 0 { return (0, true) }
        if framesBeforeCutoff > Double(frames) { return (frames, false) }
        return (Int(framesBeforeCutoff), true)
    }
}
