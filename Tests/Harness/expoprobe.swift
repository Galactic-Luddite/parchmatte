// Exposé / Mission Control probe: samples the full window list at ~250 Hz
// for <seconds> and prints a line whenever the Dock's or WindowManager's
// windows, the target app's normal windows, or Parchmatte's windows change
// (layer, bounds, alpha, on-screen). Used to find the window-list signal for App Exposé.
//
// Usage: expoprobe <app> <seconds>
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : "TextEdit"
let seconds = args.count > 2 ? Double(args[2]) ?? 4 : 4

func rect(_ e: [String: Any]) -> CGRect {
    CGRect(dictionaryRepresentation: (e[kCGWindowBounds as String] as? NSDictionary) ?? [:]) ?? .zero
}
func r(_ c: CGRect) -> String { String(format: "%.0f,%.0f %.0fx%.0f", c.minX, c.minY, c.width, c.height) }

let start = Date()
var last: [String] = []
while Date().timeIntervalSince(start) < seconds {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    var lines: [String] = []
    for (i, e) in list.enumerated() {
        let owner = e[kCGWindowOwnerName as String] as? String ?? "?"
        let layer = e[kCGWindowLayer as String] as? Int ?? -99
        guard owner == "Dock" || owner == "WindowManager" || owner == "Parchmatte" || (owner == target && layer == 0) else { continue }
        let name = e[kCGWindowName as String] as? String ?? ""
        let alpha = e[kCGWindowAlpha as String] as? Double ?? -1
        let id = e[kCGWindowNumber as String] as? Int ?? 0
        lines.append("  #\(i) \(owner) id=\(id) L=\(layer) a=\(String(format: "%.2f", alpha)) \(r(rect(e))) '\(name)'")
    }
    if lines != last {
        print(String(format: "t=%.3f n=%d", Date().timeIntervalSince(start), list.count))
        lines.forEach { print($0) }
        last = lines
    }
    usleep(4000)
}
