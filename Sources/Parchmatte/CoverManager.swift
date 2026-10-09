import Cocoa
#if SWIFT_PACKAGE
import WindowListBridge
#endif

extension NSScreen {
    /// A stable identity for this display. Two identical monitors share a
    /// localized name, so covers are keyed by the hardware display ID.
    var displayKey: String {
        let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return id.map { "display-\($0.uint32Value)" } ?? localizedName
    }

    /// The key the Displays menu stores for this display: its hardware UUID,
    /// which survives reboots and reconnects and tells identical monitors
    /// apart. Earlier builds stored the display name; `isDisabled` still
    /// honours those entries.
    var displayPrefKey: String {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id.uint32Value)?.takeRetainedValue(),
              let text = CFUUIDCreateString(nil, uuid) else { return displayKey }
        return text as String
    }

    func isDisabled(in disabled: Set<String>) -> Bool {
        disabled.contains(displayPrefKey) || disabled.contains(localizedName)
    }
}

/// A cover pinned to one window of another app.
final class WindowCover {
    /// Changes when the cover follows a tab switch to a sibling window.
    var windowID: CGWindowID
    /// Last on-screen bounds in CoreGraphics coordinates.
    var lastRect: CGRect?
    /// When the tracked window was first found missing from the screen, or
    /// nil while it is showing.
    var missingSince: Date?
    /// Hidden (alpha 0) while its window animates into or out of full screen;
    /// shown again, exactly sized and on the right Space, when it lands.
    var inTransition = false
    /// Experimental paper fade during a Dock collapse, separate from Space
    /// and full-screen identity handling.
    var minimizeFade = MinimizeFade(detectShallowStretch: CoverManager.ribbonTrial)
    let ownerPID: pid_t
    let appName: String
    /// Replaced, not reused, when the cover must move to another Space: a
    /// window keeps its Space even after being ordered out and back in.
    private(set) var window: CoverWindow
    /// This cover's own look: a copy of the global style when it was added,
    /// then changed only through this cover (menu section or hotkeys while
    /// its window is in front). Like the cover itself, not kept across launches.
    var style: CoverStyle
    /// The window this cover was last stacked directly above (the tracked
    /// window, or a tab strip docked on top of it).
    var stackAbove: CGWindowID?
    /// How many on-screen windows were above `stackAbove` when a lifted
    /// cover was last checked for a window raised over its own (see
    /// `restackLifted`); nil forces the check.
    var windowsAbove: Int?
    /// When the window was first seen on screen without its cover, while
    /// that has held on every full scan since. Mid-swipe, and for a few
    /// frames after a desktop swipe lands, this is true in passing; only a
    /// miss that lasts means the cover is stranded on another Space.
    var strandedSince: CFAbsoluteTime?
    /// The covered window's corner radius, estimated without looking at its
    /// pixels (see `WindowCover.cornerRadius(osMajor:)`).
    let cornerRadius: CGFloat

    init(windowID: CGWindowID, ownerPID: pid_t, appName: String, style: CoverStyle, frame: NSRect) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.appName = appName
        self.style = style
        cornerRadius = WindowCover.cornerRadius(osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        window = WindowCover.makeWindow(frame: frame)
    }

    /// Window corner radius in points, by macOS major version. Screen
    /// capture of other apps is off the table, so this is an estimate that
    /// the window list can't refine (it doesn't say whether a window has a
    /// toolbar); it is rounded up, because an unpapered sliver at a corner
    /// is far less visible than paper past the window's edge on the desktop.
    ///
    /// - 27 and later: measured on the harness's own windows (titled; unified,
    ///   unified-compact and expanded toolbars with items; full-size content;
    ///   utility panel). Every style matched a continuous-curve radius of
    ///   about 17 pt; 18 covers it.
    /// - 26: toolbar windows are reported at about 26 pt and titlebar-only
    ///   ones at about 16 pt; the larger value wins.
    /// - 13 to 15: about 10 pt for every standard window.
    static func cornerRadius(osMajor: Int) -> CGFloat {
        switch osMajor {
        case ..<26: return 10
        case 26: return 26
        default: return 18
        }
    }

    private static func makeWindow(frame: NSRect) -> CoverWindow {
        let window = CoverWindow(frame: frame)
        window.level = .normal
        // Keep the window server from independently shrinking the cover into
        // Expose/Mission Control before our public Dock-window signal hides it.
        // `stationary` leaves it at the target's resting frame for that short
        // interval, so it can never chase or reveal a transformed thumbnail.
        window.collectionBehavior = [.stationary, .fullScreenAuxiliary, .ignoresCycle]
        return window
    }

    /// Swaps in a fresh window, which lands on the active Space when shown.
    func replaceWindow() {
        let frame = window.frame
        window.orderOut(nil)
        window.close()
        window = WindowCover.makeWindow(frame: frame)
    }
}

/// Owns every cover window: one per enabled display in whole-screen mode, plus
/// any number of covers that track individual windows at display refresh rate.
final class CoverManager {
    /// A real-app candidate switch; the default build keeps its existing fade
    /// until the owner accepts this production-path implementation.
    fileprivate static let attachedVariant: AttachedPaperGeometry.Variant? = {
        let prefix = "--attached-paper="
        guard let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return AttachedPaperGeometry.Variant(rawValue: String(arg.dropFirst(prefix.count)))
    }()
    fileprivate static let ribbonTrial = ProcessInfo.processInfo.arguments.contains("--ribbon-trial") || attachedVariant != nil

    private let settings = Settings.shared
    /// Whole-screen covers by display key, one per Space visited.
    private var spaceCovers: [String: [CoverWindow]] = [:]
    private var coveredDisplays: [String] = []
    private var screenCovers: [CoverWindow] { spaceCovers.values.flatMap { $0 } }
    private(set) var windowCovers: [WindowCover] = []
    private var trackingTimer: Timer?

    /// Set by the app when snooze, schedule or battery say covers should be off.
    var suppressed = false {
        didSet { if suppressed != oldValue { refreshVisibility() } }
    }

