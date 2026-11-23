import Foundation

/// Multi-tap edits only the last uncommitted character. Flicks always append.
struct KanaTapCycle {
    struct Edit: Equatable {
        var text: String
        var replacesLast: Bool
    }
    private var previousValues: [String] = []
    private var reverseValues: [String] = []
    private var previousIndex = 0
    private var previousTime = -Double.infinity
    static let interval: Double = 0.8

    mutating func reset() {
        reverseValues = []; previousValues = []; previousIndex = 0; previousTime = -Double.infinity
    }

    func canReverse(_ last: String?) -> Bool {
        guard let last else { return false }
        return reverseValues.count > 1 && reverseValues.contains(last)
    }

    mutating func reverse(currentLast: String?, at time: Double) -> Edit? {
        guard let currentLast, reverseValues.count > 1,
              let index = reverseValues.firstIndex(of: currentLast) else { return nil }
        previousIndex = (index + reverseValues.count - 1) % reverseValues.count
        previousValues = reverseValues
        previousTime = time
        return Edit(text: reverseValues[previousIndex], replacesLast: true)
    }

    mutating func resolve(values: [String], selectedIndex: Int, at time: Double,
                          currentLast: String?) -> Edit {
        precondition(!values.isEmpty && values.indices.contains(selectedIndex))
        defer { reverseValues = values }
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
