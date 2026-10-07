// Shows which key (virtual key code) types each hotkey character under
// several keyboard layouts, without switching the active layout. Uses the
// same UCKeyTranslate lookup as HotKeys.currentLayoutMap().
//
// Usage: swift Tests/Harness/layouts.swift
import Carbon.HIToolbox
import Foundation

func map(for layoutID: String) -> [Character: Int]? {
    let filter = [kTISPropertyInputSourceID as String: layoutID] as CFDictionary
    guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
          let source = list.first,
          let dataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(dataRef).takeUnretainedValue() as Data
    var result: [Character: Int] = [:]
    data.withUnsafeBytes { raw in
        let layout = raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
        for keyCode in 0..<128 {
            var dead: UInt32 = 0, length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            guard UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                 OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars) == noErr,
                  length == 1, !(65...92).contains(keyCode), // skip the numeric keypad, as HotKeys does
                  let s = Unicode.Scalar(chars[0]) else { continue }
            let c = Character(s).lowercased().first!
            if result[c] == nil { result[c] = keyCode }
        }
    }
    return result
}

// Current bindings (AppController.registerHotKeys): Control-Option plus the
// key typing o, p, t, l, i, s, g, and the four arrows by key code. The arrows
// sit in the same place on every layout, so only the letters are looked up.
let ansi: [Character: Int] = ["o": kVK_ANSI_O, "p": kVK_ANSI_P, "t": kVK_ANSI_T, "l": kVK_ANSI_L,
                              "i": kVK_ANSI_I, "s": kVK_ANSI_S, "g": kVK_ANSI_G]
var failures = 0
for id in ["com.apple.keylayout.US", "com.apple.keylayout.German", "com.apple.keylayout.French",
           "com.apple.keylayout.Dvorak"] {
    let short = id.replacingOccurrences(of: "com.apple.keylayout.", with: "")
    guard let m = map(for: id) else {
        // US must exist; the others are optional installs.
        if short == "US" { print("FAIL US layout not available"); failures += 1 } else { print("\(short): skipped (not installed)") }
        continue
    }
    var row: [String] = []
    for c in ansi.keys.sorted() {
        guard let code = m[c] else {
            row.append("\(c)=none"); failures += 1; continue
        }
        // On US the character lookup must land on the ANSI position.
        if short == "US" && code != ansi[c]! { failures += 1; row.append("\(c)=\(code)!") }
        else { row.append("\(c)=\(code)\(code != ansi[c]! ? "*" : "")") }
    }
    // Every letter needs its own key, or two hotkeys would collide.
    let codes = ansi.keys.compactMap { m[$0] }
    if Set(codes).count != codes.count { failures += 1; row.append("DUPLICATE KEY") }
    print("\(short): \(row.joined(separator: " "))")
}
print("* = differs from the US key position; arrows (123-126) bind by key code")
if failures > 0 { print("layouts: FAIL (\(failures))"); exit(1) }
print("layouts: PASS")
