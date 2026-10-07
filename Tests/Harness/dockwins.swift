// Prints every Dock-owned window (all attributes), on-screen and off.
import CoreGraphics
import Foundation
for opt in [CGWindowListOption.optionOnScreenOnly, .optionAll] {
    print(opt == .optionOnScreenOnly ? "== on screen" : "== all")
    let list = CGWindowListCopyWindowInfo(opt, kCGNullWindowID) as? [[String: Any]] ?? []
    for e in list where (e[kCGWindowOwnerName as String] as? String) == "Dock" {
        print(e.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ").replacingOccurrences(of: "\n", with: ""))
    }
}
