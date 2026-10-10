import Carbon.HIToolbox
import Cocoa
import ServiceManagement

/// Menu-bar controller: builds the menu, wires hotkeys, and decides whether
/// covers are active given snooze, schedule and battery state.
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private var statusItem: NSStatusItem!
    private var covers: CoverManager!
    private var hotKeys: HotKeys!
    /// Hotkey binding IDs by menu shortcut, to tell which ones registered.
    private var shortcutIDs: [String: [UInt32]] = [:]
    private var power: PowerWatcher!
    private var clockTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        covers = CoverManager()
        power = PowerWatcher { [weak self] in self?.evaluateState() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = AppController.activeIcon
        // Excluded apps pause paper while they are in front.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.evaluateState() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.evaluateState() }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        registerHotKeys()
        NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: .main
        ) { [weak self] _ in self?.evaluateState() }
        // Schedule and snooze boundaries are minute-grained; a generous
        // tolerance lets macOS coalesce this wake-up with others.
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.evaluateState()
        }
        clockTimer?.tolerance = 5
        evaluateState()
    }

    // MARK: - Active state

    private enum State {
        /// `excluded` is the front app's name; `schedule` carries the next
        /// start, in minutes after midnight.
        case active, snoozed(Date), battery, schedule(resumes: Int), excluded(String)

        var title: String {
            switch self {
            case .active: return "Active"
            case .snoozed(let until):
                return "Snoozed until " + DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .short)
            case .battery: return "Paused — on battery"
            case .schedule(let resumes): return "Off by schedule until \(SolarClock.format(resumes))"
            case .excluded(let app): return "Paused — \(app) is excluded"
            }
        }

        var isPaused: Bool {
            if case .active = self { return false }
            return true
        }
    }

    private var state: State {
        if let until = settings.snoozeUntil, until > Date() { return .snoozed(until) }
        if settings.pauseOnBattery && power.onBattery { return .battery }
        if let resumes = scheduleResumes() { return .schedule(resumes: resumes) }
        if covers.frontAppIsExcluded {
            return .excluded(CoverManager.frontApp?.localizedName ?? "This app")
        }
        return .active
    }

    private func evaluateState() {
        if let until = settings.snoozeUntil, until <= Date() { settings.snoozeUntil = nil; return }
        let current = state
        switch current {
        case .active, .excluded: covers.suppressed = false // exclusion is applied per app by the covers
        default: covers.suppressed = true
        }
        updateStatusIcon(current)
    }

    // MARK: - Menu-bar icon

    private static let activeIcon: NSImage = {
        let image = NSImage(systemSymbolName: "doc.plaintext", accessibilityDescription: AppInfo.name)!
        image.isTemplate = true
        return image
    }()

    /// The paper glyph with a small pause badge cut into its lower right
    /// corner. Still a template image, so it follows light and dark menu bars;
    /// the icon itself is not dimmed.
    private static let pausedIcon: NSImage = {
        let base = activeIcon
        let size = base.size
        let image = NSImage(size: NSSize(width: size.width + 3, height: size.height), flipped: false) { _ in
            base.draw(in: NSRect(origin: .zero, size: size))
            let d = min(size.width, size.height) * 0.56
            let badge = NSRect(x: size.width + 3 - d, y: 0, width: d, height: d)
            // Clear a ring around the badge so it reads as separate.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: badge.insetBy(dx: -1.2, dy: -1.2)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: badge).fill()
            // Two bars knocked out of the disc.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let barW = d * 0.16, barH = d * 0.46
            let y = badge.midY - barH / 2
            NSBezierPath(rect: NSRect(x: badge.midX - barW * 1.6, y: y, width: barW, height: barH)).fill()
            NSBezierPath(rect: NSRect(x: badge.midX + barW * 0.6, y: y, width: barW, height: barH)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()

    private func updateStatusIcon(_ current: State) {
        guard let button = statusItem?.button else { return }
        let paused = current.isPaused
        let image = paused ? AppController.pausedIcon : AppController.activeIcon
        if button.image !== image { button.image = image }
        let label = paused ? "\(AppInfo.name), \(current.title)" : AppInfo.name
        button.setAccessibilityLabel(label)
        button.toolTip = paused ? current.title : nil
    }

    /// nil while the schedule allows paper now; otherwise when it next starts
    /// (minutes after midnight).
    private func scheduleResumes() -> Int? {
        AppController.scheduleResumes(
            mode: settings.schedule, now: Date(),
            custom: (settings.customStartMinutes, settings.customEndMinutes)
        )
    }

    /// The schedule rule with the clock passed in, so tests can set it: nil
    /// while `mode` allows paper at `now`, otherwise the window's next start.
    /// `calendar` and `zone` default to the user's; tests pin them.
    static func scheduleResumes(
        mode: ScheduleMode, now: Date, custom: (start: Int, end: Int),
        calendar: Calendar = .current, zone: TimeZone = .current
    ) -> Int? {
        // Always: no clock, no sun, no zone.tab read on the idle tick.
        if mode == .always { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let window: (start: Int, end: Int)
        switch mode {
        case .always: return nil
        case .sunsetToSunrise:
            let sun = SolarClock.today(now, zone: zone)
            window = (sun.sunset, sun.sunrise)
        case .sunriseToSunset:
            let sun = SolarClock.today(now, zone: zone)
            window = (sun.sunrise, sun.sunset)
        case .customHours:
            window = custom
        }
        return minuteOfDay(minute, isWithin: window) ? nil : window.start
    }

    /// Whether `minute` falls in [start, end), wrapping past midnight when
    /// start > end. A zero-length window is never within.
    static func minuteOfDay(_ minute: Int, isWithin window: (start: Int, end: Int)) -> Bool {
        window.start <= window.end
            ? (minute >= window.start && minute < window.end)
            : (minute >= window.start || minute < window.end)
    }

    // MARK: - Actions shared by menu and hotkeys

    @objc private func toggleWholeScreen() { settings.wholeScreen.toggle() }

    @objc private func toggleFrontWindow() { covers.toggleFrontWindowCover() }

    @objc private func removeWindowCovers() { covers.removeAllWindowCovers() }

    /// One rule for every style hotkey: the front window's own cover if it
    /// has one, otherwise the global style (screen and new window covers).
    private func adjustFront(_ change: (inout CoverStyle) -> Void) {
        if let cover = covers.frontAppCover {
            covers.update(cover, change)
            NotificationCenter.default.post(name: SliderMenuView.valuesChanged, object: nil)
        } else {
            var style = settings.style
            change(&style)
            settings.style = style
        }
    }

    private func snooze(minutes: Int) {
        settings.snoozeUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    private func registerHotKeys() {
        hotKeys = HotKeys()
        shortcutIDs["o"] = [hotKeys.register(controlOption: "o", fallbackKeyCode: kVK_ANSI_O) { [weak self] in self?.toggleWholeScreen() }]
        shortcutIDs["p"] = [hotKeys.register(controlOption: "p", fallbackKeyCode: kVK_ANSI_P) { [weak self] in self?.toggleFrontWindow() }]
        // Style hotkeys all follow adjustFront's rule: the front window's
        // own cover if it has one, else the screen and new window covers.
        shortcutIDs["t"] = [hotKeys.register(controlOption: "t", fallbackKeyCode: kVK_ANSI_T) { [weak self] in
            self?.adjustFront { $0.texture = $0.texture.next }
        }]
        shortcutIDs["l"] = [hotKeys.register(controlOption: "l", fallbackKeyCode: kVK_ANSI_L) { [weak self] in
            self?.adjustFront { $0.lamp = $0.lamp.next }
        }]
        // "I" for inversion: flips the texture's grain, four states in a cycle.
        shortcutIDs["i"] = [hotKeys.register(controlOption: "i", fallbackKeyCode: kVK_ANSI_I) { [weak self] in
            self?.adjustFront { $0.orientation = $0.orientation.next }
        }]
        shortcutIDs["s"] = [hotKeys.register(controlOption: "s", fallbackKeyCode: kVK_ANSI_S) { [weak self] in
            guard let self else { return }
            if case .snoozed = self.state { self.settings.snoozeUntil = nil } else { self.snooze(minutes: 15) }
        }]
        // Arrows sit in the same place on every layout, so they bind by key
        // code. ↑/↓ change strength, ←/→ softness.
        shortcutIDs["updown"] = [
            hotKeys.register(controlOptionKeyCode: kVK_UpArrow) { [weak self] in self?.adjustFront { $0.opacity += 0.05 } },
            hotKeys.register(controlOptionKeyCode: kVK_DownArrow) { [weak self] in self?.adjustFront { $0.opacity -= 0.05 } },
        ]
        shortcutIDs["leftright"] = [
            hotKeys.register(controlOptionKeyCode: kVK_RightArrow) { [weak self] in self?.adjustFront { $0.softness += 0.05 } },
            hotKeys.register(controlOptionKeyCode: kVK_LeftArrow) { [weak self] in self?.adjustFront { $0.softness -= 0.05 } },
        ]
        // Steps the Page Light strength up, wrapping to the bottom. With the
        // lamp off this only changes the strength used next time; it doesn't
        // switch the lamp on.
        shortcutIDs["g"] = [hotKeys.register(controlOption: "g", fallbackKeyCode: kVK_ANSI_G) { [weak self] in
            self?.adjustFront { $0.lampStrength = LampStrength.next($0.lampStrength) }
        }]
    }

    // MARK: - Menu

    /// A shortcut another app already owns is shown as in use, not advertised.
    private func shortcutWorks(_ name: String) -> Bool {
        hotKeys.available(shortcutIDs[name] ?? [])
    }

    private func shortcutText(_ name: String, _ text: String) -> String {
        if shortcutWorks(name) { return text }
        let keys = text.trimmingCharacters(in: .whitespaces)
        return text.hasPrefix(" ") ? "   (\(keys) in use)" : "in use"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: state.title, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let whole = item("Paper Whole Screen", #selector(toggleWholeScreen), key: shortcutWorks("o") ? "o" : "")
        whole.state = settings.wholeScreen ? .on : .off
        menu.addItem(whole)

        let front = CoverManager.frontWindow()
        let frontName = front?.appName ?? CoverManager.frontApp?.localizedName ?? "Front"
        let existing = covers.frontAppCover
        let windowTitle = existing == nil ? "Paper \(frontName) Window" : "Remove Paper from \(frontName) Window"
        let windowItem = item(windowTitle, #selector(toggleFrontWindow), key: shortcutWorks("p") ? "p" : "")
        windowItem.isEnabled = front != nil
        menu.addItem(windowItem)

        let removeAll = item("Remove Window Papers (\(covers.windowCovers.count))", #selector(removeWindowCovers))
        removeAll.isEnabled = !covers.windowCovers.isEmpty
        menu.addItem(removeAll)
        menu.addItem(.separator())

        // Style: the front window's own cover first, when it has one, then the
        // global style. The hotkeys act on whichever section comes first.
        if let cover = existing {
            menu.addItem(header("This Window — \(cover.appName)"))
            addStyleItems(to: menu, shortcuts: true, current: { cover.style }) { [weak self] change in
                self?.covers.update(cover, change)
            }
            menu.addItem(.separator())
        }
        menu.addItem(header("Screen and New Windows"))
        addStyleItems(to: menu, shortcuts: existing == nil, current: { [weak self] in
            self?.settings.style ?? Settings.shared.style
        }) { [weak self] change in
            guard let self else { return }
            var style = self.settings.style
            change(&style)
            self.settings.style = style
        }
        menu.addItem(.separator())

        var snoozeEntries: [(String, Bool, () -> Void)] = [(5, "5 minutes"), (15, "15 minutes"), (60, "1 hour"), (180, "3 hours")]
            .map { minutes, title in (title, false, { [weak self] in self?.snooze(minutes: minutes) }) }
        if case .snoozed = state {
            snoozeEntries.append(("Resume Now", false, { [weak self] in self?.settings.snoozeUntil = nil }))
        }
        menu.addItem(submenu(shortcutWorks("s") ? "Snooze   ⌃⌥S = 15 min" : "Snooze", entries: snoozeEntries))

        menu.addItem(scheduleMenu())
        menu.addItem(displaysMenu())
        menu.addItem(excludedAppsMenu())
        menu.addItem(.separator())

        menu.addItem(toggle("Pause on Battery", settings.pauseOnBattery) { [weak self] in
            self?.settings.pauseOnBattery.toggle()
        })
        menu.addItem(toggle("Hide from Screenshots", settings.hideFromScreenshots) { [weak self] in
            self?.settings.hideFromScreenshots.toggle()
        })
        menu.addItem(toggle("Launch at Login", SMAppService.mainApp.status == .enabled) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
            } catch {
                // The toggle would otherwise silently refuse to flip. Say why,
                // and offer the Login Items pane where macOS explains itself.
                NSLog("\(AppInfo.name): launch at login change failed: \(error.localizedDescription)")
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Launch at Login couldn't be changed"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Open Login Items Settings")
                if alert.runModal() == .alertSecondButtonReturn {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        })
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem(title: "Privacy Policy…") {
            NSWorkspace.shared.open(AppInfo.privacyPolicyURL)
        })
        let quit = NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Strength and softness sliders plus Texture and Page Light submenus (the
    /// latter with its own strength slider) for
    /// one style, either a window cover's own or the global one.
    private func addStyleItems(
        to menu: NSMenu, shortcuts: Bool, current: @escaping () -> CoverStyle,
        change: @escaping ((inout CoverStyle) -> Void) -> Void
    ) {
        let style = current()
        func key(_ name: String, _ text: String) -> String { shortcuts ? shortcutText(name, text) : "" }
        menu.addItem(sliderItem(
            label: "Strength", value: style.opacity, shortcut: key("updown", "⌃⌥↑↓"), current: { current().opacity }
        ) { value in change { $0.opacity = value } })
        menu.addItem(sliderItem(
            label: "Softness", value: style.softness, maxValue: 1, shortcut: key("leftright", "⌃⌥←→"), current: { current().softness }
        ) { value in change { $0.softness = value } })
        let textures: [(String, Bool, () -> Void)] = Texture.allCases.map { texture in
            (texture.title, style.texture == texture, { change { $0.texture = texture } })
        }
        menu.addItem(submenu("Texture" + key("t", "   ⌃⌥T"), entries: textures))
        let orientations: [(String, Bool, () -> Void)] = Orientation.allCases.map { orientation in
            (orientation.title, style.orientation == orientation, { change { $0.orientation = orientation } })
        }
        menu.addItem(submenu("Orientation" + key("i", "   ⌃⌥I"), entries: orientations))
        let lamps: [(String, Bool, () -> Void)] = LampPreset.allCases.map { lamp in
            (lamp.title, style.lamp == lamp, { change { $0.lamp = lamp } })
        }
        let lampMenu = submenu("Page Light" + key("l", "   ⌃⌥L"), entries: lamps)
        lampMenu.submenu?.addItem(.separator())
        lampMenu.submenu?.addItem(sliderItem(
            label: "Light Strength", value: style.lampStrength, maxValue: 1, shortcut: key("g", "⌃⌥G"),
            current: { current().lampStrength }
        ) { value in change { $0.lampStrength = value } })
        menu.addItem(lampMenu)
    }

    private func scheduleMenu() -> NSMenuItem {
        let sun = SolarClock.today()
        let modes: [(String, Bool, () -> Void)] = ScheduleMode.allCases.map { mode in
            (mode.title, settings.schedule == mode, { [weak self] in self?.settings.schedule = mode })
        }
        let parent = submenu("Schedule", entries: modes)
        let sub = parent.submenu!
        sub.addItem(.separator())
        sub.addItem(hourPicker("Custom Start", current: settings.customStartMinutes) { [weak self] in
            self?.settings.customStartMinutes = $0
        })
        sub.addItem(hourPicker("Custom End", current: settings.customEndMinutes) { [weak self] in
            self?.settings.customEndMinutes = $0
        })
        sub.addItem(.separator())
        let info = NSMenuItem(
            title: "Sunrise \(SolarClock.format(sun.sunrise)) · Sunset \(SolarClock.format(sun.sunset))",
            action: nil, keyEquivalent: ""
        )
        info.isEnabled = false
        sub.addItem(info)
        return parent
    }

    private func hourPicker(_ label: String, current: Int, set: @escaping (Int) -> Void) -> NSMenuItem {
        let entries: [(String, Bool, () -> Void)] = (0..<24).map { hour in
            (SolarClock.format(hour * 60), current == hour * 60, { set(hour * 60) })
        }
        let item = submenu(label, entries: entries)
        item.title = "\(label): \(SolarClock.format(current))"
        return item
    }

    private func displaysMenu() -> NSMenuItem {
        let disabled = settings.disabledDisplays
        let screens = NSScreen.screens
        let entries: [(String, Bool, () -> Void)] = screens.enumerated().map { index, screen in
            let name = screen.localizedName
            // Identical monitors share a name; number them so each row is distinct.
            let twins = screens.filter { $0.localizedName == name }
            let label = twins.count > 1
                ? "\(name) (\((twins.firstIndex { $0 === screen } ?? 0) + 1))" : name
            let key = screen.displayPrefKey
            return (label, !screen.isDisabled(in: disabled), { [weak self] in
                guard let self else { return }
                var set = self.settings.disabledDisplays
                // Migrate a name-keyed entry from an earlier build: it
                // becomes explicit per-display keys for every display that
                // shared the name, then this one is toggled.
                if set.remove(name) != nil {
                    screens.filter { $0.localizedName == name }.forEach { set.insert($0.displayPrefKey) }
                }
                if set.contains(key) { set.remove(key) } else { set.insert(key) }
                self.settings.disabledDisplays = set
            })
        }
        return submenu("Displays", entries: entries)
    }

    private func excludedAppsMenu() -> NSMenuItem {
        var entries: [(String, Bool, () -> Void)] = []
        let excluded = settings.excludedApps
        if let app = CoverManager.frontApp, let id = app.bundleIdentifier,
           id != Bundle.main.bundleIdentifier, excluded[id] == nil {
            let name = app.localizedName ?? id
            entries.append(("Exclude \(name)", false, { [weak self] in self?.settings.excludedApps[id] = name }))
        }
        for (id, name) in excluded.sorted(by: { $0.value < $1.value }) {
            entries.append((name, true, { [weak self] in self?.settings.excludedApps[id] = nil }))
        }
        if entries.isEmpty {
            entries.append(("No Apps Excluded", false, {}))
        }
        return submenu("Excluded Apps", entries: entries)
    }

    // MARK: - Menu building helpers

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.control, .option]
        item.target = self
        return item
    }

    private func toggle(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        item.state = on ? .on : .off
        return item
    }

    /// A submenu of checkmarked choices, optionally followed by a second group.
    private func submenu(
        _ title: String,
        entries: [(String, Bool, () -> Void)]
    ) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, on, action) in entries { sub.addItem(toggle(title, on, action)) }
        parent.submenu = sub
        return parent
    }

    private func sliderItem(
        label: String, value: Double, maxValue: Double = AppInfo.maxOpacity, shortcut: String = "",
        current: (() -> Double)? = nil, onChange: @escaping (Double) -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = SliderMenuView(label: label, value: value, maxValue: maxValue, shortcut: shortcut,
                                   current: current, onChange: onChange)
        return item
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

/// "Label  NN%" above a slider, for embedding in the menu. With `current`,
/// the slider follows changes made elsewhere (hotkeys) while the menu is open.
final class SliderMenuView: NSView {
    /// Posted when a value a slider shows changed outside the slider.
    static let valuesChanged = Notification.Name("ParchmatteSliderValuesChanged")

    private let label = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let slider = NSSlider()
    private let title: String
    private let onChange: (Double) -> Void
    private let current: (() -> Double)?
    private var observers: [NSObjectProtocol] = []

    init(label title: String, value: Double, maxValue: Double, shortcut: String = "",
         current: (() -> Double)? = nil, onChange: @escaping (Double) -> Void) {
        self.title = title
        self.onChange = onChange
        self.current = current
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 50))

        label.font = .menuFont(ofSize: 0)
        label.frame = NSRect(x: 20, y: 26, width: 170, height: 18)
        addSubview(label)
        shortcutLabel.font = .menuFont(ofSize: 0)
        shortcutLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .right
        shortcutLabel.stringValue = shortcut
        shortcutLabel.frame = NSRect(x: 170, y: 26, width: 72, height: 18)
        addSubview(shortcutLabel)
        if current != nil {
            for name in [Settings.didChange, SliderMenuView.valuesChanged] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.refresh()
                })
            }
        }

        slider.minValue = 0
        slider.maxValue = maxValue
        slider.doubleValue = value
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        slider.frame = NSRect(x: 18, y: 4, width: 224, height: 20)
        // VoiceOver reads the row's own label; the slider needs its own.
        slider.setAccessibilityLabel(title)
        addSubview(slider)
        updateLabel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    private func refresh() {
        guard let value = current?(), abs(value - slider.doubleValue) > 0.0001 else { return }
        slider.doubleValue = value
        updateLabel()
    }

    @objc private func changed() {
        updateLabel()
        onChange(slider.doubleValue)
    }

    private func updateLabel() {
        let percent = "\(Int((slider.doubleValue * 100).rounded()))%"
        label.stringValue = "\(title)  \(percent)"
        slider.setAccessibilityValueDescription(percent)
    }
}
