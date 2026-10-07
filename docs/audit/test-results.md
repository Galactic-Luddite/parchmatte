# Release Test Results

This file records the public, reproducible conclusions from release testing.
Raw recordings can contain desktop content and are intentionally excluded from
the repository. A release result is valid only when it names the tested source
revision or distributed build and records the relevant suite totals.

## Current release status

Build 21 (source `f7170cad97bc4d4d6ff14acf7bb878dccf2a580b`) is the submitted
candidate, Waiting for Review since 2026-10-02, with the same-app activation
flash disclosed as a limitation. PR #26 (head
`96bc128`) corrects that flash and two motion defects; its free-build evidence
is below. Build 22 (`48f92a3` on `v2`) is that fix plus the texture
orientation hotkey; it was uploaded on 2026-10-03 and not submitted. The final signed Store build
of build 22 still requires the complete audit in
[`docs/TEST_PLAN.md`](../TEST_PLAN.md), exact preference restoration, artifact
inspection, and replacement Store media captured from that exact build.

## PR #26 motion verification (free builds of `96bc128`)

Machines: a Mac mini on macOS 15.7.4 with one 1920×1080 60 Hz display (the
test Mac), and an Apple-silicon laptop on macOS 27.2 with a 120 Hz 2056×1329
notched display. Sandboxed `scripts/build.sh` bundles; comparisons against a
build of the submitted build 21 source, interleaved rounds. Probes sample
once per display refresh (`probe.swift --vsync`).

- **Click flash (C14):** 12 real clicks in a covered window, frames with the
  cover stacked under its window: laptop, Safari, 17 → 0; Mac mini,
  TextEdit, 0 → 0; zoomed windows 0 throughout.
- **Overlap (C15):** 6/6 on the Mac mini: a same-app and a Finder window
  over the covered one show no paper; a click returns the cover directly
  over its window.
- **Cross-app re-activation** (`activation_run.sh`, 10 rounds, two runs):
  build 21 0 and 0 blinks; PR #26 1 and 2 blinks of at most 10 ms.
- **Drag (C16):** mean gap / jitter / worst, px, drag at 300 px/s · fast
  drag · drag to the screen edge. Mac mini build 21 9.1/5.5/39 ·
  36.6/30.1/160 · 32.9/21.2/94; PR #26 5.6/5.9/46 · 20.4/21.2/96 ·
  18.5/24.6/156. Laptop build 21 7.3/7.0/46 · 26.2/26.2/158 · 26.7/26.2/125;
  PR #26 4.1/4.9/38 · 22.2/32.4/190 · 15.9/16.6/62. CPU during a 4 s drag:
  Mac mini 16.7% → 12.4%, laptop 11.7% → 13.4%; 0% at rest. No uncovered
  frames in any run.
- **Same-app full-screen swipe (C17):** five out-and-back swipes, frames
  with the covered window under a faded or missing cover: 162 → 7 (the
  first frame of each slide).
