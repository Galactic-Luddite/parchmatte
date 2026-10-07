// Cover probe: samples the window server at ~120 Hz and reports frames where a
// target app's main window is on screen but Parchmatte's cover over it is
// missing or misaligned.
//
// Usage: swift Tests/Harness/probe.swift <target app name> <seconds>
// Prints one summary line: samples, visible, uncovered (no cover, or only
// faded ones under alpha 0.5), behind (cover stacked under the window),
// misaligned, max error.
import CoreGraphics
import CoreVideo
import Foundation

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : "Ghostty"
let seconds = args.count > 2 ? Double(args[2]) ?? 5 : 5

struct Win { let owner: String; let rect: CGRect; let alpha: Double; let layer: Int }

func sample() -> [Win] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return list.compactMap { entry in
        // Covers sit at the normal layer, one above it while lifted during
        // an app activation (about 600 ms), or float (3) over full screen.
        let layer = entry[kCGWindowLayer as String] as? Int ?? -1
        guard let owner = entry[kCGWindowOwnerName as String] as? String,
              layer == 0 || (owner == "Parchmatte" && (layer == 1 || layer == 3)),
              let dict = entry[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: dict) else { return nil }
        return Win(owner: owner, rect: rect, alpha: entry[kCGWindowAlpha as String] as? Double ?? 1, layer: layer)
    }
}

let verbose = CommandLine.arguments.contains("--timeline")
// --vsync: one sample per display refresh, taken when the display link
// fires (the state about to be composited), instead of every 8 ms. A gap
// that opens and closes inside one frame is never drawn, so this mode
// reports what the screen shows rather than what the window server held.
let vsync = CommandLine.arguments.contains("--vsync")
let frameSemaphore = DispatchSemaphore(value: 0)
var displayLink: CVDisplayLink?
if vsync {
    CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
    if let displayLink {
        CVDisplayLinkSetOutputHandler(displayLink) { _, _, _, _, _ in frameSemaphore.signal(); return kCVReturnSuccess }
        CVDisplayLinkStart(displayLink)
    }
}
var lastState = ""
func describe(_ r: CGRect?) -> String {
    guard let r else { return "none" }
    return "\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height))"
}

var samples = 0, visible = 0, uncovered = 0, misaligned = 0, behind = 0
var maxError: CGFloat = 0
let start = Date()
let end = Date().addingTimeInterval(seconds)
while Date() < end {
    let wins = sample()
    samples += 1
    if verbose {
        let mains = wins.filter { $0.owner == target && $0.rect.height > 150 }.map { describe($0.rect) }
        let covers = wins.filter { $0.owner == "Parchmatte" }.map { describe($0.rect) + ($0.alpha < 0.5 ? " faded" : "") }
        let state = "target=\(mains) covers=\(covers)"
        if state != lastState {
            print(String(format: "%6.3f ", Date().timeIntervalSince(start)) + state)
            lastState = state
        }
    }
    // The target's main window: its largest on-screen normal window.
    if let main = wins.filter({ $0.owner == target }).max(by: { $0.rect.height < $1.rect.height }),
       main.rect.height > 150 {
        visible += 1
        let covers = wins.filter { $0.owner == "Parchmatte" && $0.alpha >= 0.5 }
        // The cover may extend upward over a docked tab strip, so compare the
        // left, right and bottom edges.
        if let cover = covers.min(by: {
            abs($0.rect.maxY - main.rect.maxY) + abs($0.rect.minX - main.rect.minX)
                < abs($1.rect.maxY - main.rect.maxY) + abs($1.rect.minX - main.rect.minX)
        }) {
            let err = max(abs(cover.rect.minX - main.rect.minX), abs(cover.rect.maxX - main.rect.maxX),
                          abs(cover.rect.maxY - main.rect.maxY))
            maxError = max(maxError, err)
            if err > 2 { misaligned += 1 }
            // The list is front to back: a cover listed after its window at
            // the same layer is under it, so the window shows bare.
            if cover.layer == main.layer,
               let wi = wins.firstIndex(where: { $0.owner == target && $0.rect == main.rect }),
               let ci = wins.firstIndex(where: { $0.owner == "Parchmatte" && $0.rect == cover.rect }), ci > wi {
                behind += 1
                if verbose { print(String(format: "%6.3f behind", Date().timeIntervalSince(start))) }
            }
        } else {
            uncovered += 1
        }
    }
    if vsync { _ = frameSemaphore.wait(timeout: .now() + 0.05) } else { usleep(8_000) }
}
print("samples=\(samples) visible=\(visible) uncovered=\(uncovered) behind=\(behind) misaligned=\(misaligned) maxErrorPx=\(Int(maxError))")
