import Foundation

@main struct ApplicationInstallTests {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("voice-seed-install-test-" + UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let applications = root.appendingPathComponent("Applications")
        try manager.createDirectory(at: applications, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Downloads/こえのたね.app")
        let destination = applications.appendingPathComponent("こえのたね.app")
        func fixture(_ app: URL, identifier: String = "test.voice-seed", payload: String = "synthetic binary") throws {
            try manager.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":identifier,"CFBundlePackageType":"APPL","CFBundleExecutable":"VoiceSeed"], format: .xml, options: 0)
            try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
            let executable = app.appendingPathComponent("Contents/MacOS/VoiceSeed")
            try Data(payload.utf8).write(to: executable)
            try manager.setAttributes([.posixPermissions:0o755], ofItemAtPath: executable.path)
        }
        try fixture(source)
        var checks = 0, verified: [URL] = []
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        let service = ApplicationInstallService(destination: destination, bundleIdentifier: "test.voice-seed") { verified.append($0) }
        check(!service.isInstalled(source), "Downloads is not the installation")
        check(service.isInstalled(destination), "Only the canonical application bundle is installed")
        check(!service.isInstalled(applications.appendingPathComponent("Subfolder/こえのたね.app")), "An Applications subfolder is not the destination")
        check(!service.isInstalled(root.appendingPathComponent("Applications-other/こえのたね.app")), "A path prefix cannot pass installation checks")
        check(service.isMatchingApplication(source), "Synthetic app identity is accepted")
        check(try service.verifiedExistingApplication() == nil, "A new install is recognized")
        let sentinel = root.appendingPathComponent("preferences-sentinel")
        try Data("synthetic dictionary/history/settings".utf8).write(to: sentinel)
        let installed = try service.install(from: source)
        check(installed == destination && manager.fileExists(atPath: destination.path), "First install is copied to Applications")
        check(manager.fileExists(atPath: source.path), "Source download remains intact")
        check(try Data(contentsOf: destination.appendingPathComponent("Contents/MacOS/VoiceSeed")) == Data("synthetic binary".utf8), "Installed bytes are identical")
        check(verified.count == 2 && verified.first == source && verified.last?.lastPathComponent.hasPrefix(".voice-seed-install-") == true, "Source and staged bundle are verified before installation")
        check(try service.verifiedExistingApplication() == destination, "The installed app is verified before opening")
        do { _ = try service.install(from: source); preconditionFailure("Existing app must not be overwritten") }
        catch ApplicationInstallService.InstallError.alreadyInstalled { checks += 1 }
        check(try Data(contentsOf: sentinel) == Data("synthetic dictionary/history/settings".utf8), "Installer never accesses preferences, dictionary or history")
        check(try service.install(from: destination) == destination, "Installed startup does not copy itself again")
        let alias = root.appendingPathComponent("application-alias.app")
        try manager.createSymbolicLink(at: alias, withDestinationURL: destination)
        check(service.isInstalled(alias), "Canonical path comparison handles filesystem aliases")
        let linkedDestination = ApplicationInstallService(destination: alias, bundleIdentifier: "test.voice-seed", verify: { _ in })
        check(!linkedDestination.isInstalled(destination), "An Applications entry that only links elsewhere is not an installation")
        do { _ = try linkedDestination.verifiedExistingApplication(); preconditionFailure("A linked installation must not be accepted") }
        catch ApplicationInstallService.InstallError.differentApplication { checks += 1 }
        let invalid = root.appendingPathComponent("Other.app")
        try fixture(invalid, identifier: "other.app")
        check(!service.isMatchingApplication(invalid), "Wrong bundle ID is rejected")
        do { _ = try service.install(from: invalid); preconditionFailure("Wrong source must not install") }
        catch ApplicationInstallService.InstallError.invalidApplication { checks += 1 }
        let wrongDestination = applications.appendingPathComponent("Different.app")
        try fixture(wrongDestination, identifier: "other.app", payload: "must be preserved")
        let wrong = ApplicationInstallService(destination: wrongDestination, bundleIdentifier: "test.voice-seed", verify: { _ in })
        do { _ = try wrong.verifiedExistingApplication(); preconditionFailure("Wrong destination must not open") }
        catch ApplicationInstallService.InstallError.differentApplication { checks += 1 }
        check(try Data(contentsOf: wrongDestination.appendingPathComponent("Contents/MacOS/VoiceSeed")) == Data("must be preserved".utf8), "An unrelated destination is preserved")
        let failedTarget = applications.appendingPathComponent("Failed.app")
        let failing = ApplicationInstallService(destination: failedTarget, bundleIdentifier: "test.voice-seed") { url in
            if url != source { throw ApplicationInstallService.InstallError.invalidSignature }
        }
        do { _ = try failing.install(from: source); preconditionFailure("Invalid staged signature must not install") }
        catch ApplicationInstallService.InstallError.invalidSignature { checks += 1 }
        check(!manager.fileExists(atPath: failedTarget.path), "Failed validation never publishes the app")
        check(try manager.contentsOfDirectory(atPath: applications.path).allSatisfy { !$0.hasPrefix(".voice-seed-install-") }, "Only the installer-owned temporary stage is cleaned up")
        print("PASS: \(checks) application placement checks (temporary synthetic bundles only)")
    }
}
