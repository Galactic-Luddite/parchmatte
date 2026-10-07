// Decode the owned activation fixture recordings without third-party tools.
// These fixed patches match activation_relation_trial's capture rectangle.
// A bare target patch is a failure signal, not a complete visual acceptance test.
import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import Foundation

private struct Patch {
    let x: Int, y: Int, width: Int, height: Int
}

private struct Measurement {
    let mean: Double, deviation: Double, redMinusGreen: Double
    var bare: Bool { mean > 240 && deviation < 1 }
    // Calibrated against the native-child control: Denim over white at
    // 40% has mean ~250 and deviation ~5, rather than a dark mean <240.
    var paper: Bool { mean > 100 && mean < 254 && deviation > 2 }
}

private func failure(_ message: String) -> NSError {
    NSError(domain: "Parchmatte.ActivationFrames", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
}

private func measure(_ buffer: CVPixelBuffer, patch: Patch) throws -> Measurement {
    guard patch.x >= 0, patch.y >= 0,
          patch.x + patch.width <= CVPixelBufferGetWidth(buffer),
          patch.y + patch.height <= CVPixelBufferGetHeight(buffer),
          CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else {
        throw failure("patch or pixel format does not match the fixture recording")
    }
    guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
        throw failure("cannot lock decoded frame")
    }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let address = CVPixelBufferGetBaseAddress(buffer) else { throw failure("no decoded pixels") }
    let bytes = address.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    var sum = 0.0, square = 0.0, redMinusGreen = 0.0
    for y in patch.y ..< patch.y + patch.height {
        for x in patch.x ..< patch.x + patch.width {
            let offset = y * stride + x * 4
            let value = (Double(bytes[offset]) + Double(bytes[offset + 1]) + Double(bytes[offset + 2])) / 3
            sum += value; square += value * value
            redMinusGreen += Double(bytes[offset + 2]) - Double(bytes[offset + 1])
        }
    }
    let count = Double(patch.width * patch.height)
    let mean = sum / count
    return Measurement(mean: mean, deviation: sqrt(max(0, square / count - mean * mean)),
                       redMinusGreen: redMinusGreen / count)
}

