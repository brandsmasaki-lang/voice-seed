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
}
