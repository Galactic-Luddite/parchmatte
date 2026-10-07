// Full-screen gap probe: samples the window server at ~250 Hz for <seconds>
// and measures how much of the main display's width is papered by visible
// (alpha > 0.5) whole-screen covers. Covers ride Space animations, so a cover
// sliding out at x = -500 still papers the part it overlaps.
//   gap    = under 95% of the width papered (the 64 pt gutter macOS draws
//            between sliding Spaces is about 3% and is not a gap)
//   double = two covers overlap across more than 5% of the width
// Prints state changes with --timeline, then one summary line.
//
// Usage: fsgap <seconds> [--timeline] [--owner NAME]
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let seconds = args.count > 1 ? Double(args[1]) ?? 5 : 5
let verbose = args.contains("--timeline")
let owner = args.firstIndex(of: "--owner").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "Parchmatte"
let main = CGDisplayBounds(CGMainDisplayID())
let start = Date()
var last = "", samples = 0, gaps = 0, doubles = 0
var uncovered: TimeInterval = 0, longest: TimeInterval = 0, doubled: TimeInterval = 0
var gapStart: Date?, doubleStart: Date?, prev = Date()

/// Papered fraction and overlapped fraction of the main display's width.
func coverage(_ spans: [(CGFloat, CGFloat)]) -> (Double, Double) {
    let w = main.width
    var covered: CGFloat = 0, overlap: CGFloat = 0
    let step: CGFloat = 8
    var x = main.minX
    while x < main.maxX {
        let n = spans.filter { $0.0 <= x && x < $0.1 }.count
        if n >= 1 { covered += step }
        if n >= 2 { overlap += step }
        x += step
    }
    return (Double(covered / w), Double(overlap / w))
}

while Date().timeIntervalSince(start) < seconds {
    let now = Date()
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let covers = list.filter {
        ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0
    }
    var spans: [(CGFloat, CGFloat)] = []
    for entry in covers {
        let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
        guard alpha > 0.5, let d = entry[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: d),
              abs(r.minY - main.minY) < 2, r.height >= main.height - 40, r.width >= main.width - 2 else { continue }
        spans.append((r.minX, r.maxX))
    }
    let (frac, over) = coverage(spans)
    samples += 1
    if frac < 0.95 {
        if gapStart == nil { gapStart = now; gaps += 1 }
    } else if let g = gapStart {
        let len = now.timeIntervalSince(g); uncovered += len; longest = max(longest, len); gapStart = nil
    }
    if over > 0.05 {
        if doubleStart == nil { doubleStart = now; doubles += 1 }
    } else if let d = doubleStart {
        doubled += now.timeIntervalSince(d); doubleStart = nil
    }
    if verbose {
        let desc = covers.map { e -> String in
            let b = e[kCGWindowBounds as String] as? [String: Any] ?? [:]
            return "#\(e[kCGWindowNumber as String] ?? 0) a=\(e[kCGWindowAlpha as String] ?? 1) \(b["X"] ?? 0),\(b["Y"] ?? 0)"
        }.joined(separator: " ")
        let state = String(format: "papered=%3d%% double=%3d%% ", Int(frac * 100), Int(over * 100)) + "[\(desc)]"
        if state != last { print(String(format: "%6.3f ", now.timeIntervalSince(start)) + state); last = state }
    }
    prev = now
    usleep(4_000)
}
if let g = gapStart { let len = prev.timeIntervalSince(g); uncovered += len; longest = max(longest, len) }
if let d = doubleStart { doubled += prev.timeIntervalSince(d) }
print("samples=\(samples) gaps=\(gaps) uncoveredMs=\(Int(uncovered * 1000)) longestGapMs=\(Int(longest * 1000)) doubles=\(doubles) doubleMs=\(Int(doubled * 1000))")
