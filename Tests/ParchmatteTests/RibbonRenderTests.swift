import Cocoa
import Metal
import QuartzCore
import XCTest
@testable import Parchmatte

final class RibbonRenderTests: XCTestCase {
    func testAttachedFrontTrialRestoresWindowLevelAfterCancellation() throws {
        guard #available(macOS 14.0, *) else { throw XCTSkip("Metal display link") }
        _ = NSApplication.shared
        let cover = CoverWindow(frame: NSRect(x: 200, y: 200, width: 326, height: 212))
        defer { cover.close() }
        cover.apply(CoverStyle(texture: .parchmatte, softness: 0.4, opacity: 0.4,
                               lamp: .off, glow: .medium), hideFromCapture: true)
        cover.level = .normal
        cover.orderFrontRegardless()
        XCTAssertTrue(cover.beginAttachedPaper(target: NSRect(x: 400, y: 100, width: 150, height: 120),
                                              variant: .soft, restoring: true, raiseDuringMotion: true))
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        XCTAssertGreaterThan(cover.level.rawValue, NSWindow.Level.normal.rawValue)
        cover.orderOut(nil)
        XCTAssertEqual(cover.level, .normal)
        XCTAssertFalse(cover.isRibbonActive)
        XCTAssertFalse(cover.isVisible)
    }

    func testPreparedMotionMaterialInvalidatesForStyleAndSize() throws {
        _ = NSApplication.shared
        let cover = CoverWindow(frame: NSRect(x: 0, y: 0, width: 120, height: 90))
        defer { cover.close() }
        cover.apply(CoverStyle(texture: .linen, softness: 0, opacity: 0.1,
                               lamp: .off, glow: .medium), hideFromCapture: true)
        cover.preparePaperForMotion()
        let first = try XCTUnwrap(cover.motionPaperSnapshot())
        cover.cornerRadius = 24
        let rounded = try XCTUnwrap(cover.motionPaperSnapshot())
        XCTAssertNotEqual(first.image.dataProvider!.data! as Data, rounded.image.dataProvider!.data! as Data)
        cover.apply(CoverStyle(texture: .linen, softness: 0, opacity: 0.6,
                               lamp: .lateNight, glow: .warm), hideFromCapture: true)
        let changed = try XCTUnwrap(cover.motionPaperSnapshot())
        XCTAssertNotEqual(first.image.dataProvider!.data! as Data, changed.image.dataProvider!.data! as Data)
        cover.preparePaperForMotion()
        cover.place(NSRect(x: 10, y: 10, width: 240, height: 180))
        let resized = try XCTUnwrap(cover.motionPaperSnapshot())
        XCTAssertEqual(resized.logicalSize, CGSize(width: 240, height: 180))
        XCTAssertEqual(resized.image.width, changed.image.width * 2)
    }

    func testHiddenCoverDoesNotStartUnpresentableRibbon() {
        _ = NSApplication.shared
        let cover = CoverWindow(frame: NSRect(x: 0, y: 0, width: 326, height: 212))
        defer { cover.close() }
        cover.apply(CoverStyle(texture: .parchmatte, softness: 0, opacity: 0.4, lamp: .off, glow: .medium),
            hideFromCapture: true)
        XCTAssertFalse(cover.isVisible)
        XCTAssertFalse(cover.beginRibbon(restoring: true))
        XCTAssertFalse(cover.isRibbonActive)
        XCTAssertFalse(cover.contentView!.layer!.sublayers!.contains { $0 is CAMetalLayer })
    }

