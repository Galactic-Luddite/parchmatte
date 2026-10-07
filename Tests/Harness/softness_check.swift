// Softness continuity check: renders a texture at softness steps 0, 1 and 2
// through the same Core Image pipeline the app uses, and compares each to
// the source PNG. Step 0 must equal the source; neighbouring steps must be
// close, so the slider never jumps.
//
// Usage: swift Tests/Harness/softness_check.swift Sources/Parchmatte/Textures/matte.png
import AppKit
import CoreImage

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Sources/Parchmatte/Textures/matte.png"
guard let nsImage = NSImage(contentsOfFile: path),
      let source = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("cannot load \(path)")
}
let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

func render(step: Int) -> CGImage {
    let amount = Double(step) / 20
    let extent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
    let tile = CIImage(cgImage: source, options: [.colorSpace: NSNull()])
    var img = tile
    for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
        img = tile.transformed(by: CGAffineTransform(translationX: CGFloat(dx) * extent.width,
                                                     y: CGFloat(dy) * extent.height)).composited(over: img)
    } }
    if amount > 0 {
        img = img.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: amount * 1.2])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(1 + amount * 1.6)),
            ])
    }
    return context.createCGImage(img.cropped(to: extent), from: extent, format: .RGBA8,
                                 colorSpace: source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)!
}

func rgba(_ image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let ctx = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return data
}

func meanDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
    zip(a, b).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) } / Double(a.count)
}

func meanAlpha(_ a: [UInt8]) -> Double {
    stride(from: 3, to: a.count, by: 4).reduce(0.0) { $0 + Double(a[$1]) } / Double(a.count / 4)
}

let src = rgba(source)
// Diagnose a sub-pixel or whole-pixel offset between the pipeline and the file.
do {
    let s0 = rgba(render(step: 0))
    let w = source.width, h = source.height
    var best = (dx: 0, dy: 0, d: Double.infinity)
    for dy in -2...2 { for dx in -2...2 {
        var total = 0.0
        for y in 0..<h { for x in 0..<w {
            let a = (y * w + x) * 4 + 3
            let b = (((y + dy + h) % h) * w + (x + dx + w) % w) * 4 + 3
            total += abs(Double(s0[a]) - Double(src[b]))
        } }
        let d = total / Double(w * h)
        if d < best.d { best = (dx, dy, d) }
    } }
    print(String(format: "best alignment dx=%d dy=%d alphaDiff=%.3f", best.dx, best.dy, best.d))
    var flipped = 0.0
    for y in 0..<h { for x in 0..<w {
        flipped += abs(Double(s0[(y * w + x) * 4 + 3]) - Double(src[((h - 1 - y) * w + x) * 4 + 3]))
    } }
    print(String(format: "vertical flip alphaDiff=%.3f", flipped / Double(w * h)))
}
let s0 = rgba(render(step: 0)), s1 = rgba(render(step: 1)), s2 = rgba(render(step: 2))
print(String(format: "source vs step0: %.3f   step0 vs step1: %.3f   step1 vs step2: %.3f",
             meanDiff(src, s0), meanDiff(s0, s1), meanDiff(s1, s2)))
print(String(format: "mean alpha  source %.1f  step0 %.1f  step1 %.1f  step2 %.1f",
             meanAlpha(src), meanAlpha(s0), meanAlpha(s1), meanAlpha(s2)))

// Assertions: step 0 must reproduce the source, and neighbouring steps must
// stay close (0.70 and 0.74 when last tuned), so the slider never jumps.
var failures: [String] = []
if meanDiff(src, s0) > 0.5 { failures.append("step 0 differs from the source") }
if meanDiff(s0, s1) > 2.0 { failures.append("step 0 -> 1 jumps") }
if meanDiff(s1, s2) > 2.0 { failures.append("step 1 -> 2 jumps") }
if failures.isEmpty {
    print("softness: PASS")
} else {
    print("softness: FAIL " + failures.joined(separator: "; "))
    exit(1)
}
