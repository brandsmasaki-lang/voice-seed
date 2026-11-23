import Foundation

/// A key-down while Fn is held cancels dictation. Key characters and key codes are not needed for that check.
struct FnKeyState {
    enum Action: Equatable { case pressed, released, keyboardChord }
    private(set) var held = false
    private(set) var chordUntilRelease = false

    mutating func update(keyCode: Int64, fnDown: Bool, otherModifiers: Bool) -> Action? {
        if !fnDown {
            let wasHeld = held
            held = false; chordUntilRelease = false
            return wasHeld ? .released : nil
        }
        if held && otherModifiers { return usedWithKey() }
        guard keyCode == 63, !otherModifiers, !held, !chordUntilRelease else { return nil }
        held = true
        return .pressed
    }

    mutating func usedWithKey() -> Action? {
        guard held else { return nil }
        held = false; chordUntilRelease = true
        return .keyboardChord
    }

    @discardableResult mutating func reset() -> Bool {
        let wasHeld = held
        held = false
        chordUntilRelease = false
        return wasHeld
    }
}

/// Tracks transitions between modifier snapshots. A key pressed between two
/// snapshots cancels the hold even when Fn was released in the same interval.
struct SampledFnHold {
    private var previousFn: Bool?
    private var previousKeyDownCount: UInt32?
    private(set) var recording = false

    mutating func sample(fn: Bool, otherModifier: Bool, keyDownCount: UInt32,
                         secureInput: Bool, typingEndedBeforeFn: @autoclosure () -> Bool = false) -> FnKeyState.Action? {
        defer { previousFn = fn; previousKeyDownCount = keyDownCount }
        guard let previousFn else { return nil }
        let chord = otherModifier || previousKeyDownCount != keyDownCount
        if recording && (chord || secureInput) {
            recording = false
            return .keyboardChord
        }
        if recording && !fn {
            recording = false
            return .released
        }
        if fn && !previousFn && !otherModifier && !secureInput,
           previousKeyDownCount == keyDownCount || typingEndedBeforeFn() {
            recording = true
            return .pressed
        }
        return nil
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
