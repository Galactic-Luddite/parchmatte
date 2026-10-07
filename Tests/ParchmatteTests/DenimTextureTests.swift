import AppKit
import XCTest
@testable import Parchmatte

final class DenimTextureTests: XCTestCase {
    func testDenimIsSelectableAndCyclesBackToParchmatte() {
        XCTAssertEqual(Texture.denim.rawValue, "denim")
        XCTAssertEqual(Texture.denim.title, "Denim")
        XCTAssertEqual(Texture.felt.next, .denim)
        XCTAssertEqual(Texture.denim.next, .parchmatte)
        XCTAssertEqual(Texture.allCases.count, 8)
    }

    func testDenimResourceRendersAcrossSoftnessAndDisplayScales() throws {
        for scale: CGFloat in [1, 2] {
            let crisp = try XCTUnwrap(Texture.denim.renderedTile(softness: 0, scale: scale))
            let middle = try XCTUnwrap(Texture.denim.renderedTile(softness: 0.5, scale: scale))
            let soft = try XCTUnwrap(Texture.denim.renderedTile(softness: 1, scale: scale))

            XCTAssertEqual(crisp.maximumAlpha, 150.0 / 255, accuracy: 1.0 / 255)
            XCTAssertLessThanOrEqual(middle.maximumAlpha, 1)
            XCTAssertLessThanOrEqual(soft.maximumAlpha, 1)
            XCTAssertEqual(crisp.image.size.width * scale, 512)
            XCTAssertEqual(crisp.image.size.height * scale, 512)

            for tile in [crisp, middle, soft] {
                let layers = AppInfo.coverOpacities(
                    texture: AppInfo.maxOpacity, maximumAlpha: tile.maximumAlpha, lamp: AppInfo.maxOpacity
                )
                let combined = layers.lamp + tile.maximumAlpha * layers.texture * (1 - layers.lamp)
                XCTAssertLessThanOrEqual(combined, AppInfo.maxOpacity + 1e-12)
            }
        }
    }
}
