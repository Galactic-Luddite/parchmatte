# Animation implementation trials

The approved visual reference and the owner’s latest feedback define the
candidate. For Ribbon, preserve the reference mesh, folding, travel rotation,
perspective, lighting and texture behavior. State which parameters differ and
why; do not substitute a flat strip or another effect while calling it the
approved design. Technical limitations must be supported by API or runtime
evidence and separated from choices made for implementation convenience.

## Prove the implementation

Use the same component and code path intended for the app: actual
`CoverWindow` and `CoverManager`, bundled material and lamp, clamped opacity,
window identity, stacking, screenshot sharing policy, Space handling and
cleanup. A controlled target window supplies repeatable input; it does not
replace the application with a separately rendered approximation. Label a
standalone investigation exploratory and do not use it as the acceptance POC.

Preserve the approved mesh math in a testable function. Generate golden
frames independently from the reference; compare geometry, rotation, fold
depth, lighting and terminal alpha. Then test real app covers with overlapping
windows, minimize/restore, ordinary drag/resize, closing and interruption,
Spaces/full screen and the existing performance suites. Capture visible
output and frame pacing. The current Ribbon candidate uses display-linked
drawables on macOS 14 and later; macOS 13 retains the existing fade. Callback cadence alone cannot establish smoothness.

Regression cases include a recorded shallow cross-display stretch, ordinary
drag/resize in both detector modes, backing-density changes during a fold,
and a minimize held past the three-second closed-window cleanup threshold.
Keep the exact target window identity through restore; reopening its app can
create a new document and invalidate the test. Include close/quit during visibility
changes: confirm covers existed first, then inspect raw app-owned panels after
target teardown. A checker that finds no target must not silently pass an orphan
cover. Also test native Command–Shift–4 window selection; a click-through cover
can still intercept the screenshot picker. Inspect encoded frames at the final
restore handoff for a one-frame texture disappearance. Measure presentation separately
on each display, with native minimize events anchoring capture timing rather
than a delayed fixture command write.

For activation, capture direct click-to-raise and native same-app window cycling
separately from app switching. Include one- and two-window cases, overlapping
and uncovered neighbors, and inspect consecutive encoded frames for bare paper
patches. Use the stacking probe to distinguish a hidden/faded panel from one
ordered beneath its target. Final alignment alone is not an activation pass.
Any faster watch must also satisfy the idle CPU gate.

The current cause, public-API research, exploratory ordering comparisons and
guarded native click/cycle failures are recorded in
[the activation flash investigation](design/activation-flash-research-2026-09-30.md).
Its guarded local probe is an investigation tool, not release acceptance.

For an external window, public geometry metadata does not supply the native
animation mesh or clock. Evaluate synchronization separately from mesh
fidelity. A geometry test pass cannot turn a visibly wrong real-app trial into
a success. Keep all privacy/public-API restrictions in AGENTS.md authoritative.

## Give the owner the candidate

Identify the exact build, revision and active renderer. Protect the existing
signed production app and preferences before replacing or pausing it. Present
the actual candidate for hands-on review, record known differences plainly,
and leave it available until the owner explicitly says done or requests
rollback. Do not restore production automatically after automated checks,
a timer, fixture closure or agent completion. Preserve an explicit handoff
naming the active candidate, protected rollback and remaining owner review.

Automated correctness and performance checks prepare the candidate; owner
visual acceptance is a separate requirement. A rejected appearance is a
failed candidate even if its unit tests pass. Owner trial authorization does
not authorize publishing, merging to release or store submission.
