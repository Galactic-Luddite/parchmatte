// Clipped-cover probe: samples the window server at ~250 Hz for <seconds>
// and prints, whenever it changes, the hole list a clipped cover over the
// target app's largest window SHOULD have (every normal window in front of
// it, clipped to the cover, relative to the cover's top-left, sorted), in
// the same format the app logs with the `maskTrace` default. mask_lag.py
// compares the two timelines. Also counts samples where the cover is
// stacked under its window, like actprobe.
//
// Usage: occprobe <app> <seconds>
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : "TextEdit"
let seconds = args.count > 2 ? Double(args[2]) ?? 4 : 4
func rect(_ e: [String: Any]) -> CGRect {
    CGRect(dictionaryRepresentation: (e[kCGWindowBounds as String] as? NSDictionary) ?? [:]) ?? .zero
}
func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
func owner(_ e: [String: Any]) -> String { e[kCGWindowOwnerName as String] as? String ?? "" }
func layer(_ e: [String: Any]) -> Int { e[kCGWindowLayer as String] as? Int ?? -1 }

let start = Date()
var last = "", samples = 0, under = 0
while Date().timeIntervalSince(start) < seconds {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    samples += 1
    let wins = list.enumerated().filter {
        owner($0.element) == target && layer($0.element) == 0
            && rect($0.element).width > 150 && rect($0.element).height > 150
    }
    var line = "none"
    if let main = wins.max(by: { area(rect($0.element)) < area(rect($1.element)) }) {
        let r = rect(main.element)
        if let c = list.enumerated().first(where: {
            owner($0.element) == "Parchmatte" && (0...3).contains(layer($0.element))
                && area(rect($0.element).intersection(r)) > area(r) * 0.8
        }) {
            if c.offset > main.offset { under += 1 }
            let cr = rect(c.element)
            let holes = list[..<main.offset].filter {
                layer($0) == 0 && owner($0) != "Parchmatte" && rect($0).intersects(cr)
            }.map { e -> String in
                let h = rect(e).intersection(cr).offsetBy(dx: -cr.minX, dy: -cr.minY).integral
                return "\(Int(h.minX)),\(Int(h.minY)),\(Int(h.width)),\(Int(h.height))"
            }.sorted().joined(separator: ";")
            line = "holes=\(holes)"
        } else { line = "gone" }
    }
    if line != last {
        print(String(format: "probe t=%.4f ", Date().timeIntervalSince1970) + line)
        last = line
    }
    usleep(4_000)
}
print("samples=\(samples) under=\(under)")