@main private struct ActivationFrameStats {
    static func main() async throws {
        let args = CommandLine.arguments
        guard (4 ... 5).contains(args.count) else {
            throw failure("input.mp4 output.csv summary.json [preview-directory]")
        }
        for path in args[2 ... 3] where FileManager.default.fileExists(atPath: path) {
            throw failure("refusing to overwrite \(path)")
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw failure("recording has no video track")
        }
        let duration = try await asset.load(.duration).seconds
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw failure("cannot add video decoder") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? failure("decoder did not start") }
        let csvURL = URL(fileURLWithPath: args[2])
        guard FileManager.default.createFile(atPath: csvURL.path, contents: nil) else {
            throw failure("cannot create CSV")
        }
        let csv = try FileHandle(forWritingTo: csvURL)
        defer { try? csv.close() }
        try csv.write(contentsOf: Data("frame,pts,targetMean,targetDeviation,targetBare,overlapMean,overlapDeviation,overlapBare,ownerRedMinusGreen,visibleOwner,overlapFailure\n".utf8))
        let target = Patch(x: 50, y: 200, width: 48, height: 48)
        let overlap = Patch(x: 620, y: 430, width: 48, height: 48)
        let owner = Patch(x: 704, y: 504, width: 16, height: 16)
        let preview = args.count == 5 ? URL(fileURLWithPath: args[4], isDirectory: true) : nil
        if let preview { try FileManager.default.createDirectory(at: preview, withIntermediateDirectories: false) }
        let context = CIContext(options: [.cacheIntermediates: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var count = 0, bare = 0, runs = 0, paper = 0
        var ownerUnknown = 0, missingOverlap = 0, neighborSpill = 0, overlapUnclassified = 0
        var ownerCounts: [String: Int] = [:]
        var first: Double?, last: Double?, began: Double?
        var maxGap = 0.0, longest = 0.0
        var wroteBarePreview = false
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw failure("decoded sample has no image") }
            guard CVPixelBufferGetWidth(buffer) == 1100, CVPixelBufferGetHeight(buffer) == 760 else {
                throw failure("recording must use the fixture's 1100 x 760 capture rectangle")
            }
            let pts = sample.presentationTimeStamp.seconds
            guard pts.isFinite, last.map({ pts > $0 }) ?? true else { throw failure("non-increasing video timestamps") }
            if let last { maxGap = max(maxGap, pts - last) }
            first = first ?? pts; last = pts
            let a = try measure(buffer, patch: target), b = try measure(buffer, patch: overlap)
            let identity = try measure(buffer, patch: owner)
            let visibleOwner = identity.redMinusGreen > 50 ? "target" : (identity.redMinusGreen < -50 ? "neighbor" : "unknown")
            ownerCounts[visibleOwner, default: 0] += 1
            var overlapFailure = ""
            if visibleOwner == "unknown" { ownerUnknown += 1 }
            else if !b.bare && !b.paper { overlapUnclassified += 1 }
            else if visibleOwner == "target" && b.bare { missingOverlap += 1; overlapFailure = "missing-paper" }
            else if visibleOwner == "neighbor" && b.paper { neighborSpill += 1; overlapFailure = "neighbor-spill" }
            if a.paper { paper += 1 }
            if a.bare {
                bare += 1
                if began == nil { began = pts; runs += 1 }
            } else if let start = began { longest = max(longest, pts - start); began = nil }
            if let preview, count == 0 || (a.bare && !wroteBarePreview) {
                // Export only the blank owned target's interior, no desktop.
                let image = CIImage(cvPixelBuffer: buffer).cropped(to: CGRect(x: 30, y: 410, width: 256, height: 200))
                let name = count == 0 ? "first-target.png" : "first-bare-target.png"
                try context.writePNGRepresentation(of: image, to: preview.appendingPathComponent(name),
                                                   format: .RGBA8, colorSpace: colorSpace, options: [:])
                if a.bare { wroteBarePreview = true }
            }
            let row = String(format: "%d,%.9f,%.6f,%.6f,%d,%.6f,%.6f,%d,%.6f", count, pts,
                             a.mean, a.deviation, a.bare ? 1 : 0, b.mean, b.deviation, b.bare ? 1 : 0,
                             identity.redMinusGreen) + ",\(visibleOwner),\(overlapFailure)\n"
            try csv.write(contentsOf: Data(row.utf8))
            count += 1
        }
        guard reader.status == .completed, count > 0, let first, let last else {
            throw reader.error ?? failure("decoder ended without a complete nonempty video")
        }
        if let start = began { longest = max(longest, duration - start) }
        let summary: [String: Any] = ["frames": count, "firstPTS": first, "lastPTS": last,
                                     "assetDuration": duration, "maxEncodedFrameGapMs": maxGap * 1000,
                                     "finalFrameHoldMs": max(0, duration - last) * 1000,
                                     "bareTargetFrames": bare, "bareTargetRuns": runs,
                                     "paperReferenceFrames": paper, "unclassifiedTargetFrames": count - paper - bare,
                                     "visibleOwnerFrames": ownerCounts, "unknownOwnerFrames": ownerUnknown,
                                     "missingOverlapPaperFrames": missingOverlap, "neighborSpillFrames": neighborSpill,
                                     "unclassifiedOverlapFrames": overlapUnclassified,
                                     "longestBareMs": longest * 1000,
                                     "scope": "fixture patches and owned owner marker; variable-rate encoded images hold until the next timestamp; missing marker leaves overlap unqualified; does not prove whole-window correctness"]
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: URL(fileURLWithPath: args[3]))
        FileHandle.standardOutput.write(data + Data([10]))
    }
}
