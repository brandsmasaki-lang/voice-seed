import Foundation

struct RecentInput: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let text: String
    let application: String
}

struct UsageTotals: Codable, Equatable {
    var characters = 0
    var sessions = 0
    var inputSeconds: Double = 0
    var applicationCharacters: [String: Int] = [:]
    var lastUseDay: String?
    var consecutiveDays = 0

    var charactersPerMinute: Double {
        guard inputSeconds > 0 else { return 0 }
        let rate = Double(characters) * 60 / inputSeconds
        return rate.isFinite && rate < Double(Int.max) ? rate : 0
    }
    var topApplication: String? {
        applicationCharacters.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first?.key
    }
    func estimatedSavedSeconds(typingCharactersPerMinute: Int) -> Double {
        max(0, Double(characters) * 60 / Double(max(20, typingCharactersPerMinute)) - inputSeconds)
    }
    func currentStreak(on date: Date, calendar: Calendar = .current) -> Int {
        let today = LocalActivityStore.dayKey(date, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date).map { LocalActivityStore.dayKey($0, calendar: calendar) }
        return lastUseDay == today || lastUseDay == yesterday ? consecutiveDays : 0
    }
}

struct LocalActivitySnapshot: Codable, Equatable {
    var history: [RecentInput] = []
    var usage = UsageTotals()
    var savesHistory = true
    var collectsUsage = true
    // A user-editable assumption for the comparison, not a measured typing speed.
    var typingCharactersPerMinute = 100
}

final class LocalActivityStore {
    private let defaults: UserDefaults
    private let key = "localActivity.v1"
    private(set) var snapshot = LocalActivitySnapshot()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: key), data.count <= 2_000_000,
              var value = try? JSONDecoder().decode(LocalActivitySnapshot.self, from: data),
              value.history.count <= 5,
              value.history.allSatisfy({ !$0.text.isEmpty && $0.text.utf8.count <= 256_000 && $0.application.count <= 120 }),
              (0...1_000_000_000_000).contains(value.usage.characters), (0...1_000_000_000).contains(value.usage.sessions),
              value.usage.inputSeconds.isFinite, (0...1_000_000_000_000).contains(value.usage.inputSeconds),
              value.usage.applicationCharacters.count <= 50,
              value.usage.applicationCharacters.allSatisfy({ $0.key.count <= 120 && $0.value >= 0 }),
              (0...1_000_000).contains(value.usage.consecutiveDays) else { return }
        value.typingCharactersPerMinute = min(1000, max(20, value.typingCharactersPerMinute))
        snapshot = value
    }

    func record(text: String, application: String, inputSeconds: Double?, at date: Date = Date(), calendar: Calendar = .current) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let name = String(application.prefix(120))
        if snapshot.savesHistory && text.utf8.count <= 256_000 {
            snapshot.history.insert(RecentInput(id: UUID(), createdAt: date, text: text, application: name), at: 0)
            snapshot.history = Array(snapshot.history.prefix(5))
        }
        // Imported audio is available in history but is not a measured dictation session.
        if snapshot.collectsUsage, let seconds = inputSeconds, seconds.isFinite, seconds >= 0 {
            snapshot.usage.characters += text.count
            snapshot.usage.sessions += 1
            snapshot.usage.inputSeconds += seconds
            snapshot.usage.applicationCharacters[name, default: 0] += text.count
            if snapshot.usage.applicationCharacters.count > 50 {
                snapshot.usage.applicationCharacters = Dictionary(uniqueKeysWithValues: snapshot.usage.applicationCharacters.sorted { $0.value > $1.value }.prefix(50).map { ($0.key, $0.value) })
            }
            let day = Self.dayKey(date, calendar: calendar)
            if snapshot.usage.lastUseDay != day {
                let yesterday = calendar.date(byAdding: .day, value: -1, to: date).map { Self.dayKey($0, calendar: calendar) }
                snapshot.usage.consecutiveDays = snapshot.usage.lastUseDay == yesterday ? snapshot.usage.consecutiveDays + 1 : 1
                snapshot.usage.lastUseDay = day
            }
        }
        persist()
    }

    func setHistoryEnabled(_ enabled: Bool) { snapshot.savesHistory = enabled; persist() }
    func setUsageEnabled(_ enabled: Bool) { snapshot.collectsUsage = enabled; persist() }
    func setTypingSpeed(_ speed: Int) { snapshot.typingCharactersPerMinute = min(1000, max(20, speed)); persist() }
    func clearHistory() { snapshot.history = []; persist() }
    func clearUsage() { snapshot.usage = UsageTotals(); persist() }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}
