// Holds a window by its title bar for a few seconds while the caller switches desktops, so
// the window lands on the next desktop without its cover. Test code only.
// Usage: carry <x> <y>   (the caller switches desktops while this holds)
import CoreGraphics
import Foundation
let a = CommandLine.arguments.dropFirst().map { String($0) }
let p = CGPoint(x: Double(a[0])!, y: Double(a[1])!)
func mouse(_ t: CGEventType, _ q: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: q, mouseButton: .left)?.post(tap: .cghidEventTap) }
mouse(.mouseMoved, p); usleep(80_000)
mouse(.leftMouseDown, p); usleep(150_000)
for i in 1...40 { mouse(.leftMouseDragged, CGPoint(x: p.x + Double(i) * 2, y: p.y + Double(i))); usleep(15_000) }
let q = CGPoint(x: p.x + 80, y: p.y + 40)
for _ in 1...150 { mouse(.leftMouseDragged, q); usleep(20_000) }
mouse(.leftMouseUp, q)
