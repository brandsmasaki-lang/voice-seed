import Foundation

/// Fires once after both modifiers are released, only if no other key was used.
struct ModifierShortcutState {
    private var armed = false
    private var blocked = false

    mutating func update(control: Bool, command: Bool, otherModifiers: Bool, keyDown: Bool = false) -> Bool {
        if keyDown || otherModifiers { blocked = true; armed = false }
        if !control && !command {
            let fire = armed && !blocked
            reset()
            return fire
        }
        if control && command && !blocked { armed = true }
        return false
    }
    mutating func reset() { armed = false; blocked = false }
}
