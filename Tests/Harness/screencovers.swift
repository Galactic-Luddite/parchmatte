// Screen-cover probe: samples ~120 Hz and prints each change in how many of
// Parchmatte's whole-screen covers are on screen and where.
//
// Usage: swift Tests/Harness/screencovers.swift <seconds>
import CoreGraphics
import Foundation

let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 5 : 5
let start = Date()
var last = ""
var samples = 0, gaps = 0
while Date().timeIntervalSince(start) < seconds {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let covers = list.filter {
        ($0[kCGWindowOwnerName as String] as? String) == "Parchmatte" && ($0[kCGWindowLayer as String] as? Int ?? 0) > 0
    }.map { entry -> String in
        let b = entry[kCGWindowBounds as String] as? [String: Any] ?? [:]
        return "\(b["X"] ?? 0),\(b["Y"] ?? 0) \(b["Width"] ?? 0)x\(b["Height"] ?? 0)"
    }.sorted()
    samples += 1
    let state = "\(covers.count) \(covers)"
    if state != last {
        print(String(format: "%6.3f ", Date().timeIntervalSince(start)) + state)
        last = state
    }
    usleep(8_000)
}
print("samples=\(samples)")
