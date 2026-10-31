import Foundation

/// 光标离开选区后重新计时。
struct SelectionHover {
    static let delay: Duration = .milliseconds(300)
    let bounds: [CGRect]
    private var enteredAt: ContinuousClock.Instant?
    var isInside: Bool { enteredAt != nil }

    init(bounds: [CGRect]) {
        self.bounds = bounds
    }

    mutating func update(at point: CGPoint, now: ContinuousClock.Instant = .now) -> Bool {
        guard bounds.contains(where: { $0.contains(point) }) else {
            enteredAt = nil
            return false
        }
        guard let enteredAt else {
            self.enteredAt = now
            return false
        }
        return now - enteredAt >= Self.delay
    }
}
