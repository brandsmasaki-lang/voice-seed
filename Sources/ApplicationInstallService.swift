import Foundation

/// The installer copies only a verified app bundle. It never replaces an existing installation or user data.
struct ApplicationInstallService {
    static let applicationURL = URL(fileURLWithPath: "/Applications/こえのたね.app", isDirectory: true)
    let destination: URL
    let bundleIdentifier: String
    private let verify: (URL) throws -> Void

    init(destination: URL = Self.applicationURL, bundleIdentifier: String = "jp.ainotane.voice-seed", verify: @escaping (URL) throws -> Void = Self.verifyCode) {
        self.destination = destination
        self.bundleIdentifier = bundleIdentifier
        self.verify = verify
    }

    func isInstalled(_ source: URL) -> Bool {
        guard (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return false }
        return source.resolvingSymlinksInPath().standardizedFileURL == destination.resolvingSymlinksInPath().standardizedFileURL
    }

    func isMatchingApplication(_ url: URL) -> Bool {
        guard url.pathExtension == "app", let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == bundleIdentifier,
              info["CFBundlePackageType"] as? String == "APPL",
              let executable = info["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), executable != ".", executable != ".." else { return false }
        return FileManager.default.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/" + executable).path)
    }

    func verifiedExistingApplication() throws -> URL? {
        guard FileManager.default.fileExists(atPath: destination.path) else { return nil }
        guard (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw InstallError.differentApplication }
        guard isMatchingApplication(destination) else { throw InstallError.differentApplication }
        try verify(destination)
        return destination
    }

    func install(from source: URL) throws -> URL {
        if isInstalled(source) { return destination }
        guard isMatchingApplication(source) else { throw InstallError.invalidApplication }
        try verify(source)
        if try verifiedExistingApplication() != nil { throw InstallError.alreadyInstalled }
        let manager = FileManager.default
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".voice-seed-install-" + UUID().uuidString + ".app", isDirectory: true)
        defer { if manager.fileExists(atPath: stage.path) { try? manager.removeItem(at: stage) } }
        try manager.copyItem(at: source, to: stage)
        guard isMatchingApplication(stage) else { throw InstallError.invalidApplication }
        try verify(stage)
        // moveItem fails if an installation appeared while copying. Never overwrite it.
        try manager.moveItem(at: stage, to: destination)
        return destination
    }

    private static func verifyCode(_ url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallError.invalidSignature }
    }

    enum InstallError: LocalizedError {
        case invalidApplication, invalidSignature, differentApplication, alreadyInstalled
        var errorDescription: String? {
            switch self {
            case .invalidApplication: return "インストールするアプリの内容を確認できませんでした。"
            case .invalidSignature: return "アプリのコード署名を検証できませんでした。公式のダウンロードから入手し直してください。"
            case .differentApplication: return "インストール先に別の内容があります。自動で置き換えずに停止しました。"
            case .alreadyInstalled: return "すでにインストールされています。アプリケーション内のこえのたねを開いて更新してください。"
            }
        }
    }
}
