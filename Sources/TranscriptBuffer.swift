import Foundation

/// Progressive hypotheses replace their time range; only finalized words may be pasted.
struct TranscriptBuffer {
    struct Segment {
        let start: Double
        let end: Double
        let text: String
        let isFinal: Bool
    }
    private var segments: [Segment] = []
    let paragraphPause: Double?
    init(paragraphPause: Double? = nil) { self.paragraphPause = paragraphPause }

    private func joined(_ values: [Segment]) -> String {
        var output = ""
        var previous: Segment?
        for segment in values {
            if let threshold = paragraphPause, let prior = previous,
               segment.start - prior.end >= threshold,
               let last = output.last, "。？！.!?".contains(last),
               let first = segment.text.first, !first.isWhitespace,
               !"。？！.!?、，,」』）)".contains(first) {
                output += "\n"
            }
            output += segment.text
            previous = segment
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    mutating func update(start: Double, end: Double, text: String, isFinal: Bool) {
        guard start.isFinite, end.isFinite, end >= start else { return }
        func overlaps(_ segment: Segment) -> Bool {
            abs(segment.start - start) < 0.00001 || (segment.start < end && start < segment.end)
        }
        if !isFinal && segments.contains(where: { $0.isFinal && overlaps($0) }) { return }
        segments.removeAll(where: overlaps)
        segments.append(Segment(start: start, end: end, text: text, isFinal: isFinal))
        segments.sort { $0.start < $1.start }
    }
    var preview: String { joined(segments) }
    var finalText: String { joined(segments.filter(\.isFinal)) }
}
