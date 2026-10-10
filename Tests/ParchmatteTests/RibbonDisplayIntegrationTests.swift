import Cocoa
import Metal
import QuartzCore
import XCTest
@testable import Parchmatte

final class RibbonDisplayIntegrationTests: XCTestCase {
    func testAttachedMotionFollowsReturnAndOutlivesLegacyDeadline() throws {
        guard #available(macOS 14.0, *) else { throw XCTSkip("Metal display link") }
        _ = NSApplication.shared
        let source = NSRect(x: 200, y: 200, width: 800, height: 600)
        let target = NSRect(x: 1000, y: 100, width: 350, height: 250)
        let cover = CoverWindow(frame: source)
        defer { cover.close() }
        cover.apply(CoverStyle(texture: .parchmatte, softness: 0.4, opacity: 0.4, lamp: .off, lampStrength: 0.5), hideFromCapture: true)
        cover.orderFrontRegardless()
        XCTAssertTrue(cover.beginAttachedPaper(target: target, variant: .curve, restoring: true))
        for _ in 0..<7 {
            cover.observeAttachedPaper(target)
            RunLoop.main.run(until: Date().addingTimeInterval(0.045))
        }
        XCTAssertTrue(cover.isRibbonActive, "Fresh motion must not expire at the old 250ms deadline")
        XCTAssertNotEqual(cover.frame.origin, source.origin, "Returning paper must travel with its target")
        cover.observeAttachedPaper(source)
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        XCTAssertTrue(cover.isRibbonActive, "Flat bounds precede the native proxy handoff; retain material briefly")
        // Settlement completes on a queued display frame after its minimum hold.
        // Keep observations fresh while waiting, so a stale-observation abort
        // cannot satisfy the assertion when a display callback is delayed.
        let settlementDeadline = ProcessInfo.processInfo.systemUptime + 1
        while cover.isRibbonActive && ProcessInfo.processInfo.systemUptime < settlementDeadline {
            cover.observeAttachedPaper(source)
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(cover.isRibbonActive, "Fresh flat observations must settle on a display frame within one second")
        XCTAssertEqual(cover.alphaValue, 1)
    }

    func testAttachedStaleObservationHidesAndReleasesMaterial() throws {
        guard #available(macOS 14.0, *) else { throw XCTSkip("Metal display link") }
        _ = NSApplication.shared
        let cover = CoverWindow(frame: NSRect(x: 200, y: 200, width: 326, height: 212))
        defer { cover.close() }
        cover.apply(CoverStyle(texture: .parchmatte, softness: 0.4, opacity: 0.4,
                               lamp: .off, lampStrength: 0.5), hideFromCapture: true)
        cover.orderFrontRegardless()
        XCTAssertTrue(cover.beginAttachedPaper(target: NSRect(x: 400, y: 100, width: 150, height: 120),
                                              variant: .soft, restoring: true, raiseDuringMotion: true))
        RunLoop.main.run(until: Date().addingTimeInterval(0.24))
        XCTAssertFalse(cover.isRibbonActive)
        XCTAssertFalse(cover.isVisible, "Missing observations must not leave a detached paper square")
        XCTAssertEqual(cover.alphaValue, 0)
        XCTAssertEqual(cover.level, .normal)
        XCTAssertFalse(cover.contentView!.layer!.sublayers!.contains { $0 is CAMetalLayer })
    }

    func testLateDrawableFailureRestoresStaticMaterialThroughFade() throws {
        guard #available(macOS 14.0, *) else { throw XCTSkip("Display-linked Ribbon requires macOS 14") }
        _ = NSApplication.shared
        let cover = CoverWindow(frame: NSRect(x: 0, y: 0, width: 326, height: 212))
        defer { cover.close() }
        cover.apply(CoverStyle(texture: .parchmatte, softness: 0, opacity: 0.4, lamp: .off, lampStrength: 0.5),
            hideFromCapture: true)
        cover.orderFrontRegardless()
        XCTAssertTrue(cover.beginRibbon(restoring: true))
        let layer = try XCTUnwrap(cover.contentView?.layer?.sublayers?.compactMap { $0 as? CAMetalLayer }.first)
        // Induce a real public-API drawable failure, without a mocked renderer.
        layer.device = nil
        RunLoop.main.run(until: Date().addingTimeInterval(0.27))
        XCTAssertFalse(cover.isRibbonActive)
        XCTAssertTrue(cover.isRestoreFadeActive)
        XCTAssertFalse(cover.contentView!.layer!.sublayers!.contains { $0 is CAMetalLayer })
        XCTAssertFalse(cover.contentView!.layer!.sublayers!.first!.isHidden)
    }
}
