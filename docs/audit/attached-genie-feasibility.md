# Attached-paper Genie feasibility — September 30, 2026

Status: **geometry gate not passed; app integration held**. This is a
diagnostic result, not a new native trial or a proof that every possible
public-API implementation is impossible. Build 14 remains unchanged.

Source examined: `92188392be9d511b3746d7c450b7a48ee74f6fce`.

## What ran

- Existing source baseline: all 84 Swift tests pass.
- One capture attempt encountered a macOS consent prompt and returned no usable
  window rows. No privacy settings were changed. This is invalid evidence for
  motion feasibility, not a failed animation.
- Two local native Genie captures: a normal minimize/restore cycle and a
  separate idle cycle with a 4.5-second minimized hold. ScreenCaptureKit
  sample timing had a maximum gap of 33.3 ms in both. The encoded video was
  checked separately: normal-cycle motion gaps stayed at 33.333 ms, while
  the idle recording had a 41.667 ms gap and fails the plan's capture-cadence
  admission threshold. It is diagnostic corroboration only, not a qualified
  held-out acceptance run. Native events, window bounds and capture
  presentation and monotonic timestamps were recorded.
- Capture covered the full 2056×1329 logical display. H.264 pads the encoded
  height to 1330. Genie bounds may extend below the visible display; those
  off-screen regions are not capture truncation or on-screen ghosting.
- The exact production `RibbonGeometry.swift` was compiled into a diagnostic
  that projected its vertices against the owned fixture's
  recorded silhouette. This was not a replacement renderer or an actual
  app acceptance run. Recordings containing desktop content are not included.

## Findings

**Observation timing is promising, not fully qualified.** In the normal
cycle, the first substantial change to the fixture's green body appeared
at video time 0.791667 seconds. The first changed bounds were available at
approximately 0.793425 on the correlated monotonic timeline. That is within one
captured frame, subject to capture/metadata synchronization uncertainty.
Do not substitute the earlier native `will-minimize` event for visible
motion onset. Restore bounds in the retained trace also show the growing
window well before the old `fadeIn` event.

**Positioning the folded mesh in the bounding rectangle is insufficient.**
An exploratory geometry-only phase estimate used source-relative center
displacement and contraction, preserving the demo mesh and its fade curve.
The mesh was oriented toward travel and uniformly fitted inside current
bounds. In portions of the recording the entire sampled body mesh fell
outside the curved visible window, despite fitting inside its rectangle.

**A curvature offset improved placement but did not qualify.** Keeping the
same geometry and phase estimate, offsets of 0, 0.05, 0.10 and 0.15 times
the current rectangle's diagonal were tested normal to travel, blended from
zero while folding. The 0.15 placement improved the normal cycle but still
failed its geometric screen: 11 of 63 sampled motion frames contained at
least one on-screen body vertex outside the silhouette expanded by two
logical points, including seven consecutive-frame pairs. The idle recording
also showed outliers, but its encoded cadence failure means it cannot qualify
the model on held-out data. A small scale-inset comparison on the first cycle
also retained outlying vertices; it was not qualified on a new native trial.

These are geometric screening observations, not pixel-complete rendering
measurements. The silhouette was estimated from the owned solid-color
fixture, with its white lettering filled within green row spans. We did
not infer production geometry from captured pixels. Point sampling cannot
establish whole-triangle containment, material ink coverage, perceived
quality, or native-app performance. The analyzer therefore can reject a
geometric candidate but never return a full attachment PASS.

## Decision

The planned app integration is held at Task 1. Do not promote a timing-only
change as “paper attached throughout,” and do not silently substitute a
fade-only effect. The sampled placement models need a better deformation
model before product integration. These failures do not establish that
all possible inferred models must fail.

The outgoing-path-prior estimator, complete repeated-cycle matrix,
alternative Dock/display configurations, actual renderer handoff changes
and visual acceptance have not been completed.
There is no build 15 from this work and no release or Store submission.

## Regression evidence and review

`Tests/Harness/genie_attachment_gate.py` records a fail-closed geometric
screen: consecutive on-screen outliers reject; an empty or malformed
recording is invalid; zero observed outliers remains inconclusive.
Its unit cases distinguish consecutive visible spill, zero-alpha endpoints,
separate motion segments, invalid observations and false acceptance from
vertex-only sampling.

Runtime cleanup restored the owned fixture's paper and verified preferences
byte-for-byte against the baseline. The tested candidate was not replaced.
