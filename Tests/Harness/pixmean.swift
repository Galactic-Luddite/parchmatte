// Mean colour of a screen region: captures it with screencapture (so the
// covers must not be hidden from screenshots) and prints "R G B" as 0-255.
//
// Usage: pixmean <x> <y> <w> <h>     (points, top-left origin)
import AppKit
import Foundation

let a = CommandLine.arguments
guard a.count == 5 else { print("usage: pixmean x y w h"); exit(2) }
let path = NSTemporaryDirectory() + "pixmean-\(getpid()).png"
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
task.arguments = ["-x", "-R", "\(a[1]),\(a[2]),\(a[3]),\(a[4])", path]
try task.run()
task.waitUntilExit()
guard let image = NSImage(contentsOfFile: path),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("capture failed"); exit(1) }
try? FileManager.default.removeItem(atPath: path)
let w = cg.width, h = cg.height
var data = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
var r = 0.0, g = 0.0, b = 0.0
for i in stride(from: 0, to: data.count, by: 4) {
    r += Double(data[i]); g += Double(data[i + 1]); b += Double(data[i + 2])
}
let n = Double(w * h)
print(String(format: "%.0f %.0f %.0f", r / n, g / n, b / n))
