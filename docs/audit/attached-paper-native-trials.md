# Attached paper: actual app trial record

The owner requested repeated signed builds and native tests after the earlier
geometry-only feasibility check. These are experiments, not release acceptance.

## Build 15 — 05a160c

Three launch-only variants use the real CoverManager, CoverWindow, bundled
material, and Metal renderer: curve, sheet, and soft. Restore consumes live
intermediate geometry rather than playing a second animation after settling.

- 89 Swift tests passed; debug/release builds and strict signature verification passed.
- Each variant completed two captured native minimize/restore cycles.
- Encoded capture maximum frame gaps were 33.3 ms. This does not establish
  frame-perfect synchronization of the material with the native animation.
- Soft completed rapid reversal and returned to the exact target frame.
- Measured soft one-window idle CPU 0.85%; whole-screen 0.00%; paused CPU delta zero.
- Actual close-up capture showed the native window largely bare during motion.
  Metadata confirmed the moving cover existed at normal window level, suggesting
  it was behind the native animation. These recordings do not qualify a shape.
- Renderer setup took 16–31 ms in the observed runs. Minimize onset was about
  200 ms after the native event; initial bounds changes resemble ordinary resize.

## Build 16 — 4c34741

Adds an explicit `--attached-front` comparison flag. After a queued mesh draw,
the transient panel rises to the public Dock window level plus one, then restores
its previous level through the shared cancellation path. This may spill above
intervening normal windows and requires native crossing/Space checks. Shared
Metal shader/device setup is warmed before trial motion; material and GPU buffers
remain per renderer. Setup timing now separates material and renderer costs.

91 Swift tests passed, including stale-observation teardown, return during growth,
and raised-panel level restoration. All four native suites passed: windows 13,
Spaces 3, full screen 5, and performance 2. Idle CPU was 0.99%; paused CPU delta
was 0.03 seconds. Native overlap and rapid-reversal recordings returned to the
correct frame. The paper became visible over the moving target. Independent
review requested and received raised stale-cleanup coverage.

## Build 17 — 4568890

A single bounded prepared material snapshot removed rasterization from warmed
transitions: measured setup fell to 1.84–2.53 ms, with material time 0.00 ms.
92 Swift tests passed. Actual frame-by-frame inspection caught a restore handoff
flash: full paper, then one bare window frame, then paper again.

Window, Spaces, and full-screen suites passed, but paused performance failed
(130 ms CPU over the sample). After teardown, five paper panels remained without
their targets. A saved public-window inventory proves the orphan panels; two
isolated retries of the race did not reproduce it. The interaction was between
the missing-target grace and a visibility mode that stopped tracking before
ordering out all covers. Build 17 is not a passing candidate.

The owner's texture-only screenshots were reproduced separately: native window
selection picked the click-through paper panel itself. Setting sharingType.none
still selected it and capture failed instead of selecting the underlying window.
Apple calls that sharing enum a [legacy mechanism](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum).
This is not evidence that the app captured target pixels; the screenshot utility
selected the wrong window.

## Builds 18 and 19 — 915774f / 2e6fb3d

The combined candidate includes:

- Pale Wash Denim: a deterministic 512-pixel RGBA tile, appended to Texture
  cycling/menu choices. Existing seven PNGs remain byte-identical. Tests cover
  resource loading at 1×/2×, softness and combined opacity. Repeated tile joins
  and the actual rendered white-page composite were inspected.
- A 120 ms flat-material hold before returning the animated panel to its normal
  level. The reviewed build 19 capture no longer contains build 17's bare-frame
  handoff flash. The hold is reset by renewed motion.
- Immediate ordering-out before visibility modes stop tracking. Departing or
  confirmed closed targets hide immediately; ordinary tab/metadata gaps retain
  reattachment grace. Build 19 narrows this condition after independent review.
- Automatic withdrawal of covers while the native screenshot picker is open.
  Detection uses the existing public owner/layer/bounds keys, without pixels,
  titles, new permissions, or input monitoring. It polls at 8 Hz only while
  relevant paper can show (or while the picker is active), stopping when paused.

