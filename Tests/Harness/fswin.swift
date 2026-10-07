// Window-cover full-screen probe: samples the window server at ~250 Hz for
// <seconds> and measures how well Parchmatte's window covers (layer 0 or 3)
// track a target app's main window through a full-screen enter or exit.
//   uncovered  = the target is on screen but under 90% of it is papered
//   misaligned = papered, but the nearest cover's edges are off by > 2 px
//   stray      = a window cover is on screen over none of the target's windows
//                (left behind, or on the wrong Space)
//   double     = two covers overlap over more than 20% of the target
// Prints state changes with --timeline, then one summary line.
//
// Usage: fswin <app> <seconds> [--timeline]
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : "TextEdit"
let seconds = args.count > 2 ? Double(args[2]) ?? 4 : 4
let verbose = args.contains("--timeline")

func rect(_ e: [String: Any]) -> CGRect {
    CGRect(dictionaryRepresentation: (e[kCGWindowBounds as String] as? NSDictionary) ?? [:]) ?? .zero
}
func fmt(_ r: CGRect) -> String { "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))" }
func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

/// Fraction of `r` covered by the union of `rs`, sampled on an 8 pt grid.
func coverage(_ r: CGRect, by rs: [CGRect]) -> (Double, Double) {
    var hit = 0, twice = 0, total = 0
    var y = r.minY + 4
    while y < r.maxY {
        var x = r.minX + 4
        while x < r.maxX {
            let n = rs.filter { $0.contains(CGPoint(x: x, y: y)) }.count
            total += 1
            if n >= 1 { hit += 1 }
            if n >= 2 { twice += 1 }
            x += 8
        }
        y += 8
    }
    return total == 0 ? (0, 0) : (Double(hit) / Double(total), Double(twice) / Double(total))
}

var displayIDs = [CGDirectDisplayID](repeating: 0, count: 8); var displayCount: UInt32 = 0
CGGetActiveDisplayList(8, &displayIDs, &displayCount)
let displays = displayIDs.prefix(Int(displayCount)).map { CGDisplayBounds($0) }
let start = Date()
var last = "", samples = 0, visible = 0
var tAnim: TimeInterval = 0, tUncovered: TimeInterval = 0, tMisaligned: TimeInterval = 0, tStray: TimeInterval = 0, tDouble: TimeInterval = 0
var longestUncovered: TimeInterval = 0, run: TimeInterval = 0
var maxErr: CGFloat = 0
var prev = Date()
while Date().timeIntervalSince(start) < seconds {
    let now = Date()
    let dt = now.timeIntervalSince(prev)
    prev = now
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    let wins = list.filter {
        ($0[kCGWindowOwnerName as String] as? String) == target && ($0[kCGWindowLayer as String] as? Int) == 0
    }.map(rect).filter { $0.width > 150 && $0.height > 150 }
    let covers = list.filter {
        ($0[kCGWindowOwnerName as String] as? String) == "Parchmatte"
            && [0, 3].contains($0[kCGWindowLayer as String] as? Int ?? -1)
            && ($0[kCGWindowAlpha as String] as? Double ?? 1) > 0.5
    }.map(rect)
    samples += 1
    var state = ""
    // Every app's normal windows: a cover over some other app's window is
    // someone else's cover, not a stray.
    let anyWins = list.filter {
        ($0[kCGWindowOwnerName as String] as? String) != "Parchmatte" && ($0[kCGWindowLayer as String] as? Int) == 0
    }.map(rect)
    let stray = covers.filter { c in !anyWins.contains { area(c.intersection($0)) > area(c) * 0.9 } }
    if !stray.isEmpty { tStray += dt }
    // The app's animation stand-in fills the whole display (notch included);
    // the real window is off screen meanwhile. Covering it is not the goal,
    // so that time is reported separately as animMs. (On a display without
    // a notch a real full-screen window looks the same; use a notch Mac.)
    if let main = wins.max(by: { area($0) < area($1) }), displays.contains(main) {
        tAnim += dt
        state = "anim target=\(fmt(main)) covers=\(covers.map(fmt))"
        if verbose && state != last { print(String(format: "%6.3f ", now.timeIntervalSince(start)) + state); last = state }
        run = 0
        usleep(4_000)
        continue
    }
    if let main = wins.max(by: { area($0) < area($1) }) {
        visible += 1
        let (frac, dbl) = coverage(main, by: covers)
        if dbl > 0.2 { tDouble += dt }
        if frac < 0.9 {
            tUncovered += dt; run += dt; longestUncovered = max(longestUncovered, run)
        } else {
            run = 0
            if let c = covers.min(by: { abs($0.maxY - main.maxY) + abs($0.minX - main.minX) < abs($1.maxY - main.maxY) + abs($1.minX - main.minX) }) {
                let err = max(abs(c.minX - main.minX), abs(c.maxX - main.maxX), abs(c.maxY - main.maxY))
                maxErr = max(maxErr, err)
                if err > 2 { tMisaligned += dt }
            }
        }
        state = String(format: "papered=%3d%% ", Int(frac * 100)) + "target=\(fmt(main))"
    } else {
        run = 0
        state = "target=none"
    }
    state += " covers=\(covers.map(fmt))" + (stray.isEmpty ? "" : " STRAY")
    if verbose && state != last {
        print(String(format: "%6.3f ", now.timeIntervalSince(start)) + state)
        last = state
    }
    usleep(4_000)
}
print("samples=\(samples) visible=\(visible) animMs=\(Int(tAnim * 1000)) uncoveredMs=\(Int(tUncovered * 1000)) longestUncoveredMs=\(Int(longestUncovered * 1000)) misalignedMs=\(Int(tMisaligned * 1000)) maxErrPx=\(Int(maxErr)) strayMs=\(Int(tStray * 1000)) doubleMs=\(Int(tDouble * 1000))")
