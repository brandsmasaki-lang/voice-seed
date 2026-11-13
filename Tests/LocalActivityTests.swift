import Foundation

@main struct LocalActivityTests {
    static func main() {
        let suite = "voice-seed-test-activity-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 10))!
        let store = LocalActivityStore(defaults: defaults)
        defaults.set("synthetic dictionary sentinel", forKey: "dictionary")
        check(store.snapshot.history.isEmpty && store.snapshot.usage.sessions == 0, "No invented history or statistics")
        for i in 1...7 { store.record(text: "架空の文章\(i)\n改行を保持。", application: "テスト入力先", inputSeconds: 10, at: first, calendar: calendar) }
        check(store.snapshot.history.count == 5, "Only five final texts are retained")
        check(store.snapshot.history.first?.text == "架空の文章7\n改行を保持。", "Newest first and exact copy text")
        check(store.snapshot.history.last?.text.contains("3") == true, "Oldest overflow is discarded")
        check(Set(store.snapshot.history.map(\.id)).count == 5, "Each completed input has a stable distinct identity")
        check(store.snapshot.usage.sessions == 7, "Statistics outlive the five-item text limit")
        check(store.snapshot.usage.characters == (1...7).reduce(0) { $0 + "架空の文章\($1)\n改行を保持。".count }, "Japanese characters are counted without word guessing")
        check(store.snapshot.usage.inputSeconds == 70, "Measured elapsed time is accumulated")
        check(LocalActivityStore(defaults: defaults).snapshot == store.snapshot, "History and totals survive reopening")
        let beforeFile = store.snapshot.usage
        store.record(text: "合成音声ファイルの結果", application: "音声ファイル", inputSeconds: nil, at: first, calendar: calendar)
        check(store.snapshot.history.first?.application == "音声ファイル", "Imported text can be copied from history")
        check(store.snapshot.usage == beforeFile, "Imports do not inflate typing-speed or time-saved statistics")
        let previous = store.snapshot
        store.record(text: "  \n", application: "空", inputSeconds: 10, at: first, calendar: calendar)
        check(store.snapshot == previous, "Empty output is not a completed input")
        store.setHistoryEnabled(false)
        let retained = store.snapshot.history
        store.record(text: "保存しない合成文", application: "メモ", inputSeconds: 2, at: first, calendar: calendar)
        check(store.snapshot.history == retained, "History off prevents new text storage without deleting old text")
        check(store.snapshot.usage.sessions == 8, "Usage is independently configurable")
        store.setHistoryEnabled(true); store.setUsageEnabled(false)
        let frozen = store.snapshot.usage
        store.record(text: "履歴だけの合成文", application: "メモ", inputSeconds: 2, at: first, calendar: calendar)
        check(store.snapshot.usage == frozen && store.snapshot.history.first?.text == "履歴だけの合成文", "Usage off still allows requested text history")
        store.clearHistory()
        check(store.snapshot.history.isEmpty && store.snapshot.usage == frozen, "Clearing history does not clear statistics")
        store.record(text: "次の合成履歴", application: "メモ", inputSeconds: nil, at: first, calendar: calendar)
        let retainedText = store.snapshot.history
        store.clearUsage()
        check(store.snapshot.usage.sessions == 0 && store.snapshot.history == retainedText, "Resetting statistics does not delete text")
        check(defaults.string(forKey: "dictionary") == "synthetic dictionary sentinel", "Activity controls never touch dictionary data")
        store.setTypingSpeed(0); check(store.snapshot.typingCharactersPerMinute == 20, "Typing assumption has a safe lower bound")
        store.setTypingSpeed(5000); check(store.snapshot.typingCharactersPerMinute == 1000, "Typing assumption has a bounded upper range")
        var usage = UsageTotals(); usage.characters = 200; usage.inputSeconds = 30
        check(usage.estimatedSavedSeconds(typingCharactersPerMinute: 100) == 90, "Savings subtract actual input time from the explicit typing assumption")
        check(usage.estimatedSavedSeconds(typingCharactersPerMinute: 1000) == 0, "A slower voice session never produces negative saved time")
        check(usage.charactersPerMinute == 400, "Voice speed uses characters and actual elapsed time")
        usage.inputSeconds = 0; check(usage.charactersPerMinute == 0, "No division by zero")
        store.setUsageEnabled(true)
        store.record(text: "初日", application: "A", inputSeconds: 1, at: first, calendar: calendar)
        check(store.snapshot.usage.currentStreak(on: first, calendar: calendar) == 1, "First active day")
        store.record(text: "同日", application: "B", inputSeconds: 1, at: first, calendar: calendar)
        check(store.snapshot.usage.consecutiveDays == 1, "Multiple sessions do not invent active days")
        let second = calendar.date(byAdding: .day, value: 1, to: first)!
        store.record(text: "翌日", application: "A", inputSeconds: 1, at: second, calendar: calendar)
        check(store.snapshot.usage.consecutiveDays == 2, "Adjacent local dates extend the streak")
        let third = calendar.date(byAdding: .day, value: 1, to: second)!
        check(store.snapshot.usage.currentStreak(on: third, calendar: calendar) == 2, "Yesterday's use remains an active streak")
        let gap = calendar.date(byAdding: .day, value: 2, to: third)!
        check(store.snapshot.usage.currentStreak(on: gap, calendar: calendar) == 0, "Expired streak is not shown as current")
        store.record(text: "再開", application: "A", inputSeconds: 1, at: gap, calendar: calendar)
        check(store.snapshot.usage.consecutiveDays == 1, "A gap restarts the streak")
        check(store.snapshot.usage.topApplication == "A", "Top app uses accumulated created characters")
        store.clearHistory()
        let encoded = String(data: defaults.data(forKey: "localActivity.v1")!, encoding: .utf8)!
        check(!encoded.contains("再開") && !encoded.contains("合成履歴"), "Aggregate statistics do not secretly retain cleared text")
        defaults.set(Data("invalid".utf8), forKey: "localActivity.v1")
        check(LocalActivityStore(defaults: defaults).snapshot.history.isEmpty, "Corrupt local data does not crash startup")
        check(RecordingPresentation.forRecording(startedFromGlobalKey: true) == .nonactivatingNotice, "Fn and shortcut results cannot request the main window")
        check(RecordingPresentation.forRecording(startedFromGlobalKey: false) == .mainWindow, "Explicit in-app recording can display its result")
        check(RecordingPresentation.canPaste(startingApplication: 10, currentApplication: 10), "Same target may receive paste")
        check(!RecordingPresentation.canPaste(startingApplication: 10, currentApplication: 11), "Changed app must never be activated or pasted into")
        check(!RecordingPresentation.canPaste(startingApplication: nil, currentApplication: 10), "Unknown original app cannot receive paste")
        check(!RecordingPresentation.canPaste(startingApplication: 10, currentApplication: nil), "Unknown frontmost app cannot receive paste")
        check(!RecordingPresentation.canPaste(startingApplication: nil, currentApplication: nil), "Two missing app identifiers are not a match")
        print("PASS: \(checks) local history, usage and focus policy checks (synthetic data only)")
    }
}
