# Parchmatte Release Test Plan

Goal: nobody who installs Parchmatte should find a case where it hides their
work, blocks input, drains their battery or gets stuck. Every row below gets a
pass/fail and evidence before 1.0 ships.

## How we run it

- **Automated test qualification:** hosted CI runs `swift test --skip
  RibbonDisplayIntegrationTests`, covering 92 tests. The three excluded tests
  exercise `CAMetalDisplayLink` callbacks and main-run-loop timers and require a
  logged-in, visible normal desktop. Keep the test fixture windows visible rather than occluded by another
  app’s fullscreen Space. Release qualification requires an unfiltered `swift test` in the
  supported desktop condition with all 95 tests passing. Do not describe the
  hosted 92-test result as an all-95 run.
- **Two builds, every pass:** the free build (`scripts/build.sh`) and the
  sandboxed store build (Xcode archive). Behaviour must match.
- **Machines:** an Apple-silicon Retina Mac on the current macOS, plus at least
  one older supported macOS and one non-Retina external display. An Intel
  Mac would also be useful if one is available.
- **Automated harness** (to build first, `Tests/Harness/`): a tiny helper app
  that opens scripted test windows (moves, resizes, tabs, full screen,
  minimize, close) while a probe reads Parchmatte's cover bounds through
  `CGWindowListCopyWindowInfo`. It reports per-frame **tracking lag (ms)** and
  **bounds error (px)**, so window-cover cases are measured rather than
  eyeballed.
- **Running it on another Mac:** `scripts/remote_audit.sh <host>` builds the
  chosen commit on a second Mac over SSH, runs the automated harness in a
  Terminal window there, and copies `Tests/Harness/results/<run-id>/` back.
  That Mac needs a display, two desktops, and the SSH user logged in at the
  front; the first run there must be done by hand from Terminal to accept
  the Accessibility, Automation and Screen Recording prompts.
  `--check` runs the preflight only and refuses a locked console session. The
  generated command closes only its own Terminal TTY when the recorded run is
  complete, so repeated audits do not accumulate completed windows. It keeps
  this machine's screen free and
  gives the additional macOS version the exit criteria ask for. Every audit also
  runs `gui_preflight.sh` inside Terminal before changing preferences: System
  Events and TextEdit Apple Events get a 10-second deadline. A public-AppKit
  helper first makes a bounded attempt to foreground Terminal and posts one
  click inside its own window (so macOS will deliver its Automation events),
  then the preflight verifies System Events directly. The assist is not itself
  a pass criterion: the functional Automation check is authoritative. The
  click uses public CoreGraphics APIs and Terminal's existing Accessibility
  grant. This works even when the Terminal window was launched in the
  background. The helper then activates TextEdit and verifies it. The
  harness then creates and removes one disposable TextEdit cover to prove that
  the app's hotkeys and cover manager are ready before suite 1. Failures are
  saved as `gui-preflight.log` or `app-readiness.log` instead of contaminating
  the measured suites or requiring a person to click the test Mac. The
  readiness log records the cover probe's actual failure and frontmost app.
  Before changing settings, the runner asks the signed app executable to
  export its own sandboxed preferences as a plist. It rejects an invalid
  snapshot. On exit it imports the snapshot, exports again, and checks exact
  equality before deleting the backup. A failed restore keeps the backup for
  recovery. The whole-screen probe reads the app's checked menu state; an
  external `defaults read` cannot be trusted for a sandboxed release build.
  The network watch reads the same signed-app snapshot and fails if it cannot
  restore the lamp, texture or whole-screen setting it cycled.
- **Result logging:** each pass records the following reproducible fields:
  - Params: build flavour, macOS version, display layout, texture, softness,
    opacity.
  - Metrics: CPU %, idle wake-ups/s, memory, energy impact, tracking lag
    p50/p95, bounds error.
  - Artifacts: screenshots, logs, the pass/fail table.

  These fields let releases be compared and performance regressions detected.
- **Manual cases** use a checklist in the run's artifacts, with a screenshot
  per case (Hide from Screenshots turned off).

## A. Displays

