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

    func testReviewKeepsCorrectedTextUntilAnExplicitSinglePaste() {
        var state = prepared()
        var recording = request(state)
        recording.reviewBeforeInsertion = true
        XCTAssertTrue(state.begin(recording, at: now))
        state.preview = "仮の認識結果"
        XCTAssertTrue(state.publish(delivery(recording, text: "洗濯")))
        XCTAssertNotEqual(state.retainedDraft?.isInterruptedPreview, true)
        XCTAssertNil(state.claimDelivery(requestID: recording.id, focusID: recording.focusID, documentID: recording.documentID, now: now))
        XCTAssertFalse(state.reviseDraft(UUID(), replacing: "洗濯", with: "別"))
        XCTAssertTrue(state.reviseDraft(recording.id, replacing: "洗濯", with: "選択"))
        XCTAssertFalse(state.reviseDraft(recording.id, replacing: "洗濯", with: "古い結果"))
        state.disconnect()
        XCTAssertEqual(state.retainedDraft?.text, "選択")
        XCTAssertEqual(state.takeRetainedDraft(recording.id)?.text, "選択")
        XCTAssertNil(state.takeRetainedDraft(recording.id))
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

extension SessionTests {
    func testLongProgressiveTextRetainsAllFinalSegments() {
        var buffer = TranscriptBuffer()
        var expected = ""
        for i in 0..<120 {
            let text = "第\(i)項。午後3時までに資料を送らないでください。\n"
            let start = Double(i * 2)
            buffer.update(start: start, end: start + 2, text: "第", isFinal: false)
            buffer.update(start: start, end: start + 2, text: text, isFinal: true)
            buffer.update(start: start, end: start + 2, text: "古い途中結果", isFinal: false)
            expected += text
        }
        XCTAssertEqual(buffer.finalText, expected.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testTwentyConsecutiveDeliveriesAreInsertedOnceInOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try SharedSessionStore(directory: directory)
        let keyboard = try SharedSessionStore(directory: directory)
        try host.update { $0 = prepared() }
        var inserted: [String] = []
        for i in 0..<20 {
            try host.update { $0.phase = .ready }
            let next = request(try keyboard.read())
            try host.update { XCTAssertTrue($0.begin(next, at: now)) }
            try host.update { XCTAssertTrue($0.publish(delivery(next, text: "入力\(i)"))) }
            let received = try keyboard.update {
                $0.claimDelivery(requestID: next.id, focusID: next.focusID, documentID: next.documentID, now: now)
            }
            inserted.append(try XCTUnwrap(received).text)
            try keyboard.update {
                XCTAssertNil($0.claimDelivery(requestID: next.id, focusID: next.focusID, documentID: next.documentID, now: now))
                $0.delivery?.status = .inserted
            }
        }
        XCTAssertEqual(inserted, (0..<20).map { "入力\($0)" })
        XCTAssertEqual(try host.read().history.count, 5)
    }
}

extension SessionTests {
    func testSilentCompletionReleasesRequestWithoutPublishingText() {
        var state = prepared(); let first = request(state)
        XCTAssertTrue(state.begin(first, at: now))
        state.finishWithoutDelivery(first.id); state.phase = .ready
        XCTAssertNil(state.request); XCTAssertNil(state.delivery)
        XCTAssertEqual(state.finishedRequestID, first.id)
        XCTAssertTrue(state.begin(request(state), at: now))
    }

    func testRejectedRequestDoesNotEraseActiveUtterance() {
        var state = prepared(); let active = request(state); let rejected = request(state)
        XCTAssertTrue(state.begin(active, at: now))
        XCTAssertFalse(state.begin(rejected, at: now))
        state.finishWithoutDelivery(rejected.id)
        XCTAssertEqual(state.request?.id, active.id)
        XCTAssertEqual(state.phase, .listening)
        XCTAssertTrue(state.publish(delivery(active)))
        XCTAssertEqual(state.finishedRequestID, active.id)
    }

    func testLongCaptureRenewsStandbyButIdleSessionStillExpires() {
        var state = prepared(); state.settings.sessionMinutes = 1
        XCTAssertTrue(state.begin(request(state), at: now))
        for second in 1...180 {
            let tick = now.addingTimeInterval(Double(second))
            state.refreshHeartbeat(at: tick)
            XCTAssertTrue(state.isLive(at: tick))
        }
        state.phase = .ready
        let expiry = state.expiresAt
        state.refreshHeartbeat(at: now.addingTimeInterval(230))
        XCTAssertEqual(state.expiresAt, expiry)
        state.refreshHeartbeat(at: now.addingTimeInterval(241))
        XCTAssertFalse(state.isLive(at: now.addingTimeInterval(241)))
    }

    func testPreviousSnapshotWithoutCompletionFieldStillDecodes() throws {
        let encoder = JSONEncoder()
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(prepared())) as? [String: Any])
        fields.removeValue(forKey: "finishedRequestID")
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertNil(decoded.finishedRequestID)
        XCTAssertEqual(decoded.phase, .ready)
    }
}

