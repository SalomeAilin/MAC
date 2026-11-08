import Foundation

/// 光标离开选区后重新计时。
struct SelectionHover {
    let delay: Duration
    let bounds: [CGRect]
    private var enteredAt: ContinuousClock.Instant?
    var isInside: Bool { enteredAt != nil }

    init(bounds: [CGRect], delay: Duration = .milliseconds(AdaptiveHoverTiming.initialMilliseconds)) {
        self.bounds = bounds
        self.delay = delay
    }

    func isWaiting(at point: CGPoint, now: ContinuousClock.Instant = .now) -> Bool {
        guard let enteredAt, bounds.contains(where: { $0.contains(point) }) else { return false }
        return now >= enteredAt && now - enteredAt < delay
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
        return now - enteredAt >= delay
    }
}
