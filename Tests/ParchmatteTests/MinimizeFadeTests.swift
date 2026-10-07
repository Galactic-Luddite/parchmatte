import CoreGraphics
import XCTest
@testable import Parchmatte

final class MinimizeFadeTests: XCTestCase {
    let resting = CGRect(x: 200, y: 150, width: 800, height: 600)
    let collapsing = CGRect(x: 350, y: 300, width: 680, height: 500)

    func testOppositeSidesOfRestoreToleranceCannotPoisonNextMinimize() {
        var fade = MinimizeFade(detectShallowStretch: true)
        let source = CGRect(x: 900, y: 150, width: 600, height: 500)
        _ = fade.observe(source, at: 0, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 1100, y: 900, width: 300, height: 225), at: 0.1, nearDisplayEdge: true)
        _ = fade.observe(nil, at: 1, nearDisplayEdge: false)
        // Recorded first restore: 602 -> 600. Its stationary reference used
        // to remain 602, allowing the next 601 -> 604 opening to adopt 604.
        _ = fade.observe(CGRect(x: 900, y: 150, width: 602, height: 500), at: 2, nearDisplayEdge: false)
        _ = fade.observe(source, at: 2.02, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(source, at: 2.14, nearDisplayEdge: false), .fadeIn)
        _ = fade.observe(CGRect(x: 900, y: 150, width: 601, height: 500), at: 3, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 900, y: 150, width: 604, height: 500), at: 3.016, nearDisplayEdge: false)
        XCTAssertLessThanOrEqual(fade.restingRect!.width, 602)
        _ = fade.observe(CGRect(x: 900, y: 166, width: 650, height: 501), at: 3.04, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 900, y: 200, width: 675, height: 501), at: 3.06, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(CGRect(x: 900, y: 250, width: 690, height: 501),
            at: 3.08, nearDisplayEdge: false), .fadeOut)
        _ = fade.observe(nil, at: 4, nearDisplayEdge: false)
        _ = fade.observe(source, at: 8, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(source, at: 8.2, nearDisplayEdge: false), .fadeIn)
    }

    func testSmallOpeningStepsDoNotPreventOriginalWindowRestore() {
        var fade = MinimizeFade(detectShallowStretch: true)
        let source = CGRect(x: 900, y: 150, width: 600, height: 500)
        _ = fade.observe(source, at: 0, nearDisplayEdge: false)
        _ = fade.observe(source, at: 1, nearDisplayEdge: false)
        // The failed native cycle retained a 603pt cover for a 600pt target.
        // Small consecutive steps must not count as a long stationary period.
        for (time, width) in [(1.01, 601.0), (1.025, 603.0)] {
            _ = fade.observe(CGRect(x: 900, y: 150, width: width, height: 500),
                at: time, nearDisplayEdge: false)
        }
        _ = fade.observe(CGRect(x: 900, y: 166, width: 650, height: 501), at: 1.04, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 900, y: 200, width: 675, height: 501), at: 1.06, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(CGRect(x: 900, y: 250, width: 690, height: 501),
            at: 1.08, nearDisplayEdge: false), .fadeOut)
        _ = fade.observe(nil, at: 2, nearDisplayEdge: false)
        _ = fade.observe(source, at: 6, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(source, at: 6.2, nearDisplayEdge: false), .fadeIn)
        XCTAssertFalse(fade.isHidden)
    }

    func testShallowCrossDisplayGenieStartsRibbonBeforeCollapse() throws {
        var fade = MinimizeFade(detectShallowStretch: true)
        let source = CGRect(x: 242, y: -1007, width: 800, height: 600)
        _ = fade.observe(source, at: 0, nearDisplayEdge: false)
        // Public bounds recorded during a real cross-display Genie. Its
        // maximum width is only 6.125% above rest; the old 12% hint misses it.
        let samples: [(Double, CGFloat, CGFloat, CGFloat)] = [
            (0.090, 243, -893, 818), (0.110, 246, -828, 828),
            (0.130, 255, -753, 837), (0.150, 271, -667, 846),
            (0.170, 301, -570, 849),
        ]
        var fadedAt: Double?
        for (time, x, y, width) in samples {
            let action = fade.observe(CGRect(x: x, y: y, width: width, height: 601),
                at: time, nearDisplayEdge: y + 601 >= -24)
            if action == .fadeOut { fadedAt = time }
        }
        let began = try XCTUnwrap(fadedAt, "Ribbon must start while the Genie is still stretching")
        XCTAssertLessThanOrEqual(began, 0.17)
        XCTAssertEqual(fade.restingRect, source)
    }

    func testSmallRestoreStepsMustStopBeforePaperReturns() {
        var fade = MinimizeFade(detectShallowStretch: true)
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        _ = fade.observe(collapsing, at: 0.1, nearDisplayEdge: true)
        _ = fade.observe(nil, at: 1, nearDisplayEdge: false)
        for step in 0...20 {
            let moving = resting.offsetBy(dx: CGFloat(step), dy: 0)
            XCTAssertEqual(fade.observe(moving, at: 2 + Double(step) * 0.02,
                nearDisplayEdge: false), .none, "One-point steps still add up to motion")
        }
        XCTAssertEqual(fade.observe(resting.offsetBy(dx: 20, dy: 0), at: 2.6,
            nearDisplayEdge: false), .fadeIn)
    }

    func testShallowLinearResizeStillDoesNotTriggerRibbon() {
        var fade = MinimizeFade(detectShallowStretch: true)
        let source = CGRect(x: 200, y: 150, width: 800, height: 600)
        _ = fade.observe(source, at: 0, nearDisplayEdge: true)
        for step in 1...8 {
            let delta = CGFloat(step * 8)
            let rect = CGRect(x: 200, y: 150 + delta * 2, width: 800 + delta, height: 600)
            XCTAssertEqual(fade.observe(rect, at: Double(step) * 0.02, nearDisplayEdge: true), .none)
        }
        XCTAssertFalse(fade.isHidden)
    }

    func testDragNearEdgeShowingKeepsPaperVisible() {
        for mode in [false, true] {
            var fade = MinimizeFade(detectShallowStretch: mode)
            _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
            XCTAssertEqual(fade.observe(resting.offsetBy(dx: 180, dy: 120), at: 0.1, nearDisplayEdge: true), .none)
            XCTAssertFalse(fade.isHidden)
        }
    }

    func testResizeAwayFromEdgeKeepsPaperVisible() {
        for mode in [false, true] {
            var fade = MinimizeFade(detectShallowStretch: mode)
            _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
            XCTAssertEqual(fade.observe(collapsing, at: 0.1, nearDisplayEdge: false), .none)
            XCTAssertFalse(fade.isHidden)
        }
    }

    func testRapidTwoAxisCollapseNearEdgeFadesOutOnce() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(collapsing, at: 0.1, nearDisplayEdge: true), .fadeOut)
        XCTAssertTrue(fade.isHidden)
        XCTAssertEqual(fade.observe(CGRect(x: 1200, y: 950, width: 60, height: 45), at: 0.12, nearDisplayEdge: true), .none)
    }

    func testRibbonSourceRetainsUndistortedWindowSize() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        _ = fade.observe(collapsing, at: 0.1, nearDisplayEdge: true)
        XCTAssertEqual(fade.restingRect, resting)
        _ = fade.observe(nil, at: 0.2, nearDisplayEdge: false)
        XCTAssertEqual(fade.restingRect, resting)
    }

    func testTinyWindowAndAbsenceDoNotRevealPaper() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        _ = fade.observe(collapsing, at: 0.1, nearDisplayEdge: true)
        _ = fade.observe(nil, at: 1, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 1200, y: 950, width: 60, height: 45), at: 2, nearDisplayEdge: true)
        XCTAssertEqual(fade.observe(CGRect(x: 1200, y: 950, width: 60, height: 45), at: 3, nearDisplayEdge: false), .none)
        XCTAssertTrue(fade.isHidden)
    }

    func testRestoreWaitsUntilFullSizeHasSettled() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        _ = fade.observe(collapsing, at: 0.1, nearDisplayEdge: true)
        XCTAssertEqual(fade.observe(resting, at: 1, nearDisplayEdge: true), .none)
        XCTAssertEqual(fade.observe(resting, at: 1.05, nearDisplayEdge: false), .none)
        XCTAssertEqual(fade.observe(resting, at: 1.18, nearDisplayEdge: false), .fadeIn)
        XCTAssertFalse(fade.isHidden)
        XCTAssertEqual(fade.observe(resting, at: 1.2, nearDisplayEdge: false), .none)
    }

    func testSlowResizeNearEdgeDoesNotFade() {
        for mode in [false, true] {
            var fade = MinimizeFade(detectShallowStretch: mode)
            _ = fade.observe(resting, at: 0, nearDisplayEdge: true)
            XCTAssertEqual(fade.observe(collapsing, at: 0.5, nearDisplayEdge: true), .none)
            XCTAssertFalse(fade.isHidden)
        }
    }

    func testOneAxisResizeNearEdgeDoesNotFade() {
        for mode in [false, true] {
            var fade = MinimizeFade(detectShallowStretch: mode)
            _ = fade.observe(resting, at: 0, nearDisplayEdge: true)
            XCTAssertEqual(fade.observe(CGRect(x: 300, y: 150, width: 680, height: 600), at: 0.1, nearDisplayEdge: true), .none)
            XCTAssertFalse(fade.isHidden)
        }
    }

    func testCornerResizeNearEdgeDoesNotFade() {
        for mode in [false, true] {
            for rect in [CGRect(x: 200, y: 150, width: 680, height: 500),
                         CGRect(x: 320, y: 250, width: 680, height: 500)] {
                var fade = MinimizeFade(detectShallowStretch: mode)
                _ = fade.observe(resting, at: 0, nearDisplayEdge: true)
                XCTAssertEqual(fade.observe(rect, at: 0.1, nearDisplayEdge: true), .none)
                XCTAssertFalse(fade.isHidden)
            }
        }
    }

    func testSymmetricResizeDoesNotFade() {
        for mode in [false, true] {
            var fade = MinimizeFade(detectShallowStretch: mode)
            _ = fade.observe(resting, at: 0, nearDisplayEdge: true)
            XCTAssertEqual(fade.observe(CGRect(x: 250, y: 200, width: 700, height: 500), at: 0.1, nearDisplayEdge: true), .none)
            XCTAssertFalse(fade.isHidden)
        }
    }

    func testGenieStretchThenAnchoredContractionFades() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 200, y: 166, width: 950, height: 601), at: 0.1, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 714, y: 587, width: 763, height: 595), at: 0.2, nearDisplayEdge: true)
        XCTAssertEqual(fade.observe(CGRect(x: 916, y: 690, width: 563, height: 492), at: 0.23, nearDisplayEdge: true), .fadeOut)
    }

    func testIntermediateRestoreSizeStaysHidden() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        _ = fade.observe(collapsing, at: 0.1, nearDisplayEdge: true)
        let intermediate = CGRect(x: 200, y: 150, width: 720, height: 540)
        _ = fade.observe(intermediate, at: 1, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(intermediate, at: 1.2, nearDisplayEdge: false), .none)
        XCTAssertTrue(fade.isHidden)
    }

    func testResizeSmallerThenImmediatelyMinimizeRestoresPaper() {
        for resized in [CGRect(x: 200, y: 150, width: 600, height: 450),
                        CGRect(x: 200, y: 150, width: 600, height: 600)] {
            var fade = MinimizeFade()
            _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
            _ = fade.observe(resized, at: 0.05, nearDisplayEdge: false)
            let collapse = CGRect(x: 1000, y: 900, width: 300, height: 225)
            XCTAssertEqual(fade.observe(collapse, at: 0.10, nearDisplayEdge: true), .fadeOut)
            _ = fade.observe(resized, at: 1, nearDisplayEdge: false)
            XCTAssertEqual(fade.observe(resized, at: 1.2, nearDisplayEdge: false), .fadeIn)
        }
    }

    func testEnlargeThenMinimizeWaitsForNewFullSize() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        let enlarged = CGRect(x: 200, y: 150, width: 1000, height: 750)
        _ = fade.observe(enlarged, at: 0.05, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 1000, y: 900, width: 300, height: 225), at: 0.10, nearDisplayEdge: true)
        _ = fade.observe(resting, at: 1, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(resting, at: 1.2, nearDisplayEdge: false), .none)
        XCTAssertTrue(fade.isHidden)
        _ = fade.observe(enlarged, at: 1.3, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(enlarged, at: 1.5, nearDisplayEdge: false), .fadeIn)
    }

    func testRestoreFadeRemainsActiveAcrossSubsequentScans() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        _ = fade.observe(collapsing, at: 0.1, nearDisplayEdge: true)
        _ = fade.observe(resting, at: 1, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(resting, at: 1.2, nearDisplayEdge: false), .fadeIn)
        _ = fade.observe(resting, at: 1.22, nearDisplayEdge: false)
        XCTAssertTrue(fade.isFadingIn(at: 1.22))
        XCTAssertFalse(fade.isFadingIn(at: 1.36))
    }

    func testContinuingGenieStretchFadesBeforeNearEdgeCollapse() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 200, y: 150, width: 897, height: 601), at: 0.05, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(CGRect(x: 200, y: 158, width: 931, height: 601), at: 0.075, nearDisplayEdge: false), .none)
        XCTAssertEqual(fade.observe(CGRect(x: 200, y: 166, width: 950, height: 601), at: 0.10, nearDisplayEdge: false), .fadeOut)
        XCTAssertTrue(fade.isHidden)
        // Ongoing motion, even while full-sized, must not restore the paper.
        XCTAssertEqual(fade.observe(CGRect(x: 218, y: 239, width: 1050, height: 601), at: 0.15, nearDisplayEdge: false), .none)
        XCTAssertTrue(fade.isHidden)
        XCTAssertEqual(fade.observe(collapsing, at: 0.20, nearDisplayEdge: true), .none)
    }

    func testContinuingVerticalStretchFadesBeforeNearEdgeCollapse() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 200, y: 150, width: 800, height: 660), at: 0.05, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(CGRect(x: 208, y: 150, width: 800, height: 700), at: 0.075, nearDisplayEdge: false), .none)
        XCTAssertEqual(fade.observe(CGRect(x: 222, y: 150, width: 800, height: 730), at: 0.10, nearDisplayEdge: false), .fadeOut)
    }

    func testSingleStretchShapedMoveAndResizeJumpDoesNotFade() {
        for mode in [false, true] {
            var fade = MinimizeFade(detectShallowStretch: mode)
            _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
            let moved = CGRect(x: 220, y: 166, width: 950, height: 600)
            XCTAssertEqual(fade.observe(moved, at: 0.05, nearDisplayEdge: false), .none)
            XCTAssertEqual(fade.observe(moved, at: 0.10, nearDisplayEdge: false), .none)
            XCTAssertFalse(fade.isHidden)
        }
    }

    func testDraggingAnAlreadyWideWindowDoesNotFade() {
        for mode in [false, true] {
            var fade = MinimizeFade(detectShallowStretch: mode)
            _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
            let wide = CGRect(x: 200, y: 150, width: 950, height: 600)
            _ = fade.observe(wide, at: 0.05, nearDisplayEdge: false)
            XCTAssertEqual(fade.observe(wide.offsetBy(dx: 30, dy: 20), at: 0.075, nearDisplayEdge: false), .none)
            XCTAssertFalse(fade.isHidden)
        }
    }

    func testAnchoredAndCenteredWidthEnlargementDoesNotFade() {
        for mode in [false, true] {
            for centered in [false, true] {
                var fade = MinimizeFade(detectShallowStretch: mode)
                _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
                for step in 1...8 {
                    let width = 800.0 + Double(step) * 30
                    let rect = CGRect(x: centered ? 600 - width / 2 : 200, y: 150, width: width, height: 600)
                    XCTAssertEqual(fade.observe(rect, at: Double(step) * 0.025, nearDisplayEdge: false), .none)
                }
                XCTAssertFalse(fade.isHidden)
            }
        }
    }

    func testSlowStretchShapedResizeDoesNotFadeEarly() {
        for mode in [false, true] {
            var fade = MinimizeFade(detectShallowStretch: mode)
            _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
            _ = fade.observe(CGRect(x: 200, y: 150, width: 897, height: 601), at: 0.1, nearDisplayEdge: false)
            XCTAssertEqual(fade.observe(CGRect(x: 200, y: 158, width: 931, height: 601), at: 0.4, nearDisplayEdge: false), .none)
            XCTAssertFalse(fade.isHidden)
        }
    }

    func testLinearAnimatedWidthResizeAndTranslationDoesNotFadeEarly() {
        for mode in [false, true] {
            var fade = MinimizeFade(detectShallowStretch: mode)
            _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
            _ = fade.observe(CGRect(x: 200, y: 150, width: 870, height: 600), at: 0.05, nearDisplayEdge: false)
            for step in 1...8 {
                let rect = CGRect(x: 200, y: 150 + Double(step) * 8, width: 870 + Double(step) * 30, height: 600)
                XCTAssertEqual(fade.observe(rect, at: 0.05 + Double(step) * 0.025, nearDisplayEdge: false), .none)
            }
            XCTAssertFalse(fade.isHidden)
        }
    }

    func testPauseInLargeForwardGeniePhaseDoesNotRestorePaper() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 200, y: 150, width: 897, height: 601), at: 0.05, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 200, y: 158, width: 931, height: 601), at: 0.075, nearDisplayEdge: false)
        let stretched = CGRect(x: 200, y: 166, width: 950, height: 601)
        _ = fade.observe(stretched, at: 0.10, nearDisplayEdge: false)
        _ = fade.observe(stretched, at: 0.15, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(stretched, at: 0.30, nearDisplayEdge: false), .none)
        XCTAssertTrue(fade.isHidden)
        _ = fade.observe(CGRect(x: 1200, y: 900, width: 60, height: 45), at: 0.35, nearDisplayEdge: true)
        _ = fade.observe(resting, at: 1, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(resting, at: 1.2, nearDisplayEdge: false), .fadeIn)
    }

    func testFalseEarlyInferenceRecoversAfterLongStationaryFrame() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 200, y: 150, width: 897, height: 601), at: 0.05, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 200, y: 158, width: 931, height: 601), at: 0.075, nearDisplayEdge: false)
        let stretched = CGRect(x: 200, y: 166, width: 950, height: 601)
        _ = fade.observe(stretched, at: 0.10, nearDisplayEdge: false)
        _ = fade.observe(stretched, at: 0.15, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(stretched, at: 0.30, nearDisplayEdge: false), .none)
        XCTAssertEqual(fade.observe(stretched, at: 1.16, nearDisplayEdge: false), .fadeIn)
        XCTAssertFalse(fade.isHidden)
    }

    func testShortGenieStretchPausePreservesRestoreSizeThroughAnchoredCollapse() {
        var fade = MinimizeFade()
        let original = CGRect(x: 300, y: 200, width: 1000, height: 700)
        let shortStretch = CGRect(x: 370, y: 480, width: 1104, height: 701)
        _ = fade.observe(original, at: 0, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(shortStretch, at: 0.05, nearDisplayEdge: true), .none)
        // A metadata pause at a stretch below 12% must not replace the
        // original reference; the fixed far corner can look like resizing.
        XCTAssertEqual(fade.observe(shortStretch, at: 0.25, nearDisplayEdge: true), .none)
        let fixedCornerCollapse = CGRect(x: 600, y: 580, width: 874, height: 601)
        XCTAssertEqual(fade.observe(fixedCornerCollapse, at: 0.28, nearDisplayEdge: true), .fadeOut)
        XCTAssertTrue(fade.isHidden)
        _ = fade.observe(original, at: 1, nearDisplayEdge: false)
        XCTAssertTrue(fade.isRestoring)
        XCTAssertEqual(fade.observe(original, at: 1.14, nearDisplayEdge: false), .fadeIn)
        XCTAssertFalse(fade.isHidden)
    }

    func testShortCurvingStretchPrimesCollapseWithoutLoweringEarlyFadeThreshold() {
        var fade = MinimizeFade()
        let original = CGRect(x: 300, y: 200, width: 1000, height: 700)
        _ = fade.observe(original, at: 0, nearDisplayEdge: false)
        _ = fade.observe(CGRect(x: 300, y: 250, width: 1085, height: 701), at: 0.05, nearDisplayEdge: false)
        XCTAssertEqual(fade.observe(CGRect(x: 300, y: 258, width: 1100, height: 701), at: 0.075, nearDisplayEdge: false), .none)
        XCTAssertEqual(fade.observe(CGRect(x: 300, y: 274, width: 1118, height: 701), at: 0.10, nearDisplayEdge: false), .none)
        XCTAssertFalse(fade.isHidden)
    }

    func testStationaryStretchHintExpiresBeforeLaterResizeAndRestore() {
        var fade = MinimizeFade()
        _ = fade.observe(resting, at: 0, nearDisplayEdge: false)
        let wider = CGRect(x: 200, y: 160, width: 900, height: 600)
        for time in [0.05, 0.25, 0.75] {
            XCTAssertEqual(fade.observe(wider, at: time, nearDisplayEdge: false), .none)
        }
        let resized = CGRect(x: 200, y: 160, width: 750, height: 600)
        _ = fade.observe(resized, at: 0.8, nearDisplayEdge: false)
        // Unambiguous two-axis motion hides paper at minimize as usual.
        let collapse = CGRect(x: 400, y: 400, width: 500, height: 350)
        XCTAssertEqual(fade.observe(collapse, at: 0.85, nearDisplayEdge: true), .fadeOut)
        _ = fade.observe(resized, at: 2, nearDisplayEdge: false)
        XCTAssertTrue(fade.isRestoring)
        XCTAssertEqual(fade.observe(resized, at: 2.14, nearDisplayEdge: false), .fadeIn)
    }
}
