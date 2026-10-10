import Cocoa
import CoreImage

/// The app's display name lives here and in the bundle info file only.
enum AppInfo {
    static let name = "Parchmatte"
    /// Covers can never be stronger than this, so screen content always stays
    /// legible no matter what the slider, a hotkey or a preferences file says.
    static let maxOpacity = 0.6

    /// Clamps any opacity, including NaN or infinity, into 0...maxOpacity.
    static func safeOpacity(_ value: Double) -> Double {
        value.isFinite ? min(maxOpacity, max(0, value)) : 0
    }

    /// Source-over layer opacities that preserve the requested lamp while
    /// keeping the strongest texture pixel at or below the cover cap.
    static func coverOpacities(texture requestedTexture: Double, maximumAlpha: Double?, lamp requestedLamp: Double) -> (texture: Double, lamp: Double) {
        let texture = safeOpacity(requestedTexture)
        let lamp = safeOpacity(requestedLamp)
        guard let maximumAlpha else { return (0, lamp) }
        let alpha = maximumAlpha.isFinite ? min(1, max(0, maximumAlpha)) : 1
        guard alpha > 0, lamp < 1 else { return (texture, lamp) }
        let textureBudget = (maxOpacity - lamp) / (alpha * (1 - lamp))
        return (min(texture, max(0, textureBudget)), lamp)
    }
    /// Hosted copy of docs/PRIVACY.md.
    static let privacyPolicyURL = URL(string: "https://parchmatte.com/privacy/")!
}

/// Everything that decides how a cover looks, apart from where it is. The
/// global settings hold one for the whole screen and new window covers; each
/// window cover owns its own copy.
struct CoverStyle: Equatable {
    var texture: Texture
    var softness: Double
    var opacity: Double
    var lamp: LampPreset
    /// How strong the Page Light tint is, 0...1 (see `LampStrength`).
    var lampStrength: Double = LampStrength.standard
    var orientation: Orientation = .normal

    /// Clamps strength, softness and light strength into range, whatever set them.
    var clamped: CoverStyle {
        var s = self
        s.opacity = AppInfo.safeOpacity(opacity)
        s.softness = softness.isFinite ? min(1, max(0, softness)) : 0
        s.lampStrength = LampStrength.clamped(lampStrength)
        return s
    }
}

