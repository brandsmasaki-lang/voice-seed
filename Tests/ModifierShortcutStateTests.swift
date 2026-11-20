import Foundation

@main struct ModifierShortcutStateTests {
    static func main() {
        for controlFirst in [true, false] {
            for releaseControlFirst in [true, false] {
                var state = ModifierShortcutState()
                precondition(!state.update(control: controlFirst, command: !controlFirst, otherModifiers: false))
                precondition(!state.update(control: true, command: true, otherModifiers: false))
                precondition(!state.update(control: !releaseControlFirst, command: releaseControlFirst, otherModifiers: false))
                precondition(state.update(control: false, command: false, otherModifiers: false))
                precondition(!state.update(control: false, command: false, otherModifiers: false))
            }
        }
        var state = ModifierShortcutState()
        precondition(!state.update(control: true, command: true, otherModifiers: false))
        precondition(!state.update(control: true, command: true, otherModifiers: false, keyDown: true))
        precondition(!state.update(control: false, command: false, otherModifiers: false))
        precondition(!state.update(control: true, command: true, otherModifiers: true))
        precondition(!state.update(control: true, command: true, otherModifiers: false))
        precondition(!state.update(control: false, command: false, otherModifiers: false))
        precondition(!state.update(control: true, command: true, otherModifiers: false))
        state.reset()
        precondition(!state.update(control: false, command: false, otherModifiers: false))
        precondition(!state.update(control: true, command: false, otherModifiers: false))
        precondition(!state.update(control: false, command: false, otherModifiers: false))
        print("PASS: modifier shortcut orders, single trigger, chords, interruption and single modifier")
    }
}
