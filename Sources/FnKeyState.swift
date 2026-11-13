import Foundation

/// Only modifier transitions are observed. Ordinary keystrokes are never read.
struct FnKeyState {
    enum Action: Equatable { case pressed, released }
    private(set) var held = false

    mutating func update(keyCode: Int64, fnDown: Bool, otherModifiers: Bool) -> Action? {
        if held && !fnDown { held = false; return .released }
        guard keyCode == 63, fnDown, !otherModifiers, !held else { return nil }
        held = true
        return .pressed
    }

    @discardableResult mutating func reset() -> Bool {
        let wasHeld = held
        held = false
        return wasHeld
    }
}

/// A release during asynchronous microphone permission must cancel preparation,
/// rather than let recording start after the user has released Fn.
struct HoldRecordingState {
    enum ReleaseAction: Equatable { case stop, cancelPreparation }
    private(set) var active = false
    mutating func begin(canStart: Bool) -> Bool {
        guard canStart, !active else { return false }
        active = true
        return true
    }
    mutating func release(recordingStarted: Bool) -> ReleaseAction? {
        guard active else { return nil }
        active = false
        return recordingStarted ? .stop : .cancelPreparation
    }
    mutating func reset() { active = false }
}