95 Swift tests passed. Strict signature checks passed. Native build 18 tests
confirmed both window capture and whole-screen picker cancellation: the correct
underlying window is captured, and paper returns afterwards. Build 19 native
suites passed windows 23/23, Spaces 3/3, and full screen 5/5. Performance assertions
passed: one-window idle CPU 1.61% (limit 2%); paused CPU delta 0 over 15 seconds
(limit 0.03 seconds). Whole-screen CPU measured 0.31%. The strengthened closed-
window regression verifies five covers exist before teardown and queries raw
cover windows afterwards, propagating probe errors. Denim was selected through
the actual Texture submenu and rendered over a readable white document. The
final raw inventory at that checkpoint contained one cover aligned to the owned
test window, with no orphan or whole-screen panel.

Additional checks against the exact build 19 binary passed:

- Left- and right-side Dock minimize/restore returned to the aligned target.
  Initial recordings were obscured by another window; replacement recordings
  put the fixture in front. The original bottom Dock orientation was restored.
- Rapid reversal, neighbor overlap, and drag/resize through four geometries
  returned to the aligned cover without a leftover panel.
- Two native document tabs were merged and switched; coverage remained aligned
  before and after switching. Closing the documents left no orphan cover.
- Native Command-Shift-4, Space selection captured the underlying test window;
  the paper cover returned afterwards.

The final raw inventory contained exactly one cover aligned to the owned test
window, with Denim selected and the candidate still running. These checks
establish lifecycle and alignment outcomes, not exact native Genie silhouettes.
Recordings are omitted because they may include the surrounding desktop.

The first build 19 MOV writer failed; its replacement MP4 is usable for visual
inspection but has a maximum encoded gap of 41.667 ms. It cannot support a
whole-recording claim of 33.3 ms or better. Capture callback cadence is not
presentation proof.

## Build 19 follow-up — same-app activation flash (unresolved)

Owner testing found a brief bare-window flash on direct click-to-raise and
window cycling, while app switching remained covered. Native Command-backtick
was the effective window-cycle shortcut in the reproduction.

Four switches of each kind were captured against the real build 19 binary.
The 250 Hz stacking probe found four gaps per run at the default 45 Hz watch
rate: maximum 25 ms for clicks and 32 ms for window cycling. All bad samples
were classified `under`: the paper panel remained present but the target was
raised above it. The click recording separately contains two consecutive bare
frames at an 8.33 ms interval, confirmed by texture disappearance from blank
document patches. Sampled stacking latency and encoded visible frames are
separate measurements; neither guarantees capture of every display refresh.

A launch-only 120 Hz comparison reduced the sampled maxima to 11 ms and 24 ms,
but did not remove the gaps. One-cover/two-window idle CPU rose to 3.14%, failing
the 2% limit. The higher-rate experiment was removed; build 19 remains running
at its normal rate with Denim. There is no fix or new build from this experiment.

`keepAbove` repairs ordering after an external window raises itself. App
activation has a temporary level lift; same-app cycling has no equivalent
pre-raise signal in the current public metadata path. Apple's
[relative ordering method](https://developer.apple.com/documentation/appkit/nswindow/order(_:relativeto:))
changes stacking; it does not establish the persistent relationship described
by [child-window ordering](https://developer.apple.com/documentation/appkit/nswindow/addchildwindow(_:ordered:)).
The latter requires an NSWindow object, which this app does not own for an
external target. Permanently raising paper risks covering intervening windows.
No such workaround has been accepted or implemented.

A separate code-review finding is that the fast watch currently requires two
normal windows in the front app. A sole covered window can also be raised;
that case needs its own reproduction and latency coverage. Broadening the watch
would be a mitigation, not a solution to the confirmed two-window flash.

The earlier native suite and final-alignment passes remain valid for their
assertions, but do not qualify uninterrupted paper during activation. Treat
this as an open visual failure before release. Supporting recordings are not
published because they may include desktop content.

## Required before release

Owner visual acceptance remains outstanding. The early Genie silhouette is
still inferred from rectangular metadata; these experiments do not establish
pixel-exact attachment. Current native evidence comes from one Retina display;
1× resource tests are not native cross-display animation qualification.

Leave the selected candidate available for owner testing; do not automatically
restore production. Denim is now included. Issue #24's corrected subtitle,
updated Store assets, and final owner acceptance remain release requirements.
No release merge, publication, or Apple submission occurred in these trials.