extension SessionTests {
    func testKeyboardLaunchWaitsForOriginalFieldAndCanOnlyBeClaimedOnce() {
        var state = prepared()
        state.keyboardLaunch = .init(documentID: "original-note", createdAt: now)
        XCTAssertFalse(state.claimKeyboardLaunch(documentID: "another-note", at: now))
        XCTAssertNotNil(state.keyboardLaunch)
        state.phase = .preparing
        XCTAssertFalse(state.claimKeyboardLaunch(documentID: "original-note", at: now))
        state.phase = .ready
        XCTAssertTrue(state.claimKeyboardLaunch(documentID: "original-note", at: now))
        XCTAssertFalse(state.claimKeyboardLaunch(documentID: "original-note", at: now))
    }
    func testExpiredOrDisconnectedKeyboardLaunchCannotStartLater() {
        var state = prepared()
        state.keyboardLaunch = .init(documentID: "original-note", createdAt: now.addingTimeInterval(-61))
        XCTAssertFalse(state.claimKeyboardLaunch(documentID: "original-note", at: now))
        XCTAssertNil(state.keyboardLaunch)
        state.keyboardLaunch = .init(documentID: "original-note", createdAt: now)
        state.disconnect()
        XCTAssertNil(state.keyboardLaunch)
    }
}

extension SessionTests {
    func testTemporaryKeyboardDismissalRetainsUnfinishedTextWithoutAutoDelivery() {
        var state = prepared(); let active = request(state)
        XCTAssertTrue(state.begin(active, at: now))
        state.preview = "撮影の前に話していた合成の文章です。"
        state.finishWithoutDelivery(active.id, preservingPreview: true)
        XCTAssertEqual(state.retainedDraft?.text, "撮影の前に話していた合成の文章です。")
        XCTAssertEqual(state.retainedDraft?.isInterruptedPreview, true)
        XCTAssertNil(state.request); XCTAssertNil(state.delivery)
        XCTAssertEqual(state.preview, "")
        state.phase = .ready
        XCTAssertFalse(state.begin(request(state), at: now), "Must not replace an unresolved draft")
    }
    func testAudioInterruptionAndReactivationKeepDraftForManualRecovery() {
        var state = prepared(); let active = request(state)
        XCTAssertTrue(state.begin(active, at: now)); state.preview = "途中まで認識した文章"
        state.disconnect(message: "合成の中断")
        XCTAssertEqual(state.retainedDraft?.id, active.id)
        XCTAssertNil(state.delivery)
        state.activate(at: now)
        XCTAssertEqual(state.retainedDraft?.text, "途中まで認識した文章")
        XCTAssertNil(state.takeRetainedDraft(UUID()))
        XCTAssertEqual(state.takeRetainedDraft(active.id)?.text, "途中まで認識した文章")
        XCTAssertNil(state.takeRetainedDraft(active.id), "Recovery cannot insert twice")
        state.phase = .ready
        XCTAssertTrue(state.begin(request(state), at: now))
    }
    func testExplicitCancelStillDiscardsAndStaleCancelCannotTouchActivePreview() {
        var state = prepared(); let active = request(state)
        XCTAssertTrue(state.begin(active, at: now)); state.preview = "残すべき進行中の文章"
        state.finishWithoutDelivery(UUID(), preservingPreview: true)
        XCTAssertEqual(state.preview, "残すべき進行中の文章"); XCTAssertNil(state.retainedDraft)
        state.finishWithoutDelivery(active.id, preservingPreview: false)
        XCTAssertNil(state.retainedDraft); XCTAssertEqual(state.preview, "")
    }
    func testEmptyInterruptedCaptureDoesNotCreateRecoveryPrompt() {
        var state = prepared(); let active = request(state)
        XCTAssertTrue(state.begin(active, at: now))
        state.preview = " \n "
        state.finishWithoutDelivery(active.id, preservingPreview: true)
        XCTAssertNil(state.retainedDraft)
    }
    func testCompletedInsertionIsNotRecoveredAgainAfterDisconnect() {
        var state = prepared(); let active = request(state)
        XCTAssertTrue(state.begin(active, at: now)); state.preview = "入力済みになる文章"
        XCTAssertTrue(state.publish(delivery(active)))
        XCTAssertNotNil(state.claimDelivery(requestID: active.id, focusID: active.focusID, documentID: active.documentID, now: now))
        state.delivery?.status = .inserted
        state.disconnect()
        XCTAssertNil(state.retainedDraft)
    }
    func testRetainedDraftSurvivesSharedStoreReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DraftQA-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try SharedSessionStore(directory: directory)
        var state = prepared(); let active = request(state)
        XCTAssertTrue(state.begin(active, at: now)); state.preview = "合成の長文" + String(repeating: "続きです。", count: 100)
        state.finishWithoutDelivery(active.id, preservingPreview: true)
        try store.update { $0 = state }
        let reopened = try SharedSessionStore(directory: directory)
        let restored = try XCTUnwrap(reopened.read().retainedDraft)
        let original = try XCTUnwrap(state.retainedDraft)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.text, original.text)
        // The store encodes milliseconds; floating-point date round trips need a bounded tolerance.
        XCTAssertEqual(restored.date.timeIntervalSince1970, original.date.timeIntervalSince1970, accuracy: 0.001)
    }
    func testOlderSnapshotsAndCommandsDecodeWithoutRecoveryFields() throws {
        let encoder = JSONEncoder()
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(prepared())) as? [String: Any])
        fields.removeValue(forKey: "retainedDraft")
        XCTAssertNil(try JSONDecoder().decode(SessionSnapshot.self, from: JSONSerialization.data(withJSONObject: fields)).retainedDraft)
        let command = SessionCommand(kind: .cancel, request: request(prepared()))
        var oldCommand = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(command)) as? [String: Any])
        oldCommand.removeValue(forKey: "preservePreview")
        XCTAssertNil(try JSONDecoder().decode(SessionCommand.self, from: JSONSerialization.data(withJSONObject: oldCommand)).preservePreview)
        let interrupted = SessionCommand(kind: .cancel, request: command.request, preservePreview: true)
        XCTAssertEqual(try JSONDecoder().decode(SessionCommand.self, from: encoder.encode(interrupted)).preservePreview, true)
    }
}
