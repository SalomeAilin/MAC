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
}
