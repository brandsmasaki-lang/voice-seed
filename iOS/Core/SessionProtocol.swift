import Foundation

enum SessionPhase: String, Codable, Sendable {
    case inactive, preparing, ready, listening, processing, failed
    var label: String {
        switch self {
        case .inactive: "本体アプリでマイクを準備"
        case .preparing: "準備中"
        case .ready: "タップして話す"
        case .listening: "聞き取り中"
        case .processing: "文章を確定中"
        case .failed: "本体アプリを確認"
        }
    }
}

struct CaptureRequest: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var sessionID: UUID
    var focusID: UUID
    var documentID: String
    var startedAt: Date
    var stoppedAt: Date?
    var benchmarkID: String?
}

struct SessionCommand: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case activate, start, stop, cancel, disconnect, showSettings }
    var id = UUID()
    var kind: Kind
    var createdAt = Date()
    var request: CaptureRequest?
    var keyboardLaunch: KeyboardLaunch?
}

struct KeyboardLaunch: Codable, Equatable, Sendable {
    var id = UUID()
    var documentID: String
    var createdAt: Date
    var keyboardID: UUID?
}

struct DictationMetrics: Codable, Equatable, Sendable {
    var speechSeconds: Double
    var finalizationMilliseconds: Double
    var refinementMilliseconds: Double
    var firstPreviewMilliseconds: Double?
    var refinementApplied: Bool
    var insertionMilliseconds: Double? = nil
}

struct TextDelivery: Codable, Equatable, Sendable, Identifiable {
    enum Status: String, Codable, Sendable { case pending, claimed, inserted, focusChanged }
    var id: UUID { request.id }
    var request: CaptureRequest
    var text: String
    var metrics: DictationMetrics
    var createdAt: Date
    var status: Status = .pending
}

struct LocalHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var text: String
    var date: Date
    var metrics: DictationMetrics
}

struct LocalSettings: Codable, Equatable, Sendable {
    var removeFillers = true
    var refineWithAppleIntelligence = false
    var saveHistory = true
    var sessionMinutes = 5
    var dictionary: [DictionaryEntry] = []
}

struct SessionSnapshot: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var sessionID: UUID?
    var phase: SessionPhase = .inactive
    var heartbeat: Date?
    var expiresAt: Date?
    var request: CaptureRequest?
    var preview = ""
    // Optional for compatibility with snapshots written by earlier builds.
    var finishedRequestID: UUID?
    var keyboardLaunch: KeyboardLaunch?
    var level: Double = 0
    var keyboardActivationTicket: KeyboardLaunch?
    var hostIsForeground: Bool?
    var message = ""
    var commands: [SessionCommand] = []
    var handledCommandIDs: [UUID] = []
    var delivery: TextDelivery?
    var history: [LocalHistoryEntry] = []
    var settings = LocalSettings()
    var benchmarks: [BenchmarkResult] = []

    func isLive(at now: Date) -> Bool {
        guard let heartbeat, let expiresAt, sessionID != nil,
              phase != .inactive, phase != .failed, now < expiresAt else { return false }
        let age = now.timeIntervalSince(heartbeat)
        return age >= -1 && age <= 2
    }

    func keyboardGuidance(at now: Date) -> String {
        if isLive(at: now) {
            if phase == .preparing { return "マイクに接続しています…" }
            return "このまま話せます。タップで開始・もう一度タップで入力。"
        }
        return "マイクを押すと、こえのたねが一度開きます。戻ると聞き取りが始まります。"
    }

    mutating func claimKeyboardLaunch(documentID: String, keyboardID: UUID? = nil, at now: Date) -> Bool {
        guard let launch = keyboardLaunch else { return false }
        let age = now.timeIntervalSince(launch.createdAt)
        guard age >= -1 && age <= 60 else { keyboardLaunch = nil; return false }
        guard phase == .ready, isLive(at: now), hostIsForeground != true else { return false }
        // A document proxy may be recreated when the host application resumes.
        // Only the keyboard instance that issued the launch can rebind it.
        if let owner = launch.keyboardID {
            guard owner == keyboardID else { return false }
        } else {
            guard launch.documentID == documentID else { return false }
        }
        keyboardLaunch = nil
        return true
    }

    mutating func consumeActivationTicket(_ id: UUID, at now: Date) -> KeyboardLaunch? {
        guard let ticket = keyboardActivationTicket, ticket.id == id else { return nil }
        keyboardActivationTicket = nil
        let age = now.timeIntervalSince(ticket.createdAt)
        return age >= -1 && age <= 60 ? ticket : nil
    }

    mutating func renewStandby(at now: Date) {
        expiresAt = now.addingTimeInterval(Double(min(10, max(1, settings.sessionMinutes))) * 60)
    }

    mutating func refreshHeartbeat(at now: Date) {
        heartbeat = now
        if phase == .listening || phase == .processing { renewStandby(at: now) }
    }

    mutating func activate(at now: Date) {
        sessionID = UUID()
        phase = .preparing
        heartbeat = now
        renewStandby(at: now)
        request = nil; delivery = nil; preview = ""; level = 0; message = ""
    }

    mutating func disconnect(message: String = "") {
        phase = .inactive; sessionID = nil; heartbeat = nil; expiresAt = nil
        request = nil; keyboardLaunch = nil; preview = ""; level = 0; self.message = message
        // Keep completed text available for manual recovery, never auto-insert it again.
        if delivery?.status == .pending { delivery?.status = .focusChanged }
    }

    mutating func begin(_ next: CaptureRequest, at now: Date) -> Bool {
        guard phase == .ready, isLive(at: now), next.sessionID == sessionID,
              now.timeIntervalSince(next.startedAt) >= -1,
              now.timeIntervalSince(next.startedAt) <= 5 else { return false }
        request = next; delivery = nil; phase = .listening; preview = ""; level = 0; message = ""
        renewStandby(at: now)
        return true
    }

    mutating func finishWithoutDelivery(_ id: UUID) {
        // A rejected/stale command must never clear a different active request.
        if request?.id == id { request = nil; preview = ""; level = 0 }
        finishedRequestID = id
    }

    mutating func publish(_ next: TextDelivery) -> Bool {
        guard request?.id == next.id, request?.focusID == next.request.focusID,
              next.request.sessionID == sessionID, !next.text.isEmpty else { return false }
        delivery = next; preview = ""; request = nil; level = 0; finishedRequestID = next.id
        if settings.saveHistory {
            history.removeAll { $0.id == next.id }
            history.insert(.init(id: next.id, text: next.text, date: next.createdAt, metrics: next.metrics), at: 0)
            history = Array(history.prefix(5))
        }
        return true
    }

    // Claim before touching UIKit: a crash may require copying from history, but cannot duplicate text.
    mutating func claimDelivery(requestID: UUID, focusID: UUID, documentID: String,
                                now: Date) -> TextDelivery? {
        guard var value = delivery, value.status == .pending,
              value.id == requestID, value.request.focusID == focusID,
              value.request.documentID == documentID,
              value.request.sessionID == sessionID,
              now.timeIntervalSince(value.createdAt) >= -1,
              now.timeIntervalSince(value.createdAt) <= 30 else { return nil }
        value.status = .claimed; delivery = value
        return value
    }
}