/// Which way a texture's grain runs: the tile flipped before it is tiled,
/// so a directional weave (Denim's twill, Woven's linen) can run the other
/// way without another texture. ⌃⌥I cycles the four in this order.
enum Orientation: String, CaseIterable {
    case normal, flippedHorizontally = "flipH", flippedVertically = "flipV", flippedBoth = "flipBoth"

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .flippedHorizontally: return "Flipped Horizontally"
        case .flippedVertically: return "Flipped Vertically"
        case .flippedBoth: return "Flipped Both Ways"
        }
    }

    var flipsX: Bool { self == .flippedHorizontally || self == .flippedBoth }
    var flipsY: Bool { self == .flippedVertically || self == .flippedBoth }

    var next: Orientation {
        let all = Orientation.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// A tileable surface texture baked by scripts/generate_textures.py.
enum Texture: String, CaseIterable {
    case parchmatte, matte, chalkboard, linen, press, vellum, felt, denim

    /// User-facing names can change without invalidating stored texture keys
    /// or renaming the procedurally generated image resources.
    var title: String {
        switch self {
        case .parchmatte: return "Parchmatte"
        case .matte: return "Fine Grain"
        case .chalkboard: return "Chalkboard"
        case .linen: return "Woven"
        case .press: return "Imprint"
        case .vellum: return "Soft Leaf"
        case .felt: return "Felt"
        case .denim: return "Denim"
        }
    }

    var next: Texture {
        let all = Texture.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    private static var sourceCache: [Texture: CGImage] = [:]
    struct RenderedTile {
        let image: NSImage
        let maximumAlpha: Double
    }

    private static var softenedCache: [String: RenderedTile] = [:]
    /// Keys of `softenedCache`, least recently used first.
    private static var softenedOrder: [String] = []
    /// How many softened tiles to keep (see `renderedTile(softness:scale:)`).
    static let softenedCacheLimit = 12
    /// No colour management: the grain map's values pass through exactly, so
    /// every softness level shares one look and only the blur changes.
    private static let ciContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    /// Loads the PNG from the app bundle (Xcode build) or the SwiftPM resource bundle.
    private var source: CGImage? {
        if let cached = Texture.sourceCache[self] { return cached }
        var url = Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "Textures")
        #if SWIFT_PACKAGE
        if url == nil {
            url = Bundle.module.url(forResource: rawValue, withExtension: "png", subdirectory: "Textures")
                ?? Bundle.module.url(forResource: rawValue, withExtension: "png")
        }
        #endif
        guard let url, let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        Texture.sourceCache[self] = cg
        return cg
    }

    /// The source tile mirrored on the axes the orientation flips, pixel for
    /// pixel (no resampling), before it is wrapped and softened. A tileable
    /// tile stays tileable under a mirror, so the seams stay seamless.
    static func flipped(_ image: CGImage, _ orientation: Orientation) -> CGImage? {
        guard orientation != .normal else { return image }
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.translateBy(x: orientation.flipsX ? CGFloat(width) : 0, y: orientation.flipsY ? CGFloat(height) : 0)
        context.scaleBy(x: orientation.flipsX ? -1 : 1, y: orientation.flipsY ? -1 : 1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// The tile surrounded by eight copies of itself, offset by whole pixels,
    /// so blurring wraps seamlessly across edges without resampling the grain.
    private static func wrapped(_ tile: CIImage, extent: CGRect) -> CIImage {
        var result = tile
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let moved = tile.transformed(by: CGAffineTransform(
                    translationX: CGFloat(dx) * extent.width, y: CGFloat(dy) * extent.height
                ))
                result = moved.composited(over: result)
            }
        }
        return result
    }

    /// The tile at a given softness (0 = crisp, 1 = very soft). Softening lightly
    /// blurs the grain (wrapping across tile edges so it stays seamless), then
    /// restores most of the strength the blur averaged away, so the surface
    /// reads smoother rather than fainter.
    func renderedTile(softness: Double, scale: CGFloat, orientation: Orientation = .normal) -> RenderedTile? {
        let safeSoftness = softness.isFinite ? min(1, max(0, softness)) : 0
        let safeScale = scale.isFinite && scale > 0 ? scale : 1
        let step = Int((safeSoftness * 20).rounded())
        // The orientation is part of the key: two covers flipped differently
        // must not share a tile.
        let key = "\(rawValue)-\(step)-\(safeScale)-\(orientation.rawValue)"
        if let cached = Texture.softenedCache[key] {
            // Most recently used goes to the back of the eviction line.
            Texture.softenedOrder.removeAll { $0 == key }
            Texture.softenedOrder.append(key)
            return cached
        }
        guard let unflipped = self.source, let source = Texture.flipped(unflipped, orientation) else { return nil }

        // Every level, including 0, goes through the same pipeline so the
        // slider changes smoothly with no jump at the bottom.
        let amount = Double(step) / 20
        let extent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        var softened = Texture.wrapped(CIImage(cgImage: source, options: [.colorSpace: NSNull()]), extent: extent)
        if amount > 0 {
            softened = softened
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: amount * 1.2])
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(1 + amount * 1.6)),
                ])
        }
        // Tag the result with the source's own profile so level 0 is
        // pixel-identical to the file.
        guard let output = Texture.ciContext.createCGImage(
            softened.cropped(to: extent), from: extent, format: .RGBA8,
            colorSpace: source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        ) else {
            return nil
        }
        // One texture pixel per device pixel on the cover's own display, so
        // the grain is the same physical size on Retina and standard screens.
        let image = NSImage(cgImage: output, size: NSSize(
            width: CGFloat(output.width) / safeScale, height: CGFloat(output.height) / safeScale
        ))
        guard let maximumAlpha = Texture.maximumAlpha(in: output) else { return nil }
        let tile = RenderedTile(image: image, maximumAlpha: maximumAlpha)
        // Tiles are up to 1024 px (4 MB each), so keep only a dozen
        // texture/softness levels (at most ~48 MB, usually far less) rather
        // than every level ever visited. Twelve leaves room for the screen
        // plus several window covers each with its own texture and softness.
        // Evict the least recently used tile, not the whole cache: one drag
        // of the softness slider visits 21 levels, and clearing everything
        // would make every other cover re-render its own tile afterwards.
        while Texture.softenedCache.count >= Texture.softenedCacheLimit, !Texture.softenedOrder.isEmpty {
            Texture.softenedCache[Texture.softenedOrder.removeFirst()] = nil
        }
        Texture.softenedCache[key] = tile
        Texture.softenedOrder.append(key)
        return tile
    }

    private static func maximumAlpha(in image: CGImage) -> Double? {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        guard let context = CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        var maximum: UInt8 = 0
        for index in stride(from: 3, to: pixels.count, by: 4) {
            maximum = max(maximum, pixels[index])
        }
        return Double(maximum) / 255
    }
}

