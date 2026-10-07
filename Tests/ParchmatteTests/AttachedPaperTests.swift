import CoreGraphics
import XCTest
@testable import Parchmatte

final class AttachedPaperTests: XCTestCase {
    let source = CGRect(x: 200, y: 150, width: 800, height: 600)

    func testFlatEndpointPreservesMaterialGeometry() {
        for variant in AttachedPaperGeometry.Variant.allCases {
            let result = AttachedPaperGeometry.evaluate(source: source, target: source, variant: variant)
            XCTAssertEqual(result.progress, 0)
            XCTAssertEqual(result.fade, 1)
            XCTAssertEqual(result.center, CGPoint(x: 600, y: 450))
            XCTAssertEqual(result.mesh.points.first!.x, -400, accuracy: 0.001)
            XCTAssertEqual(result.mesh.points.first!.y, -300, accuracy: 0.001)
        }
    }

    func testReturnHasVisiblePaperBeforeFullWindowSize() {
        let small = CGRect(x: 1450, y: 1020, width: 300, height: 350)
        let result = AttachedPaperGeometry.evaluate(source: source, target: small, variant: .curve)
        XCTAssertGreaterThan(result.progress, 0)
        XCTAssertLessThan(result.progress, 1)
        XCTAssertGreaterThan(result.fade, 0)
    }

    func testSameGeometryHasSameShapeInBothDirections() {
        let path = [source, CGRect(x: 230, y: 200, width: 950, height: 601),
                    CGRect(x: 1000, y: 700, width: 750, height: 600),
                    CGRect(x: 1688, y: 1346, width: 54, height: 48)]
        let outward = path.map { AttachedPaperGeometry.evaluate(source: source, target: $0, variant: .curve) }
        let inward = path.reversed().map { AttachedPaperGeometry.evaluate(source: source, target: $0, variant: .curve) }
        for (a, b) in zip(outward, inward.reversed()) {
            XCTAssertEqual(a.progress, b.progress)
            XCTAssertEqual(a.center, b.center)
            XCTAssertEqual(a.mesh.points.map(\.x), b.mesh.points.map(\.x))
        }
        XCTAssertEqual(outward.last!.fade, 0)
    }

    func testVariantsRemainFiniteAndRespectOpacityBudget() {
        for variant in AttachedPaperGeometry.Variant.allCases {
            for target in [CGRect(x: -900, y: 500, width: 300, height: 400),
                           CGRect(x: 1000, y: 700, width: 750, height: 600)] {
                let output = AttachedPaperGeometry.evaluate(source: source, target: target, variant: variant)
                XCTAssertEqual(output.mesh.points.count, 315)
                XCTAssertTrue(output.mesh.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
                XCTAssertTrue((0...1).contains(output.fade))
                XCTAssertTrue(output.mesh.points.allSatisfy { abs($0.x) <= source.width/2 && abs($0.y) <= source.height/2 })
            }
        }
    }
}
