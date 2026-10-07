import CoreGraphics
import XCTest
@testable import Parchmatte

final class ScreenshotPickerTests: XCTestCase {
    func testPublicPickerOverlayAndOrdinaryScreenshotWindows() {
        let display = CGRect(x: -1000, y: 0, width: 1000, height: 800)
        func entry(_ owner: String, _ layer: Int, _ rect: CGRect) -> [String: Any] {
            [kCGWindowOwnerName as String: owner, kCGWindowLayer as String: layer,
             kCGWindowBounds as String: rect.dictionaryRepresentation]
        }
        for owner in ["screencapture", "Screenshot", "ScreenshotUI"] {
            XCTAssertTrue(CoverManager.screenshotPickerShowing(in: [entry(owner, 1498, display)], displays: [display]))
            XCTAssertFalse(CoverManager.screenshotPickerShowing(in: [entry(owner, 0, display)], displays: [display]))
            XCTAssertFalse(CoverManager.screenshotPickerShowing(in: [entry(owner, 1498, CGRect(x: 0, y: 0, width: 100, height: 80))], displays: [display]))
        }
        XCTAssertFalse(CoverManager.screenshotPickerShowing(in: [entry("Other", 1498, display)], displays: [display]))
        XCTAssertFalse(CoverManager.screenshotPickerShowing(in: [[:]], displays: [display]))
    }
}
