// Checks whether a target app's frontmost on-screen window has a matching
// Parchmatte cover. Prints one line and exits 0 on match, 1 when uncovered
// or misaligned, 2 when the target has no on-screen window.
//
// Usage: check_cover <app name> [--expect-none]
//        check_cover <app name> --expect-uncovered [--rect x y width height]
//   --expect-none: succeed only when NO window cover is on screen.
//   --expect-uncovered: succeed when the target window has no matching cover;
//                       unrelated covers are ignored.
//   --rect: use a known target-window rectangle. This lets disappearance tests
//           detect a stale cover after the window is minimized, hidden, or gone.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : "TextEdit"
let expectNone = args.contains("--expect-none")
let expectUncovered = args.contains("--expect-uncovered")
let expectedRect: CGRect? = {
    guard let index = args.firstIndex(of: "--rect"), args.count > index + 4,
          let x = Double(args[index + 1]), let y = Double(args[index + 2]),
          let width = Double(args[index + 3]), let height = Double(args[index + 4])
    else { return nil }
    return CGRect(x: x, y: y, width: width, height: height)
}()

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
func rect(_ e: [String: Any]) -> CGRect {
    CGRect(dictionaryRepresentation: (e[kCGWindowBounds as String] as? NSDictionary) ?? [:]) ?? .zero
}
let normal = list.filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
// Window covers sit at the normal layer, one above it while lifted during an
// app activation, or float (layer 3) over a native full-screen window.
// Whole-screen covers use the overlay layer and are ignored.
let covers = list.filter {
    ($0[kCGWindowOwnerName as String] as? String) == "Parchmatte"
        && [0, 1, 3].contains($0[kCGWindowLayer as String] as? Int ?? -1)
}.map(rect)
let windows = normal.filter {
    ($0[kCGWindowOwnerName as String] as? String) == target && rect($0).width > 150 && rect($0).height > 150
}.map(rect)

func fmt(_ r: CGRect) -> String { "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))" }

if expectNone {
    print(covers.isEmpty ? "PASS no window covers" : "FAIL \(covers.count) cover(s): \(covers.map(fmt))")
    exit(covers.isEmpty ? 0 : 1)
}
let targets = expectedRect.map { [$0] } ?? windows
guard let win = targets.first else { print("NOWINDOW \(target) covers=\(covers.map(fmt))"); exit(2) }
func aligns(_ cover: CGRect, _ window: CGRect) -> Bool {
    max(abs(cover.minX - window.minX), abs(cover.maxX - window.maxX), abs(cover.maxY - window.maxY)) <= 2
}
let aligned = covers.first { cover in
    targets.contains { aligns(cover, $0) }
}
if expectUncovered {
    print(aligned == nil ? "PASS target uncovered" : "FAIL target still covered: \(fmt(aligned!))")
    exit(aligned == nil ? 0 : 1)
}
// A cover may extend upward over a docked tab strip; compare left, right, bottom.
let best = covers.min { a, b in
    abs(a.minX - win.minX) + abs(a.maxY - win.maxY) < abs(b.minX - win.minX) + abs(b.maxY - win.maxY)
}
guard let cover = best else { print("FAIL uncovered window \(fmt(win))"); exit(1) }
let err = max(abs(cover.minX - win.minX), abs(cover.maxX - win.maxX), abs(cover.maxY - win.maxY))
if err <= 2 {
    print("PASS window \(fmt(win)) cover \(fmt(cover))")
    exit(0)
}
print("FAIL misaligned by \(Int(err))px window \(fmt(win)) cover \(fmt(cover))")
exit(1)
