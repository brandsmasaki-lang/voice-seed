import XCTest
@testable import VoiceSeedCore

final class KeyboardEditingTests: XCTestCase {
    func testKeyboardHandoffWaitsForReturnAndRebindsOnlyItsOwner() {
        let now = Date(), owner = UUID()
        var state = SessionSnapshot(); state.activate(at: now); state.phase = .ready
        state.keyboardLaunch = .init(documentID: "before-switch", createdAt: now, keyboardID: owner)
        state.hostIsForeground = true
        XCTAssertFalse(state.claimKeyboardLaunch(documentID: "before-switch", keyboardID: owner, at: now))
        XCTAssertNotNil(state.keyboardLaunch)
        state.hostIsForeground = false
        XCTAssertFalse(state.claimKeyboardLaunch(documentID: "before-switch", keyboardID: UUID(), at: now))
        XCTAssertTrue(state.claimKeyboardLaunch(documentID: "recreated-proxy", keyboardID: owner, at: now))
        XCTAssertFalse(state.claimKeyboardLaunch(documentID: "recreated-proxy", keyboardID: owner, at: now))
    }
    func testBunsetsuDeletionIncludesGrammaticalEndings() {
        for (text, removed) in [("今日は東京に行きました。", "行きました。"), ("今日は東京に", "東京に"),
                                ("これはテストです", "テストです"), ("文字を削除します", "削除します")] {
            XCTAssertEqual(String(text.suffix(BunsetsuDeletion.characterCount(beforeCursor: text))), removed)
        }
    }
    func testDeletionDoesNotCrossParagraphOrEraseWholeEnglishLine() {
        XCTAssertEqual(BunsetsuDeletion.characterCount(beforeCursor: "前の段落。\n東京に"), 3)
        XCTAssertEqual(BunsetsuDeletion.characterCount(beforeCursor: "前の段落。\n"), 1)
        XCTAssertEqual(BunsetsuDeletion.characterCount(beforeCursor: "hello world"), 5)
        XCTAssertEqual(BunsetsuDeletion.characterCount(beforeCursor: "文字  "), 2)
        XCTAssertEqual(BunsetsuDeletion.characterCount(beforeCursor: ""), 0)
    }
    func testLeftFlickNeverAlsoDeletesACharacter() {
        var gesture = DeleteKeyGesture()
        gesture.move(dx: -40, dy: 5)
        XCTAssertEqual(gesture.repeatTick(), .none)
        XCTAssertEqual(gesture.end(), .bunsetsu)
    }
    func testHoldDeletesRepeatedlyWithoutExtraDeleteOnRelease() {
        var gesture = DeleteKeyGesture()
        XCTAssertEqual(gesture.repeatTick(), .character)
        XCTAssertEqual(gesture.repeatTick(), .character)
        XCTAssertEqual(gesture.end(), .none)
        XCTAssertEqual(DeleteKeyGesture().end(), .character)
    }
    func testURLCannotStartMicrophoneWithoutOneUseKeyboardTicket() {
        let now = Date(), ticket = KeyboardLaunch(documentID: "synthetic-field", createdAt: Date())
        var state = SessionSnapshot(); state.keyboardActivationTicket = ticket
        XCTAssertNil(state.consumeActivationTicket(UUID(), at: now))
        XCTAssertEqual(state.consumeActivationTicket(ticket.id, at: now)?.documentID, "synthetic-field")
        XCTAssertNil(state.consumeActivationTicket(ticket.id, at: now))
        state.keyboardActivationTicket = .init(documentID: "synthetic-field", createdAt: now.addingTimeInterval(-61))
        XCTAssertNil(state.consumeActivationTicket(state.keyboardActivationTicket!.id, at: now))
        XCTAssertEqual(VoiceSeedLink(url: VoiceSeedLink.dictationURL(ticket: ticket.id)), .dictate(ticket.id))
        XCTAssertNil(VoiceSeedLink(url: URL(string: "https://example.com/dictate")!))
        XCTAssertNil(VoiceSeedLink(url: URL(string: "koenotane://dictate?ticket=bad")!))
        XCTAssertNil(VoiceSeedLink(url: URL(string: "koenotane://dictate?ticket=\(ticket.id)&redirect=other")!))
    }
}
