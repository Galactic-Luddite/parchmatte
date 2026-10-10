import Carbon.HIToolbox
import Cocoa

/// System-wide hotkeys through Carbon's RegisterEventHotKey. Works inside the
/// App Sandbox and needs no Accessibility permission.
///
/// Hotkeys are defined by the character a key types ("o", "t", ...), not by
/// its position, so ⌃⌥T means the key labelled "T" on a German, French or
/// Dvorak keyboard too. They are re-registered when the layout changes.
final class HotKeys {
    private struct Binding {
        /// Preferred characters, best first.
        let characters: [Character]
        let fallbackKeyCode: Int
        /// Shift as well as Control-Option.
        var shift = false
        let handler: () -> Void
    }

    private var bindings: [UInt32: Binding] = [:]
    private var refs: [EventHotKeyRef] = []
    private var nextID: UInt32 = 1
    /// Bindings whose key combination another app already owns.
    private(set) var failed: Set<UInt32> = []
    private static weak var shared: HotKeys?

    init() {
        HotKeys.shared = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            DispatchQueue.main.async { HotKeys.shared?.bindings[hotKeyID.id]?.handler() }
            return noErr
        }, 1, &spec, nil, nil)

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in self?.registerAll() }
    }

    /// Registers Control-Option plus whichever key types `character` in the
    /// current layout, falling back to the US key position if none does.
    @discardableResult
    func register(controlOption characters: Character..., fallbackKeyCode: Int, _ handler: @escaping () -> Void) -> UInt32 {
        bindings[nextID] = Binding(characters: characters, fallbackKeyCode: fallbackKeyCode, handler: handler)
        nextID += 1
        registerAll()
        return nextID - 1
    }

    /// Registers Control-Option plus a key by position. For keys that type no
    /// character and sit in the same place on every layout, such as arrows.
    @discardableResult
    func register(controlOptionKeyCode keyCode: Int, _ handler: @escaping () -> Void) -> UInt32 {
        bindings[nextID] = Binding(characters: [], fallbackKeyCode: keyCode, handler: handler)
        nextID += 1
        registerAll()
        return nextID - 1
    }

    /// Registers Control-Option-Shift plus a key by position: a second row of
    /// arrow hotkeys beside the Control-Option ones.
    @discardableResult
    func register(controlOptionShiftKeyCode keyCode: Int, _ handler: @escaping () -> Void) -> UInt32 {
        bindings[nextID] = Binding(characters: [], fallbackKeyCode: keyCode, shift: true, handler: handler)
        nextID += 1
        registerAll()
        return nextID - 1
    }

    /// Whether every one of these bindings registered.
    func available(_ ids: [UInt32]) -> Bool {
        failed.isDisjoint(with: ids)
    }

    private func registerAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        failed.removeAll()
        let layout = HotKeys.currentLayoutMap()
        for (id, binding) in bindings.sorted(by: { $0.key < $1.key }) {
            let found = binding.characters.first { layout[$0] != nil }
            let keyCode = found.flatMap { layout[$0] } ?? binding.fallbackKeyCode
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(keyCode), UInt32(controlKey | optionKey | (binding.shift ? shiftKey : 0)),
                EventHotKeyID(signature: OSType(0x50524D54), id: id), // "PRMT"
                GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                refs.append(ref)
            } else {
                failed.insert(id)
                NSLog("\(AppInfo.name): hotkey ⌃⌥\(binding.shift ? "⇧" : "")\(binding.characters.first.map(String.init) ?? "key \(keyCode)") unavailable (status \(status))")
            }
        }
    }

    private static let keypadCodes: Set<Int> = [
        kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadClear,
        kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEnter, kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals,
        kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
        kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
    ]

    /// Character → key code for the unmodified keys of the current layout.
    static func currentLayoutMap() -> [Character: Int] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(dataRef).takeUnretainedValue() as Data
        var map: [Character: Int] = [:]
        data.withUnsafeBytes { raw in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for keyCode in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(keyCode), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
                )
                // Skip the numeric keypad: most Mac keyboards don't have one.
                guard status == noErr, length == 1, !HotKeys.keypadCodes.contains(keyCode),
                      let scalar = Unicode.Scalar(chars[0]) else { continue }
                let character = Character(scalar).lowercased().first!
                if map[character] == nil { map[character] = keyCode }
            }
        }
        return map
    }
}