- **Suites on the Mac mini:** `scenarios_windows.sh` 23/23,
  `scenarios_spaces.sh` 3/3, `scenarios_fullscreen.sh` 5/5,
  `scenarios_perf.sh` 2/2 (idle cover under 2% CPU; paused app 0 ms in
  15 s). `scenarios_expose.sh` fails E1 and E2 on macOS 15 for build 21 and
  PR #26 alike (cover follows overview thumbnails):
  [#27](https://github.com/Galactic-Luddite/parchmatte/issues/27).
- **Unit tests:** `swift test` on the laptop, 95 tests, 0 failures.

Raw timelines stay on the test Macs under `$TMPDIR/pm-*`; they contain no
desktop content beyond window geometry.

## Orientation (#28) verification (free build of `8695f92`)

- `swift test` on the laptop: 97 tests, 0 failures, including the two new
  `StyleTests` (cycle order and saved identifiers; flipped tiles mirror the
  normal tile pixel for pixel and get their own cache entry).
- `swift Tests/Harness/layouts.swift`: PASS; `i` has its own key on US,
  German, French and Dvorak.
- `Tests/Harness/fuzz_prefs.sh` on the laptop with the new `orientation`
  key: 180 launches survived, 0 crashed.
- Mac mini, sandboxed bundle: four ⌃⌥I presses moved the Orientation
  submenu's check Normal → Flipped Horizontally → Flipped Vertically →
  Flipped Both Ways → Normal; a press wrote the `orientation` preference.
  With the app quit, stored `flipH` and `flipBoth` came back checked at
  the next launch; a stored `sideways` read as Normal.
- Mac mini suites on the same bundle: `scenarios_windows.sh` 23/23,
  `scenarios_perf.sh` 2/2.
- Visual seam check of Denim and Woven: done on the build 22 archive at
  1x, see "Build 22 Store archive on macOS 15" below; a 2x display check
  is still open.

## Build 22 archive and upload (laptop, Xcode 27.0 / 27A266a)

Archived from `48f92a3` and uploaded to App Store Connect on 2026-10-03
with the App Store Connect API key, headlessly: `xcodebuild archive`, then
`xcodebuild -exportArchive` with `method app-store-connect`, `destination
upload`, automatic signing and the project's `DEVELOPMENT_TEAM`. An earlier
attempt failed with "No App Store Connect access for the team" because the
export options named the wrong team ID. The archived app is 1.0.0 (22),
carries only `com.apple.security.app-sandbox`, and has no quarantine
attributes. Nothing was submitted for review; the signed-build audit and
media in the private release handoff log are still open.

## Build 22 Store archive on macOS 15 (test Mac)

The uploaded archive's app (1.0.0 (22), `48f92a3`, executable SHA-256
`8540c473...9d04`, development-signed, sandboxed) installed on the Mac mini
on macOS 15.7.4 and run through `Tests/Harness/run_audit.sh store` on
2026-10-03:

- windows 23/23, adopt 3/3, fullscreen 5/5, spaces 3/3, drag 1/1, perf 2/2,
  displays 2/2, softness PASS, layouts PASS, fuzz 180 survived / 0 crashed,
  network watch 0 sockets in 15 samples.
