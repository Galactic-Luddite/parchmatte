// Sibling-raise probe: samples the window server for <seconds> and times how
// long the cover over the target app's largest window (A) stays stacked
// above a smaller window of the same app (B) while B is in front of A. A
// lifted cover left there paints over the part of B overlapping A.
// Prints each change of state with --timeline, then one summary line:
//   stale = B in front of A with A's cover still above both
//
// Usage: sibprobe <app> <seconds> [--timeline]
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : "TextEdit"
let seconds = args.count > 2 ? Double(args[2]) ?? 4 : 4
let verbose = args.contains("--timeline")

func rect(_ e: [String: Any]) -> CGRect {
    CGRect(dictionaryRepresentation: (e[kCGWindowBounds as String] as? NSDictionary) ?? [:]) ?? .zero
}
func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

let start = ProcessInfo.processInfo.systemUptime
var samples = 0, raises = 0
var last = "", lastChange = start
var stale: [Double] = []
while ProcessInfo.processInfo.systemUptime - start < seconds {
    let now = ProcessInfo.processInfo.systemUptime
    // Front-to-back order.
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] else { fatalError("window query failed") }
    samples += 1
    let windows = list.enumerated().filter {
        ($0.element[kCGWindowOwnerName as String] as? String) == target
            && ($0.element[kCGWindowLayer as String] as? Int) == 0
            && rect($0.element).width > 150 && rect($0.element).height > 150
    }
    var state = "no-pair"
    if windows.count >= 2, let a = windows.max(by: { area(rect($0.element)) < area(rect($1.element)) }),
       let b = windows.first(where: { $0.offset != a.offset }) {
        let ra = rect(a.element)
        let cover = list.enumerated().first {
            ($0.element[kCGWindowOwnerName as String] as? String) == "Parchmatte"
                && area(rect($0.element).intersection(ra)) > area(ra) * 0.8
        }
        let front = b.offset < a.offset ? "B" : "A"
        if let cover {
            let layer = cover.element[kCGWindowLayer as String] as? Int ?? -1
            let place = cover.offset < min(a.offset, b.offset) ? "top"
                : cover.offset < max(a.offset, b.offset) ? "mid" : "low"
            state = "front=\(front) cover=\(place) layer=\(layer)"
        } else {
            state = "front=\(front) cover=none"
        }
    }
    if state != last {
        if last.hasPrefix("front=B cover=top") { stale.append((now - lastChange) * 1000) }
        if state.hasPrefix("front=B"), !last.hasPrefix("front=B") { raises += 1 }
        if verbose { print(String(format: "%8.3f  %@", now - start, state)) }
        last = state
        lastChange = now
    }
    usleep(2000)
}
stale.sort()
let median = stale.isEmpty ? 0 : stale[stale.count / 2]
print(String(format: "sibling raises %d, stale %d, max %.0f ms, median %.0f ms, samples %d",
             raises, stale.count, stale.last ?? 0, median, samples))
