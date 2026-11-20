import Foundation

enum EndingIntonation { case rising, levelOrFalling, unknown }

enum DictationQuestions {
    /// Change only a likely Japanese sentence ending with usable acoustic evidence.
    static func punctuate(_ text: String, intonation: EndingIntonation, isUtteranceEnd: Bool = false) -> String {
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = phrase.last else { return text }
        let hasQuestion = last == "？" || last == "?"
        let hasStop = last == "。"
        guard hasQuestion || hasStop || isUtteranceEnd else { return text }
        let stem = hasQuestion || hasStop ? String(phrase.dropLast()) : phrase
        let casual = stem.range(of: #"(?:来られる|られる|できる|違う|大丈夫|いいの|いいかな|どうかな|要る|いるの|行ける|わかる|分かる)$"#, options: .regularExpression) != nil
        let explicit = stem.range(of: #"(?:ですか|ますか|ましたか|ませんか|でしょうか|なのか|だろうか|かな)$"#, options: .regularExpression) != nil
        let mark: String
        switch intonation {
        case _ where hasQuestion && stem.hasSuffix("だよね") && intonation != .rising: mark = "。"
        case .rising where !hasQuestion && (casual || explicit): mark = "？"
        case .levelOrFalling where hasQuestion && !explicit:
            // Keep lexical questions such as 「どこにあります？」 even with a level ending.
            let clause = stem.split(whereSeparator: { "。！？!?\n".contains($0) }).last.map(String.init) ?? stem
            guard clause.range(of: #"(?:どう|どこ|いつ|どれ|どちら|どんな|なぜ|なに|何|誰|だれ|いくら|いくつ|どの)"#, options: .regularExpression) == nil,
                  casual || stem.hasSuffix("と思う") || JapaneseSentenceEnding.complete(stem) == stem + "。" else { return text }
            mark = "。"
        default: return text
        }
        // Keep separators between recognizer segments, including trailing spaces.
        guard let range = text.range(of: phrase, options: .backwards) else { return text }
        return text.replacingCharacters(in: range, with: stem + mark)
    }

    /// An optional text-only editor cannot hear the ending. Keep each acoustic question
    /// attached to the same words, including when several sentences share an utterance.
    static func preservesQuestions(_ candidate: String, from original: String) -> Bool {
        let isQuestion: (Character) -> Bool = { $0 == "？" || $0 == "?" }
        if !original.contains(where: isQuestion) { return !candidate.contains(where: isQuestion) }
        func anchors(_ text: String) -> [String] {
            var tail = "", result: [String] = []
            for c in text {
                if isQuestion(c) { result.append(tail); tail = "" }
                else if c.isLetter || c.isNumber { tail.append(c); tail = String(tail.suffix(6)) }
            }
            return result
        }
        return anchors(original) == anchors(candidate)
    }
}

/// On the audio worker, reduce PCM to one pitch estimate per 40 ms of audio.
/// Keep recent estimates for timestamped recognizer results. No recordings are retained.
struct EndingPitchTrack {
    private struct Point { let time: Double; let hz: Double }
    private var points: [Point] = []
    private var window: [Double] = []
    private var elapsed = 0.0
    private var partial = 0.0
    private var count = 0

    mutating func append(frames: Int, sampleRate: Double, sampleAt: (Int) -> Double) {
        guard sampleRate.isFinite, sampleRate >= 4000 else { return }
        let stride = max(1, Int(sampleRate / 4000))
        let rate = sampleRate / Double(stride)
        let frameSize = Int((rate * 0.04).rounded())
        for index in 0..<frames {
            partial += sampleAt(index)
            count += 1
            guard count == stride else { continue }
            window.append(partial / Double(stride))
            count = 0; partial = 0
            if window.count == frameSize {
                elapsed += Double(frameSize) / rate
                if let hz = Self.pitch(window, rate: rate) { points.append(Point(time: elapsed, hz: hz)) }
                window.removeAll(keepingCapacity: true)
            }
        }
        if points.count > 750 { points.removeFirst(250) }
    }

    private static func pitch(_ samples: [Double], rate: Double) -> Double? {
        let mean = samples.reduce(0, +) / Double(samples.count)
        let signal = samples.map { $0 - mean }
        let energy = signal.reduce(0) { $0 + $1 * $1 }
        guard energy > Double(signal.count) * 0.002 * 0.002 else { return nil }
        let low = Int(rate / 500), high = Int(rate / 65)
        var scores: [Double] = []
        for lag in (low - 1)...(high + 1) {
            var cross = 0.0, left = 0.0, right = 0.0
            for i in 0..<(signal.count - lag) {
                let a = signal[i], b = signal[i + lag]
                cross += a * b; left += a * a; right += b * b
            }
            scores.append(cross / max(1e-12, sqrt(left * right)))
        }
        let minimum = max(0.84, (scores.max() ?? 0) * 0.95)
        for i in 1..<(scores.count - 1) where scores[i] >= minimum && scores[i] > scores[i - 1] && scores[i] >= scores[i + 1] {
            return rate / Double(low - 1 + i)
        }
        return nil
    }

    func ending(from start: Double, to end: Double) -> EndingIntonation {
        guard start.isFinite, end.isFinite, let last = points.last(where: { $0.time <= end + 0.02 }),
              end - last.time < 0.35 else { return .unknown }
        let tail = points.filter { $0.time >= max(start + 0.025, last.time - 0.23) && $0.time <= last.time }
        guard tail.count >= 4 else { return .unknown }
        for (a, b) in zip(tail, tail.dropFirst()) {
            guard b.time - a.time < 0.085, abs(12 * log2(b.hz / a.hz)) < 5 else { return .unknown }
        }
        let before = tail[0].hz + tail[1].hz
        let after = tail[tail.count - 2].hz + last.hz
        let semitones = 12 * log2(after / before)
        // A high plateau after the word accent is not a rise on the final syllable.
        let finalRise = 12 * log2(last.hz / tail[tail.count - 3].hz)
        if semitones >= 2.6 && finalRise >= 1 && last.hz >= tail[tail.count - 2].hz * 0.98 { return .rising }
        return semitones <= 1 ? .levelOrFalling : .unknown
    }
}
