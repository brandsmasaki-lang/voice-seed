import Foundation

struct DeleteKeyGesture {
    enum Action: Equatable { case none, character, bunsetsu }
    private(set) var isLeftFlick = false
    private(set) var didRepeat = false
    mutating func move(dx: Double, dy: Double) {
        isLeftFlick = dx <= -28 && abs(dx) > abs(dy)
    }
    mutating func repeatTick() -> Action {
        guard !isLeftFlick else { return .none }
        didRepeat = true; return .character
    }
    func end() -> Action {
        if didRepeat { return .none }
        return isLeftFlick ? .bunsetsu : .character
    }
}
