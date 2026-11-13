import Foundation

@main struct FnKeyStateTests {
    static func main() {
        var key = FnKeyState()
        precondition(key.update(keyCode: 56, fnDown: false, otherModifiers: true) == nil)
        precondition(key.update(keyCode: 63, fnDown: true, otherModifiers: false) == .pressed)
        precondition(key.update(keyCode: 63, fnDown: true, otherModifiers: false) == nil, "No repeat starts")
        precondition(key.update(keyCode: 56, fnDown: true, otherModifiers: true) == nil, "Other modifier changes must not end a hold")
        precondition(key.update(keyCode: 63, fnDown: false, otherModifiers: false) == .released)
        precondition(key.update(keyCode: 63, fnDown: false, otherModifiers: false) == nil, "No repeat stops")
        precondition(key.update(keyCode: 63, fnDown: true, otherModifiers: true) == nil, "Fn plus another modifier does not start dictation")
        precondition(key.update(keyCode: 123, fnDown: true, otherModifiers: false) == nil, "An arrow with synthesized Fn flags is not a physical Fn press")
        precondition(key.update(keyCode: 63, fnDown: true, otherModifiers: false) == .pressed)
        precondition(key.reset() && !key.held, "Lost event tap releases state")
        var recording = HoldRecordingState()
        precondition(recording.release(recordingStarted: true) == nil, "An unrelated Fn release cannot stop button recording")
        precondition(!recording.begin(canStart: false))
        precondition(recording.begin(canStart: true))
        precondition(!recording.begin(canStart: true))
        precondition(recording.release(recordingStarted: false) == .cancelPreparation, "Release before permission resolves cancels startup")
        precondition(recording.begin(canStart: true))
        precondition(recording.release(recordingStarted: true) == .stop)
        precondition(recording.release(recordingStarted: true) == nil, "Only one stop per hold")
        print("PASS: 18 Fn hold and recording lifecycle checks")
    }
}
