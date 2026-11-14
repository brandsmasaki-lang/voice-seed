import Foundation

enum AppGroupContainer {
    static func open() throws -> SharedSessionStore {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "VoiceSeedAppGroup") as? String,
              identifier.hasPrefix("group."),
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw SharedStoreError.unavailable
        }
        return try SharedSessionStore(directory: root.appendingPathComponent("VoiceSeed", isDirectory: true))
    }
}
