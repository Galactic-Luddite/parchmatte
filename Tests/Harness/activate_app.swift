// Brings a running application to the foreground using public AppKit APIs.
//
// `open -a` launches an application but macOS can decline its activation when
// the request originated in a background Terminal window.  The GUI harness
// uses this helper to make activation explicit and to verify the result. The
// optional click posts one public CoreGraphics click inside the app's topmost
// normal window; macOS 15 requires that real input transition before a
// background-launched Terminal can send Apple Events despite existing grants.
//
// Usage: activate_app [--click] <application name>
import AppKit
import ApplicationServices
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let shouldClick = arguments.first == "--click"
let names = shouldClick ? Array(arguments.dropFirst()) : arguments
guard names.count == 1 else {
    FileHandle.standardError.write(Data("usage: activate_app [--click] <application name>\n".utf8))
    exit(2)
}

let requested = names[0]
let workspace = NSWorkspace.shared
guard let application = workspace.runningApplications.first(where: {
    $0.localizedName == requested
        || $0.bundleURL?.deletingPathExtension().lastPathComponent == requested
}) else {
    FileHandle.standardError.write(Data("application is not running: \(requested)\n".utf8))
    exit(2)
}

let options: NSApplication.ActivationOptions
if #available(macOS 14, *) {
    options = [.activateAllWindows]
} else {
    options = [.activateAllWindows, .activateIgnoringOtherApps]
}
let appKitAccepted = application.activate(options: options)
if !appKitAccepted {
    // A process launched in a background Terminal session can have its AppKit
    // activation rejected. Terminal already needs Accessibility for the GUI
    // harness, so use the corresponding public AX attributes as a fallback.
    let element = AXUIElementCreateApplication(application.processIdentifier)
    _ = AXUIElementSetAttributeValue(
        element, kAXFrontmostAttribute as CFString, kCFBooleanTrue
    )
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
       let windows = value as? [AXUIElement], let window = windows.first {
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}

let deadline = Date().addingTimeInterval(5)
var reachedForeground = false
while Date() < deadline {
    if workspace.frontmostApplication?.processIdentifier == application.processIdentifier {
        reachedForeground = true
        break
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}

guard reachedForeground else {
    let frontmost = workspace.frontmostApplication?.localizedName ?? "none"
    FileHandle.standardError.write(
        Data("activation did not reach the foreground: \(requested) (frontmost: \(frontmost))\n".utf8)
    )
    exit(1)
}

if shouldClick {
    let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] ?? []
    let point = windows.lazy.compactMap { entry -> CGPoint? in
        guard (entry[kCGWindowOwnerPID as String] as? pid_t) == application.processIdentifier,
              (entry[kCGWindowLayer as String] as? Int) == 0,
              let bounds = CGRect(
                  dictionaryRepresentation: (entry[kCGWindowBounds as String] as? NSDictionary) ?? [:]
              ),
              bounds.width >= 200, bounds.height >= 100 else { return nil }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }.first
    guard let point else {
        FileHandle.standardError.write(Data("no clickable window found: \(requested)\n".utf8))
        exit(1)
    }
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(
            mouseEventSource: nil, mouseType: type,
            mouseCursorPosition: point, mouseButton: .left
        )?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
}

let frontmost = workspace.frontmostApplication?.localizedName ?? "none"
guard workspace.frontmostApplication?.processIdentifier == application.processIdentifier else {
    FileHandle.standardError.write(
        Data("application lost the foreground: \(requested) (frontmost: \(frontmost))\n".utf8)
    )
    exit(1)
}
