// Lists Parchmatte's on-screen covers and a target app's on-screen windows,
// one per line, for scripted assertions.
//
// Usage: swift Tests/Harness/covers.swift <target app name>
import CoreGraphics
import Foundation

let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "TextEdit"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
var covers = 0
for entry in list {
    let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
    // Covers: normal layer, 1 while lifted during an activation, 3 over full screen.
    let layer = entry[kCGWindowLayer as String] as? Int ?? -1
    guard (owner == target && layer == 0) || (owner == "Parchmatte" && [0, 1, 3].contains(layer)) else { continue }
    let b = entry[kCGWindowBounds as String] as? [String: Any] ?? [:]
    if owner == "Parchmatte" { covers += 1 }
    print(owner, entry[kCGWindowNumber as String] ?? 0, "\(b["X"] ?? 0),\(b["Y"] ?? 0) \(b["Width"] ?? 0)x\(b["Height"] ?? 0)")
}
print("windowCovers=\(covers)")
