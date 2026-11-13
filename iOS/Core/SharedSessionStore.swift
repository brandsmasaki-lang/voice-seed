import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum SharedStoreError: LocalizedError {
    case unavailable, damaged, tooLarge, busy
    var errorDescription: String? {
        switch self {
        case .unavailable: "アプリとキーボードの共有領域を開けません。App Groupsの設定を確認してください。"
        case .damaged: "共有データの形式を確認できません。既存データは変更していません。"
        case .tooLarge: "共有データが上限を超えています。辞書の件数を減らしてください。"
        case .busy: "共有領域を使用中です。少し待ってもう一度お試しください。"
        }
    }
}

/// Both processes lock the same inode; atomic replacement never replaces the lock file.
final class SharedSessionStore: @unchecked Sendable {
    static let maximumBytes = 2 * 1024 * 1024
    let directory: URL
    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let value = JSONEncoder(); value.dateEncodingStrategy = .millisecondsSince1970
        value.outputFormatting = [.sortedKeys]; return value
    }()
    private let decoder: JSONDecoder = {
        let value = JSONDecoder(); value.dateDecodingStrategy = .millisecondsSince1970; return value
    }()

    init(directory: URL) throws {
        guard directory.isFileURL else { throw SharedStoreError.unavailable }
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var excluded = directory
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try excluded.setResourceValues(flags)
    }

    private func withFileLock<T>(_ action: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        let descriptor = open(directory.appendingPathComponent("session.lock").path,
                              O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw SharedStoreError.unavailable }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw SharedStoreError.busy }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try action()
    }

    private func readUnlocked() throws -> SessionSnapshot {
        let url = directory.appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return SessionSnapshot() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw SharedStoreError.damaged }
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= Self.maximumBytes else { throw SharedStoreError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumBytes else { throw SharedStoreError.tooLarge }
        guard let value = try? decoder.decode(SessionSnapshot.self, from: data), value.schemaVersion == 1,
              value.history.count <= 5, value.commands.count <= 16,
              value.handledCommandIDs.count <= 32, value.benchmarks.count <= 50 else { throw SharedStoreError.damaged }
        return value
    }

    func read() throws -> SessionSnapshot { try withFileLock { try readUnlocked() } }

    @discardableResult func update<T>(_ transform: (inout SessionSnapshot) throws -> T) throws -> T {
        try withFileLock {
            let before = try readUnlocked()
            var after = before
            let result = try transform(&after)
            guard after != before else { return result }
            let bytes = try encoder.encode(after)
            guard bytes.count <= Self.maximumBytes else { throw SharedStoreError.tooLarge }
            let url = directory.appendingPathComponent("session.json")
            try bytes.write(to: url, options: .atomic)
            var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
            #if os(iOS)
            attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
            #endif
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
            return result
        }
    }

    func enqueue(_ command: SessionCommand) throws {
        try update {
            guard $0.commands.count < 16 else { throw SharedStoreError.busy }
            $0.commands.append(command)
        }
    }

    func nextCommand(at now: Date) throws -> SessionCommand? {
        try update { value in
            while !value.commands.isEmpty {
                let next = value.commands.removeFirst()
                guard !value.handledCommandIDs.contains(next.id) else { continue }
                value.handledCommandIDs.append(next.id)
                value.handledCommandIDs = Array(value.handledCommandIDs.suffix(32))
                let age = now.timeIntervalSince(next.createdAt)
                if age >= -1 && age <= 10 { return next }
            }
            return nil
        }
    }
}
