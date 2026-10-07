// Private diagnostic recording of the owned activation fixture. macOS 15+.
// This executable stays outside the product; it never requests permissions.
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

private func fail(_ message: String) -> NSError {
    NSError(domain: "Parchmatte.ActivationCapture", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
}

private final class Meter: NSObject, SCStreamOutput {
    // Accessed only on the capture sample queue, including final readback.
    var count = 0
    var complete = 0
    var first: Double?
    var firstComplete: Double?
    var last: Double?
    var maxGap = 0.0
    var statuses: [String: Int] = [:]
    var error: String?
    let log: FileHandle

    init(url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path),
              FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw fail("cannot create new sample log")
        }
        log = try FileHandle(forWritingTo: url)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid else { return }
        let pts = sample.presentationTimeStamp.seconds
        guard let rows = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]], let row = rows.first,
              let raw = row[.status] as? Int, let status = SCFrameStatus(rawValue: raw), pts.isFinite else {
            error = "missing frame-status attachment or timestamp"; return
        }
        if let last { maxGap = max(maxGap, pts - last) }
        first = first ?? pts; last = pts; count += 1
        statuses[String(raw), default: 0] += 1
        if status == .complete { complete += 1; firstComplete = firstComplete ?? pts }
        let record: [String: Any] = ["t": ProcessInfo.processInfo.systemUptime, "pts": pts,
                                     "status": raw, "complete": status == .complete,
                                     "displayTime": row[.displayTime] ?? NSNull()]
        do {
            try log.write(contentsOf: JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) + Data([10]))
        } catch { self.error = String(describing: error) }
    }
}

private final class Recording: NSObject, SCRecordingOutputDelegate {
    private let lock = NSLock()
    private var started = false
    private var finished = false
    private var error: String?

    func recordingOutputDidStartRecording(_ output: SCRecordingOutput) {
        lock.lock(); defer { lock.unlock() }; started = true
    }
    func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) {
        lock.lock(); defer { lock.unlock() }; finished = true
    }
    func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: Error) {
        lock.lock(); defer { lock.unlock() }; self.error = String(describing: error); finished = true
    }
    func snapshot() -> (started: Bool, finished: Bool, error: String?) {
        lock.lock(); defer { lock.unlock() }; return (started, finished, error)
    }
}

@main private struct ActivationCapture {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 7, let seconds = Double(args[2]), seconds > 0,
              let x = Double(args[3]), let y = Double(args[4]),
              let width = Int(args[5]), let height = Int(args[6]), width > 0, height > 0 else {
            throw fail("out.mp4 seconds x y width height")
        }
        guard CGPreflightScreenCaptureAccess() else { throw fail("screen recording permission is absent") }
        let url = URL(fileURLWithPath: args[1])
        let base = url.deletingPathExtension()
        let readyURL = base.appendingPathExtension("ready.json")
        for path in [url.path, readyURL.path] where FileManager.default.fileExists(atPath: path) {
            throw fail("refusing to overwrite " + path)
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let rectangle = CGRect(x: x, y: y, width: Double(width), height: Double(height))
        guard let display = content.displays.first(where: { $0.frame.contains(rectangle) }) else {
            throw fail("capture rectangle is not wholly on one display")
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = rectangle.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        configuration.width = width; configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        configuration.queueDepth = 8
        configuration.showsCursor = false; configuration.capturesAudio = false
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        let queue = DispatchQueue(label: "activation-capture-samples")
        let meter = try Meter(url: base.appendingPathExtension("samples.jsonl"))
        try stream.addStreamOutput(meter, type: .screen, sampleHandlerQueue: queue)
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = url
        recordingConfiguration.videoCodecType = .h264; recordingConfiguration.outputFileType = .mp4
        let delegate = Recording()
        let recording = SCRecordingOutput(configuration: recordingConfiguration, delegate: delegate)
        try stream.addRecordingOutput(recording)
        try await stream.startCapture()
        do {
            var ready = false
            for _ in 0 ..< 40 {
                ready = delegate.snapshot().started && queue.sync { meter.complete > 0 }
                if ready { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard ready else { throw fail("recording did not start with a complete image") }
            let start: [String: Any] = queue.sync {
                ["ready": true, "firstCompletePTS": meter.firstComplete!,
                 "t": ProcessInfo.processInfo.systemUptime]
            }
            try JSONSerialization.data(withJSONObject: start, options: [.sortedKeys])
                .write(to: readyURL, options: .atomic)
            try await Task.sleep(for: .seconds(seconds))
        } catch {
            try await stream.stopCapture()
            throw error
        }
        try await stream.stopCapture()
        for _ in 0 ..< 40 {
            if delegate.snapshot().finished { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let state = delegate.snapshot()
        let summary: [String: Any] = try queue.sync {
            try meter.log.close()
            return ["samples": meter.count, "completeImages": meter.complete,
                    "statuses": meter.statuses, "firstPTS": meter.first as Any? ?? NSNull(),
                    "firstCompletePTS": meter.firstComplete as Any? ?? NSNull(),
                    "lastPTS": meter.last as Any? ?? NSNull(), "maxSampleGapMs": meter.maxGap * 1000,
                    "recordingStarted": state.started, "recordingFinished": state.finished,
                    "recordingError": state.error as Any? ?? NSNull(),
                    "sampleError": meter.error as Any? ?? NSNull(), "bytes": recording.recordedFileSize]
        }
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]) + Data([10]))
        guard state.started, state.finished, state.error == nil,
              queue.sync(execute: { meter.error == nil && meter.complete > 0 }), recording.recordedFileSize > 0 else {
            throw fail("recording or sample logging failed")
        }
    }
}
