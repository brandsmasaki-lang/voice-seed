import Foundation

@main struct MicrophoneTailTests {
    static func main() {
        // A 100 ms tap arrived after key-up, but its samples predate the cutoff.
        let pending = MicrophoneTail.slice(frames: 4_800, sampleRate: 48_000, secondsBeforeCutoff: 0.15)
        precondition(pending.count == 4_800 && !pending.reachedEnd)

        // Keep the part of the following buffer with the end of the word.
        // Discard samples after the cutoff, as playback can resume after it.
        let last = MicrophoneTail.slice(frames: 4_800, sampleRate: 48_000, secondsBeforeCutoff: 0.05)
        precondition(last.count == 2_400 && last.reachedEnd)
        let late = MicrophoneTail.slice(frames: 4_800, sampleRate: 48_000, secondsBeforeCutoff: -0.05)
        precondition(late.count == 0 && late.reachedEnd)
        print("PASS: delayed microphone buffers retain the last word without extending the recording past the cutoff")
    }
}
