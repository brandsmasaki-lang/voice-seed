import Foundation

/// Progressive hypotheses replace their time range; only finalized words may be pasted.
struct TranscriptBuffer {
    struct WordBoundary {
        let midpoint: Double
        let offset: Int
    }
    struct Segment {
        let start: Double
        let end: Double
        let text: String
        let isFinal: Bool
        var words: [WordBoundary] = []
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
    mutating func update(start: Double, end: Double, text: String, isFinal: Bool, words: [WordBoundary] = []) {
        guard start.isFinite, end.isFinite, end >= start else { return }
        func overlaps(_ segment: Segment) -> Bool {
            abs(segment.start - start) < 0.00001 || (segment.start < end && start < segment.end)
        }
        if !isFinal && segments.contains(where: { $0.isFinal && overlaps($0) }) { return }
        segments.removeAll(where: overlaps)
        segments.append(Segment(start: start, end: end, text: text, isFinal: isFinal, words: words))
        segments.sort { $0.start < $1.start }
    }
    /// Taps stay on the audio timeline even if a later hypothesis changes the spelling.
    func paragraphs(at breaks: [Double], finalOnly: Bool = false) -> [String] {
        let values = finalOnly ? segments.filter(\.isFinal) : segments
        guard !breaks.isEmpty else { return [joined(values)] }
        var groups: [[Segment]] = [[]]
        var remaining = breaks.sorted()[...]
        for segment in values {
            let words = segment.words.isEmpty
                ? [WordBoundary(midpoint: (segment.start + segment.end) / 2, offset: 0)] : segment.words
            let characters = Array(segment.text)
            var lower = 0
            for word in words {
                guard let first = remaining.first, first <= word.midpoint else { continue }
                let offset = min(characters.count, max(lower, word.offset))
                if offset > lower {
                    groups[groups.count - 1].append(Segment(start: segment.start, end: segment.end,
                        text: String(characters[lower..<offset]), isFinal: segment.isFinal))
                }
                lower = offset
                while let time = remaining.first, time <= word.midpoint {
                    groups.append([])
                    remaining = remaining.dropFirst()
                }
            }
            if lower < characters.count {
                groups[groups.count - 1].append(Segment(start: segment.start, end: segment.end,
                    text: String(characters[lower...]), isFinal: segment.isFinal))
            }
        }
        return groups.map(joined) + Array(repeating: "", count: remaining.count)
    }

    var preview: String { joined(segments) }
    var finalText: String { joined(segments.filter(\.isFinal)) }
}