| # | Case | Expect |
|---|---|---|
| A1 | Single built-in display | Full cover, no gaps at the edges or under the notch |
| A2 | 2–3 displays with mixed scale (1x external + 2x Retina) | Grain looks the same physical size on each; no seams |
| A3 | Hot-plug and unplug a display while running | Covers rebuild within 1 s; no orphan cover left on a missing display |
| A4 | Change resolution or scaling in System Settings | Covers resize; grain re-renders at the new scale |
| A5 | Rearrange displays, or change which one is main | Covers follow; window-cover coordinates stay correct on every display |
| A6 | Mirroring on and off | No double or offset covers |
| A7 | Clamshell mode (lid closed, external only) | Correct |
| A8 | Sleep/wake, lock/unlock, display sleep | Covers come back; snooze and schedule state are right after waking |
| A9 | Displays menu: switch one display off, then on | Only that display changes; the setting persists across relaunch |
| A10 | ProMotion 120 Hz and 60 Hz externals | Tracking stays smooth; no extra CPU at 120 Hz |

## B. Spaces and full screen

| # | Case | Expect |
|---|---|---|
| B1 | Multiple desktops; switch between them | Whole-screen cover on every desktop |
| B2 | Native full screen, enter and exit (Ghostty, Safari, Pages, Xcode) | Whole-screen and window covers survive both directions |
| B3 | Split View (two apps full screen side by side) | Each covered window keeps its cover; no bleed onto the other half |
| B4 | Mission Control / App Exposé open | Covers don't break Mission Control's thumbnails or get stuck in them |
| B5 | Stage Manager on | Covers follow windows in and out of the stage |
| B6 | "Displays have separate Spaces" off | Still correct |
| B7 | Move a covered window to another desktop or display (`carry_run.sh` carries one to the next desktop) | The cover follows, or hides; it never stays behind |
| B8 | Choose "Paper <App> Window" from the menu with the mouse (`menu_click_run.sh`) | The front window is covered; the menu names the app in use, not Parchmatte |
| B8 | Games and video in exclusive full screen | Cover shows or hides consistently; no stutter caused by us |

### Focused excluded-app swipe evidence (#11)

Run this focused check on both supported macOS test versions and with both the
free and store builds. Each run needs 10 departure-and-return cycles between a
Space showing an excluded, uniquely labelled TextEdit fixture and a papered
Space. Preserve an actual-display recording for independent frame-by-frame
review; metadata alone cannot show the first visible composited frame.

Before changing settings, use the running signed app's
`--audit-export-preferences` command to save its preferences in the audit output
directory and validate the plist. Import a copy that changes only whole-screen
paper and the TextEdit exclusion, then export again and compare it with the
intended copy. After the run, close only the uniquely labelled document, remove
only covers created for that fixture, restore the signed export, and require an
exact export comparison before deleting the backup. Do not quit TextEdit or
reset unrelated documents, settings, or covers.

Start the display recording and metadata trace together, then analyze the
completed 10-cycle run:

```sh
swift Tests/Harness/swipe_trace.swift 120 90 > RUN-DIR/swipe-trace.jsonl
python3 Tests/Harness/swipe_trace.py RUN-DIR/swipe-trace.jsonl \
  --visual-correlation RUN-DIR/visual-correlation.json --cycles 10
```

The canonical schema and validation rules live in
`Tests/Harness/swipe_trace.py`; recorder fields are defined in
`Tests/Harness/swipe_trace.swift`. Correlation uses schema
`parchmatte.swipe-trace.v1`, source `display-recording-correlation`, a
`calibration` object with `videoFrameDurationNS`, `maxResidualNS`,
`maxTotalErrorNS`, and at least two bracketing `{videoTimeNS,
wallTimeUnixNS}` events. Each cycle records its number, incoming first-visible
and settled video timestamps, expected cover IDs identified from that run, and
the actual display bounds. Tests for the accepted shape and failure cases are
in `Tests/Harness/test_swipe_trace.py`.

Inspect every frame from the first incoming visible frame through settlement
for all 10 cycles. Paper must be visible on the complete actual display frame
at the first visible frame and every following transition frame. Repeat that
review for each OS/build combination. A `sampled-pass` means only that every
evaluated metadata sample contained a complete cover candidate; it always
leaves `zeroGapProven` false and issue acceptance incomplete. `sampled-fail`
means the sampled cover evidence failed. Missing, malformed, ambiguous, or
insufficient evidence is `incomplete`. A sampled pass never clears #11.

Bracket the recording with visually identifiable clock events and record each
event's video and wall-clock timestamps. The analyzer includes half a video
frame, calibration residual, recorder anchor uncertainty, and half the adjacent
metadata interval in the first-visible uncertainty. Unknown or variable frame
timing, a missing bracket, a dropped interval across the boundary, residual
above half a frame, or combined uncertainty above one frame makes the evidence
incomplete. Never infer a missing frame or move the boundary to a later sample.

