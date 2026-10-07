// Posts a real left mouse click at a global point (top-left origin), for
// click-through tests: the click must reach whatever is under a cover.
//
// Usage: swift Tests/Harness/click.swift <x> <y>
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count == 3, let x = Double(args[1]), let y = Double(args[2]) else {
    fatalError("usage: click.swift <x> <y>")
}
let point = CGPoint(x: x, y: y)
for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(60_000)
}