- expose 2/4: the same E1/E2 macOS 15 overview failures as build 21
  ([#27](https://github.com/Galactic-Luddite/parchmatte/issues/27)), so the
  runner reports the audit as failed.
- Click flash (C14, TextEdit): 0 frames behind or uncovered in 361 normal
  and 360 zoomed samples. Overlap (C15): 6/6. Same-app full-screen swipe
  (C17): 0 s uncovered. Motion run with `--vsync`: no uncovered or
  behind frames in the swipe, drag, tile and click phases.

- Orientation seams: with whole-screen paper at the strength cap over a
  white window, Denim and Woven were captured at softness 0% and 100% in
  all four orientations (16 captures, Hide from Screenshots off). The five
  inspected (both textures, both softness levels, every flipped
  orientation at least once) show the grain mirrored and no tile seam. A 1x
  display only; preferences restored byte for byte afterward.

This is the archive that was uploaded, not the TestFlight-delivered copy:
TestFlight on the test Mac is not signed in. The macOS 27 audit of the
TestFlight install is still open.

## Build 22 TestFlight build on macOS 27 (laptop, 120 Hz)

The TestFlight-delivered 1.0.0 (22) (signed "TestFlight Beta Distribution",
store receipt present, executable SHA-256 `48a85574...12f9`; the sandbox
entitlement plus the application and team identifiers and
`beta-reports-active` that distribution signing adds) ran
`Tests/Harness/run_audit.sh store` on 2026-10-03:

- windows 23/23, expose 4/4, adopt 3/3, fullscreen 5/5, drag 1/1, perf 2/2,
  displays 2/2, softness PASS, layouts PASS, fuzz 180 survived / 0 crashed,
  network watch 0 sockets. Click flash (Safari) 0 bare or behind frames in
  721 normal and 721 zoomed samples; overlap 6/6.
- **spaces B1 failed**, and kept failing about half the time: the covered
  window sat bare for 3 to 7 samples (~50 ms) as a desktop swipe back to it
  landed. Interleaved on the same Mac, a build of the build 21 source passed
  5/5 while build 22 failed 3/5; across the session build 22 failed 12 of
  24 runs. The test Mac (60 Hz, macOS 15) never showed it.

Cause: the wait before re-homing a cover that looks stranded off its Space
was four scans, and build 22 scans at 240 Hz while windows move, so the
wait had shrunk to ~17 ms and expired before the swipe had landed; the
cover was torn down and recreated. An instrumented build logged the
re-home at the gap. (A first guess, the "window lifted into full screen"
rule, was tested and did not fix it.)

Fix (`f57ea99`, 0.1 s of continuous stranded state instead of four scans),
free build on the laptop: spaces B1 16/16 (6 of them interleaved with
build 22, which failed 2/6 in that run), windows 26/26, fullscreen 5/5,
expose 4/4, adopt 3/3, perf 2/2, overlap 6/6, click flash 0 bare frames,
motion swipe and rapid swipe 0 bare frames, full-screen swipe 0.011 s
uncovered. `swift test`: 97 tests, 0 failures.

The same fix on the test Mac (macOS 15, 60 Hz): spaces 3/3 three times,
windows 23/23, fullscreen 5/5, adopt 3/3, motion and full-screen swipe 0
bare frames. Perf H2 (idle cover under 2% CPU) failed once straight after
the other suites, then passed in two interleaved rounds against build 22
(1.93% and under the limit both times; build 22 measured 1.95% and 1.55%),
so it sits at the threshold on that Mac in both builds.

Build 23 shortens that wait to 0.05 s. Carrying a covered window to the
next desktop (`Tests/Harness/carry_run.sh`, the real case the wait delays)
leaves it bare for the length of the slide in any build: 33 or 34 samples
of 720 in each of three interleaved rounds for both the 0.05 s build and
build 22, so the wait costs nothing measurable there. Spaces B1 with
0.05 s on the laptop: 22/22, six of them interleaved with build 22 (which
failed 2/6).
One 16-run batch was discarded: the laptop had dropped to a single desktop
and no swipe took place (every sample showed the window on screen); check
`visible < samples` before trusting a B1 pass.

Build 22 should not be submitted; build 23 carries the fix.

## Build 23 TestFlight audit and the menu-by-mouse defect (laptop, macOS 27)

The TestFlight-delivered 1.0.0 (23) (commit `a8158a4`, "TestFlight Beta
Distribution", executable SHA-256 `3686d3ef...be13`) passed
`Tests/Harness/run_audit.sh store` on 2026-10-03 with no failures: windows
26/26, expose 4/4, adopt 3/3, fullscreen 5/5, spaces 3/3, drag 1/1, perf
2/2, displays 2/2, softness and layouts PASS, fuzz 180/0, network watch 0
sockets. Spaces B1 9/9 with real swipes; click flash 0 bare frames in 720
normal and 720 zoomed samples; overlap 6/6; carry 33 and 35 bare samples.
Denim and Woven at softness 0% and 100% in all four orientations on the
2x display: grain mirrored, no tile seam in the captures inspected.

Scripting the review recording with real mouse clicks then showed that
"Paper <App> Window" chosen from the menu **with the mouse** does nothing
on macOS 27, in build 23 and, by the unchanged code, every earlier build:
a click on the status item makes this app `frontmostApplication`, so
`frontWindow()` found nothing and the menu was rebuilt as "Paper
Parchmatte Window", disabled. The hotkey and accessibility-press paths,
which every suite used, were unaffected. Not checked on macOS 15 (the test
Mac was locked), and a hardware click was not available to compare with
the posted one.

Build 24 falls back to `menuBarOwningApplication` when this app is
frontmost. New `Tests/Harness/menu_click_run.sh` (TEST_PLAN B8, now part of
`run_audit.sh`): build 23 TestFlight 1 of 4, build 24 free build 4 of 4.
Build 24 free build, full audit on the laptop: passed, with windows,
expose 4/4, adopt 3/3, menuclick 4/4, fullscreen 5/5, spaces 3/3, perf
2/2, fuzz 180/0, 0 sockets; spaces B1 5/5 more; `swift test` 97 tests, 0
failures.

## Build 24 TestFlight audit and review recording (laptop, macOS 27)

The TestFlight-delivered 1.0.0 (24) (commit `e061123`, "TestFlight Beta
Distribution", store receipt present, no quarantine attributes, executable
SHA-256 `1fa15ccc...29d6`; uploaded archive `9afe3075...1c35`) passed
`Tests/Harness/run_audit.sh store` on 2026-10-03 with no failures: windows
26/26, expose 4/4, adopt 3/3, menuclick 4/4, fullscreen 5/5, spaces 3/3,
drag 1/1, perf 2/2, displays 2/2, softness and layouts PASS, fuzz 180/0,
network watch 0 sockets. Spaces B1 6/6 with real swipes; click flash 0
bare frames in 721 normal and 721 zoomed samples; overlap 6/6; carry 35
bare samples.

Review recording from that installed build: one continuous take of the 13
steps in `APP_STORE.md`, driven by posted mouse and keyboard events on a
blank desktop, 134.6 s, H.264 1920x1242 at 30 fps, 22.6 MB, SHA-256
`3901b73d...fce9`, kept outside the repository. It decodes without
errors; contact sheets every 2.5 s and the notification corner of every
sampled frame were inspected and show no other desktop, notification or
personal content. Step 7 uses the menu item with the mouse. The Privacy
Policy step opens the default browser, set to an empty Safari window for
the take and set back afterwards; desktop icons and widgets were hidden
for the take. The app's preferences were restored byte for byte.

Store screenshots, 2026-10-03: six 2880x1800 RGB frames with no alpha,
rendered by the website repository's `render_release_shots.py` from six
full-screen captures of the same TestFlight build 24 (light appearance, a
blank desktop, a neutral TextEdit page, Hide from Screenshots off). The
enlarged menu panel in each is a crop of that capture, taken from the menu
rectangles the accessibility API reported. Frames 2 to 6 show the
Orientation row; frame 3 lists all eight textures. SHA-256 prefixes:
`08aec975` hero, `0767b539` menu, `bea21fe8` texture, `237569ac` page
light, `548f34f8` per window, `5592c70d` schedule. Raw captures and frames
are kept outside the repository. Appearance, desktop icons, widgets and
the app's preferences were restored afterwards.

Not done: uploading the frames and the recording to App Store Connect,
and the website's homepage menu image, which still shows build 21 without
the Orientation row.

## Build 19 focused validation

- Deterministic Denim generation, 1x/2x resource checks, softness and opacity
  coverage, menu selection, and rendered inspection passed.
- The Swift suite passed 95 tests with no failures.
- Focused window, Spaces, full-screen, performance, screenshot-picker, and
  lifecycle checks passed for the recorded candidate.
- Same-app click-to-raise and window cycling exposed a brief bare target.
  Fourteen investigated external-cover strategies failed the continuous
  coverage criterion. App-owned child-window controls passed, but they do not
  represent a cover attached to another application's window.

These results are scoped to the tested candidate and environments. They do not
establish behavior on every supported macOS version, display configuration, or
third-party application.

## Build 6 distributed-build audit

The installed TestFlight build 1.0.0 (6) passed the complete GUI audit on the
recorded Apple-silicon system: 29 checks, zero failures, and 168 malformed
preference launches without a crash. Window, Expose, adoption, full-screen,
Spaces, drag, performance, network, softness, keyboard-layout, and display
checks passed. The network watch observed zero sockets, and the signed app's
preferences were restored and compared byte for byte.

The corresponding signed archive audit also passed 29 checks with zero
failures. `swift build`, 27 Swift tests, the Xcode Release build and archive,
code-signature verification, and package version checks passed. These are
historical Build 6 results and do not substitute for a Build 21 audit.

## Audit-runner behavior

The checked-in audit runner fails the overall run if a suite, signed-app
preference import, exact preference comparison, or app restart fails. It keeps
the recovery snapshot when restoration cannot be verified. The remote wrapper
uses its own status marker because an SSH transport can otherwise obscure the
remote command's exit status, and GUI preflight rejects a locked console before
starting a measured suite.

Focused regressions cover restoration failure, complete success, prior suite
failure, locked-console rejection, and remote-status transport. Shell syntax is
checked one file at a time, and the Python harness regression suite is part of
release qualification.

## Known limits

- The activation flash is a demonstrated user-visible failure, not a cosmetic
  uncertainty. It remains open until an exact signed candidate passes the
  visual continuity check.
- Metadata sampling and geometry alignment alone cannot prove that every
  displayed frame contains correctly placed paper.
- A passed focused suite or historical build does not promote a later build.
- Manual and GUI evidence must preserve user preferences and distinguish a
  locked or otherwise invalid test session from a product failure.
