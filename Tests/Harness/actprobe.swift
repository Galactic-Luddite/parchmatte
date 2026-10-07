// Window-cover activation probe: samples the window server at ~250 Hz for
// <seconds> and counts samples where the target app's largest window is on
// screen but its cover is not painting over it:
//   gone   = no Parchmatte cover on screen over the window
//   faded  = the cover is on screen but its alpha is under 0.5
//   under  = the cover is on screen but stacked below the window
// A "blink" is one run of consecutive bad samples. Prints each blink with
// --timeline, then one summary line.
//
// Usage: actprobe <app> <seconds> [--timeline] [--assert-covered]
// Optional exact identity: --pid=N --window=N --cover-pid=N --cover-window=N --neighbor=N.
// --jsonl=PATH retains every sampled ordering state for latency comparisons.
import CoreGraphics
import Foundation

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : "TextEdit"
let seconds = args.count > 2 ? Double(args[2]) ?? 4 : 4
let verbose = args.contains("--timeline")
func argument(_ name: String) -> String? {
    let prefix = "--\(name)="
    return args.first(where: { $0.hasPrefix(prefix) }).map { String($0.dropFirst(prefix.count)) }
}
func number(_ name: String) -> Int? {
    guard let value = argument(name) else { return nil }
    guard let result = Int(value), result > 0 else { fatalError("invalid --\(name)") }
    return result
}
let targetPID = number("pid"), targetID = number("window")
let coverPID = number("cover-pid"), neighborID = number("neighbor")
let coverID = number("cover-window")
var output: FileHandle?
if let path = argument("jsonl") {
    guard FileManager.default.createFile(atPath: path, contents: nil) else { fatalError("cannot create sample log") }
    output = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
}

func rect(_ e: [String: Any]) -> CGRect {
    CGRect(dictionaryRepresentation: (e[kCGWindowBounds as String] as? NSDictionary) ?? [:]) ?? .zero
}
func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }

let start = Date()
var samples = 0, bad = 0, blinks = 0, inBlink = false, blinkStart = Date(), longest: TimeInterval = 0
var kinds: [String: Int] = [:]
var targetSamples = 0, missingTargetSamples = 0
while Date().timeIntervalSince(start) < seconds {
    let now = Date()
    // Front-to-back order.
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] else { fatalError("window query failed") }
    samples += 1
    let candidates = list.enumerated().filter { indexed in
        let entry = indexed.element
        return (targetPID.map { (entry[kCGWindowOwnerPID as String] as? Int) == $0 }
            ?? ((entry[kCGWindowOwnerName as String] as? String) == target))
            && (targetID.map { (entry[kCGWindowNumber as String] as? Int) == $0 } ?? true)
            && (entry[kCGWindowLayer as String] as? Int) == 0
            && rect(entry).width > 150 && rect(entry).height > 150
    }
    var kind = ""
    var state: [String: Any] = ["t": ProcessInfo.processInfo.systemUptime, "targetPresent": false]
    if let main = candidates.max(by: { area(rect($0.element)) < area(rect($1.element)) }) {
        targetSamples += 1
        state["targetPresent"] = true
        state["targetIndex"] = main.offset
        let r = rect(main.element)
        let cover = list.enumerated().first { indexed in
            let entry = indexed.element
            return (coverPID.map { (entry[kCGWindowOwnerPID as String] as? Int) == $0 }
                    ?? ((entry[kCGWindowOwnerName as String] as? String) == "Parchmatte"))
                && (coverID.map { (entry[kCGWindowNumber as String] as? Int) == $0 } ?? true)
                && (0...3).contains(entry[kCGWindowLayer as String] as? Int ?? -1)
                && area(rect(entry).intersection(r)) > area(r) * 0.8
        }
        if let c = cover {
            state["coverIndex"] = c.offset
            state["coverLayer"] = c.element[kCGWindowLayer as String] ?? -1
            if (c.element[kCGWindowAlpha as String] as? Double ?? 1) < 0.5 { kind = "faded" }
            else if c.offset > main.offset { kind = "under" }
            if let neighborID, let neighbor = list.enumerated().first(where: {
                ($0.element[kCGWindowNumber as String] as? Int) == neighborID
            }) {
                state["neighborAboveTarget"] = neighbor.offset < main.offset
                state["coverAboveNeighbor"] = c.offset < neighbor.offset
                state["overlap"] = area(r.intersection(rect(neighbor.element)))
            }
        } else { kind = "gone" }
    } else {
        missingTargetSamples += 1
    }
    state["kind"] = kind
    if let output {
        let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        try output.write(contentsOf: data + Data([10]))
    }
    if !kind.isEmpty {
        bad += 1
        kinds[kind, default: 0] += 1
        if !inBlink { inBlink = true; blinkStart = now; blinks += 1 }
    } else if inBlink {
        inBlink = false
        let len = now.timeIntervalSince(blinkStart)
        longest = max(longest, len)
        if verbose { print(String(format: "%.3f blink %.0f ms", blinkStart.timeIntervalSince1970, len * 1000)) }
    }
    usleep(4_000)
}
if inBlink {
    let len = Date().timeIntervalSince(blinkStart)
    longest = max(longest, len)
    if verbose { print(String(format: "%.3f blink %.0f ms (at end)", blinkStart.timeIntervalSince1970, len * 1000)) }
}
try output?.close()
let k = kinds.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
print("samples=\(samples) targetSamples=\(targetSamples) missingTargetSamples=\(missingTargetSamples) badSamples=\(bad) blinks=\(blinks) longestMs=\(Int(longest * 1000)) \(k)")
if args.contains("--assert-covered"), bad > 0 || targetSamples == 0 || missingTargetSamples > 0 { exit(1) }
