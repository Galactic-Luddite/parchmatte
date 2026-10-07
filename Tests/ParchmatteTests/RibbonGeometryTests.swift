import CoreGraphics
import XCTest
@testable import Parchmatte

final class RibbonGeometryTests: XCTestCase {
    struct Reference: Decodable {
        struct Face: Decodable { let indices: [Int]; let depth: Double; let shade: Double }
        let progress: Double, collapse: Double, travel: Double, scale: Double, alpha: Double
        let points: [[Double]]
        let faces: [Face]
    }
    func testApprovedDemoGeometryAndLightingAtGoldenFrames() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ribbon-demo.json")
        let references = try JSONDecoder().decode([Reference].self, from: Data(contentsOf: url))
        for reference in references {
            let state = RibbonGeometry.demoState(progress: reference.progress)
            XCTAssertEqual(state.collapse, reference.collapse, accuracy: 1e-12)
            XCTAssertEqual(state.travel, reference.travel, accuracy: 1e-12)
            XCTAssertEqual(state.scale, reference.scale, accuracy: 1e-12)
            XCTAssertEqual(state.alpha, reference.alpha, accuracy: 1e-12)
            let mesh = RibbonGeometry.mesh(size: CGSize(width: 326, height: 212), state: state)
            XCTAssertEqual(mesh.points.count, 315)
            XCTAssertEqual(mesh.faces.count, 560)
            for (point, expected) in zip(mesh.points, reference.points) {
                XCTAssertEqual(point.x, expected[0], accuracy: 1e-9)
                XCTAssertEqual(point.y, expected[1], accuracy: 1e-9)
                XCTAssertEqual(point.z, expected[2], accuracy: 1e-9)
            }
            // JavaScript and libm can order equal-depth cosine rows differently
            // at the last floating-point bit. Compare lighting by triangle identity,
            // and compare sorted depth independently within the declared tolerance.
            let expectedFaces = Dictionary(uniqueKeysWithValues: reference.faces.map { ($0.indices, $0) })
            for (face, depthReference) in zip(mesh.faces, reference.faces) {
                let expected = expectedFaces[face.indices]!
                XCTAssertEqual(face.depth, expected.depth, accuracy: 1e-9)
                XCTAssertEqual(face.shade, expected.shade, accuracy: 1e-9)
                XCTAssertEqual(face.depth, depthReference.depth, accuracy: 1e-9)
            }
            for (a, b) in zip(mesh.faces, mesh.faces.dropFirst()) {
                XCTAssertLessThanOrEqual(a.depth, b.depth)
            }
        }
    }
    func testRestAndUniformWindowScalingPreserveShape() {
        let rest = RibbonGeometry.mesh(size: CGSize(width: 326, height: 212), state: .init(collapse: 0, travel: 0, scale: 1, alpha: 0.6))
        XCTAssertEqual(rest.points.first!.x, -163, accuracy: 1e-12)
        XCTAssertEqual(rest.points.first!.y, -106, accuracy: 1e-12)
        let state = RibbonGeometry.demoState(progress: 0.7)
        let small = RibbonGeometry.mesh(size: CGSize(width: 326, height: 212), state: state)
        let large = RibbonGeometry.mesh(size: CGSize(width: 652, height: 424), state: state)
        for (a, b) in zip(small.points, large.points) {
            XCTAssertEqual(b.x, a.x * 2, accuracy: 1e-9)
            XCTAssertEqual(b.y, a.y * 2, accuracy: 1e-9)
            XCTAssertEqual(b.z, a.z * 2, accuracy: 1e-9)
        }
    }
    func testUnsupportedDimensionsAndScaleCannotProduceGPUVertices() {
        let state = RibbonGeometry.demoState(progress: 0.7)
        for dimension in [CGFloat.zero, -1, .nan, .infinity, .greatestFiniteMagnitude] {
            for size in [CGSize(width: dimension, height: 212), CGSize(width: 326, height: dimension)] {
                let mesh = RibbonGeometry.mesh(size: size, state: state)
                XCTAssertTrue(mesh.points.isEmpty)
                XCTAssertTrue(mesh.faces.isEmpty)
            }
        }
        for scale in [-1.0, 1.1, .nan, .infinity, .greatestFiniteMagnitude] {
            let mesh = RibbonGeometry.mesh(size: CGSize(width: 326, height: 212),
                state: .init(collapse: 1, travel: 1, scale: scale, alpha: 0))
            XCTAssertTrue(mesh.points.isEmpty)
        }
        // The largest supported sheet and nonfinite fold/travel state remain
        // finite; the latter clamps to rest rather than reaching GPU buffers.
        let mesh = RibbonGeometry.mesh(size: CGSize(width: RibbonGeometry.maximumSheetDimension, height: 1),
            state: .init(collapse: .nan, travel: .infinity, scale: 1, alpha: 0.6))
        XCTAssertEqual(mesh.points.count, 315)
        XCTAssertTrue(mesh.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
        XCTAssertTrue(mesh.faces.allSatisfy { $0.depth.isFinite && $0.shade.isFinite })
    }
}
