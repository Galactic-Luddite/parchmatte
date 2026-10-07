// Drags with a real left mouse button from one global point to another
// (top-left origin) in <steps> moves over <seconds>, like a hand on a
// trackpad. Test code only: it posts events and never reads any.
//
// Usage: drag <x0> <y0> <x1> <y1> [seconds] [steps]
import CoreGraphics
import Foundation

let a = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard a.count >= 4 else { print("usage: drag x0 y0 x1 y1 [seconds] [steps]"); exit(2) }
let seconds = a.count > 4 ? a[4] : 1.0
let steps = a.count > 5 ? Int(a[5]) : 60
let from = CGPoint(x: a[0], y: a[1]), to = CGPoint(x: a[2], y: a[3])

func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
post(.mouseMoved, from); usleep(80_000)
post(.leftMouseDown, from); usleep(120_000)
for i in 1...steps {
    let t = Double(i) / Double(steps)
    post(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
    usleep(useconds_t(seconds / Double(steps) * 1_000_000))
}
usleep(80_000)
post(.leftMouseUp, to)
