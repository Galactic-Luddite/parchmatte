# Release notes

## 1.0 (24) — released on the Mac App Store 2026-10-07

The first public release: https://apps.apple.com/us/app/parchmatte/id6815385110?mt=12

Build 23 plus one fix. Builds 22 and 23 were uploaded and never submitted.

- Fixed "Paper <App> Window" doing nothing when chosen from the menu with
  the mouse on current macOS. Opening the menu with a click makes
  Parchmatte the frontmost app there, so the item had no window to act on
  and the menu then offered "Paper Parchmatte Window". The menu, the
  window hotkeys and Excluded Apps now act on the app that owns the menu
  bar in that case. The hotkey (⌃⌥P) was not affected. Present since the
  first release.

## 1.0.0 (23) — uploaded, not submitted

Build 22 plus one fix. Build 22 was uploaded and never submitted.

- Fixed the paper vanishing for about 50 ms at the end of a desktop swipe
  back to a covered window, seen on 120 Hz displays in build 22. The check
  for a cover left behind on another desktop now waits 50 ms rather than
  four scans, which the faster scanning in build 22 had shortened to under
  one swipe-landing.

## 1.0.0 (22) — uploaded, not submitted

- Added Orientation: ⌃⌥I, or the Orientation submenu beside Texture, flips
  a texture's grain horizontally, vertically or both, so Denim's twill or
  Woven's weave can run the other way. Per window or for the screen, like
  the other style controls.
  ([#28](https://github.com/Galactic-Luddite/parchmatte/issues/28))
- Fixed the paper flashing on every click in a window that is not zoomed or
  full screen. Clicking re-raises a window above its paper; the paper now
  rests one level above ordinary windows while nothing overlaps its window,
  so a raise cannot pass it, and drops back only while another window
  overlaps. Measured at zero bare frames over repeated clicks on two Macs.
  ([#26](https://github.com/Galactic-Luddite/parchmatte/pull/26))
- Paper follows a dragged window more closely: it moves from the cheap
  per-tick scan and checks 240 times a second while something moves, which
  halves the gap at the same CPU cost. About one frame remains because
  macOS moves a dragged window and draws the frame in one pass.
- Paper no longer disappears for the whole slide when swiping back from a
  full-screen window of the same app to a desktop with a covered window.
- Known: on macOS 15, paper follows App Exposé and Mission Control
  thumbnails instead of hiding; this predates build 21
  ([#27](https://github.com/Galactic-Luddite/parchmatte/issues/27)).

## 1.0.0 (21) — submission candidate, unreleased

- Completed the privacy manifest with reason `35F9.1` for the existing
  `systemUptime` calls that measure animation elapsed time and enable timers.
  No timing data is transmitted. The UserDefaults reason `CA92.1`, no-tracking
  declaration and no-data-collection declaration remain in place.
- Retained the frozen Build 20 Denim/Ribbon implementation. The same-app
  activation flash remains a known issue; no visual behavior changed.

## 1.0.0 (20) — development candidate, unreleased

- Added Denim, a pale washed texture with subtle cotton twill, to the eight
  texture choices.
- Added the owner-selected Ribbon minimize/restore animation and retained
  the focused lifecycle and screenshot-picker corrections from the latest
  candidate.

- Fixed Page Light Glow fading as paper Strength increased. Strength now
  changes the paper while the selected Glow stays steady, with their combined
  opacity still limited to 60%. ([#15](https://github.com/Galactic-Luddite/parchmatte/issues/15))
- Updated how Parchmatte checks window order so window papers use the supported
  public macOS interface. ([#8](https://github.com/Galactic-Luddite/parchmatte/issues/8))

The owner froze this implementation and deferred further activation-flash
work. Clicking a window or cycling windows within one app can still briefly
raise it above its paper; this limitation remains open. Final signed Store
qualification and replacement review media are pending.

The corrected App Store subtitle, `Paper texture and warm tint`, was saved
and verified after reload on 2026-09-30. The next submission is tracked in
[#24](https://github.com/Galactic-Luddite/parchmatte/issues/24).
