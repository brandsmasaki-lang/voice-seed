import XCTest
@testable import VoiceSeedCore

final class SessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func prepared() -> SessionSnapshot {
        var state = SessionSnapshot(); state.activate(at: now); state.phase = .ready; return state
    }
    private func request(_ state: SessionSnapshot) -> CaptureRequest {
        .init(id: UUID(), sessionID: state.sessionID!, focusID: UUID(), documentID: "synthetic-document", startedAt: now)
    }
    private func delivery(_ request: CaptureRequest, text: String = "合成の文章です。") -> TextDelivery {
        .init(request: request, text: text,
              metrics: .init(speechSeconds: 2, finalizationMilliseconds: 300, refinementMilliseconds: 0,
                             firstPreviewMilliseconds: 100, refinementApplied: false), createdAt: now)
    }

    func testHeartbeatAndExpiryStopStaleSession() {
        var state = prepared()
        XCTAssertTrue(state.isLive(at: now.addingTimeInterval(1)))
        XCTAssertFalse(state.isLive(at: now.addingTimeInterval(3)))
        XCTAssertFalse(state.isLive(at: now.addingTimeInterval(-5)))
        state.expiresAt = now
        XCTAssertFalse(state.isLive(at: now))
    }
    func testPreviousSessionAndOldCommandsCannotStartListening() {
        var state = prepared(); let old = request(state)
        state.activate(at: now); state.phase = .ready
        XCTAssertFalse(state.begin(old, at: now))
        var next = request(state); next.startedAt = now.addingTimeInterval(-20)
        XCTAssertFalse(state.begin(next, at: now))
    }
    func testOnlyCurrentRequestCanPublish() {
        var state = prepared(); let active = request(state)
        XCTAssertTrue(state.begin(active, at: now))
        XCTAssertFalse(state.publish(delivery(request(state))))
        XCTAssertTrue(state.publish(delivery(active)))
        XCTAssertFalse(state.publish(delivery(active)))
    }
    func testFocusAndDocumentMustMatchBeforeClaim() {
        var state = prepared(); let active = request(state)
        XCTAssertTrue(state.begin(active, at: now)); XCTAssertTrue(state.publish(delivery(active)))
        XCTAssertNil(state.claimDelivery(requestID: active.id, focusID: UUID(), documentID: active.documentID, now: now))
        XCTAssertNil(state.claimDelivery(requestID: active.id, focusID: active.focusID, documentID: "other", now: now))
        XCTAssertNotNil(state.claimDelivery(requestID: active.id, focusID: active.focusID, documentID: active.documentID, now: now))
        XCTAssertNil(state.claimDelivery(requestID: active.id, focusID: active.focusID, documentID: active.documentID, now: now))
        XCTAssertEqual(state.delivery?.status, .claimed)
    }
    func testExpiredDeliveryIsNeverInserted() {
        var state = prepared(); let active = request(state)
        XCTAssertTrue(state.begin(active, at: now)); XCTAssertTrue(state.publish(delivery(active)))
        XCTAssertNil(state.claimDelivery(requestID: active.id, focusID: active.focusID, documentID: active.documentID, now: now.addingTimeInterval(31)))
    }
    func testDisconnectPreventsOldDeliveryButKeepsManualRecovery() {
        var state = prepared(); let active = request(state)
        XCTAssertTrue(state.begin(active, at: now)); XCTAssertTrue(state.publish(delivery(active)))
        state.disconnect()
        XCTAssertEqual(state.delivery?.status, .focusChanged)
        XCTAssertEqual(state.history.count, 1)
        XCTAssertNil(state.claimDelivery(requestID: active.id, focusID: active.focusID, documentID: active.documentID, now: now))
    }
    func testHistoryIsLimitedToFiveAndOptOutDoesNotDeleteExisting() {
        var state = prepared()
        for index in 0..<8 {
            state.phase = .ready
            let active = request(state); XCTAssertTrue(state.begin(active, at: now))
            XCTAssertTrue(state.publish(delivery(active, text: "合成\(index)")))
        }
        XCTAssertEqual(state.history.count, 5)
        XCTAssertEqual(state.history.first?.text, "合成7")
        state.settings.saveHistory = false; state.phase = .ready
        let next = request(state); XCTAssertTrue(state.begin(next, at: now))
        XCTAssertTrue(state.publish(delivery(next, text: "保存しない")))
        XCTAssertEqual(state.history.first?.text, "合成7")
    }
    func testDictionaryAndFillerRulesPreserveNumbersNegationAndQuotes() {
        let entries: [DictionaryEntry] = [.init(heard: "こえの種", written: "こえのたね")]
        XCTAssertEqual(TextPipeline.process("えー、こえの種で15時までに送らないでください。", entries: entries, removeFillers: true), "こえのたねで15時までに送らないでください。")
        XCTAssertEqual(TextPipeline.removeFillers("「えっと」と書いてください。"), "「えっと」と書いてください。")
        XCTAssertFalse(TextPipeline.acceptsRefinement(original: "15時に3名です。", candidate: "16時に3名です。"))
    }
    func testProgressiveRecognitionNeverDuplicatesRevisedText() {
        var buffer = TranscriptBuffer()
        buffer.update(start: 0, end: 2, text: "今日は", isFinal: false)
        buffer.update(start: 0, end: 2, text: "今日は晴れです。", isFinal: true)
        buffer.update(start: 0, end: 2, text: "今日", isFinal: false)
        XCTAssertEqual(buffer.finalText, "今日は晴れです。")
    }
    func testCharacterErrorRateCountsJapaneseEdits() {
        XCTAssertEqual(TextAccuracy.characterErrorRate(reference: "明日は晴れ", candidate: "明日は雨れ"), 0.2, accuracy: 0.00001)
        XCTAssertEqual(TextAccuracy.characterErrorRate(reference: "明日 は 晴れ", candidate: "明日は晴れ"), 0)
        XCTAssertEqual(TextAccuracy.characterErrorRate(reference: "", candidate: ""), 0)
        XCTAssertEqual(TextAccuracy.characterErrorRate(reference: "", candidate: "声"), 1)
    }
}
