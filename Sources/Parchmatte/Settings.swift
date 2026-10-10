import Foundation

/// UserDefaults-backed preferences. Every setter posts `Settings.didChange`.
final class Settings {
    static let didChange = Notification.Name("ParchmatteSettingsDidChange")
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            "wholeScreen": true,
            "opacity": 0.15,
            "softness": 0.35,
            "texture": Texture.parchmatte.rawValue,
            "lamp": LampPreset.off.rawValue,
            "orientation": Orientation.normal.rawValue,
            "schedule": ScheduleMode.always.rawValue,
            "customStartMinutes": 9 * 60,
            "customEndMinutes": 17 * 60,
            "pauseOnBattery": false,
            "hideFromScreenshots": true,
        ])
    }

    private static func minuteOfDay(_ value: Int) -> Int {
        (value % 1440 + 1440) % 1440
    }

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    private func changed() {
        NotificationCenter.default.post(name: Settings.didChange, object: self)
    }

    var wholeScreen: Bool {
        get { defaults.bool(forKey: "wholeScreen") }
        set { defaults.set(newValue, forKey: "wholeScreen"); changed() }
    }

    /// Default opacity for whole-screen covers and newly added window covers, 0...1.
    var opacity: Double {
        get { AppInfo.safeOpacity(defaults.double(forKey: "opacity")) }
        set { defaults.set(AppInfo.safeOpacity(newValue), forKey: "opacity"); changed() }
    }

    /// How much the grain is blurred and eased, 0...1.
    var softness: Double {
        get { Settings.unit(defaults.double(forKey: "softness")) }
        set { defaults.set(Settings.unit(newValue), forKey: "softness"); changed() }
    }

    var texture: Texture {
        get { Texture(rawValue: defaults.string(forKey: "texture") ?? "") ?? .parchmatte }
        set { defaults.set(newValue.rawValue, forKey: "texture"); changed() }
    }

    var lamp: LampPreset {
        get { LampPreset(rawValue: defaults.string(forKey: "lamp") ?? "") ?? .off }
        set { defaults.set(newValue.rawValue, forKey: "lamp"); changed() }
    }

    /// Page Light strength, 0...1. Until it has been set, a glow level saved
    /// by 1.0 decides it, so an existing light looks the same after updating.
    var lampStrength: Double {
        get {
            if let stored = defaults.object(forKey: "lampStrength") as? Double { return LampStrength.clamped(stored) }
            return LampStrength.migrated(fromGlow: defaults.string(forKey: "glow") ?? "") ?? LampStrength.standard
        }
        set { defaults.set(LampStrength.clamped(newValue), forKey: "lampStrength"); changed() }
    }

    /// The global style: whole-screen covers and the starting point for new
    /// window covers. Setting it writes every part and posts one change.
    /// An unknown stored value (an older or hostile preference) reads as normal.
    var orientation: Orientation {
        get { Orientation(rawValue: defaults.string(forKey: "orientation") ?? "") ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: "orientation"); changed() }
    }

    var style: CoverStyle {
        get { CoverStyle(texture: texture, softness: softness, opacity: opacity, lamp: lamp, lampStrength: lampStrength, orientation: orientation) }
        set {
            let s = newValue.clamped
            defaults.set(s.texture.rawValue, forKey: "texture")
            defaults.set(s.softness, forKey: "softness")
            defaults.set(s.opacity, forKey: "opacity")
            defaults.set(s.lamp.rawValue, forKey: "lamp")
            defaults.set(s.lampStrength, forKey: "lampStrength")
            defaults.set(s.orientation.rawValue, forKey: "orientation")
            changed()
        }
    }

    var schedule: ScheduleMode {
        get { ScheduleMode(rawValue: defaults.string(forKey: "schedule") ?? "") ?? .always }
        set { defaults.set(newValue.rawValue, forKey: "schedule"); changed() }
    }

    var customStartMinutes: Int {
        get { Settings.minuteOfDay(defaults.integer(forKey: "customStartMinutes")) }
        set { defaults.set(Settings.minuteOfDay(newValue), forKey: "customStartMinutes"); changed() }
    }

    var customEndMinutes: Int {
        get { Settings.minuteOfDay(defaults.integer(forKey: "customEndMinutes")) }
        set { defaults.set(Settings.minuteOfDay(newValue), forKey: "customEndMinutes"); changed() }
    }

    var pauseOnBattery: Bool {
        get { defaults.bool(forKey: "pauseOnBattery") }
        set { defaults.set(newValue, forKey: "pauseOnBattery"); changed() }
    }

    var hideFromScreenshots: Bool {
        get { defaults.bool(forKey: "hideFromScreenshots") }
        set { defaults.set(newValue, forKey: "hideFromScreenshots"); changed() }
    }

    /// Displays the user has switched off, by hardware UUID (display names
    /// from builds 1-2 are still honoured; see `NSScreen.isDisabled`).
    var disabledDisplays: Set<String> {
        get { Set(defaults.stringArray(forKey: "disabledDisplays") ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: "disabledDisplays"); changed() }
    }

    /// Excluded apps: bundle identifier -> display name.
    var excludedApps: [String: String] {
        // Bounded, so a doctored preferences file can't stall the menu. Keys
        // longer than any real bundle identifier are dropped, not truncated:
        // two long keys sharing a prefix would otherwise collide.
        get {
            let stored = defaults.dictionary(forKey: "excludedApps") as? [String: String] ?? [:]
            let kept = stored.filter { $0.key.count <= 256 }.sorted { $0.key < $1.key }.prefix(100)
            return Dictionary(kept.map { ($0.key, String($0.value.prefix(256))) }, uniquingKeysWith: { first, _ in first })
        }
        set { defaults.set(newValue, forKey: "excludedApps"); changed() }
    }

    /// Snooze end time, or nil when not snoozed. Not persisted across launches.
    var snoozeUntil: Date? {
        didSet { changed() }
    }
}