    func testBackingChangeDoesNotCancelCrossDisplayRibbon() throws {
        guard #available(macOS 14.0, *) else { throw XCTSkip("Display-linked Ribbon requires macOS 14") }
        _ = NSApplication.shared
        let cover = CoverWindow(frame: NSRect(x: 0, y: 0, width: 326, height: 212))
        defer { cover.close() }
        cover.apply(CoverStyle(texture: .parchmatte, softness: 0.4, opacity: 0.4, lamp: .off, glow: .medium),
            hideFromCapture: true)
        cover.orderFrontRegardless()
        XCTAssertTrue(cover.beginRibbon(restoring: false))
        NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: cover)
        XCTAssertTrue(cover.isRibbonActive, "A density change along the Genie path must not abort its mesh")
        cover.orderOut(nil)
        XCTAssertFalse(cover.isRibbonActive)
    }

    func testMinimizeCompletionReleasesTransientMaterial() throws {
        guard #available(macOS 14.0, *) else { throw XCTSkip("Display-linked Ribbon requires macOS 14") }
        _ = NSApplication.shared
        let cover = CoverWindow(frame: NSRect(x: 0, y: 0, width: 326, height: 212))
        defer { cover.close() }
        cover.apply(CoverStyle(texture: .parchmatte, softness: 0, opacity: 0.4, lamp: .off, glow: .medium),
            hideFromCapture: true)
        cover.orderFrontRegardless()
        XCTAssertTrue(cover.beginRibbon(restoring: false))
        // Either display-paced completion or the occlusion deadline must
        // remove the transient layer and departing window.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(cover.isRibbonActive)
        XCTAssertFalse(cover.isVisible)
        XCTAssertFalse(cover.contentView!.layer!.sublayers!.contains { $0 is CAMetalLayer })
    }

    func testSnapshotUsesCurrentTextureLampAndOpacity() throws {
        _ = NSApplication.shared
        let cover = CoverWindow(frame: NSRect(x: 0, y: 0, width: 120, height: 90))
        defer { cover.close() }
        func bytes(opacity: Double, lamp: LampPreset) throws -> [UInt8] {
            cover.apply(CoverStyle(texture: .linen, softness: 0,
                opacity: opacity, lamp: lamp, glow: .warm), hideFromCapture: false)
            let snapshot = try XCTUnwrap(cover.paperSnapshot())
            let data = try XCTUnwrap(snapshot.image.dataProvider?.data)
            return Array(UnsafeBufferPointer(start: CFDataGetBytePtr(data), count: CFDataGetLength(data)))
        }
        let low = try bytes(opacity: 0.1, lamp: .off)
        let high = try bytes(opacity: 0.6, lamp: .off)
        let lit = try bytes(opacity: 0.6, lamp: .lateNight)
        XCTAssertNotEqual(low, high, "snapshot must retain actual style opacity")
        XCTAssertNotEqual(high, lit, "snapshot must retain actual lamp tint")
        for pixels in [low, high, lit] {
            XCTAssertLessThanOrEqual(stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }.max()!, 153)
        }
    }

    func testRestyleAndOrderOutTearDownTransientRenderer() throws {
        guard #available(macOS 14.0, *) else { throw XCTSkip("Display-linked Ribbon requires macOS 14") }
        _ = NSApplication.shared
        let cover = CoverWindow(frame: NSRect(x: 0, y: 0, width: 326, height: 212))
        defer { cover.close() }
        let style = CoverStyle(texture: .parchmatte, softness: 0.4, opacity: 0.4, lamp: .off, glow: .medium)
        cover.apply(style, hideFromCapture: true)
        cover.orderFrontRegardless()
        XCTAssertTrue(cover.beginRibbon(restoring: false))
        XCTAssertTrue(cover.isRibbonActive)
        cover.apply(style, hideFromCapture: false)
        XCTAssertFalse(cover.isRibbonActive)
        XCTAssertEqual(cover.alphaValue, 0, "restyling a departing cover must not reveal its static rectangle")
        XCTAssertEqual(cover.sharingType, .readOnly)
        XCTAssertTrue(cover.beginRibbon(restoring: true))
        cover.orderOut(nil)
        XCTAssertFalse(cover.isRibbonActive)
    }

    func testRealCoverMaterialKeepsOpacityCapThroughFoldOverlap() throws {
        _ = NSApplication.shared
        let cover = CoverWindow(frame: NSRect(x: 0, y: 0, width: 326, height: 212))
        defer { cover.close() }
        let style = CoverStyle(texture: .parchmatte, softness: 0.4,
            opacity: AppInfo.maxOpacity, lamp: .off, glow: .medium)
        cover.apply(style, hideFromCapture: true)
        let snapshot = try XCTUnwrap(cover.paperSnapshot())
        let renderer = try XCTUnwrap(RibbonRenderer(paper: snapshot))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: 326, height: 212, mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .shared
        let target = try XCTUnwrap(renderer.device.makeTexture(descriptor: descriptor))
        var foundPaper = false
        for p in [0.0, 0.2, 0.43, 0.7, 0.9, 1] {
            let state = RibbonGeometry.demoState(progress: p)
            let mesh = RibbonGeometry.mesh(size: snapshot.logicalSize, state: state)
            let command = try XCTUnwrap(renderer.render(mesh: mesh, to: target,
                canvasSize: snapshot.logicalSize, fade: state.alpha / AppInfo.maxOpacity))
            command.commit()
            command.waitUntilCompleted()
            XCTAssertEqual(command.status, .completed)
            var pixels = [UInt8](repeating: 0, count: 326 * 212 * 4)
            target.getBytes(&pixels, bytesPerRow: 326 * 4,
                from: MTLRegionMake2D(0, 0, 326, 212), mipmapLevel: 0)
            let alphas = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
            XCTAssertLessThanOrEqual(alphas.max()!, 153, "fold overlaps must not accumulate alpha")
            if p == 0 { foundPaper = alphas.contains { $0 > 0 } }
            if p == 1 { XCTAssertEqual(alphas.max(), 0) }
        }
        XCTAssertTrue(foundPaper, "actual styled layers must reach the GPU")
        XCTAssertEqual(cover.sharingType, .none)
        XCTAssertFalse(cover.canBecomeKey)
        XCTAssertFalse(cover.canBecomeMain)
        XCTAssertTrue(cover.ignoresMouseEvents)
    }
}
