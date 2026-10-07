import AppKit
import XCTest
@testable import Parchmatte

/// Clamping and cycling: the promises the security plan's S1 and S5 rest on.
final class StyleTests: XCTestCase {
    func testOpacityNeverExceedsTheCap() {
        XCTAssertEqual(AppInfo.maxOpacity, 0.6)
        XCTAssertEqual(AppInfo.safeOpacity(5), 0.6)
        XCTAssertEqual(AppInfo.safeOpacity(0.6), 0.6)
        XCTAssertEqual(AppInfo.safeOpacity(0.15), 0.15)
        XCTAssertEqual(AppInfo.safeOpacity(-1), 0)
    }

    func testHostileOpacityBecomesZero() {
        XCTAssertEqual(AppInfo.safeOpacity(.nan), 0)
        XCTAssertEqual(AppInfo.safeOpacity(.infinity), 0)
        XCTAssertEqual(AppInfo.safeOpacity(-.infinity), 0)
        XCTAssertEqual(AppInfo.safeOpacity(1e308), 0.6)
    }

    func testCoverStyleClampsBothSliders() {
        let wild = CoverStyle(texture: .felt, softness: 7, opacity: 9, lamp: .aurora, glow: .warm)
        let clamped = wild.clamped
        XCTAssertEqual(clamped.opacity, AppInfo.maxOpacity)
        XCTAssertEqual(clamped.softness, 1)
        XCTAssertEqual(clamped.texture, .felt)
        XCTAssertEqual(clamped.lamp, .aurora)
        let broken = CoverStyle(texture: .matte, softness: .nan, opacity: .infinity, lamp: .off, glow: .subtle).clamped
        XCTAssertEqual(broken.softness, 0)
        XCTAssertEqual(broken.opacity, 0)
    }

    func testOrientationCyclesInIssueOrderAndKeepsSavedIdentifiers() {
        XCTAssertEqual(Orientation.allCases, [.normal, .flippedHorizontally, .flippedVertically, .flippedBoth])
        XCTAssertEqual(Orientation.normal.next, .flippedHorizontally)
        XCTAssertEqual(Orientation.flippedBoth.next, .normal)
        XCTAssertEqual(Orientation.allCases.map(\.rawValue), ["normal", "flipH", "flipV", "flipBoth"])
        XCTAssertNil(Orientation(rawValue: "sideways"))
        XCTAssertEqual(CoverStyle(texture: .denim, softness: 0, opacity: 0.3, lamp: .off, glow: .medium).orientation, .normal)
    }

