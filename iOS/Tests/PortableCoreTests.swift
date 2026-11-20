import Foundation

@main enum PortableCoreTests {
    static func main() throws {
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name); assertions += 1
        }
        let now = Date()
        var state = SessionSnapshot(); state.activate(at: now); state.phase = .ready
        expect(state.isLive(at: now), "fresh heartbeat")
        expect(!state.isLive(at: now.addingTimeInterval(3)), "dead process cannot stay ready")
        let request = CaptureRequest(id: UUID(), sessionID: state.sessionID!, focusID: UUID(), documentID: "synthetic", startedAt: now)
        expect(state.begin(request, at: now), "start current request")
        let metrics = DictationMetrics(speechSeconds: 1, finalizationMilliseconds: 10, refinementMilliseconds: 0, refinementApplied: false)
        expect(state.publish(.init(request: request, text: "合成の文章", metrics: metrics, createdAt: now)), "publish once")
        expect(state.claimDelivery(requestID: request.id, focusID: UUID(), documentID: request.documentID, now: now) == nil, "new focus cannot claim")
        expect(state.claimDelivery(requestID: request.id, focusID: request.focusID, documentID: "other", now: now) == nil, "new document cannot claim")
        expect(state.claimDelivery(requestID: request.id, focusID: request.focusID, documentID: request.documentID, now: now) != nil, "claim same focus")
        expect(state.claimDelivery(requestID: request.id, focusID: request.focusID, documentID: request.documentID, now: now) == nil, "never insert duplicate")
        state.disconnect(); expect(!state.isLive(at: now), "disconnect")
        expect(state.history.count == 1, "manual recovery remains")
        for _ in 0..<8 {
            state.activate(at: now); state.phase = .ready
            let next = CaptureRequest(id: UUID(), sessionID: state.sessionID!, focusID: UUID(), documentID: "synthetic", startedAt: now)
            expect(state.begin(next, at: now), "history start")
            expect(state.publish(.init(request: next, text: "合成", metrics: metrics, createdAt: now)), "history publish")
        }
        expect(state.history.count == 5, "bounded history")
        expect(TextPipeline.process("えー、こえの種を15時に送らないでください。", entries: [.init(heard: "こえの種", written: "こえのたね")], removeFillers: true) == "こえのたねを15時に送らないでください。", "numbers and negation")
        expect(TextPipeline.removeFillers("「えっと」と書く") == "「えっと」と書く", "quotes stay")
        expect(!TextPipeline.acceptsRefinement(original: "15時に3人", candidate: "16時に3人"), "reject changed facts")
        expect(TextAccuracy.characterErrorRate(reference: "明日は晴れ", candidate: "明日は雨れ") == 0.2, "CER is measured")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceSeedSynthetic-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let a = try SharedSessionStore(directory: url), b = try SharedSessionStore(directory: url)
        try a.update { $0.settings.removeFillers = false }
        try b.update { $0.message = "fixture" }
        let read = try a.read()
        expect(!read.settings.removeFillers && read.message == "fixture", "no cross-process lost update")
        try a.update { value in
            do { try b.update { $0.message = "must not write" }; preconditionFailure("lock did not protect state") }
            catch SharedStoreError.busy { assertions += 1 }
            value.message = "protected"
        }
        let command = SessionCommand(kind: .activate)
        try a.enqueue(command); try a.enqueue(command)
        let first = try a.nextCommand(at: Date()), duplicate = try a.nextCommand(at: Date())
        expect(first?.id == command.id && duplicate == nil, "replay protection")
        let path = url.appendingPathComponent("session.json"), damaged = Data("synthetic damage".utf8)
        try damaged.write(to: path)
        do { try a.update { $0.message = "must not replace" }; preconditionFailure("damaged state was overwritten") }
        catch SharedStoreError.damaged { assertions += 1 }
        let preserved = try Data(contentsOf: path)
        expect(preserved == damaged, "damaged state stays intact")
        print("PASS: \(assertions) iOS shared-core assertions; synthetic data only")
    }
}
