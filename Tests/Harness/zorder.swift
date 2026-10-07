// Prints the on-screen windows of the named apps (plus Parchmatte's
// covers) front to back, one per line: "<index> <owner> <layer> <x>,<y> <w>x<h>".
// Only layer 0 windows and Parchmatte's covers (layers 0, 1 and 3), so the
// order shows what is stacked over what.
//
// Usage: zorder <app name>...
import CoreGraphics
import Foundation

let apps = Set(CommandLine.arguments.dropFirst())
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    as? [[String: Any]] ?? []
var index = 0
for entry in list {
    guard let owner = entry[kCGWindowOwnerName as String] as? String,
          let layer = entry[kCGWindowLayer as String] as? Int,
          let dict = entry[kCGWindowBounds as String] as? NSDictionary,
          let r = CGRect(dictionaryRepresentation: dict) else { continue }
    let cover = owner == "Parchmatte" && [0, 1, 3].contains(layer)
    guard cover || (layer == 0 && apps.contains(owner)) else { continue }
    print("\(index) \(owner) \(layer) \(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))")
    index += 1
}
