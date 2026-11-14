import Foundation

/// Multi-tap edits only the last uncommitted character. Flicks always append.
struct KanaTapCycle {
    struct Edit: Equatable {
        var text: String
        var replacesLast: Bool
    }
    private var previousValues: [String] = []
    private var previousIndex = 0
    private var previousTime = -Double.infinity
    static let interval: Double = 0.8

    mutating func reset() {
        previousValues = []; previousIndex = 0; previousTime = -Double.infinity
    }

    mutating func resolve(values: [String], selectedIndex: Int, at time: Double,
                          currentLast: String?) -> Edit {
        precondition(!values.isEmpty && values.indices.contains(selectedIndex))
        if selectedIndex != 0 || values.count == 1 {
            reset()
            return Edit(text: values[selectedIndex], replacesLast: false)
        }
        let age = time - previousTime
        let replace = previousValues == values && age >= 0 && age < Self.interval
            && currentLast == values[previousIndex]
        let index = replace ? (previousIndex + 1) % values.count : 0
        previousValues = values; previousIndex = index; previousTime = time
        return Edit(text: values[index], replacesLast: replace)
    }
}
