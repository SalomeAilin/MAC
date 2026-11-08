import CoreGraphics
import Foundation

struct AdaptiveHoverTiming: Equatable {
    enum Feedback {
        case earlyShortcut, extendedAfterEscape
    }

    static let initialMilliseconds = 300
    private static let limits = 150...750
    private(set) var milliseconds = initialMilliseconds
    private var evidence = 0.0
    var delay: Duration { .milliseconds(milliseconds) }

    init(saved: [String: Any]? = nil) {
        guard let milliseconds = saved?["milliseconds"] as? Int, Self.limits.contains(milliseconds),
              let evidence = saved?["evidence"] as? Double, evidence.isFinite, abs(evidence) < 2.25
        else { return }
        self.milliseconds = milliseconds
        self.evidence = evidence
    }

    var savedValues: [String: Any] { ["milliseconds": milliseconds, "evidence": evidence] }

    mutating func record(_ feedback: Feedback) {
        // 每次保留四分之三的旧反馈。从零开始，连续三次同向反馈才调整一次。
        evidence = evidence * 0.75 + (feedback == .earlyShortcut ? -1 : 1)
        guard abs(evidence) >= 2.25 else { return }
        let next = milliseconds + (evidence < 0 ? -30 : 30)
        milliseconds = min(Self.limits.upperBound, max(Self.limits.lowerBound, next))
        evidence = 0
    }
}

/// 只在内存中保留刚关闭的选区，用于识别同一窗口里紧接着发生的扩选。
struct DismissedHover {
    static let extensionWindow: Duration = .milliseconds(1500)
    let processID: pid_t
    let windowID: CGWindowID
    let bounds: [CGRect]
    let escapedAt: ContinuousClock.Instant

    init?(processID: pid_t, windowID: CGWindowID, bounds: [CGRect],
          shownAt: ContinuousClock.Instant, escapedAt: ContinuousClock.Instant) {
        guard !bounds.isEmpty, escapedAt >= shownAt, escapedAt - shownAt <= .milliseconds(800) else { return nil }
        self.processID = processID
        self.windowID = windowID
        self.bounds = bounds
        self.escapedAt = escapedAt
    }

    func wasExtended(to next: [CGRect], processID: pid_t, windowID: CGWindowID?, at now: ContinuousClock.Instant) -> Bool {
        guard self.processID == processID, self.windowID == windowID,
              now >= escapedAt, now - escapedAt <= Self.extensionWindow else { return false }
        // 逐行比对，允许一个屏幕点的取整误差。重新选中同一个词不算扩选。
        return bounds.allSatisfy { old in next.contains { $0.insetBy(dx: -1, dy: -1).contains(old) } }
            && next.contains { line in !bounds.contains { $0.insetBy(dx: -1, dy: -1).contains(line) } }
    }
}
