import Foundation
import Testing
@testable import SelectTranslate

@MainActor
struct SelectionHoverTests {
    private let rect = CGRect(x: 10, y: 20, width: 100, height: 20)

    private func check(_ hover: inout SelectionHover, at point: CGPoint, now: ContinuousClock.Instant, ready: Bool) {
        let result = hover.update(at: point, now: now)
        #expect(result == ready)
    }

    @Test func requires300MillisecondsOfContinuousHover() {
        var hover = SelectionHover(bounds: [rect])
        let start = ContinuousClock.now
        check(&hover, at: CGPoint(x: 30, y: 25), now: start, ready: false)
        check(&hover, at: CGPoint(x: 80, y: 25), now: start + .milliseconds(299), ready: false)
        check(&hover, at: CGPoint(x: 80, y: 25), now: start + .milliseconds(300), ready: true)
    }

    @Test func leavingAndReturningRestartsTheWait() {
        var hover = SelectionHover(bounds: [rect])
        let start = ContinuousClock.now
        check(&hover, at: CGPoint(x: 30, y: 25), now: start, ready: false)
        check(&hover, at: CGPoint(x: 130, y: 25), now: start + .milliseconds(200), ready: false)
        #expect(!hover.isInside)
        check(&hover, at: CGPoint(x: 30, y: 25), now: start + .seconds(1), ready: false)
        check(&hover, at: CGPoint(x: 30, y: 25), now: start + .milliseconds(1299), ready: false)
        check(&hover, at: CGPoint(x: 30, y: 25), now: start + .milliseconds(1300), ready: true)
    }

    @Test func whitespaceBetweenSelectedLinesResetsTheWait() {
        var hover = SelectionHover(bounds: [rect, CGRect(x: 10, y: 50, width: 30, height: 20)])
        let start = ContinuousClock.now
        check(&hover, at: CGPoint(x: 30, y: 25), now: start, ready: false)
        check(&hover, at: CGPoint(x: 80, y: 55), now: start + .seconds(1), ready: false)
        check(&hover, at: CGPoint(x: 20, y: 55), now: start + .seconds(2), ready: false)
        check(&hover, at: CGPoint(x: 20, y: 55), now: start + .seconds(3), ready: true)
    }

    @Test func supportsScreensWithNegativeCoordinates() {
        var hover = SelectionHover(bounds: [CGRect(x: -1400, y: -400, width: 100, height: 20)])
        let start = ContinuousClock.now
        check(&hover, at: CGPoint(x: -1380, y: -390), now: start, ready: false)
        check(&hover, at: CGPoint(x: -1380, y: -390), now: start + .seconds(1), ready: true)
    }

    @Test func missingBoundsNeverTrigger() {
        var hover = SelectionHover(bounds: [])
        let start = ContinuousClock.now
        check(&hover, at: .zero, now: start, ready: false)
        check(&hover, at: .zero, now: start + .seconds(10), ready: false)
    }

    @Test func learnedDelayAppliesToTheWholeHover() {
        let start = ContinuousClock.now
        let inside = CGPoint(x: 30, y: 25)
        for ms in [150, 270, 330, 750] {
            var hover = SelectionHover(bounds: [rect], delay: .milliseconds(ms))
            check(&hover, at: inside, now: start, ready: false)
            #expect(hover.isWaiting(at: inside, now: start + .milliseconds(ms - 1)))
            #expect(!hover.isWaiting(at: .zero, now: start))
            check(&hover, at: inside, now: start + .milliseconds(ms - 1), ready: false)
            check(&hover, at: inside, now: start + .milliseconds(ms), ready: true)
            #expect(!hover.isWaiting(at: inside, now: start + .milliseconds(ms)))
        }
    }

    @Test func recentRepeatedFeedbackChangesTheWaitInSmallSteps() {
        var timing = AdaptiveHoverTiming()
        timing.record(.earlyShortcut)
        timing.record(.earlyShortcut)
        #expect(timing.milliseconds == 300)
        timing = AdaptiveHoverTiming(saved: timing.savedValues)
        timing.record(.earlyShortcut)
        #expect(timing.milliseconds == 270)
        timing.record(.earlyShortcut)
        timing.record(.extendedAfterEscape)
        timing.record(.extendedAfterEscape)
        #expect(timing.milliseconds == 270)
        timing.record(.extendedAfterEscape)
        timing.record(.extendedAfterEscape)
        #expect(timing.milliseconds == 300)
    }

    @Test func learningHasLimitsAndInvalidPreferencesStartFresh() {
        var timing = AdaptiveHoverTiming()
        for _ in 0..<100 { timing.record(.earlyShortcut) }
        #expect(timing.milliseconds == 150)
        for _ in 0..<200 { timing.record(.extendedAfterEscape) }
        #expect(timing.milliseconds == 750)
        #expect(AdaptiveHoverTiming(saved: ["milliseconds": -1, "evidence": 0.0]) == AdaptiveHoverTiming())
        #expect(AdaptiveHoverTiming(saved: ["milliseconds": 330, "evidence": Double.nan]) == AdaptiveHoverTiming())
    }

    @Test func onlyAQuickEscapeFollowedByExtendingTheOriginalSelectionCounts() throws {
        let start = ContinuousClock.now
        let escaped = start + .milliseconds(800)
        let expanded = rect.union(CGRect(x: 110, y: 20, width: 20, height: 20))
        let dismissal = try #require(DismissedHover(processID: 1, windowID: 2, bounds: [rect], shownAt: start, escapedAt: escaped))
        #expect(dismissal.wasExtended(to: [expanded], processID: 1, windowID: 2, at: escaped + .milliseconds(1500)))
        #expect(!dismissal.wasExtended(to: [rect], processID: 1, windowID: 2, at: escaped))
        #expect(!dismissal.wasExtended(to: [rect.offsetBy(dx: 120, dy: 0)], processID: 1, windowID: 2, at: escaped))
        #expect(!dismissal.wasExtended(to: [expanded], processID: 2, windowID: 2, at: escaped))
        #expect(!dismissal.wasExtended(to: [expanded], processID: 1, windowID: 3, at: escaped))
        #expect(!dismissal.wasExtended(to: [expanded], processID: 1, windowID: 2, at: escaped + .milliseconds(1501)))
        #expect(DismissedHover(processID: 1, windowID: 2, bounds: [rect], shownAt: start, escapedAt: escaped + .milliseconds(1)) == nil)
    }
}