## C. Window covers

| # | Case | Expect |
|---|---|---|
| C1 | Drag and resize quickly | Lag p95 < 50 ms; cover never ends up larger than the window when it settles |
| C2 | Minimize and restore | Hides, then returns on the same window |
| C2b | Hold minimized for at least 4.5 s, then restore the same window without reopening its app | Its cover survives the closed-window cleanup threshold and returns aligned |
| C2c | Minimize/restore from a 1x external display with the Dock on a 2x display | Shallow Genie engages Ribbon; density changes retain the fold; long holds restore the same cover |
| C2d | Narrow window with a different-sized sibling behind it; three 4.5 s minimizes using the original window ID | Each restore returns paper at the original size; the sibling stays uncovered; small Genie steps cannot replace the resting footprint |
| C3 | Hide the app (⌘H), then unhide | Same |
| C4 | Close the covered window | Cover removed; count drops |
| C5 | Quit the app, or kill it | Cover removed within 3 s |
| C6 | Native tabs: switch, add, close, drag a tab out into its own window | Cover stays with the tab group; a torn-off tab doesn't take the cover unexpectedly |
| C7 | Tab bars and toolbars drawn as separate windows (Ghostty) | Covered along with the window |
| C8 | Sheets, popovers, autocomplete and context menus of the covered app | Stay visible and usable. Decide whether they get texture; they must never be hidden under an opaque cover |
| C9 | Two same-size windows of one app stacked exactly | The cover must not jump between them (a known risk in sibling adoption) |
| C10 | Many covers (10+) across apps | CPU stays acceptable (see H) |
| C11 | Cover a window, then quit and relaunch Parchmatte | Documented behaviour: covers don't persist. Decide if they should |
| C12 | App matrix: Safari, Chrome, Firefox, Ghostty, Terminal, iTerm2, VS Code, Xcode, Finder, Preview, Pages, Excel, Word, Slack, Zoom, Photoshop, Figma | Correct in each; note any quirks |
| C13 | Windows that change their ID or level (Electron apps, floating panels) | Cover follows or cleanly drops |
| C14 | Click repeatedly inside a covered window at a normal size, then zoomed (`click_flash_run.sh`, vsync probe) | Zero frames with the cover stacked under its window in both states |
| C15 | A same-app window, then another app's window, placed over the covered one; click the covered window back to the front (`overlap_run.sh`) | Overlapping windows show no paper; after the click the cover is directly over its window |
| C16 | Real mouse drags at three speeds and to the screen edge, new build against the previous (`drag_ab.sh 2 <old.app> <new.app>` with `PROBE_FLAGS=--vsync`, `drag_cpu.sh`) | Mean gap and jitter no worse than the previous build; drag CPU no higher; no uncovered frames |
| C17 | Swipe between a full-screen window of the covered app and the desktop holding its covered window, slowly and quickly (`fs_swipe_run.sh`) | The cover rides every slide; at most the first frame of a slide faded |

## D. Input and focus (never get in the way)