/// A warm or coloured tint laid over the texture, like a lamp on a desk.
enum LampPreset: String, CaseIterable {
    case off, candlelight, lateNight, readingLamp, goldenHour, gallery, aurora

    var title: String {
        switch self {
        case .off: return "Off"
        case .candlelight: return "Candlelight"
        case .lateNight: return "Late Night"
        case .readingLamp: return "Reading Lamp"
        case .goldenHour: return "Golden Hour"
        case .gallery: return "Gallery"
        case .aurora: return "Aurora"
        }
    }

    /// Tint colour and its peak opacity at the centre of the glow.
    var tint: (color: NSColor, alpha: CGFloat)? {
        switch self {
        case .off: return nil
        case .candlelight: return (NSColor(srgbRed: 1.00, green: 0.62, blue: 0.28, alpha: 1), 0.16)
        case .lateNight: return (NSColor(srgbRed: 0.95, green: 0.45, blue: 0.12, alpha: 1), 0.24)
        case .readingLamp: return (NSColor(srgbRed: 1.00, green: 0.93, blue: 0.80, alpha: 1), 0.12)
        case .goldenHour: return (NSColor(srgbRed: 1.00, green: 0.78, blue: 0.35, alpha: 1), 0.16)
        case .gallery: return (NSColor(srgbRed: 0.93, green: 0.95, blue: 1.00, alpha: 1), 0.08)
        case .aurora: return (NSColor(srgbRed: 0.55, green: 0.95, blue: 0.75, alpha: 1), 0.10)
        }
    }

    var next: LampPreset {
        let all = LampPreset.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// How strong the Page Light tint is. The setting runs 0...1 and scales each
/// preset's own tint: the middle leaves the preset as designed, the bottom
/// halves it and the top doubles it, so the whole slider makes a visible
/// difference while the strongest preset stays under the cover cap.
enum LampStrength {
    /// The setting that shows a preset exactly as designed.
    static let standard = 0.5
    /// How far one press of the hotkey moves the setting.
    static let step = 0.25
    /// Fraction of the centre tint that remains at the edges of the glow.
    static let edgeRetention: CGFloat = 0.55

    /// Clamps any setting, including NaN or infinity, into 0...1.
    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : standard
    }

    /// Multiplier on the preset's tint: 0.5 at the bottom, 1 in the middle, 2 at the top.
    static func multiplier(_ setting: Double) -> Double {
        pow(4, clamped(setting) - standard)
    }

    /// The next setting for the hotkey: up one step, wrapping to the bottom past the top.
    static func next(_ setting: Double) -> Double {
        let value = clamped(setting)
        return value >= 1 ? 0 : min(1, value + step)
    }

    /// The setting matching a glow level saved by 1.0 (subtle, medium, warm),
    /// whose tint multipliers were 0.7, 1 and 1.35.
    static func migrated(fromGlow raw: String) -> Double? {
        switch raw {
        case "subtle": return standard + log(0.7) / log(4)
        case "medium": return standard
        case "warm": return standard + log(1.35) / log(4)
        default: return nil
        }
    }
}

enum ScheduleMode: String, CaseIterable {
    case always, sunsetToSunrise, sunriseToSunset, customHours

    var title: String {
        switch self {
        case .always: return "Always"
        case .sunsetToSunrise: return "Sunset to Sunrise"
        case .sunriseToSunset: return "Sunrise to Sunset"
        case .customHours: return "Custom Hours"
        }
    }
}
