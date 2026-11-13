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
    var preview: String { segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines) }
    var finalText: String { segments.filter(\.isFinal).map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines) }
}
