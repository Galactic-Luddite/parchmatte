// Texture preview: composites a texture tile (tiled 2x2) over a plain page at
// a chosen strength and writes a zoomed PNG, for judging the look by eye.
//
// Usage: swift Tests/Harness/preview_texture.swift <texture.png> <out.png> [opacity] [zoom] [white|dark]
import AppKit

let args = CommandLine.arguments
guard args.count >= 3, let tile = NSImage(contentsOfFile: args[1]),
      let cg = tile.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("usage: preview_texture.swift <texture.png> <out.png> [opacity] [zoom] [white|dark]")
}
let opacity = args.count > 3 ? CGFloat(Double(args[3]) ?? 0.6) : 0.6
let zoom = args.count > 4 ? Int(args[4]) ?? 3 : 3
let dark = args.count > 5 && args[5] == "dark"

let w = cg.width * 2, h = cg.height * 2
let ctx = CGContext(data: nil, width: w * zoom, height: h * zoom, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .none
ctx.setFillColor(dark ? CGColor(srgbRed: 0.16, green: 0.17, blue: 0.2, alpha: 1) : CGColor(gray: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: w * zoom, height: h * zoom))
ctx.setAlpha(opacity)
for ty in 0..<2 { for tx in 0..<2 {
    ctx.draw(cg, in: CGRect(x: tx * cg.width * zoom, y: ty * cg.height * zoom,
                            width: cg.width * zoom, height: cg.height * zoom))
} }
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
