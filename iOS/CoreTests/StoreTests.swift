import Foundation
import XCTest
@testable import VoiceSeedCore

final class StoreTests: XCTestCase {
    private func fixture() throws -> (URL, SharedSessionStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceSeedSynthetic-" + UUID().uuidString)
        return (directory, try SharedSessionStore(directory: directory))
    }
    func testTwoProcessesShareUpdatesWithoutOverwritingOtherFields() throws {
        let (url, first) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let second = try SharedSessionStore(directory: url)
        try first.update { $0.settings.removeFillers = false }
        try second.update { $0.message = "合成" }
        XCTAssertFalse(try first.read().settings.removeFillers)
        XCTAssertEqual(try second.read().message, "合成")
    }
    func testConcurrentLockFailsWithoutLosingData() throws {
        let (url, first) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let second = try SharedSessionStore(directory: url)
        try first.update { value in
            XCTAssertThrowsError(try second.update { $0.message = "上書きしない" })
            value.message = "保持"
        }
        XCTAssertEqual(try first.read().message, "保持")
    }
    func testDamagedFileIsNotSilentlyOverwritten() throws {
        let (url, store) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let data = Data("not valid state".utf8), path = url.appendingPathComponent("session.json")
        try data.write(to: path)
        XCTAssertThrowsError(try store.update { $0.message = "保存しない" })
        XCTAssertEqual(try Data(contentsOf: path), data)
    }
    func testReplayedAndOldCommandsAreConsumedWithoutExecution() throws {
        let (url, store) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let now = Date(), command = SessionCommand(kind: .activate, createdAt: Date())
        try store.enqueue(command); try store.enqueue(command)
        XCTAssertEqual(try store.nextCommand(at: now)?.id, command.id)
        XCTAssertNil(try store.nextCommand(at: now))
        try store.enqueue(.init(kind: .activate, createdAt: now.addingTimeInterval(-61)))
        XCTAssertNil(try store.nextCommand(at: now))
    }
    func testQueueIsBoundedAndHistoryFileIsPrivate() throws {
        let (url, store) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        for _ in 0..<16 { try store.enqueue(.init(kind: .activate)) }
        XCTAssertThrowsError(try store.enqueue(.init(kind: .activate)))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.appendingPathComponent("session.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}

extension StoreTests {
    func testColdLaunchGetsGraceButOldAudioCommandsDoNot() throws {
        let (url, store) = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let now = Date()
        let command = SessionCommand(kind: .activate, createdAt: now.addingTimeInterval(-20),
            keyboardLaunch: .init(documentID: "synthetic-note", createdAt: now.addingTimeInterval(-20)))
        try store.enqueue(command)
        XCTAssertEqual(try store.nextCommand(at: now)?.keyboardLaunch?.documentID, "synthetic-note")
        try store.enqueue(.init(kind: .start, createdAt: now.addingTimeInterval(-11)))
        XCTAssertNil(try store.nextCommand(at: now))
    }
}