    init() {
        if Self.attachedVariant != nil { RibbonRenderer.prepare() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildScreenCovers() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateFrontApp(app ?? CoverManager.frontApp)
            self?.refreshVisibility()
            self?.activated(pid: app?.processIdentifier)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.windowCovers.forEach { $0.window.cancelRibbon() }
            self?.updateFrontApp()
            self?.refreshVisibility()
            self?.watchSpaceTransition()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.refreshVisibility(restoreParked: true) }
        }
        NotificationCenter.default.addObserver(
            forName: Settings.didChange, object: nil, queue: .main
        ) { [weak self] _ in self?.settingsChanged() }
        updateFrontApp()
        rebuildScreenCovers()
    }

    // The native screenshot window picker can select a click-through cover
    // itself. Recognize only its public, display-sized high-level UI window;
    // no screen pixels, window titles, or keyboard events are inspected.
    private var capturePickerActive = false
    private var capturePickerTimer: Timer?

    static func screenshotPickerShowing(in windows: [[String: Any]], displays: [CGRect]) -> Bool {
        windows.contains { entry in
            guard let owner = entry[kCGWindowOwnerName as String] as? String,
                  ["screencapture", "Screenshot", "ScreenshotUI"].contains(owner),
                  (entry[kCGWindowLayer as String] as? Int) ?? 0 >= 1000,
                  let raw = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: raw) else { return false }
            return displays.contains {
                abs(rect.minX - $0.minX) <= 2 && abs(rect.minY - $0.minY) <= 2
                    && abs(rect.width - $0.width) <= 2 && abs(rect.height - $0.height) <= 2
            }
        }
    }

    private func updateCapturePickerTimer() {
        let needed = capturePickerActive || (!suppressed && !frontAppIsExcluded
            && (settings.wholeScreen || !windowCovers.isEmpty))
        guard needed else {
            capturePickerTimer?.invalidate()
            capturePickerTimer = nil
            return
        }
        guard capturePickerTimer == nil else { return }
        let timer = Timer(timeInterval: 0.125, repeats: true) { [weak self] _ in
            self?.checkCapturePicker()
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        capturePickerTimer = timer
    }

    private func checkCapturePicker() {
        let windows = Self.windowList(options: [.optionOnScreenOnly, .excludeDesktopElements])
        let active = Self.screenshotPickerShowing(in: windows,
            displays: NSScreen.screens.map { Self.cgRect(fromAppKit: $0.frame) })
        guard active != capturePickerActive else { return }
        capturePickerActive = active
        if active {
            windowCovers.forEach { $0.window.orderOut(nil) }
            // Remove only screen panels on the current Space. Ordering them
            // out loses their Space association; recreating those on exit
            // avoids bringing several old-Space panels onto this desktop.
            let visible = Set(windows.compactMap { $0[kCGWindowNumber as String] as? Int })
            for (key, list) in spaceCovers {
                spaceCovers[key] = list.filter { cover in
                    guard visible.contains(cover.windowNumber) else { return true }
                    parked.remove(ObjectIdentifier(cover))
                    appHidden.remove(ObjectIdentifier(cover))
                    cover.close()
                    return false
                }
            }
        }
        refreshVisibility()
    }

    // MARK: - Whole screen

    // Each desktop (Space) gets its own whole-screen cover per display. A cover
    // that belongs to a Space slides with it during a swipe, so the paper never
    // drops out; a single all-Spaces cover is shifted off-screen by the window
    // server for the length of the animation.

    private var enabledScreens: [NSScreen] {
        let disabled = settings.disabledDisplays
        return NSScreen.screens.filter { !$0.isDisabled(in: disabled) }
    }

    /// Called on display changes (plug, unplug, resolution, and wake from
    /// sleep, which reports a change even when nothing moved). Existing covers
    /// are kept and resized rather than recreated, so the paper doesn't blink;
    /// only covers for displays that are gone or switched off are closed.
    private func rebuildScreenCovers() {
        let screens = Dictionary(enabledScreens.map { ($0.displayKey, $0) }, uniquingKeysWith: { first, _ in first })
        for (key, covers) in spaceCovers {
            guard let screen = screens[key] else {
                // Clear parked marks too: an ObjectIdentifier is reused once
                // its object is freed, and a new cover must not inherit one.
                covers.forEach { $0.orderOut(nil); $0.close(); parked.remove(ObjectIdentifier($0)); appHidden.remove(ObjectIdentifier($0)) }
                spaceCovers[key] = nil
                continue
            }
            for cover in covers {
                cover.place(screen.frame)
            }
        }
        coveredDisplays = enabledScreens.map(\.displayKey)
        refreshVisibility()
    }

    /// Makes sure every enabled display has exactly one cover on the active
    /// Space, creating it on the first visit to that Space.
    @discardableResult
    private func ensureActiveSpaceCovers() -> Set<Int> {
        // What the window server shows right now; isOnActiveSpace is not
        // reliable around full-screen Spaces.
        let showing = Set(CoverManager.windowList(options: [.optionOnScreenOnly]).compactMap {
            $0[kCGWindowNumber as String] as? Int
        })
        for screen in enabledScreens {
            let key = screen.displayKey
            var list = spaceCovers[key] ?? []
            let here = CoverManager.keeperFirst(list.filter { $0.isVisible && showing.contains($0.windowNumber) })
            if here.isEmpty {
                let cover = CoverWindow(frame: screen.frame)
                cover.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
                cover.collectionBehavior = [.transient, .fullScreenAuxiliary, .ignoresCycle]
                styleScreenCover(cover)
                cover.orderFrontRegardless()
                list.append(cover)
            } else {
                // A removed desktop hands its windows to another one; keep one.
                for extra in here.dropFirst() {
                    extra.orderOut(nil)
                    extra.close()
                    list.removeAll { $0 === extra }
                    parked.remove(ObjectIdentifier(extra))
                    appHidden.remove(ObjectIdentifier(extra))
                }
                here[0].place(screen.frame)
            }
            // Bound the pool: drop the oldest covers of Spaces not showing.
            while list.count > 16, let old = list.first(where: { !showing.contains($0.windowNumber) }) {
                old.orderOut(nil)
                old.close()
                list.removeAll { $0 === old }
                parked.remove(ObjectIdentifier(old))
                appHidden.remove(ObjectIdentifier(old))
            }
            spaceCovers[key] = list
        }
        return showing
    }

    // MARK: - Space transitions

    // Leaving full screen destroys that Space and hands its windows, our cover
    // included, to the desktop underneath. The hand-off lands at the end of the
    // exit animation, before macOS reports the Space change, and stacks two
    // papers on the desktop (a visible darkening) until something dedupes
    // them. A light watcher asks the window server about our own covers only
    // (about ten times a second, sixty-plus while a Space is animating) and
    // closes the extra on the frame it lands.

    private var spaceTimer: Timer?
    /// Covers hidden as they slid off with their Space (see `settleScreenCovers`).
    private var parked: Set<ObjectIdentifier> = []
    /// Covers faded because an excluded app was in front on their Space.
    private var appHidden: Set<ObjectIdentifier> = []

    /// Duplicates in keep-first order: a cover already showing paper beats
    /// one that arrived hidden, then the oldest wins.
    private static func keeperFirst(_ covers: [CoverWindow]) -> [CoverWindow] {
        covers.filter { $0.alphaValue > 0 } + covers.filter { $0.alphaValue == 0 }
    }
    private var spaceInterval: TimeInterval = 0
    /// Fast polling runs until then: a cover was seen mid-animation, or a
    /// Space change was just reported.
    private var fastUntil = Date.distantPast
    /// Creating covers is only safe once macOS has reported the new Space; a
    /// window created mid-animation joins the outgoing Space.
    private var createUntil = Date.distantPast

    private func watchSpaceTransition() {
        fastUntil = Date().addingTimeInterval(1.0)
        createUntil = fastUntil
        updateSpaceTimer()
    }

    /// Runs the watcher only while whole-screen paper is showing and some
    /// display has covers on more than one Space (only then can two meet).
    private func updateSpaceTimer() {
        let show = settings.wholeScreen && !suppressed && !frontAppIsExcluded && !capturePickerActive
        let needed = show && spaceCovers.values.contains { $0.count > 1 }
        guard needed else {
            spaceTimer?.invalidate()
            spaceTimer = nil
            return
        }
        let wanted: TimeInterval = Date() < fastUntil ? 1.0 / 120.0 : 1.0 / 10.0
        guard spaceTimer == nil || wanted != spaceInterval else { return }
        spaceTimer?.invalidate()
        spaceInterval = wanted
        let timer = Timer(timeInterval: wanted, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.settleScreenCovers() { self.fastUntil = Date().addingTimeInterval(0.6) }
            self.updateSpaceTimer()
        }
        timer.tolerance = wanted / 4
        RunLoop.main.add(timer, forMode: .common)
        spaceTimer = timer
    }

    /// The cheap per-frame half of `ensureActiveSpaceCovers`. Returns whether
    /// any cover is mid-animation.
    @discardableResult
    private func settleScreenCovers() -> Bool {
        guard settings.wholeScreen, !suppressed, !frontAppIsExcluded, !capturePickerActive else { return false }
        // An ordered-out window can report a non-positive number: skip it.
        var values: [UnsafeRawPointer?] = screenCovers.compactMap {
            $0.windowNumber > 0 ? UnsafeRawPointer(bitPattern: UInt($0.windowNumber)) : nil
        }
        let ids = CFArrayCreate(kCFAllocatorDefault, &values, values.count, nil)
        let entries = CGWindowListCreateDescriptionFromArray(ids) as? [[String: Any]] ?? []
        var onScreen: [Int: CGRect] = [:]
        for entry in entries where entry[kCGWindowIsOnscreen as String] as? Bool ?? false {
            if let id = entry[kCGWindowNumber as String] as? Int,
               let dict = entry[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: dict) {
                onScreen[id] = rect
            }
        }
        var needsCover = false, moving = false
        for screen in enabledScreens {
            let list = spaceCovers[screen.displayKey] ?? []
            let home = CoverManager.cgRect(fromAppKit: screen.frame)
            for cover in list {
                guard let rect = onScreen[cover.windowNumber],
                      abs(rect.minX - home.minX) >= 1 || abs(rect.minY - home.minY) >= 1 else { continue }
                moving = true
                // A cover that has slid (at full size, so not a Mission
                // Control thumbnail) all but off its display is leaving with
                // its Space. If that Space is a full-screen one being closed,
                // macOS moves the cover onto the desktop underneath a moment
                // later; hidden now, it arrives invisible instead of doubling
                // the paper there. Restored when the Space change settles.
                let showingWidth = max(0, min(rect.maxX, home.maxX) - max(rect.minX, home.minX))
                if abs(rect.width - home.width) < 1, abs(rect.minY - home.minY) < 1,
                   showingWidth < home.width * 0.03, cover.alphaValue != 0 {
                    cover.alphaValue = 0
                    parked.insert(ObjectIdentifier(cover))
                }
            }
            // Mid-animation covers sit at shifted positions; only covers at
            // rest on the display can be duplicates.
            let resting = CoverManager.keeperFirst(list.filter { cover in
                onScreen[cover.windowNumber].map { abs($0.minX - home.minX) < 1 && abs($0.minY - home.minY) < 1 } ?? false
            })
            for extra in resting.dropFirst() {
                extra.orderOut(nil)
                extra.close()
                spaceCovers[screen.displayKey]?.removeAll { $0 === extra }
                parked.remove(ObjectIdentifier(extra))
                appHidden.remove(ObjectIdentifier(extra))
            }
            // A hidden cover coming back into view (a swipe reversed midway,
            // or its own Space swiped back to) shows paper again, unless it
            // is the hand-off arriving on a desktop that has its own cover.
            let current = spaceCovers[screen.displayKey] ?? []
            for cover in current where parked.contains(ObjectIdentifier(cover)) {
                guard let rect = onScreen[cover.windowNumber] else { continue }
                let showingWidth = max(0, min(rect.maxX, home.maxX) - max(rect.minX, home.minX))
                let atHome = abs(rect.minX - home.minX) < 1 && abs(rect.minY - home.minY) < 1
                let alone = !current.contains { $0 !== cover && onScreen[$0.windowNumber] != nil }
                if showingWidth >= home.width * 0.03 && (!atHome || alone) {
                    cover.alphaValue = 1
                    parked.remove(ObjectIdentifier(cover))
                }
            }
            if !current.contains(where: { onScreen[$0.windowNumber] != nil }) { needsCover = true }
        }
        if needsCover && !moving && Date() < createUntil { ensureActiveSpaceCovers() }
        return moving
    }

    private func settingsChanged() {
        updateFrontApp()
        appHidden.removeAll() // the excluded list may have changed
        if enabledScreens.map(\.displayKey) != coveredDisplays {
            rebuildScreenCovers()
        } else {
            styleAll()
            refreshVisibility()
        }
    }

    // MARK: - Window covers

    /// Adds a cover to the frontmost app's front window, or removes it if one exists.
    /// Returns the app name that was covered, if any.
    @discardableResult
    func toggleFrontWindowCover() -> String? {
        guard let target = CoverManager.frontWindow() else { return nil }
        if let index = windowCovers.firstIndex(where: { $0.windowID == target.id }) {
            windowCovers[index].window.orderOut(nil)
            windowCovers.remove(at: index)
            updateTimer()
            return nil
        }
        let cover = WindowCover(
            windowID: target.id, ownerPID: target.pid, appName: target.appName,
            style: settings.style, frame: target.frame
        )
        windowCovers.append(cover)
        style(cover)
        updateTimer()
        forceFullScan = true
        tick()
        return target.appName
    }

    func removeAllWindowCovers() {
        windowCovers.forEach { $0.window.orderOut(nil) }
        windowCovers.removeAll()
        updateTimer()
    }

    /// The cover on the frontmost window, if the user has added one. Another
    /// window of the same app having a cover doesn't count: the hotkeys and
    /// the menu's window section act on the window in front.
    var frontAppCover: WindowCover? {
        guard let pid = CoverManager.frontApp?.processIdentifier else { return nil }
        if let front = CoverManager.frontWindow() {
            return windowCovers.first { $0.windowID == front.id }
        }
        // No ordinary window found (mid transition, say): the app's cover.
        return windowCovers.first { $0.ownerPID == pid }
    }

    /// Changes one window cover's own style.
    func update(_ cover: WindowCover, _ change: (inout CoverStyle) -> Void) {
        var style = cover.style
        change(&style)
        style = style.clamped
        guard style != cover.style else { return }
        cover.style = style
        self.style(cover)
    }

    /// 60 Hz while anything tracked is moving; 10 Hz after one still second.
    /// Attached trials keep 30 Hz at rest to reduce onset latency (measured
    /// one-window idle 0.85% CPU, below the existing 2% budget).
    private var trackingInterval: TimeInterval = 1.0 / 60.0
    /// The frontmost app owns a visible window cover and has at least two
    /// normal windows on screen. Updated on every full scan.
    private var sameAppWatch = false
    private var lastChange = Date()

    // While the covered app is in front with other windows of its own, any
    // click or Cmd-` can raise the covered window over its cover. There is no
    // notification for that (and no input monitoring, by design), so the
    // tracking timer speeds up to `watchRate` and checks the stacking on
    // every tick until the app leaves the front. The check is one window
    // server call per cover for window numbers only; the position scan still
    // runs at about 10 Hz in between. One timer does both, and it stops when
    // there are no covers or none can show.
    //
    // Measured, TextEdit in front with two windows, one covered (perf.sh):
    // 30 Hz 1.1%, 45 Hz 1.7%, 60 Hz 2.1%, 120 Hz 3.5% CPU; worst blink on a
    // click or Cmd-` 44 / 33 / 32 ms. 45 Hz stays under 2%.
    /// Checks per second while watching (harness: defaults key `restackWatchHz`).
    private static let watchRate: Double = {
        let hz = UserDefaults.standard.double(forKey: "restackWatchHz")
        return hz >= 10 && hz <= 120 ? hz : 45
    }()
    private var lastScan: CFAbsoluteTime = 0

    private func updateTimer() {
        updateCapturePickerTimer()
        // Nothing to track while no cover can show (snoozed, paused by
        // schedule or battery, an excluded app in front, or whole-screen
        // paper on). Every change out of those states calls
        // refreshVisibility, whose tick restarts the timer.
        if windowCovers.isEmpty || suppressed || frontAppIsExcluded || settings.wholeScreen {
            trackingTimer?.invalidate()
            trackingTimer = nil
            return
        }
        let still = Date().timeIntervalSince(lastChange) > 1
        // Measured with a real mouse drag (drag_ab.sh, vsync probe, two
        // Macs): a 60 Hz Timer left the cover about two frames behind,
        // uneven. 240 Hz halves that to about one frame, the floor for a
        // window the server moves itself; 360 Hz gained nothing more.
        // The cost is the same as 60 Hz was (about 12% CPU for the
        // duration of the drag, nothing at rest) because a moving tick
        // takes the fast path below instead of a full scan.
        let moving: TimeInterval = 1.0 / 240.0
        let rest: TimeInterval = CoverManager.attachedVariant == nil ? 1.0 / 10.0 : 1.0 / 30.0
        let wanted: TimeInterval = sameAppWatch ? 1.0 / max(CoverManager.watchRate, still ? 0 : 1 / moving)
            : still ? rest : moving
        if trackingTimer == nil || wanted != trackingInterval {
            trackingTimer?.invalidate()
            trackingInterval = wanted
            let timer = Timer(timeInterval: wanted, repeats: true) { [weak self] _ in self?.tick() }
            timer.tolerance = sameAppWatch ? min(0.002, wanted / 4) : wanted / 4
            RunLoop.main.add(timer, forMode: .common)
            trackingTimer = timer
        }
    }

    /// The per-tick scan already holds every tracked window's rect, so a
    /// plain move places the covers from it at once; tab strips, stacking
    /// and Space checks wait for a full scan, at most every 100 ms while
    /// something moves. Returns false when something needs the full scan.
    private func fastPlace(_ signature: [TrackedState]) -> Bool {
        guard !forceFullScan, !windowCovers.isEmpty,
              !(suppressed || frontAppIsExcluded || settings.wholeScreen || capturePickerActive) else { return false }
        let old = Dictionary(lastSignature.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let new = Dictionary(signature.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for cover in windowCovers {
            guard let was = old[cover.windowID], let now = new[cover.windowID], was.onScreen, now.onScreen,
                  cover.window.isVisible, !cover.inTransition, !cover.minimizeFade.isHidden,
                  !cover.window.isRibbonActive, cover.window.alphaValue == 1, let last = cover.lastRect,
                  // Same size: a resize or full-screen change wants the full scan.
                  abs(now.rect.width - last.width) < 1, abs(now.rect.height - last.height) < 1,
                  // The cover itself stayed where it was put (no Space slide).
                  let mine = new[CGWindowID(cover.window.windowNumber)], mine.onScreen,
                  CoverManager.cgRect(fromAppKit: cover.window.frame) == mine.rect || !mine.onScreen
            else { return false }
            if now.rect != was.rect {
                // Keep the full scan's extension over a docked tab strip.
                let strip = CoverManager.cgRect(fromAppKit: cover.window.frame)
                let dx = strip.minX - last.minX, dy = strip.minY - last.minY
                var rect = now.rect
                rect.origin.x += dx; rect.origin.y += dy
                rect.size = strip.size
                cover.window.place(CoverManager.appKitFrame(fromCG: rect))
                cover.lastRect = now.rect
            }
        }
        return true
    }

    /// Puts every resting cover straight back over its window if anything
    /// got between them.
    private func restackResting() {
        guard !(suppressed || frontAppIsExcluded || settings.wholeScreen) else { return }
        for cover in windowCovers where cover.window.isVisible && cover.window.level == .normal
            && !cover.inTransition {
            CoverManager.keepAbove(cover)
        }
    }

    /// Tracks the missing-window grace and keeps full scans active only until
    /// the existing settle interval expires. A visible window clears the state.
    static func missingWindowNeedsScan(
        isOnScreen: Bool, missingSince: inout Date?, now: Date, settle: TimeInterval
    ) -> Bool {
        if isOnScreen {
            missingSince = nil
            return false
        }
        if missingSince == nil { missingSince = now }
        return now.timeIntervalSince(missingSince!) < settle
    }

    /// Follows every tracked window: resize, reposition, and restack above it.
    private func fullTick() {
        guard !windowCovers.isEmpty else { return }
        var needsAnotherScan = false
        let onScreen = CoverManager.windowList(options: [.optionOnScreenOnly, .excludeDesktopElements])
        var bounds: [CGWindowID: CGRect] = [:]
        var normalWindows: [(id: CGWindowID, pid: pid_t, rect: CGRect)] = []
        for entry in onScreen {
            if let id = entry[kCGWindowNumber as String] as? CGWindowID,
               let dict = entry[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: dict) {
                bounds[id] = rect
                if (entry[kCGWindowLayer as String] as? Int) == 0,
                   let pid = entry[kCGWindowOwnerPID as String] as? pid_t {
                    normalWindows.append((id, pid, rect))
                }
            }
        }
        // Mission Control and App Exposé expose a display-sized WindowManager
        // window before transforming application windows. A revealed Dock
        // also exposes a display-sized Dock window, including while a window
        // animates into or out of it, so target movement cannot identify an
        // overview. Use WindowManager to enter; keep covers hidden until the
        // Dock overlay leaves so they cannot chase closing thumbnails or be
        // re-created on the wrong Space during the overview.
        let dockOverlay = CoverManager.systemOverlayShowing(in: onScreen)
        if !overviewActive, CoverManager.systemOverviewStarting(
            in: onScreen, displays: NSScreen.screens.map { CoverManager.cgRect(fromAppKit: $0.frame) }
        ) {
            overviewActive = true
        }
        if dockOverlay && overviewActive {
            windowCovers.forEach { $0.window.cancelRibbon() }
            for cover in windowCovers where cover.window.alphaValue != 0 {
                cover.window.alphaValue = 0
            }
            lastFullScan = Date()
            lastChange = Date()
            forceFullScan = true
            lastSignature = trackedSignature()
            updateTimer()
            return
        }
        let leavingOverview = overviewActive
        overviewActive = false
        // Updated as covers re-attach below, so two covers can never claim
        // the same window within one scan.
        var coveredIDs = Set(windowCovers.map(\.windowID))
        let now = Date()
        // When a tracked window vanishes, wait this long before reacting. A
        // desktop swipe needs a moment before macOS reports the new active
        // Space; reacting sooner lets a look-alike window on the incoming
        // desktop steal the cover.
        let settle: TimeInterval = 0.25
        let missingFor = { (cover: WindowCover) in cover.missingSince.map { now.timeIntervalSince($0) } ?? 0 }

        // While macOS animates a window into or out of full screen, the real
        // window leaves the on-screen list and the app shows a short-lived
        // stand-in that fills the whole display (notch area included). The
        // cover must neither follow the stand-in nor linger over the old
        // Space: it hides until the real window lands.
        let displays = NSScreen.screens.map { CoverManager.cgRect(fromAppKit: $0.frame) }
        let fillsDisplay = { (r: CGRect) in
            displays.contains {
                abs($0.minX - r.minX) < 1 && abs($0.minY - r.minY) < 1
                    && abs($0.width - r.width) < 1 && abs($0.height - r.height) < 1
            }
        }
        for cover in windowCovers where bounds[cover.windowID] == nil {
            for other in normalWindows where other.pid == cover.ownerPID
                && !coveredIDs.contains(other.id) && fillsDisplay(other.rect) {
                if transitionProxies[other.id] == nil { transitionProxies[other.id] = now }
                beginTransition(cover)
            }
        }
        transitionProxies = transitionProxies.filter { bounds[$0.key] != nil }
        // A stand-in lives well under a second; a display-sized window that
        // stays is a real one (an app that gives its full-screen window a new ID).
        let proxies = transitionProxies
        let isProxy = { (id: CGWindowID) in proxies[id].map { now.timeIntervalSince($0) < 1.5 } ?? false }
        var existingIDs: Set<CGWindowID>?
        let exists = { (id: CGWindowID) in
            // optionIncludingWindow alone is not an existence query: it can
            // omit a minimized ID. Scan all windows once, lazily, so a long
            // minimize cannot be mistaken for closing the tracked window.
            if existingIDs == nil {
                existingIDs = Set(CoverManager.windowList(options: [.optionAll]).compactMap {
                    $0[kCGWindowNumber as String] as? CGWindowID
                })
            }
            return existingIDs!.contains(id)
        }
        // A cover left on a Space that isn't showing is waiting for the swipe
        // back; same-sized windows of that app elsewhere must not steal it.
        let waitingOnOtherSpace = { (cover: WindowCover) in
            cover.window.isVisible && !cover.window.isOnActiveSpace
        }
        let mayReattach = { (cover: WindowCover) in
            bounds[cover.windowID] == nil && missingFor(cover) >= settle && !waitingOnOtherSpace(cover)
        }

        // Native macOS tabs are separate windows sharing one frame. When the
        // tracked tab is hidden or closed, follow the sibling now showing in
        // the same place.
        for cover in windowCovers where mayReattach(cover) {
            guard let last = cover.lastRect,
                  let sibling = normalWindows.first(where: {
                      $0.pid == cover.ownerPID && !coveredIDs.contains($0.id) && !isProxy($0.id)
                          && abs($0.rect.minX - last.minX) < 2 && abs($0.rect.minY - last.minY) < 2
                          && abs($0.rect.width - last.width) < 2 && abs($0.rect.height - last.height) < 40
                  }) else { continue }
            cover.windowID = sibling.id
            coveredIDs.insert(sibling.id)
        }

        // Entering or leaving full screen moves the window to another Space and
        // can give it a new ID at a new size. If the covered app is in front
        // and its tracked window is gone, re-attach to its front window.
        if windowCovers.contains(where: mayReattach), let front = CoverManager.frontWindow() {
            let fillsScreen = CoverManager.isFullScreenFrame
            for cover in windowCovers where mayReattach(cover)
                && cover.ownerPID == front.pid && !coveredIDs.contains(front.id) && !isProxy(front.id) {
                // Most apps keep the window's ID through the transition; wait
                // for it rather than jump to another window, unless it is gone.
                guard missingFor(cover) > 1.5 || !exists(cover.windowID) else { continue }
                let wasFullScreen = cover.lastRect.map { fillsScreen(CoverManager.appKitFrame(fromCG: $0)) } ?? false
                // Only full-screen transitions justify re-attaching: a closed window
                // followed by a new document is a different window.
                guard wasFullScreen || fillsScreen(front.frame) else { continue }
                cover.windowID = front.id
                coveredIDs.insert(front.id)
                break
            }
        }
        // Belt and braces: one cover per window, the oldest kept. Stacked
        // panels would exceed the 60% cap.
        var claimed = Set<CGWindowID>()
        windowCovers.removeAll { cover in
            if claimed.insert(cover.windowID).inserted { return false }
            cover.window.orderOut(nil)
            cover.window.close()
            lifted.removeAll { $0 == ObjectIdentifier(cover) }
            return true
        }
        // While Paper Whole Screen is on, the screen is already covered;
        // window covers pause so nothing gets a double layer.
        let hideAll = suppressed || frontAppIsExcluded || settings.wholeScreen || capturePickerActive
        // These modes stop the tracking timer. Hide every panel before that
        // happens, including targets absent inside the reattachment grace.
        if hideAll { windowCovers.forEach { $0.window.orderOut(nil) } }

        windowCovers.removeAll { cover in
            // A window missing from the on-screen list is minimized, hidden,
            // on another Space, mid tab switch, or closed.
            guard var rect = bounds[cover.windowID] else {
                _ = cover.minimizeFade.observe(nil, at: CFAbsoluteTimeGetCurrent(), nearDisplayEdge: false)
                if Self.attachedVariant != nil, !waitingOnOtherSpace(cover) {
                    let sameFrameSibling = cover.lastRect.map { last in
                        normalWindows.contains {
                            $0.pid == cover.ownerPID && !coveredIDs.contains($0.id) && !isProxy($0.id)
                                && abs($0.rect.minX - last.minX) < 2 && abs($0.rect.minY - last.minY) < 2
                                && abs($0.rect.width - last.width) < 2 && abs($0.rect.height - last.height) < 40
                        }
                    } ?? false
                    // Hide confirmed departure/closure immediately. A live
                    // tab or metadata gap retains its reattachment grace.
                    if cover.window.isRibbonActive || cover.minimizeFade.isHidden
                        || (!exists(cover.windowID) && !sameFrameSibling) {
                        cover.window.orderOut(nil)
                    }
                }
                if !hideAll, cover.window.isRibbonActive {
                    if exists(cover.windowID) {
                        needsAnotherScan = true
                        return false
                    }
                    // Closed target: cancel now instead of finishing a paper
                    // animation detached from any window. Minimized IDs exist.
                    cover.window.orderOut(nil)
                }
                let gracePending = CoverManager.missingWindowNeedsScan(
                    isOnScreen: false, missingSince: &cover.missingSince, now: now, settle: settle
                )
                // Mid full-screen animation: stay hidden and keep scanning at
                // the fast rate so the cover reappears the moment it lands.
                if cover.inTransition && missingFor(cover) < 3 {
                    needsAnotherScan = true
                    return false
                }
                // Hold still until the situation settles. For a tab switch the
                // new tab sits in the same place, so the cover keeps covering it.
                if gracePending {
                    needsAnotherScan = true
                    return false
                }
                let stillExists = exists(cover.windowID)
                // Its Space isn't showing: the cover sits on that Space too, so
                // leave it in place for the swipe back.
                if stillExists && waitingOnOtherSpace(cover) { return false }
                // Minimized, hidden or closed. Keep the cover through
                // full-screen transitions; drop it once closed for a while.
                cover.window.orderOut(nil)
                return !stillExists && missingFor(cover) > 3
            }
            _ = CoverManager.missingWindowNeedsScan(
                isOnScreen: true, missingSince: &cover.missingSince, now: now, settle: settle
            )
            cover.lastRect = rect
            let fadeAction = cover.minimizeFade.observe(
                rect, at: CFAbsoluteTimeGetCurrent(), nearDisplayEdge: displays.contains { display in
                    rect.intersects(display) && (rect.minX <= display.minX + 24 || rect.maxX >= display.maxX - 24
                        || rect.minY <= display.minY + 24 || rect.maxY >= display.maxY - 24)
                }
            )
            if hideAll { cover.minimizeFade = MinimizeFade(detectShallowStretch: CoverManager.ribbonTrial) }
            if !hideAll, cover.minimizeFade.isHidden {
                if let variant = CoverManager.attachedVariant, let source = cover.minimizeFade.restingRect {
                    let target = CoverManager.appKitFrame(fromCG: rect)
                    let settled = abs(rect.minX - source.minX) <= 2 && abs(rect.minY - source.minY) <= 2
                        && abs(rect.width - source.width) <= 2 && abs(rect.height - source.height) <= 2
                    let tiny = min(rect.width / source.width, rect.height / source.height) < 0.10
                    if tiny {
                        cover.window.alphaValue = 0
                        cover.window.orderOut(nil)
                    } else if settled {
                        // Visibility follows geometry now. The existing stable
                        // guard only commits the resting footprint afterwards.
                        if cover.window.isRibbonActive {
                            cover.window.observeAttachedPaper(target)
                        } else {
                            cover.window.place(target)
                            cover.window.alphaValue = 1
                        }
                        CoverManager.keepAbove(cover)
                        needsAnotherScan = true
                    } else {
                        if !cover.window.isRibbonActive {
                            cover.window.place(CoverManager.appKitFrame(fromCG: source))
                            cover.window.level = .normal
                            lifted.removeAll { $0 == ObjectIdentifier(cover) }
                            CoverManager.keepAbove(cover)
                            if !cover.window.beginAttachedPaper(target: target, variant: variant,
                                                                restoring: fadeAction != .fadeOut,
                                                                raiseDuringMotion: ProcessInfo.processInfo.arguments.contains("--attached-front")) {
                                cover.window.alphaValue = 0
                            }
                        } else {
                            cover.window.observeAttachedPaper(target)
                            CoverManager.keepAbove(cover)
                        }
                        needsAnotherScan = true
                    }
                    return false
                }
                if fadeAction == .fadeOut {
                    var began = false
                    if CoverManager.ribbonTrial, let source = cover.minimizeFade.restingRect {
                        cover.window.place(CoverManager.appKitFrame(fromCG: source))
                        cover.window.level = .normal
                        lifted.removeAll { $0 == ObjectIdentifier(cover) }
                        CoverManager.keepAbove(cover)
                        began = cover.window.beginRibbon(restoring: false)
                    }
                    if !began {
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0.08
                            cover.window.animator().alphaValue = 0
                        }
                    }
                }
                if cover.window.isRibbonActive {
                    cover.window.observeRibbonTarget(CoverManager.appKitFrame(fromCG: rect))
                    CoverManager.keepAbove(cover)
                    needsAnotherScan = true
                }
                // Once fading, do not stretch/redraw a panel to follow the
                // Genie mesh or tiny Dock thumbnail. Existing metadata scans
                // still follow the target so restore needs no new timer.
                return false
            }
            // The restore renderer owns its fixed material footprint until
            // it unfolds. Full scans continue to enforce visibility/lifecycle.
            if cover.window.isRibbonActive {
                if CoverManager.attachedVariant != nil {
                    cover.window.observeAttachedPaper(CoverManager.appKitFrame(fromCG: rect))
                }
                needsAnotherScan = true
                return false
            }
            // Some apps (Ghostty, for one) draw their tab bar as a separate,
            // full-width window docked to the top of the main window. Grow the
            // cover over any such strip and stack above whichever is frontmost.
            var stackAbove = cover.windowID
            let main = rect
            for other in normalWindows where other.pid == cover.ownerPID && other.id != cover.windowID {
                let strip = other.rect
                guard abs(strip.minX - main.minX) < 2, abs(strip.width - main.width) < 2,
                      strip.height < 150, strip.minY < main.minY, strip.maxY >= main.minY - 2 else { continue }
                rect = rect.union(strip)
                if (normalWindows.firstIndex(where: { $0.id == other.id }) ?? .max) <
                    (normalWindows.firstIndex(where: { $0.id == stackAbove }) ?? .max) {
                    stackAbove = other.id
                }
            }
            // During a desktop swipe macOS slides the whole Space, cover
            // included, and reports every window at its shifted position.
            // Moving the cover to the target's shifted spot would add the
            // offset twice, so let the system animate it.
            let home = CoverManager.cgRect(fromAppKit: cover.window.frame)
            if cover.window.isVisible,
               let drawn = bounds[CGWindowID(cover.window.windowNumber)],
               abs(drawn.minX - home.minX) > 1 || abs(drawn.minY - home.minY) > 1 {
                if cover.inTransition {
                    // The window rides the same slide at the cover's own
                    // shifted spot and size: this is a desktop swipe back
                    // from another full-screen Space of the same app (which
                    // looked like a transition stand-in while away), not a
                    // full-screen animation. Show it for the slide instead
                    // of popping in once the Space lands. (The cover can be
                    // taller over a tab strip, so compare left, bottom, width.)
                    if abs(main.minX - drawn.minX) < 2, abs(main.maxY - drawn.maxY) < 2,
                       abs(main.width - drawn.width) < 2 {
                        endTransition(cover)
                        return false
                    }
                    // Hidden for a full-screen transition: wait for the
                    // window to land somewhere.
                    needsAnotherScan = true
                    return false
                }
                // The cover's Space is sliding away but the window stayed put
                // where the cover rests: it is being lifted into full screen.
                // Hide now rather than slide off visibly without it.
                if cover.window.level != .floating, abs(main.minX - home.minX) < 1, abs(main.maxY - home.maxY) < 1 {
                    beginTransition(cover)
                    needsAnotherScan = true
                }
                return false
            }
            if hideAll {
                cover.window.orderOut(nil)
                endTransition(cover)
            } else {
                let frame = CoverManager.appKitFrame(fromCG: rect)
                cover.window.place(frame)
                // A native full-screen window lives on its own Space above
                // normal-level windows, so its cover must float instead.
                let fullScreen = CoverManager.isFullScreenFrame(frame)
                cover.window.cornerRadius = fullScreen ? 0 : cover.cornerRadius
                // The window is on screen but its cover isn't: the window
                // reached this Space without it (moved, or in or out of full
                // screen). Re-home the cover here. The window server's own
                // on-screen list is the reliable signal; isOnActiveSpace is not
                // for another app's full-screen Space.
                let coverOnScreen = bounds[CGWindowID(cover.window.windowNumber)] != nil
                let stranded = cover.window.isVisible && (!coverOnScreen || !cover.window.isOnActiveSpace)
                let now = CFAbsoluteTimeGetCurrent()
                if !stranded { cover.strandedSince = nil } else if cover.strandedSince == nil { cover.strandedSince = now }
                // Keep scanning every tick until it's confirmed either way.
                if stranded { needsAnotherScan = true }
                // A cover can be missing for a frame or two mid-swipe and
                // just after the Space lands, so wait before re-homing. The
                // wait is in time, not scans: scans run at 240 Hz while
                // windows move, and four of them passed before a landed
                // swipe settled, tearing the cover down for ~50 ms at the
                // end of half the swipes on a 120 Hz display
                // (scenarios_spaces.sh B1). 50 ms clears that landing, and
                // a window really carried to another desktop is covered
                // again as soon as before (carry_run.sh). After a
                // full-screen transition the window has landed, so re-home
                // at once.
                if (cover.strandedSince.map { now - $0 >= 0.05 } ?? false) || (stranded && cover.inTransition) {
                    cover.strandedSince = nil
                    cover.replaceWindow()
                    style(cover)
                    cover.window.place(frame)
                    cover.window.cornerRadius = fullScreen ? 0 : cover.cornerRadius
                }
                cover.stackAbove = stackAbove
                // Order the previously hidden cover before giving Metal a
                // drawable; retain zero alpha until its material is ready.
                if fadeAction == .fadeIn && CoverManager.attachedVariant == nil { cover.window.alphaValue = 0 }
                if fullScreen {
                    if cover.window.level != .floating { cover.window.level = .floating }
                    if !cover.window.isVisible { cover.window.orderFrontRegardless() }
                } else {
                    // Clicking a window re-orders it to the front of its
                    // level even when it is already there, above a cover
                    // ordered relative to it; the cover caught up a frame or
                    // two later, a flash on every click (measured: 17 bare
                    // frames in 12 clicks on Safari, click_flash_run.sh).
                    // So while nothing overlaps the window, its cover lives
                    // one level up, where no raise at the normal level can
                    // pass it, and looks the same. It drops back to the
                    // normal level, directly above its window, only while
                    // another window actually overlaps it in front.
                    let mine = CoverManager.cgRect(fromAppKit: cover.window.frame).insetBy(dx: 2, dy: 2)
                    let index = normalWindows.firstIndex { $0.id == cover.windowID } ?? 0
                    // While the cover's own app is activating, every other
                    // app's windows are about to go behind it, so only its
                    // own windows count; counting another app's window still
                    // on top would drop the cover a frame before the raise.
                    let own = cover.ownerPID == activatingPID
                    let obstructed = normalWindows[..<index].contains {
                        $0.id != stackAbove && (!own || $0.pid == cover.ownerPID) && $0.rect.intersects(mine)
                    }
                    let id = ObjectIdentifier(cover)
                    if obstructed {
                        lifted.removeAll { $0 == id }
                        if cover.window.level != .normal { cover.window.level = .normal }
                        CoverManager.keepAbove(cover)
                    } else {
                        if cover.window.level != CoverManager.liftedLevel { cover.window.level = CoverManager.liftedLevel }
                        // A new or re-homed cover has not been ordered in yet.
                        if !cover.window.isVisible { cover.window.orderFrontRegardless() }
                        if !lifted.contains(id) { lifted.append(id) }
                    }
                }
                let ribbonRestore = fadeAction == .fadeIn && CoverManager.ribbonTrial && CoverManager.attachedVariant == nil
                    && cover.window.beginRibbon(restoring: true)
                endTransition(cover, fade: leavingOverview || (fadeAction == .fadeIn && !ribbonRestore && CoverManager.attachedVariant == nil))
            }
            return false
        }
        sameAppWatch = !(suppressed || frontAppIsExcluded || settings.wholeScreen) && frontPID.map { pid in
            windowCovers.contains { $0.ownerPID == pid && $0.window.isVisible && !$0.inTransition }
                && normalWindows.filter { $0.pid == pid }.count >= 2
        } ?? false
        // Warm only the front app's resting cover. A single global snapshot
        // bounds memory even with many covers; size is checked on reuse and
        // style/density changes invalidate it. Retain the resting size through
        // the first Genie stretch. No work is added to ordinary dragging.
        if Self.attachedVariant != nil, Date().timeIntervalSince(lastChange) > 0.15,
           let cover = windowCovers.first(where: {
               $0.ownerPID == frontPID && $0.window.isVisible && !$0.inTransition
                   && !$0.minimizeFade.isHidden && !$0.window.isRibbonActive
           }) {
            cover.window.preparePaperForMotion()
        }
        lastFullScan = Date()
        forceFullScan = needsAnotherScan
        if needsAnotherScan { lastChange = Date() } // stay at the fast rate
        lastSignature = trackedSignature()
        updateTimer()
    }

    /// Stand-in windows seen during full-screen transitions, and when.
    private var transitionProxies: [CGWindowID: Date] = [:]

    private func beginTransition(_ cover: WindowCover) {
        guard !cover.inTransition else { return }
        cover.window.cancelRibbon()
        cover.inTransition = true
        cover.minimizeFade = MinimizeFade(detectShallowStretch: CoverManager.ribbonTrial)
        cover.window.alphaValue = 0
    }

    private func endTransition(_ cover: WindowCover, fade: Bool = false) {
        cover.inTransition = false
        if cover.window.isRestoreFadeActive { return }
        // Alpha is animated asynchronously. A later geometry scan must not
        // replace an in-progress minimize restore fade with an immediate 1.
        if !fade, cover.minimizeFade.isFadingIn(at: CFAbsoluteTimeGetCurrent()) { return }
        guard cover.window.alphaValue != 1 else { return }
        if fade {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                cover.window.animator().alphaValue = 1
            }
        } else {
            cover.window.alphaValue = 1
        }
    }

    /// Mission Control, App Exposé, Show Desktop or Launchpad is showing.
    private var overviewActive = false

    /// Whether the Dock's display-sized window is on screen: the window-list
    /// signal shared by Mission Control, App Exposé and Show Desktop (and a
    /// revealed auto-hidden Dock; see fullTick). Public CoreGraphics data only.
    static func systemOverlayShowing(in onScreen: [[String: Any]]) -> Bool {
        let displays = NSScreen.screens.map { cgRect(fromAppKit: $0.frame) }
        return onScreen.contains { entry in
            guard (entry[kCGWindowOwnerName as String] as? String) == "Dock",
                  (entry[kCGWindowLayer as String] as? Int) ?? 0 >= Int(CGWindowLevelForKey(.dockWindow)),
                  let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict) else { return false }
            return displays.contains {
                abs($0.minX - r.minX) < 1 && abs($0.minY - r.minY) < 1
                    && abs($0.width - r.width) < 1 && abs($0.height - r.height) < 1
            }
        }
    }

    /// Mission Control and App Exposé expose, before moving application
    /// windows, either a display-sized WindowManager layer-19 window or (on
    /// systems that never create one, see issue #12) a second display-sized
    /// Dock window next to the layer-20 overlay. Dock hover during minimize or
    /// restore exposes neither: a revealed Dock is the single overlay. The
    /// input is the shared on-screen inventory; this uses only public window
    /// metadata.
    static func systemOverviewStarting(in onScreen: [[String: Any]], displays: [CGRect]) -> Bool {
        func displaySized(_ entry: [String: Any]) -> Bool {
            guard let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict) else { return false }
            return displays.contains {
                abs($0.minX - rect.minX) < 1 && abs($0.minY - rect.minY) < 1
                    && abs($0.width - rect.width) < 1 && abs($0.height - rect.height) < 1
            }
        }
        let windowManager = onScreen.contains { entry in
            (entry[kCGWindowOwnerName as String] as? String) == "WindowManager"
                && (entry[kCGWindowLayer as String] as? Int) == 19
                && displaySized(entry)
        }
        if windowManager { return true }
        var dockWindows = Set<CGWindowID>()
        for entry in onScreen
        where (entry[kCGWindowOwnerName as String] as? String) == "Dock"
            && (entry[kCGWindowLayer as String] as? Int) ?? -1 >= 0
            && displaySized(entry) {
            guard let id = entry[kCGWindowNumber as String] as? NSNumber else { continue }
            dockWindows.insert(id.uint32Value)
        }
        return dockWindows.count >= 2
    }

    // MARK: - Tracking fast path

    private struct TrackedState: Equatable {
        let id: CGWindowID
        let rect: CGRect
        let onScreen: Bool
    }

    private var lastFullScan = Date.distantPast
    private var lastSignature: [TrackedState] = []
    private var tickCount = 0
    /// Set when something outside the tracked windows changed (activation,
    /// Space switch, new cover) so the next tick does a full scan.
    private var forceFullScan = true

    /// Runs on the tracking timer. Asking the window server about only the
    /// tracked windows is cheap; the full scan (tab strips, tab switches, full
    /// screen) runs only when one of them changed, or twice a second.
    private func tick() {
        guard !windowCovers.isEmpty else { return }
        let now = CFAbsoluteTimeGetCurrent()
        // Watching a still window at the fast rate: between position scans
        // (about ten a second), only the stacking can need attention.
        if CoverManager.attachedVariant == nil, sameAppWatch, !forceFullScan, now - lastScan < 0.095, Date().timeIntervalSince(lastChange) > 1 {
            restackLifted()
            restackResting()
            return
        }
        lastScan = now
        tickCount &+= 1
        let signature = trackedSignature()
        if signature != lastSignature {
            lastChange = Date()
        }
        if signature != lastSignature, Date().timeIntervalSince(lastFullScan) < 0.1, fastPlace(signature) {
            lastSignature = signature
            updateTimer()
            return
        }
        if forceFullScan || windowCovers.contains(where: { $0.minimizeFade.isRestoring })
            || Date().timeIntervalSince(lastFullScan) > (trackingInterval > 1.0 / 30.0 ? 1.0 : 0.5) || signature != lastSignature {
            fullTick()
            return
        }
        updateTimer() // drop to the idle rate once things have been still
        // Nothing moved. Something may still have been raised over a cover
        // (clicking the covered window brings it forward): restack if so,
        // on every tick while watching, else 10-20 times a second.
        guard sameAppWatch || trackingInterval > 1.0 / 30.0 || tickCount % 3 == 0 else { return }
        restackLifted()
        restackResting()
    }

    private var burstTimer: Timer?
    private var burstUntil = Date.distantPast

    // Raising a window (activating its app from the Dock, Cmd-Tab or
    // `open -a`, or simply clicking it) puts it above any cover ordered
    // relative to it; the cover could only catch up a frame afterwards, a
    // visible blink. So a cover whose window has nothing overlapping it in
    // front sits one level above normal windows, where a raise can't reach
    // it; it settles back to the normal level, directly above its window,
    // only while another window overlaps it (see fullTick and restackNow).
    // Activation lifts at once, before the raise, then restacks at display
    // rate for a moment in case one of the app's other windows comes over.
    private static let liftedLevel = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)

    private var lifted: [ObjectIdentifier] = []
    /// The app whose activation burst is running, if any: its covers ignore
    /// other apps' windows until the burst ends (see fullTick, restackNow).
    private var activatingPID: pid_t?

    private func activated(pid: pid_t?) {
        guard !windowCovers.isEmpty else { return }
        let showing = !(suppressed || frontAppIsExcluded || settings.wholeScreen)
        activatingPID = pid
        // A click activates the app too, and may raise one of its other
        // windows over the covered one; restackNow lowers the cover then.
        if showing, let pid {
            let normals = CoverManager.windowList(options: [.optionOnScreenOnly, .excludeDesktopElements]).filter {
                ($0[kCGWindowLayer as String] as? Int) == 0 && ($0[kCGWindowOwnerPID as String] as? pid_t) == pid
            }
            for cover in windowCovers where cover.ownerPID == pid && cover.window.isVisible
                && cover.window.level == .normal && !cover.inTransition {
                // Activation keeps the app's windows in their order. One of
                // them in front of this window would end up under the lifted
                // cover; leave that case to the restack.
                let mine = CoverManager.cgRect(fromAppKit: cover.window.frame)
                guard let index = normals.firstIndex(where: {
                    ($0[kCGWindowNumber as String] as? CGWindowID) == cover.windowID
                }) else { continue }
                let overlapped = normals[..<index].contains { entry in
                    guard let id = entry[kCGWindowNumber as String] as? CGWindowID,
                          id != cover.stackAbove,
                          let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                          let r = CGRect(dictionaryRepresentation: dict) else { return false }
                    return r.intersects(mine.insetBy(dx: 2, dy: 2))
                }
                guard !overlapped else { continue }
                cover.window.level = CoverManager.liftedLevel
                lifted.append(ObjectIdentifier(cover))
            }
        }
        // A different app coming forward over the covered window drops its
        // cover in restackNow, as soon as that window is above.
        restackBurst()
    }

    /// Restacks every visible window cover now and at display rate for the
    /// next 600 ms, while an activating app raises its windows.
    private func restackBurst() {
        guard !windowCovers.isEmpty else { return }
        restackNow()
        burstUntil = Date().addingTimeInterval(0.6)
        guard burstTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.restackNow()
            if Date() > self.burstUntil {
                self.activatingPID = nil
                timer.invalidate()
                self.burstTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        burstTimer = timer
    }

    private func restackNow() {
        guard !(suppressed || frontAppIsExcluded || settings.wholeScreen) else { return }
        // A lifted cover must not stay over a window raised above its own.
        for cover in windowCovers where cover.window.level == CoverManager.liftedLevel
            && lifted.contains(ObjectIdentifier(cover)) {
            lowerIfRaisedOver(cover)
        }
        restackResting()
    }

    /// Drops a lifted cover back to the normal level, directly above its
    /// window, when another window has come over that window.
    private func lowerIfRaisedOver(_ cover: WindowCover) {
        let target = cover.stackAbove ?? cover.windowID
        let mine = CoverManager.cgRect(fromAppKit: cover.window.frame).insetBy(dx: 2, dy: 2)
        let above = CoverManager.windowList(options: [.optionOnScreenAboveWindow], relativeTo: target)
        // Its own app's windows always count; other apps' only when
        // this app is not the one activating (those are going behind).
        let own = cover.ownerPID == activatingPID
        let raised = above.contains { entry in
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  !own || (entry[kCGWindowOwnerPID as String] as? pid_t) == cover.ownerPID,
                  let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict) else { return false }
            return r.intersects(mine)
        }
        if raised {
            cover.window.level = .normal
            cover.window.order(.above, relativeTo: Int(target))
            lifted.removeAll { $0 == ObjectIdentifier(cover) }
        }
    }

    // Clicking another window of the covered app raises it to the front of
    // the normal level, under a lifted cover, which then paints over the
    // part of that window overlapping its own. A click inside the front app
    // sends no activation, so no burst runs, and the next full scan may be
    // half a second away (measured: the cover stayed over the clicked
    // window for 10-561 ms, median 298, in 40 of 40 clicks; issue #37). So
    // the tracking timer checks lifted covers too. Anything coming over the
    // window changes how many windows are above it, and that count is one
    // window server call for window numbers only; the window list is read
    // only when it changes.
    private func restackLifted() {
        guard !(suppressed || frontAppIsExcluded || settings.wholeScreen) else { return }
        for cover in windowCovers where cover.window.level == CoverManager.liftedLevel
            && lifted.contains(ObjectIdentifier(cover)) && cover.window.isVisible && !cover.inTransition {
            var count: CFIndex = 0
            guard PMWindowCountAbove(cover.stackAbove ?? cover.windowID, &count) != PMWindowQueryFailed,
                  count != cover.windowsAbove else { continue }
            cover.windowsAbove = count
            lowerIfRaisedOver(cover)
        }
    }

    /// Position, size and on-screen state of every tracked window, and of the
    /// covers themselves: a cover whose Space starts sliding while its window
    /// stays put is the first sign of a full-screen transition.
    private func trackedSignature() -> [TrackedState] {
        // The API wants a CFArray of raw CGWindowID values, not NSNumbers.
        var values: [UnsafeRawPointer?] = windowCovers.flatMap {
            [UnsafeRawPointer(bitPattern: UInt($0.windowID))]
                + ($0.window.windowNumber > 0 ? [UnsafeRawPointer(bitPattern: UInt($0.window.windowNumber))] : [])
        }
        let ids = CFArrayCreate(kCFAllocatorDefault, &values, values.count, nil)
        // Read the dictionaries as they come rather than bridging them into
        // Swift collections, which cost more than the call itself at 10 Hz.
        guard let entries = CGWindowListCreateDescriptionFromArray(ids) as NSArray? else { return [] }
        var states: [TrackedState] = []
        states.reserveCapacity(entries.count)
        for case let entry as NSDictionary in entries {
            states.append(TrackedState(
                id: (entry[kCGWindowNumber] as? NSNumber)?.uint32Value ?? 0,
                rect: (entry[kCGWindowBounds] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero,
                onScreen: (entry[kCGWindowIsOnscreen] as? NSNumber)?.boolValue ?? false
            ))
        }
        return states
    }

    /// Orders the cover directly above its window only when something else
    /// sits between them; re-ordering every frame is what costs CPU.
    private static func keepAbove(_ cover: WindowCover) {
        let target = cover.stackAbove ?? cover.windowID
        // The typed C bridge reads CoreGraphics' raw window-number array and
        // returns only the nearest ID, preserving the cheap restack fast path.
        var nearest = kCGNullWindowID
        if cover.window.isVisible,
           PMNearestWindowAbove(target, &nearest) == PMWindowQueryFound,
           nearest == CGWindowID(cover.window.windowNumber) {
            return
        }
        cover.window.order(.above, relativeTo: Int(target))
    }

    // MARK: - Styling and visibility

    private func styleAll() {
        screenCovers.forEach(styleScreenCover)
        windowCovers.forEach(style)
    }

    private func styleScreenCover(_ cover: CoverWindow) {
        cover.apply(settings.style, hideFromCapture: settings.hideFromScreenshots)
    }

    private func style(_ cover: WindowCover) {
        cover.window.apply(cover.style, hideFromCapture: settings.hideFromScreenshots)
    }

    /// Kept up to date from activation notifications and settings changes:
    /// asking LaunchServices on every tick was a large part of a tick's cost.
    private(set) var frontAppIsExcluded = false
    private var frontPID: pid_t?

    private func updateFrontApp(_ app: NSRunningApplication? = CoverManager.frontApp) {
        // This app coming to the front for its own menu is not a change of
        // the app in use.
        let app = app?.bundleIdentifier == Bundle.main.bundleIdentifier ? CoverManager.frontApp : app
        frontPID = app?.processIdentifier
        frontAppIsExcluded = app?.bundleIdentifier.map { settings.excludedApps[$0] != nil } ?? false
    }

    /// `restoreParked` also brings back covers hidden as they slid away with
    /// their Space; otherwise those stay hidden until they are on screen
    /// again, so a hand-off still in flight can't double the paper.
    func refreshVisibility(restoreParked: Bool = false) {
        forceFullScan = true
        if suppressed || frontAppIsExcluded || settings.wholeScreen || capturePickerActive {
            windowCovers.forEach { $0.window.orderOut(nil) }
        }
        let show = settings.wholeScreen && !suppressed && !frontAppIsExcluded && !capturePickerActive
        // An excluded app pauses only its own Space's paper. Covers on other
        // Spaces keep theirs, so swiping away from the excluded app brings
        // paper in with the slide instead of popping in once macOS reports
        // the new front app at the end of the animation.
        let pausedByApp = settings.wholeScreen && !suppressed && frontAppIsExcluded && !capturePickerActive
        let showing: Set<Int>
        if show {
            showing = ensureActiveSpaceCovers()
        } else if pausedByApp {
            showing = Set(CoverManager.windowList(options: [.optionOnScreenOnly]).compactMap {
                $0[kCGWindowNumber as String] as? Int
            })
        } else {
            showing = []
        }
        // Hide by fading rather than ordering out: an ordered-out window loses
        // its Space, and each Space's cover must stay where it lives.
        for cover in screenCovers {
            let id = ObjectIdentifier(cover)
            if pausedByApp {
                if showing.contains(cover.windowNumber) {
                    appHidden.insert(id)
                    if cover.alphaValue != 0 { cover.alphaValue = 0 }
                } else {
                    // Only the Space the excluded app is in front on stays
                    // paperless; every other Space is ready for a swipe.
                    appHidden.remove(id)
                    if !parked.contains(id), cover.alphaValue != 1 { cover.alphaValue = 1 }
                }
                continue
            }
            // The excluded app's Space stays paperless until it is back on
            // screen with another app in front.
            if show, appHidden.contains(id), !showing.contains(cover.windowNumber) { continue }
            appHidden.remove(id)
            if show, !restoreParked, parked.contains(id),
               !showing.contains(cover.windowNumber) { continue }
            parked.remove(id)
            if cover.alphaValue != (show ? 1 : 0) { cover.alphaValue = show ? 1 : 0 }
        }
        updateSpaceTimer()
        updateCapturePickerTimer()
        tick()
    }

    // MARK: - Window server helpers (public CoreGraphics API only)

    struct TargetWindow {
        let id: CGWindowID
        let pid: pid_t
        let appName: String
        let frame: NSRect
    }

    /// The frontmost app's topmost normal window.
    /// The app the user is working in. Opening the status menu with the
    /// mouse makes this app the frontmost one on current macOS (it has no
    /// windows and no Dock icon, but it is what `frontmostApplication` then
    /// returns), which left "Paper <App> Window" with nothing to act on and
    /// renamed it after this app. The menu bar still belongs to the app in
    /// use, so fall back to its owner.
    static var frontApp: NSRunningApplication? {
        let own = Bundle.main.bundleIdentifier
        let workspace = NSWorkspace.shared
        if let app = workspace.frontmostApplication, app.bundleIdentifier != own { return app }
        if let app = workspace.menuBarOwningApplication, app.bundleIdentifier != own { return app }
        return nil
    }

    static func frontWindow() -> TargetWindow? {
        guard let app = frontApp else { return nil }
        for entry in windowList(options: [.optionOnScreenOnly, .excludeDesktopElements]) {
            guard (entry[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  (entry[kCGWindowLayer as String] as? Int) == 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  let dict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict),
                  rect.width > 150, rect.height > 150 else { continue } // skip toolbars and tab strips
            return TargetWindow(
                id: id, pid: app.processIdentifier,
                appName: app.localizedName ?? "App", frame: appKitFrame(fromCG: rect)
            )
        }
        return nil
    }

    static func windowList(options: CGWindowListOption, relativeTo id: CGWindowID = kCGNullWindowID) -> [[String: Any]] {
        CGWindowListCopyWindowInfo(options, id) as? [[String: Any]] ?? []
    }

    /// CoreGraphics uses a top-left origin on the primary display; AppKit uses bottom-left.
    static func appKitFrame(fromCG rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Whether a window frame is a native full-screen window. On displays with
    /// a camera notch the window stops below the notch, so "fills the display"
    /// allows for the top safe-area inset.
    static func isFullScreenFrame(_ frame: NSRect) -> Bool {
        NSScreen.screens.contains { screen in
            let s = screen.frame
            let notch = screen.safeAreaInsets.top
            return abs(frame.minX - s.minX) < 1 && abs(frame.width - s.width) < 1
                && abs(frame.minY - s.minY) < 1
                && frame.height >= s.height - notch - 1
        }
    }

    /// The inverse of `appKitFrame(fromCG:)`.
    static func cgRect(fromAppKit frame: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