    func testFlippedTilesMirrorPixelForPixelAndGetTheirOwnCacheEntry() throws {
        let normal = try XCTUnwrap(Texture.denim.renderedTile(softness: 0, scale: 1))
        let flipped = try XCTUnwrap(Texture.denim.renderedTile(softness: 0, scale: 1, orientation: .flippedHorizontally))
        let both = try XCTUnwrap(Texture.denim.renderedTile(softness: 0, scale: 1, orientation: .flippedBoth))
        XCTAssertFalse(normal.image === flipped.image, "a flipped tile must not share the normal tile's cache entry")
        func pixels(_ image: NSImage) throws -> (CGImage, [UInt8]) {
            let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let context = try XCTUnwrap(CGContext(
                data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return (cg, bytes)
        }
        let (n, a) = try pixels(normal.image)
        let (f, b) = try pixels(flipped.image)
        let (_, c) = try pixels(both.image)
        XCTAssertEqual(n.width, f.width)
        // Row 3, pixel x of the normal tile is pixel (width-1-x) of the
        // horizontally flipped one, and (height-1-3, width-1-x) of the
        // 180-degree one.
        for x in [0, 1, n.width / 2, n.width - 1] {
            let i = (3 * n.width + x) * 4, j = (3 * n.width + (n.width - 1 - x)) * 4
            let k = ((n.height - 1 - 3) * n.width + (n.width - 1 - x)) * 4
            XCTAssertEqual(Array(a[i..<i + 4]), Array(b[j..<j + 4]), "x=\(x)")
            XCTAssertEqual(Array(a[i..<i + 4]), Array(c[k..<k + 4]), "x=\(x)")
        }
        XCTAssertEqual(normal.maximumAlpha, flipped.maximumAlpha, accuracy: 1e-9)
    }

    func testCyclesWrapAround() {
        XCTAssertEqual(Texture.allCases.last!.next, Texture.allCases.first!)
        XCTAssertEqual(LampPreset.allCases.last!.next, LampPreset.allCases.first!)
        XCTAssertEqual(Glow.allCases.last!.next, Glow.allCases.first!)
        XCTAssertEqual(Texture.parchmatte.next, .matte)
        XCTAssertEqual(LampPreset.off.next, .candlelight)
    }

    func testEightTexturesAndSevenLamps() {
        // The README, the website and the store listing all say eight textures.
        XCTAssertEqual(Texture.allCases.count, 8)
        XCTAssertEqual(LampPreset.allCases.count, 7)
        XCTAssertEqual(Glow.allCases.count, 3)
    }

    func testTextureDisplayNamesKeepSavedIdentifiers() {
        XCTAssertEqual(Texture.allCases.map(\.title), [
            "Parchmatte", "Fine Grain", "Chalkboard", "Woven",
            "Imprint", "Soft Leaf", "Felt", "Denim",
        ])
        XCTAssertEqual(Texture.matte.rawValue, "matte")
        XCTAssertEqual(Texture.linen.rawValue, "linen")
        XCTAssertEqual(Texture.press.rawValue, "press")
        XCTAssertEqual(Texture.vellum.rawValue, "vellum")
    }

    func testLampTintsStayUnderTheCapAtEveryGlow() {
        // The composited cap is enforced in CoverWindow; this checks the
        // presets alone never ask for more than the cap, so the budget
        // math there only ever reduces.
        for lamp in LampPreset.allCases {
            guard let tint = lamp.tint else { continue }
            for glow in Glow.allCases {
                XCTAssertLessThanOrEqual(Double(tint.alpha * glow.strength), AppInfo.maxOpacity, "\(lamp) \(glow)")
            }
        }
    }

    func testCoverOpacityBudgetUsesRenderedTextureAlpha() {
        let result = AppInfo.coverOpacities(texture: 0.6, maximumAlpha: 150.0 / 255, lamp: 0.24)
        XCTAssertEqual(result.lamp, 0.24, accuracy: 1e-12)
        XCTAssertEqual(result.texture, 0.6, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(result.lamp + (150.0 / 255) * result.texture * (1 - result.lamp), AppInfo.maxOpacity + 1e-12)
    }

    func testCoverOpacityBudgetReducesTextureWhenNeeded() {
        let result = AppInfo.coverOpacities(texture: 0.6, maximumAlpha: 1, lamp: 0.24)
        XCTAssertEqual(result.lamp, 0.24, accuracy: 1e-12)
        XCTAssertEqual(result.texture, (0.6 - 0.24) / (1 - 0.24), accuracy: 1e-12)
    }

    func testCoverOpacityBudgetHandlesTransparentAndHostileInputs() {
        XCTAssertEqual(AppInfo.coverOpacities(texture: 0.6, maximumAlpha: 0, lamp: 0.24).texture, 0.6)
        XCTAssertEqual(AppInfo.coverOpacities(texture: .nan, maximumAlpha: .infinity, lamp: .nan).texture, 0)
        XCTAssertEqual(AppInfo.coverOpacities(texture: .infinity, maximumAlpha: -.infinity, lamp: .infinity).lamp, 0)
        XCTAssertEqual(AppInfo.coverOpacities(texture: 0.6, maximumAlpha: nil, lamp: 0.24).texture, 0)
        XCTAssertEqual(
            AppInfo.coverOpacities(texture: 0.6, maximumAlpha: .infinity, lamp: 0.24).texture,
            (0.6 - 0.24) / (1 - 0.24), accuracy: 1e-12
        )
    }

    func testEveryLampGlowStrengthStaysUnderTheCompositeCap() {
        for lamp in LampPreset.allCases {
            for glow in Glow.allCases {
                let requestedLamp = lamp.tint.map { Double($0.alpha * glow.strength) } ?? 0
                for strength in stride(from: 0.0, through: 0.6, by: 0.15) {
                    for maximumAlpha in [0.0, 76.0 / 255, 150.0 / 255, 1.0] {
                        let result = AppInfo.coverOpacities(texture: strength, maximumAlpha: maximumAlpha, lamp: requestedLamp)
                        let composite = result.lamp + maximumAlpha * result.texture * (1 - result.lamp)
                        XCTAssertLessThanOrEqual(composite, AppInfo.maxOpacity + 1e-12, "\(lamp) \(glow) \(strength) \(maximumAlpha)")
                        XCTAssertEqual(result.lamp, AppInfo.safeOpacity(requestedLamp), accuracy: 1e-12)
                    }
                }
            }
        }
    }

    func testProcessedTilesMeasureAlphaAndCacheTogether() throws {
        for texture in Texture.allCases {
            for scale: CGFloat in [1, 2] {
                for step in 0...20 {
                    let first = try XCTUnwrap(texture.renderedTile(softness: Double(step) / 20, scale: scale))
                    let second = try XCTUnwrap(texture.renderedTile(softness: Double(step) / 20, scale: scale))
                    XCTAssertTrue(first.image === second.image)
                    XCTAssertEqual(first.maximumAlpha, second.maximumAlpha)
                    XCTAssertGreaterThanOrEqual(first.maximumAlpha, 0)
                    XCTAssertLessThanOrEqual(first.maximumAlpha, 1)
                    for lamp in LampPreset.allCases {
                        for glow in Glow.allCases {
                            let center = lamp.tint.map { Double($0.alpha * glow.strength) } ?? 0
                            let edge = center * Double(glow.edgeRetention)
                            for lampAlpha in [center, edge] {
                                for strength in stride(from: 0.0, through: 0.6, by: 0.15) {
                                    let layers = AppInfo.coverOpacities(
                                        texture: strength, maximumAlpha: first.maximumAlpha, lamp: lampAlpha
                                    )
                                    let composite = layers.lamp + first.maximumAlpha * layers.texture * (1 - layers.lamp)
                                    XCTAssertLessThanOrEqual(composite, AppInfo.maxOpacity + 1e-12)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testCrispTextureMaximumAlphaMatchesAssets() throws {
        for texture in Texture.allCases {
            let tile = try XCTUnwrap(texture.renderedTile(softness: 0, scale: 1))
            let expected = texture == .vellum ? 76.0 / 255 : 150.0 / 255
            XCTAssertEqual(tile.maximumAlpha, expected, accuracy: 1e-12, "\(texture)")
        }
    }

    func testProcessedTileInputsAreClamped() throws {
        let baseline = try XCTUnwrap(Texture.linen.renderedTile(softness: 0, scale: 1))
        XCTAssertTrue(baseline.image === Texture.linen.renderedTile(softness: .nan, scale: .nan)?.image)
        XCTAssertTrue(baseline.image === Texture.linen.renderedTile(softness: -.infinity, scale: 0)?.image)
    }
}
