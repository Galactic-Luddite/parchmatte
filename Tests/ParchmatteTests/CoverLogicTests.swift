import AppKit
import XCTest
@testable import Parchmatte

/// The pieces of the cover machinery that take plain data and need no
/// window server.
final class CoverLogicTests: XCTestCase {
    func testAuditPreferenceSnapshotRestoresOnlyItsDomain() throws {
        let domain = "ParchmatteAuditPreferences-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.setPersistentDomain(["wholeScreen": true, "strength": 0.4], forName: domain)
        let snapshot = try AuditPreferences.export(from: defaults, domain: domain)
        defaults.setPersistentDomain(["wholeScreen": false], forName: domain)
        try AuditPreferences.restore(snapshot, to: defaults, domain: domain)
        XCTAssertEqual(defaults.persistentDomain(forName: domain)?["wholeScreen"] as? Bool, true)
        XCTAssertEqual(defaults.persistentDomain(forName: domain)?["strength"] as? Double, 0.4)
        XCTAssertThrowsError(try AuditPreferences.restore(Data("broken".utf8), to: defaults, domain: domain))
    }

    func testCornerRadiusByMacOSVersion() {
        XCTAssertEqual(WindowCover.cornerRadius(osMajor: 13), 10)
        XCTAssertEqual(WindowCover.cornerRadius(osMajor: 15), 10)
        XCTAssertEqual(WindowCover.cornerRadius(osMajor: 26), 26)
        XCTAssertEqual(WindowCover.cornerRadius(osMajor: 27), 18)
        XCTAssertEqual(WindowCover.cornerRadius(osMajor: 30), 18)
    }

    func testNoOverlayInAnEmptyWindowList() {
        XCTAssertFalse(CoverManager.systemOverlayShowing(in: []))
    }

    func testDockIconWindowIsNotAnOverlay() {
        // A small Dock window (the Dock itself, or a hidden Dock sliding in)
        // is not display-sized, so it is never the overview signal.
        let entry: [String: Any] = [
            kCGWindowOwnerName as String: "Dock",
            kCGWindowLayer as String: Int(CGWindowLevelForKey(.dockWindow)),
            kCGWindowBounds as String: ["X": 0, "Y": 1000, "Width": 800, "Height": 80] as NSDictionary,
        ]
        XCTAssertFalse(CoverManager.systemOverlayShowing(in: [entry]))
    }

    func testOtherAppsDisplaySizedWindowIsNotAnOverlay() throws {
        guard let screen = NSScreen.screens.first else { throw XCTSkip("no display") }
        let frame = CoverManager.cgRect(fromAppKit: screen.frame)
        let entry: [String: Any] = [
            kCGWindowOwnerName as String: "Finder",
            kCGWindowLayer as String: Int(CGWindowLevelForKey(.dockWindow)),
            kCGWindowBounds as String: [
                "X": frame.minX, "Y": frame.minY, "Width": frame.width, "Height": frame.height,
            ] as NSDictionary,
        ]
        XCTAssertFalse(CoverManager.systemOverlayShowing(in: [entry]))
    }

    func testDockDisplaySizedWindowIsAnOverlay() throws {
        guard let screen = NSScreen.screens.first else { throw XCTSkip("no display") }
        let frame = CoverManager.cgRect(fromAppKit: screen.frame)
        let entry: [String: Any] = [
            kCGWindowOwnerName as String: "Dock",
            kCGWindowLayer as String: Int(CGWindowLevelForKey(.dockWindow)),
            kCGWindowBounds as String: [
                "X": frame.minX, "Y": frame.minY, "Width": frame.width, "Height": frame.height,
            ] as NSDictionary,
        ]
        XCTAssertTrue(CoverManager.systemOverlayShowing(in: [entry]))
        XCTAssertFalse(CoverManager.systemOverviewStarting(in: [entry], displays: [frame]))
        XCTAssertFalse(CoverManager.systemOverviewStarting(in: [entry, entry], displays: [frame]))
    }

    func testDockWindowPairIsAnOverviewWithoutWindowManager() {
        // The test Mac (macOS 26.7, 1920x1080) never exposes a WindowManager
        // window during App Exposé or Mission Control. Its Dock exposes the
        // layer-20 overlay plus a second display-sized window (layer 18) a
        // frame before the target starts moving (issue #12).
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let dock = { (id: Int, layer: Int, rect: CGRect) -> [String: Any] in [
            kCGWindowNumber as String: id,
            kCGWindowOwnerName as String: "Dock",
            kCGWindowLayer as String: layer,
            kCGWindowBounds as String: rect.dictionaryRepresentation,
        ] }
        let overlay = dock(22, 20, display)
        let second = dock(4359, 18, display)
        let wallpaper = dock(650, -2147483624, display)
        XCTAssertTrue(CoverManager.systemOverviewStarting(in: [overlay, second], displays: [display]))
        XCTAssertTrue(CoverManager.systemOverviewStarting(in: [wallpaper, second, overlay], displays: [display]))
        // A revealed auto-hidden Dock is the single layer-20 overlay.
        XCTAssertFalse(CoverManager.systemOverviewStarting(in: [overlay], displays: [display]))
        XCTAssertFalse(CoverManager.systemOverviewStarting(in: [overlay, wallpaper], displays: [display]))
        // The same window listed twice is not a pair.
        XCTAssertFalse(CoverManager.systemOverviewStarting(in: [overlay, overlay], displays: [display]))
        // Both windows must be display-sized on a real display.
        let strip = dock(4359, 18, CGRect(x: 0, y: 0, width: 1920, height: 112))
        XCTAssertFalse(CoverManager.systemOverviewStarting(in: [overlay, strip], displays: [display]))
        XCTAssertFalse(CoverManager.systemOverviewStarting(in: [overlay, second], displays: []))
    }