| # | Case | Expect |
|---|---|---|
| D1 | Click, double-click, right-click, drag-drop and text selection through every cover | Identical to no cover |
| D2 | Scroll, trackpad gestures, force click, hover tooltips, cursor shape changes | Identical |
| D3 | Keyboard focus | Parchmatte never becomes key; typing always reaches the app underneath |
| D4 | ⌘Tab, the ⌘` window cycler, Exposé | Parchmatte never appears in them |
| D5 | VoiceOver and Full Keyboard Access | Covers are invisible to accessibility; focus never lands on them |
| D6 | Secure input: password fields, `sudo` in a terminal, the lock screen | Unaffected; see the security plan S3 |

## E. System UI

| # | Case | Expect |
|---|---|---|
| E1 | Menu bar and menus, Control Center, Notification Center, Spotlight, Dock | Textured, by owner decision. They must stay readable and usable at the 60% cap |
| E2 | System alerts, permission prompts, the login window, the screen saver | Must not be covered in a way that hides or mimics them |
| E3 | Screen Time and other "restricted" overlays | Unaffected |

## F. Screen capture

| # | Case | Expect |
|---|---|---|
| F1 | Hide from Screenshots ON: ⌘⇧3/4/5, the `screencapture` tool, QuickTime recording | Covers absent from captures |
| F2 | Same, for Zoom, Meet, Teams and FaceTime screen sharing | Absent. Record which tools ignore `sharingType` (macOS 15+ ScreenCaptureKit behaviour) |
| F3 | Hide from Screenshots OFF | Present |
| F4 | AirPlay / Sidecar mirroring | Document the behaviour |

## G. Settings, time and input methods

| # | Case | Expect |
|---|---|---|
| G1 | First launch with no prefs | Sensible defaults: Parchmatte, 15% opacity, 35% softness, lamp off, Launch at Login off |
| G2 | Corrupt or out-of-range prefs (`defaults write` junk values) | Clamped or reset; no crash |
| G3 | Schedule edges: custom hours across midnight, DST change days, time zone change while running, polar latitudes (no sunset) | Correct on/off; falls back gracefully |
| G4 | Snooze across sleep and across a time change | Ends at the right wall-clock time |
| G5 | Pause on Battery: unplug and replug | Toggles within seconds |
| G6 | Launch at Login from /Applications, from the user's Downloads folder and in the sandboxed build | Works, or fails with a clear state; the menu reflects reality |
| G7 | Hotkey conflicts (another app already owns ⌃⌥O and so on) | Parchmatte doesn't crash; the conflict is visible to the user. Consider remappable hotkeys |
| G8 | Non-US keyboard layouts (German, French, Dvorak): ⌃⌥= and ⌃⌥- are key positions, not characters | Document or fix. Likely worth fixing |
| G9 | Dark mode, Increase Contrast, Reduce Transparency, colour filters, accessibility Zoom | Readable; grain doesn't fight accessibility settings |
| G10 | Menu bar crowded or hidden (notch overflow, Bartender-style tools) | The app remains controllable via hotkeys; document a recovery path |
| G11 | Set Strength to maximum with Page Light and each Glow level; check every texture across low, middle and high Softness on light and dark content, for both whole-screen and single-window covers | Strength changes the paper without dimming the selected Glow; transitions remain visually smooth; the paper and Page Light together never exceed the 60% opacity cap |

## H. Performance and energy

| # | Case | Budget |
|---|---|---|
| H1 | Idle, whole screen only | ~0% CPU; no timer running |
| H2 | 1 window cover, idle | < 1% CPU; wake-ups acceptable ("Low" Energy Impact) |
| H3 | 5 and 10 window covers while dragging | Measure; set the budget from the result |
| H4 | 24-hour soak with snooze, schedule and display changes | Memory flat (no growth in the texture cache) |
| H5 | 6K and 5K displays | Texture memory is bounded (a tiled pattern, not full-screen bitmaps) |
| H6 | On battery | Energy impact compared against no-Parchmatte |

## I. Install, update, uninstall

| # | Case | Expect |
|---|---|---|
| I1 | Fresh install of each flavour | Runs; menu appears |
| I2 | Update over an older version | Prefs migrate; no duplicate login items |
| I3 | Quit, force-quit, or crash | All covers vanish with the process (the OS guarantees this); nothing left behind |
| I4 | Uninstall | Only the prefs remain; `defaults delete` removes them; the login item is gone |
| I5 | macOS 13, 14, 15, 26 | Supported floor verified |

## Known risks to target first (from code review)

1. **C9 sibling adoption:** same-app windows with the same frame could swap covers.
2. **The re-attach heuristic** (full-screen fix) might grab the wrong window
   of a multi-window app.
3. ~~**The texture cache** uses the highest display scale at first load.~~
   Resolved: the cache key includes the scale, and covers re-render on a
   backing-scale change.
4. **Whole-screen covers above system UI** (E1): the owner chose to cover
   everything. Verify legibility at the 60% cap.
5. **G8 keyboard layouts:** letter hotkeys (O, P, T, L, S, G) bind by the
   character the layout types; strength and softness use the arrow keys,
   which bind by key code and sit in the same place on every layout
   (`Tests/Harness/layouts.swift` asserts this). The old `=`/`-` bindings are
   gone.
6. **The sandbox preference-domain trap** hit during development: a shell's
   `defaults` access can return an empty domain while the signed app has real
   preferences in its container. Audit the release bundle through its signed
   preference export/import entry points; the standalone debug build's
   `Parchmatte` domain is separate and is used only for malformed-value fuzzing.

## Exit criteria for 1.0

Every row in A–I passes on both flavours on at least two macOS versions. The
H budgets are met and recorded with the release results. No open Critical or High
finding from the security plan.
