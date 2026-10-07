import XCTest
import WindowListBridgeTestSupport

final class WindowListBridgeTests: XCTestCase {
    func testEmptyWindowListIsDistinctFromQueryFailure() {
        XCTAssertEqual(PMRunWindowListBridgeTest(UInt32(PMBridgeTestEmpty)), 0)
        XCTAssertEqual(PMRunWindowListBridgeTest(UInt32(PMBridgeTestFailure)), 0)
    }

    func testNearestWindowUsesLastRawID() {
        XCTAssertEqual(PMRunWindowListBridgeTest(UInt32(PMBridgeTestSingle)), 0)
        XCTAssertEqual(PMRunWindowListBridgeTest(UInt32(PMBridgeTestMultiple)), 0)
    }

    func testHighWindowIDKeepsAllBits() {
        XCTAssertEqual(PMRunWindowListBridgeTest(UInt32(PMBridgeTestHighID)), 0)
    }

    func testQueryResultIsReleasedExactlyOnce() {
        XCTAssertEqual(PMRunWindowListBridgeTest(UInt32(PMBridgeTestOwnership)), 0)
    }
}
