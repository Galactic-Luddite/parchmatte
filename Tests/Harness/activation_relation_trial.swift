// Exploratory WindowServer experiment, not a release acceptance test.
// Compile with the actual CoverWindow/material sources (see research doc).
// Only owned fixture windows are driven; nothing reads target pixels or input.
import Cocoa
import IOKit

private func sessionReady() throws -> Bool {
    let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    let locked = root == 0 ? nil : IORegistryEntryCreateCFProperty(
        root, "IOConsoleLocked" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    if root != 0 { IOObjectRelease(root) }
    let onConsole = session["kCGSSessionOnConsoleKey"] as? Bool
    let uid = session["kCGSSessionUserIDKey"] as? NSNumber
    let ready = locked == false && onConsole == true && uid?.uint32Value == getuid()
    let record: [String: Any] = ["ready": ready, "ioLocked": locked as Any? ?? NSNull(),
                               "onConsole": onConsole as Any? ?? NSNull(),
                               "t": ProcessInfo.processInfo.systemUptime]
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
    FileHandle.standardOutput.write(Data([10]))
    return ready
}

private func writeJSON(_ value: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        .write(to: url, options: .atomic)
}

private func rect(_ entry: [String: Any]) -> CGRect {
    guard let value = entry[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: value) else { return .zero }
    return rect
}

private func list() -> [[String: Any]] {
    guard let result = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0)
        as? [[String: Any]] else { fatalError("window query failed") }
    return result
}

private func paper(frame: NSRect) -> CoverWindow {
    let cover = CoverWindow(frame: frame)
    cover.collectionBehavior = [.stationary, .fullScreenAuxiliary, .ignoresCycle]
    cover.cornerRadius = WindowCoverRadius
    cover.apply(CoverStyle(texture: .denim, softness: 0, opacity: 0.4,
                           lamp: .off, glow: .subtle), hideFromCapture: false)
    return cover
}

private let WindowCoverRadius: CGFloat = 18

