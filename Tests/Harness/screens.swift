// Prints each display: name, AppKit frame, and backing scale.
import AppKit

for (i, s) in NSScreen.screens.enumerated() {
    let f = s.frame
    print("\(i) \(s.localizedName) frame=\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)) scale=\(s.backingScaleFactor)")
}
