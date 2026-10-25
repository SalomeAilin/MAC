import Foundation

/// 只有光标连续停留在选区内一秒才放行；离开后重新计时。
struct SelectionHover {
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
        return now - enteredAt >= .seconds(1)
    }
}
