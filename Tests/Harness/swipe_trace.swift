// Records public CGWindow metadata for excluded-app Space swipe analysis.
// Output is JSON Lines. This probe does not infer Space identity or display frames.
import CoreGraphics
import Dispatch
import Foundation

struct Bounds: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct Window: Codable {
    let id: Int
    let owner: String
    let ownerPID: Int
    let layer: Int
    let alpha: Double?
    let bounds: Bounds
}

struct Record: Codable {
    let schema: String
    let type: String
    let sequence: Int?
    let monotonicNS: UInt64
    let wallTime: String?
    let wallTimeUnixNS: UInt64?
    let monotonicOriginNS: UInt64?
    let anchorUncertaintyNS: UInt64?
    let requestedIntervalNS: UInt64?
    let windows: [Window]?
}

let arguments = CommandLine.arguments
let duration = arguments.count > 1 ? Double(arguments[1]) ?? .nan : 8.0
let requestedHz = arguments.count > 2 ? Double(arguments[2]) ?? .nan : 120.0
guard duration.isFinite, requestedHz.isFinite,
      duration > 0, duration <= 3_600,
      requestedHz >= 1, requestedHz <= 500 else {
    fputs("usage: swipe_trace.swift [seconds >0 and <=3600] [sample-hz 1...500]\n", stderr)
    exit(2)
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let wallFormatter = ISO8601DateFormatter()
let intervalNS = UInt64(1_000_000_000.0 / requestedHz)
let durationNS = UInt64(duration * 1_000_000_000.0)

func wallNS() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1_000_000_000.0)
}

func emit(_ record: Record) {
    guard let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8) else {
        fputs("failed to encode trace record\n", stderr)
        exit(3)
    }
    print(line)
    fflush(stdout)
}

// Bracket the monotonic read with wall-clock reads. Their midpoint is the
// origin estimate; half the bracket width is the minimum anchor uncertainty.
let wallBefore = wallNS()
let monotonicOrigin = DispatchTime.now().uptimeNanoseconds
let wallAfter = wallNS()
let wallOrigin = wallBefore + (wallAfter - wallBefore) / 2
let anchorDate = Date(timeIntervalSince1970: Double(wallOrigin) / 1_000_000_000.0)

emit(Record(
    schema: "parchmatte.swipe-trace.v1", type: "header", sequence: nil,
    monotonicNS: monotonicOrigin, wallTime: wallFormatter.string(from: anchorDate),
    wallTimeUnixNS: wallOrigin, monotonicOriginNS: monotonicOrigin,
    anchorUncertaintyNS: (wallAfter - wallBefore) / 2,
    requestedIntervalNS: intervalNS, windows: nil
))

var sequence = 0
while DispatchTime.now().uptimeNanoseconds - monotonicOrigin < durationNS {
    let timestamp = DispatchTime.now().uptimeNanoseconds
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    let windows = list.compactMap { entry -> Window? in
        guard let owner = entry[kCGWindowOwnerName as String] as? String,
              owner == "Parchmatte",
              let id = entry[kCGWindowNumber as String] as? Int,
              let ownerPID = entry[kCGWindowOwnerPID as String] as? Int,
              let layer = entry[kCGWindowLayer as String] as? Int,
              let rawBounds = entry[kCGWindowBounds as String] as? [String: Any]
        else { return nil }
        func number(_ key: String) -> Double? { (rawBounds[key] as? NSNumber)?.doubleValue }
        guard let x = number("X"), let y = number("Y"),
              let width = number("Width"), let height = number("Height"),
              x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              abs(x) <= 1_000_000, abs(y) <= 1_000_000,
              width > 0, height > 0, width <= 1_000_000, height <= 1_000_000
        else { return nil }
        let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue
        return Window(
            id: id, owner: owner, ownerPID: ownerPID, layer: layer, alpha: alpha,
            bounds: Bounds(x: x, y: y, width: width, height: height)
        )
    }.sorted { $0.id < $1.id }
    emit(Record(
        schema: "parchmatte.swipe-trace.v1", type: "sample", sequence: sequence,
        monotonicNS: timestamp, wallTime: nil, wallTimeUnixNS: nil,
        monotonicOriginNS: nil, anchorUncertaintyNS: nil,
        requestedIntervalNS: nil, windows: windows
    ))
    sequence += 1
    let target = monotonicOrigin + min(UInt64(sequence) * intervalNS, durationNS)
    let now = DispatchTime.now().uptimeNanoseconds
    if target > now { usleep(useconds_t(min(target - now, UInt64(UInt32.max)) / 1_000)) }
}