private final class Trial: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let output: URL
    let role: String
    let mode: String
    var a: NSWindow!
    var b: NSWindow!
    var cover: CoverWindow?
    var sentinel: NSPanel?
    var target: CGWindowID = 0
    var neighbor: CGWindowID = 0
    var updates = 0
    var activations = 0
    var keyNotifications = 0
    var occlusionNotifications = 0
    var lastHole = false
    var hasMaskState = false
    var log: FileHandle!
    var observers: [NSObjectProtocol] = []
    var stopDisplayLink: (() -> Void)?
    var lastDisplayCallback: TimeInterval?
    var maxDisplayInterval: TimeInterval = 0

    init(output: URL, role: String, mode: String) {
        self.output = output; self.role = role; self.mode = mode
    }

    func record(_ value: [String: Any]) {
        var row = value
        row["t"] = ProcessInfo.processInfo.systemUptime
        do {
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            try log.write(contentsOf: data + Data([10]))
        } catch { fatalError("trial log write failed: \(error)") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let logURL = output.appendingPathComponent("\(role)-events.jsonl")
        guard FileManager.default.createFile(atPath: logURL.path, contents: nil) else {
            fatalError("cannot create trial log")
        }
        do { log = try FileHandle(forWritingTo: logURL) } catch { fatalError("\(error)") }
        if role == "fixture" { fixture() } else { overlay() }
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in self?.commands() }
        RunLoop.main.add(timer, forMode: .common)
    }

    func window(_ r: NSRect, color: NSColor, markerColor: NSColor) -> NSWindow {
        let window = NSWindow(contentRect: r, styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Owned activation fixture"
        window.backgroundColor = color
        window.delegate = self
        // Both windows paint a different owned marker at the same screen
        // position inside their overlap. The recording can then identify
        // the presented owner without relying on notification timestamps.
        let content = window.contentRect(forFrameRect: window.frame)
        let marker = NSView(frame: NSRect(x: 900 - content.minX,
                                         y: NSScreen.screens[0].frame.maxY - 674 - content.minY,
                                         width: 24, height: 24))
        marker.wantsLayer = true
        marker.layer!.backgroundColor = markerColor.cgColor
        window.contentView!.addSubview(marker)
        return window
    }

    func fixture() {
        let height = NSScreen.screens[0].frame.maxY
        a = window(NSRect(x: 200, y: height - 750, width: 800, height: 578), color: .white,
                   markerColor: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        b = window(NSRect(x: 700, y: height - 900, width: 600, height: 378), color: .white,
                   markerColor: NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        b.orderFront(nil)
        a.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        target = CGWindowID(a.windowNumber); neighbor = CGWindowID(b.windowNumber)
        if mode == "child" {
            let child = paper(frame: a.frame)
            a.addChildWindow(child, ordered: .above)
            child.order(.above, relativeTo: a.windowNumber)
            cover = child
        }
        do {
            try writeJSON(["pid": getpid(), "target": target, "neighbor": neighbor,
                           "cover": cover?.windowNumber ?? 0],
                          to: output.appendingPathComponent("fixture.json"))
        } catch { fatalError("\(error)") }
        record(["event": "ready"])
    }

    func overlay() {
        do {
            let data = try Data(contentsOf: output.appendingPathComponent("fixture.json"))
            let identity = try JSONSerialization.jsonObject(with: data) as! [String: Int]
            target = CGWindowID(identity["target"]!); neighbor = CGWindowID(identity["neighbor"]!)
        } catch { fatalError("\(error)") }
        guard let entry = list().first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == target })
        else { fatalError("owned target is not on screen") }
        let r = rect(entry), h = NSScreen.screens[0].frame.maxY
        let frame = NSRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
        cover = paper(frame: mode == "occlusion-inset" ? frame.insetBy(dx: 20, dy: 20) : frame)
        cover!.level = ["poll45", "displaylink", "occlusion", "occlusion-inset", "sentinel"].contains(mode) ? .normal : NSWindow.Level(rawValue: 1)
        cover!.order(.above, relativeTo: Int(target))
        if mode == "sentinel" {
            let panel = NSPanel(contentRect: NSRect(x: frame.midX, y: frame.midY, width: 2, height: 2),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.hidesOnDeactivate = false; panel.isOpaque = false
            panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.order(.above, relativeTo: cover!.windowNumber)
            sentinel = panel
        }
        // App-local key notifications are intentionally observed here as a
        // negative control for a purported cross-process activation signal.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.keyNotifications += 1
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.activations += 1
        })
        let observedWindow: NSWindow = sentinel ?? cover!
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                               object: observedWindow, queue: .main) { [weak self] _ in
            guard let self, let cover = self.cover else { return }
            self.occlusionNotifications += 1
            self.record(["event": "occlusion", "visible": (self.sentinel ?? cover).occlusionState.contains(.visible)])
            // The positive control deliberately orders the paper out. Its
            // notification must not query a panel absent from the server list.
            if cover.isVisible, ["occlusion", "occlusion-inset", "sentinel"].contains(self.mode) { self.update() }
        })
        do {
            try writeJSON(["pid": getpid(), "cover": cover!.windowNumber,
                           "externalObjectLookup": NSApp.window(withWindowNumber: Int(target)) != nil],
                          to: output.appendingPathComponent("overlay.json"))
        } catch { fatalError("\(error)") }
        // Initial ordering reaches WindowServer after launch returns. Start
        // observations on the timer, rather than querying the pending panel.
        if mode == "displaylink" {
            guard #available(macOS 14.0, *) else { fatalError("displaylink trial requires macOS 14 or later") }
            // Use the screen rather than the cover: the check must continue
            // when the target completely occludes its paper.
            let link = NSScreen.screens[0].displayLink(target: self, selector: #selector(displayTick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            stopDisplayLink = { link.invalidate() }
        } else if !["lifted", "occlusion", "occlusion-inset", "sentinel"].contains(mode) {
            let hz: Double = mode == "clip120" ? 120 : 45
            let timer = Timer(timeInterval: 1 / hz, repeats: true) { [weak self] _ in self?.update() }
            timer.tolerance = 0
            RunLoop.main.add(timer, forMode: .common)
        }
        record(["event": "ready", "mode": mode])
    }

    @available(macOS 14.0, *)
    @objc func displayTick(_ link: CADisplayLink) {
        guard let cover, cover.isVisible else { return }
        updates += 1
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastDisplayCallback { maxDisplayInterval = max(maxDisplayInterval, now - previous) }
        lastDisplayCallback = now
        var nearest: CGWindowID = 0
        let result = PMNearestWindowAbove(target, &nearest)
        guard result != PMWindowQueryFailed else { fatalError("window-number query failed") }
        guard result != PMWindowQueryFound || nearest != CGWindowID(cover.windowNumber) else { return }
        cover.order(.above, relativeTo: Int(target))
        record(["event": "restack", "displayTimestamp": link.timestamp,
                "targetTimestamp": link.targetTimestamp])
    }

    func update() {
        guard let cover else { return }
        updates += 1
        let windows = list()
        guard let ai = windows.firstIndex(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == target }),
              let ci = windows.firstIndex(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == CGWindowID(cover.windowNumber) })
        else { fatalError("owned target or cover missing") }
        if ["poll45", "occlusion", "occlusion-inset", "sentinel"].contains(mode) {
            if ci > ai {
                cover.order(.above, relativeTo: Int(target))
                sentinel?.order(.above, relativeTo: cover.windowNumber)
                record(["event": "restack"])
            }
            return
        }
        guard mode.hasPrefix("clip") else { return }
        let bi = windows.firstIndex { ($0[kCGWindowNumber as String] as? CGWindowID) == neighbor }
        let hole = bi.map { $0 < ai && rect(windows[$0]).intersects(rect(windows[ai])) } ?? false
        guard hole != lastHole || !hasMaskState else { return }
        let mask = CAShapeLayer()
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: cover.frame.size))
        if hole, let bi {
            let h = rect(windows[bi]).intersection(rect(windows[ai]))
            let local = CGRect(x: h.minX - rect(windows[ai]).minX,
                               y: rect(windows[ai]).maxY - h.maxY, width: h.width, height: h.height)
            path.addRect(local)
        }
        mask.path = path; mask.fillRule = .evenOdd
        CATransaction.begin(); CATransaction.setDisableActions(true)
        cover.contentView!.layer!.mask = mask
        CATransaction.commit()
        CATransaction.flush()
        lastHole = hole; hasMaskState = true
        record(["event": "mask", "hole": hole])
    }

    func windowDidBecomeKey(_ notification: Notification) {
        let window = notification.object as! NSWindow
        record(["event": "key", "window": window.windowNumber])
    }

    func requireOwnedInput() {
        guard role == "fixture", CGPreflightPostEventAccess(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() else {
            fatalError("fixture needs event-posting access and foreground ownership")
        }
    }

    func commands() {
        let file = output.appendingPathComponent("\(role)-command")
        guard let value = try? String(contentsOf: file, encoding: .utf8), !value.isEmpty else { return }
        do { try "".write(to: file, atomically: true, encoding: .utf8) } catch { fatalError("\(error)") }
        let command = value.trimmingCharacters(in: .whitespacesAndNewlines)
        record(["event": "command", "command": command])
        switch command {
        case "a": a.orderFrontRegardless(); a.makeKey()
        case "b": b.orderFrontRegardless(); b.makeKey()
        case "click-a", "click-b":
            requireOwnedInput()
            record(["event": "input-flags", "kind": "click",
                    "combinedFlags": CGEventSource.flagsState(.combinedSessionState).rawValue])
            let window: NSWindow = command == "click-a" ? a : b
            // Each title-bar point is outside the other owned window. Never
            // post to a coordinate that could select an unrelated window.
            let x = command == "click-a" ? window.frame.minX + 100 : window.frame.maxX - 100
            let point = CGPoint(x: x, y: NSScreen.screens[0].frame.maxY - window.frame.maxY + 12)
            for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                          mouseCursorPosition: point, mouseButton: .left) else {
                    fatalError("cannot create owned fixture click")
                }
                event.flags = []
                event.post(tap: .cghidEventTap)
            }
        case "cycle", "toggle":
            requireOwnedInput()
            let key: CGKeyCode = command == "cycle" ? 50 : 35
            let modifiers: [(CGKeyCode, CGEventFlags)] = command == "cycle"
                ? [(55, .maskCommand)] : [(59, .maskControl), (58, .maskAlternate)]
            func postKey(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else {
                    fatalError("cannot create fixture key event")
                }
                event.flags = flags
                event.post(tap: .cghidEventTap)
            }
            // Emit the modifier press and release as well as the shortcut.
            // Keep shortcut modifiers out of later title-bar clicks, whose
            // own events also specify an empty modifier set.
            var flags: CGEventFlags = []
            for (code, flag) in modifiers {
                flags.insert(flag); postKey(code, down: true, flags: flags)
            }
            postKey(key, down: true, flags: flags)
            postKey(key, down: false, flags: flags)
            for (code, flag) in modifiers.reversed() {
                flags.remove(flag); postKey(code, down: false, flags: flags)
            }
        case "hide-b": b.orderOut(nil)
        case "hide-paper": sentinel?.orderOut(nil); cover?.orderOut(nil)
        case "show-paper":
            cover?.order(.above, relativeTo: Int(target))
            if let cover { sentinel?.order(.above, relativeTo: cover.windowNumber) }
        case "separate": b.setFrameOrigin(NSPoint(x: 1040, y: b.frame.minY))
        case "quit":
            record(["event": "summary", "updates": updates, "activations": activations,
                    "keyNotifications": keyNotifications, "occlusionNotifications": occlusionNotifications,
                    "maxDisplayIntervalMs": maxDisplayInterval * 1000])
            record(["event": "own-state", "coverVisible": cover?.occlusionState.contains(.visible) ?? false,
                    "sentinelVisible": sentinel?.occlusionState.contains(.visible) ?? false,
                    "applicationRegistered": NSRunningApplication(processIdentifier: getpid()) != nil])
            sentinel?.orderOut(nil); sentinel?.close()
            cover?.orderOut(nil); cover?.close()
            stopDisplayLink?(); stopDisplayLink = nil
            NSApp.terminate(nil)
        default: fatalError("unknown trial command: \(command)")
        }
    }
}

@main private struct ActivationRelationTrial {
    static func main() throws {
        let args = CommandLine.arguments
        if args.count == 2, args[1] == "--preflight" { exit(try sessionReady() ? 0 : 2) }
        guard args.count == 4, ["fixture", "overlay"].contains(args[1]),
              ["poll45", "displaylink", "lifted", "clip45", "clip120", "child", "occlusion", "occlusion-inset", "sentinel"].contains(args[2]) else {
            fatalError("fixture|overlay MODE OUTPUT_DIR")
        }
        let output = URL(fileURLWithPath: args[3], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let app = NSApplication.shared
        let delegate = Trial(output: output, role: args[1], mode: args[2])
        app.delegate = delegate
        app.setActivationPolicy(args[1] == "fixture" ? .regular : .accessory)
        app.run()
    }
}