    func testWindowManagerOverviewIsRecognizedBeforeWindowsMove() {
        let frame = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        // Mission Control and App Exposé expose this row before transforming
        // the target. Dock hover during a restore does not expose it.
        let entry: [String: Any] = [
            kCGWindowOwnerName as String: "WindowManager",
            kCGWindowLayer as String: 19,
            kCGWindowBounds as String: [
                "X": frame.minX, "Y": frame.minY, "Width": frame.width, "Height": frame.height,
            ] as NSDictionary,
        ]
        XCTAssertTrue(CoverManager.systemOverviewStarting(in: [entry], displays: [frame]))
    }

    func testOverviewEntryRejectsDockAndUnrelatedSystemWindows() {
        let display = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        let cases: [(String, Int, CGRect, Bool)] = [
            ("Dock", 20, display, false),
            ("Dock", 19, display, false),
            ("WindowManager", -2147483624, display, false),
            ("WindowManager", 14, display, false),
            ("WindowManager", 19, CGRect(x: 0, y: 0, width: 2056, height: 112), false),
            ("WindowManager", 19, display.offsetBy(dx: 1, dy: 0), false),
            ("WindowManager", 19, display.offsetBy(dx: 0.5, dy: 0.5), true),
        ]
        for (owner, layer, rect, expected) in cases {
            let entry: [String: Any] = [
                kCGWindowOwnerName as String: owner,
                kCGWindowLayer as String: layer,
                kCGWindowBounds as String: rect.dictionaryRepresentation,
            ]
            XCTAssertEqual(
                CoverManager.systemOverviewStarting(in: [entry], displays: [display]), expected,
                "owner=\(owner), layer=\(layer), rect=\(rect)"
            )
        }
        XCTAssertFalse(CoverManager.systemOverviewStarting(in: [], displays: [display]))
        XCTAssertFalse(CoverManager.systemOverviewStarting(in: [[
            kCGWindowOwnerName as String: "WindowManager", kCGWindowLayer as String: 19,
        ]], displays: [display]))
    }

    func testOverviewEntryMatchesASecondaryDisplay() {
        let primary = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        let secondary = CGRect(x: -1920, y: 120, width: 1920, height: 1080)
        let entry: [String: Any] = [
            kCGWindowOwnerName as String: "WindowManager",
            kCGWindowLayer as String: 19,
            kCGWindowBounds as String: secondary.dictionaryRepresentation,
        ]
        XCTAssertTrue(CoverManager.systemOverviewStarting(in: [entry], displays: [primary, secondary]))
        XCTAssertFalse(CoverManager.systemOverviewStarting(in: [entry], displays: [primary]))
        XCTAssertFalse(CoverManager.systemOverviewStarting(in: [entry], displays: []))
    }

    func testCoordinateConversionRoundTrips() throws {
        guard NSScreen.screens.first != nil else { throw XCTSkip("no display") }
        let rect = NSRect(x: 120, y: 340, width: 800, height: 600)
        let back = CoverManager.appKitFrame(fromCG: CoverManager.cgRect(fromAppKit: rect))
        XCTAssertEqual(back.minX, rect.minX, accuracy: 0.001)
        XCTAssertEqual(back.minY, rect.minY, accuracy: 0.001)
        XCTAssertEqual(back.size, rect.size)
    }

    func testMissingWindowRequestsScansOnlyDuringGrace() {
        let firstMissing = Date(timeIntervalSinceReferenceDate: 1_000)
        var missingSince: Date?

        XCTAssertTrue(CoverManager.missingWindowNeedsScan(
            isOnScreen: false, missingSince: &missingSince, now: firstMissing, settle: 0.25
        ))
        XCTAssertEqual(missingSince, firstMissing)
        XCTAssertTrue(CoverManager.missingWindowNeedsScan(
            isOnScreen: false, missingSince: &missingSince,
            now: firstMissing.addingTimeInterval(0.249), settle: 0.25
        ))
        XCTAssertFalse(CoverManager.missingWindowNeedsScan(
            isOnScreen: false, missingSince: &missingSince,
            now: firstMissing.addingTimeInterval(0.25), settle: 0.25
        ))
        XCTAssertFalse(CoverManager.missingWindowNeedsScan(
            isOnScreen: true, missingSince: &missingSince,
            now: firstMissing.addingTimeInterval(0.251), settle: 0.25
        ))
        XCTAssertNil(missingSince)
    }
}
