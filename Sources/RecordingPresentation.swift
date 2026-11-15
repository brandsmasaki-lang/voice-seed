import Foundation

enum RecordingPresentation: Equatable {
    case mainWindow
    case nonactivatingNotice

    static func forRecording(startedFromGlobalKey: Bool) -> Self {
        startedFromGlobalKey ? .nonactivatingNotice : .mainWindow
    }

    static func canPaste(startingApplication: Int32?, currentApplication: Int32?) -> Bool {
        guard let startingApplication, let currentApplication else { return false }
        return startingApplication == currentApplication
    }

    /// A grant recorded for a different build that is no longer in effect means macOS is holding
    /// a stale record: the switch looks on in System Settings but does not apply to this build.
    static func permissionNeedsRedo(granted: Bool, grantedBuild: String?, currentBuild: String) -> Bool {
        guard !granted, let grantedBuild else { return false }
        return grantedBuild != currentBuild
    }

    /// The focused element is often unavailable (Electron, browsers), so an unknown subrole
    /// must not block pasting. Only a known password field does.
    static func canPaste(focusedSubrole: String?) -> Bool {
        focusedSubrole != "AXSecureTextField"
    }
}
