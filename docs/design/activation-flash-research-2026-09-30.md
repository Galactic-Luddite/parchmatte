# Research: Same-app activation flash

**Date:** 2026-09-30

**Question:** What causes the bare-window interval, and can it be eliminated while preserving public APIs, no input monitoring, correct neighboring-window coverage and the idle CPU limit?

**Status (updated 2026-10-02):** Corrected in [PR #26](https://github.com/Galactic-Luddite/parchmatte/pull/26). The fifteenth strategy keeps the cover at the activation lift level (`normal + 1`) as its resting state whenever nothing overlaps the covered window, dropping to the normal level only while another window overlaps; a click's re-raise then cannot pass it. `Tests/Harness/click_flash_run.sh` measured 17 → 0 bare frames per 12 clicks on the 120 Hz laptop and 0 on the 60 Hz Mac mini; `overlap_run.sh` 6/6 confirms overlapping windows of the same and other apps show no paper; `activation_run.sh` stays at build 21's level (1–2 sub-frame blinks per 10 cross-app activations). The exact-build visual check on the signed Store build is still required before the release record calls per-window paper continuous.

**Original status (2026-09-30):** Cause established; no correction qualified. All fourteen external-cover native trials failed continuous coverage; both native-child controls remained correct. Per-window release remains blocked.

## Sources consulted

| Source | Type | Link |
|---|---|---|
| Relative window ordering | Apple documentation | [order(_:relativeTo:)](https://developer.apple.com/documentation/appkit/nswindow/order(_:relativeto:)) |
| Persistent child-window relationship | Apple documentation | [addChildWindow(_:ordered:)](https://developer.apple.com/documentation/appkit/nswindow/addchildwindow(_:ordered:)) |
| Window-level precedence | Apple documentation | [level](https://developer.apple.com/documentation/appkit/nswindow/level-swift.property) |
| App-owned window lookup | Apple documentation | [window(withWindowNumber:)](https://developer.apple.com/documentation/appkit/nsapplication/window(withwindownumber:)) |
| Geometry and ordering metadata | Apple documentation | [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) |
| Occlusion notification scope | Apple documentation | [didChangeOcclusionStateNotification](https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification) |
| Bounding-box occlusion caveat | Apple documentation | [OcclusionState.visible](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.struct/visible) |
| Display-synchronized callbacks | Apple documentation and SDK header | [NSScreen.displayLink](https://developer.apple.com/documentation/appkit/nsscreen/displaylink(target:selector:)), [CADisplayLink](https://developer.apple.com/documentation/quartzcore/cadisplaylink) |
| App-local update transactions | Apple documentation and current SDK | [NSDisableScreenUpdates](https://developer.apple.com/documentation/appkit/nsdisablescreenupdates()), [disableScreenUpdatesUntilFlush](https://developer.apple.com/documentation/appkit/nswindow/disablescreenupdatesuntilflush()), [AppKit 10.14 release notes](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-10_14); `NSWindow.h` |
| Capture image/status semantics | Apple developer session and sample | [Meet ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2022/10156/), [macOS capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) |
| Compatible full test toolchain | Apple compatibility table | [Xcode system requirements](https://developer.apple.com/xcode/system-requirements) |
| Carbon lookup and event-monitor restrictions | Apple SDK headers | `MacWindows.h:HIWindowFromCGWindowID`, `CarbonEvents.h:GetEventMonitorTarget`; SDK locators below |
| Current product constraints | Repository contract | [AGENTS.md](../../AGENTS.md) |
| Actual cover tracking and rendering | Inspected source at `ad94b94` | [CoverManager.swift](../../Sources/Parchmatte/CoverManager.swift), [CoverWindow.swift](../../Sources/Parchmatte/CoverWindow.swift), [WindowListBridge.c](../../Sources/WindowListBridge/WindowListBridge.c) |
| Build 19 native failure record | Prior actual-app evidence, re-inspected | [Native trial record](../audit/attached-paper-native-trials.md#build-19-follow-up--same-app-activation-flash-unresolved) |

## Findings

### Q1: Why does a click or window cycle expose the target?

**Answer:** The normal-level cover and external target are independent windows. A target raise changes their ordering before Parchmatte observes and repairs it.

**Evidence:** `keepAbove` queries the nearest window above the target, then calls `order(.above, relativeTo:)` if the cover is no longer there. `tick` performs this check periodically. `sameAppWatch` currently requires at least two normal windows in the front app. App activation instead temporarily lifts selected covers to normal level plus one for a 600 ms burst; it subsequently lowers them. This explains the different observed behavior of app switching and same-app activation. See the inspected implementations of `keepAbove`, `tick`, `activated`, `lowerLifted` and `fullTick` in [CoverManager.swift](../../Sources/Parchmatte/CoverManager.swift).

The retained Build 19 click and cycle timelines classify the failures as `under`, rather than absent or faded. The sampled maxima were 25 and 32 ms. Direct decoding of the retained click MP4's source frame 233 shows the raised target bare while its neighboring covered window still has paper. This is consistent with ordering loss. The source MP4 has variable timestamps: do not equate a resampled PNG sequence index with its encoded source-frame index. This failure concerns resting covers; the separate minimize/restore material hold does not fix it.

**Confidence:** Confirmed for the retained Build 19 reproduction and inspected code.

**Implication:** Raising the polling frequency reduces the wait but does not establish a persistent relationship or a bound on main-thread scheduling and presentation. The prior actual-app 120 Hz trial still had gaps and exceeded the 2% idle CPU limit ([native trial record](../audit/attached-paper-native-trials.md)).

### Q2: Can the public ordering API keep the external cover attached?

**Answer:** The current call does not supply persistent attachment. Native child-window attachment supplies that behavior for app-owned window objects; no supported external attachment path was established here.

**Evidence:** Apple describes [relative ordering](https://developer.apple.com/documentation/appkit/nswindow/order(_:relativeto:)) as repositioning a window in the server list. Apple explicitly describes [child attachment](https://developer.apple.com/documentation/appkit/nswindow/addchildwindow(_:ordered:)) as maintaining relative position during subsequent ordering operations, and its signature takes an `NSWindow`. The [application window lookup](https://developer.apple.com/documentation/appkit/nsapplication/window(withwindownumber:)) depends on a corresponding object owned by the calling app. The separate-process exploratory probes returned false for an external object lookup. Their native child control preserved the sampled cover/target ordering through all twenty scripted raises.

**Confidence:** Confirmed for the API contracts and object lookup. The absence of a public external attachment solution is a research result, not a proof that every possible public approach is impossible.

**Implication:** Converting a foreign numeric window ID into an owned parent window is not a demonstrated implementation route. A cooperating target app could use native child attachment, but that changes the product's general external-window design.

The Carbon conversion route is also excluded by its actual declaration: the Apple SDK's `HIWindowFromCGWindowID` is 32-bit-only and explicitly returns no window reference for another process. `GetEventMonitorTarget` lists input events as its supported kinds; it does not provide a foreign window-activation event subscription. Neither is a substitute for persistent attachment under this product's contract.

### Q3: Would permanently lifting and clipping the paper solve it?

**Answer:** A raised panel avoids being overtaken by a normal-level target, but its coverage must then be corrected around neighbors. The exploratory mask experiment still had delayed corrections.

**Evidence:** Apple's [window-level contract](https://developer.apple.com/documentation/appkit/nswindow/level-swift.property) places a higher-level panel over all normal-level windows. The exploratory harness compiles the actual `CoverWindow`, Denim material and renderer dependencies into separate owned fixture/overlay processes. It compares a 45 Hz restack, permanent level-one panel, level-one panels with a rectangular neighboring-window mask at 45/120 Hz, and native child attachment. It changes one ordering strategy at a time and posts twenty target-app ordering operations, retaining each sampled state and mask submission.

| Exploratory strategy | Sampled ordering result | Limitation |
|---|---|---|
| Normal panel, 45 Hz repair | 10 gaps; maximum 35 ms; 27 `under` samples | Recovers after a raise |
| Permanently level-one panel | No `under` samples; ordered above the raised neighbor in 486 samples | Paper is above a window that should occlude the target |
| Level one plus 45 Hz mask | No `under` samples; stale hole after target raise up to 20.89 ms; late neighbor hole up to 25.48 ms | Delayed mask changes can expose a target patch or cover its neighbor |
| Level one plus 120 Hz mask | No `under` samples; stale/late holes up to 7.18/7.05 ms | Reduces logical mismatch without eliminating it |
| Native child control | No `under` samples and normal-level ordering preserved | Parent is owned by the fixture app |

These are **WindowServer ordering and submitted-mask measurements**, not displayed-frame measurements. The session was initially ready but later found locked, and these early trials did not bind readiness throughout execution. Their metadata still demonstrates ordering relationships, but the rows must not be promoted to native visual passes or failures. The recordings failed; no new video qualifies any strategy.

The subsequent guarded native comparison confirms visible neighbor spill for the unmasked elevated panel, and visible stale holes for both masked rates. Those image results are recorded below; the earlier locked-session measurements remain metadata-only.

**Confidence:** Confirmed for the final guarded native image failures. Earlier sampled mask timings retain their narrower qualification.

**Implication:** A zero-`under` counter alone can hide a coverage failure elsewhere. Any elevated-panel candidate needs separate neighbor-spill and missing-paper checks in consecutive displayed frames.

### Q4: Could our own occlusion notifications repair the cover sooner?

**Answer:** The guarded programmatic trials now deliver callbacks, but the notification-based repairs still expose bare images.

**Evidence:** Apple's [notification](https://developer.apple.com/documentation/appkit/nswindow/didchangeocclusionstatenotification) reports a change in overall occlusion state, rather than every change in occlusion region. The [visible flag](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.struct/visible) may remain set for a nonrectangular window whose bounding box intersects a visible region. The prototype therefore includes the actual cover, an inset-cover diagnostic and a small transparent interior sentinel. Earlier locked-session trials remain inconclusive.

The subsequent unlocked run on macOS 15.7.4 / Apple M4 / 1920×1080 at 60 Hz passed both owned hide/show callback controls and repeated session checks. The full-size cover remained logically visible after the target overtook it, supplying no useful repair notifications during the raises; its video contains 28 bare target images. The inset-cover and interior-sentinel modes supplied repairs, but each contains ten bare target images; their sampled ordering gaps reached 25 ms. See the guarded programmatic comparison below.

**Confidence:** Confirmed for these guarded runtime trials; broader platform and target-shape behavior remains unqualified.

**Implication:** The full-size cover can miss the signal, and an interior diagnostic can deliver the signal after an exposed image. Neither measured approach satisfies uninterrupted coverage.

The guarded runner now requires both hidden and shown occlusion notifications from an owned visibility control before running the timing experiment. Missing delivery makes that trial inconclusive. The hidden control skips restacking an intentionally ordered-out panel, and hides the sentinel as well as the paper when that mode is selected.

### Q5: Would aligning the check with display updates help?

**Answer:** The public display-linked check also exposes bare images in the guarded programmatic trial.

**Evidence:** Apple's [screen display link](https://developer.apple.com/documentation/appkit/nsscreen/displaylink(target:selector:)) supplies display-synchronized callbacks on macOS 14 and later. [CADisplayLink](https://developer.apple.com/documentation/quartzcore/cadisplaylink) exposes the previous and target frame timestamps. The new `displaylink` exploratory mode uses those callbacks and the actual public `PMNearestWindowAbove` C bridge, with AppKit ordering on the main thread. It subscribes to the screen, so the subscription is not tied to the cover's visibility. It records real callback intervals and the frame timestamps for each repair.

On the same unlocked 60 Hz display, the mode delivered 645 callbacks over approximately 10.76 seconds, with a maximum callback interval of 16.73 ms. The ordering sampler recorded nine gaps, maximum 21 ms; the video contains ten bare target images, including held images lasting 33.33 ms. Requesting 120 callbacks per second did not turn this display into a 120 Hz display.

**Confidence:** Confirmed failure for this guarded programmatic trial. Native trigger and other platform results are separate.

**Implication:** Display synchronization alone did not eliminate the post-raise repair interval. No CPU optimization of this failed strategy qualifies the required visual behavior; macOS 13 behavior is also unresolved.

### Q6: Could a screen-update transaction hold the target until its paper is ready?

**Answer:** The inspected public APIs do not provide that cross-process barrier.

**Evidence:** [NSDisableScreenUpdates](https://developer.apple.com/documentation/appkit/nsdisablescreenupdates()) documents updates for windows belonging to the caller. Apple's [AppKit release notes](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-10_14) explain that modern AppKit commits its view/window operations transactionally and recommends `NSAnimationContext` for stronger app-local atomicity. The current SDK's `NSWindow.h` deprecation message says `disableScreenUpdatesUntilFlush` does nothing and should not be called. The [website discussion](https://developer.apple.com/documentation/appkit/nswindow/disablescreenupdatesuntilflush()) still describes historical flushing behavior; this conflict is resolved in favor of the current SDK declaration. No screen-freezing experiment was run.

**Confidence:** Confirmed scope and current SDK restriction; no universal claim about unexamined techniques.

**Implication:** Batching this app's panel/mask operations cannot hold an independent target app's activation until those operations are submitted.

## Guarded programmatic comparison

All nine modes completed on an unlocked console with readiness checked before, during and after each run. The fixture uses two overlapping owned windows in one process and the real `CoverWindow`, Denim, renderer dependencies and public C bridge in another. Each run submits twenty alternating target-app raises. This isolates ordering behavior; it is not native input or signed-application acceptance.

| Mode | Ordering gaps / maximum | Bare target images | Interpretation |
|---|---:|---:|---|
| Normal panel, 45 Hz | 10 / 24 ms | 9 | Visible repair delay |
| Display-linked repair | 9 / 21 ms | 10 | Visible repair delay |
| Full-size cover occlusion | 1 / 9,157 ms | 28 | Visibility signal misses the raises |
| Inset-cover occlusion | 10 / 25 ms | 10 | Signal arrives after an exposed image |
| Interior sentinel | 10 / 25 ms | 10 | Signal arrives after an exposed image |
| Native child control | 0 | 0 | Owned attachment preserves the target patch |
| Permanently elevated | 0 | 0 | Neighbor coverage remains unqualified |
| Elevated with 45 Hz mask | 0 | 0 | Overlap coverage remains unqualified |
| Elevated with 120 Hz mask | 0 | 0 | Overlap coverage remains unqualified |

The target patch lies outside the overlap and remains visible in both window orders. White, untextured target images are direct failures. Zero counts qualify only that patch, not masked holes, neighbor spill or whole-window continuity. The native phase uses different colored owned markers at the same overlap point, so the image itself identifies the visible owner independently of key-notification or metadata timing.

`activation_frame_stats.swift` decodes every stored image with AVFoundation and retains timestamps and patch statistics. Initial paper-reference classification incorrectly required a mean below 240; the native-child preview shows Denim over white at 40% has a mean near 250 with visible texture variation. The corrected classifier separates that material from a flat white patch; original v1 analyses are retained and their zero reference counts are not acceptance results.

The videos are variable-rate: sparse encoded image timestamps and a final held image are not a count of display refreshes. Apple's [capture session](https://developer.apple.com/videos/play/wwdc2022/10156/) distinguishes new complete images from idle callbacks containing unchanged content. The original meter counted all valid callbacks. The native phase records statuses and the first complete-image timestamp, and waits for capture readiness before posting input. A requested capture interval, callback count or resampled PNG sequence must not be promoted to a presentation-rate measurement.

## Guarded native click/cycle comparison

All sixteen corrected native runs completed with valid recordings and all twenty expected alternating key-window changes. Different target/neighbor markers were identified in every decoded image, and all target/overlap material classifications were known. Each cell below gives **click / Command-backtick** counts of encoded images, not counts of display refreshes or activation events.

| Strategy | Bare target images | Missing overlap paper | Neighbor spill |
|---|---:|---:|---:|
| Normal panel, 45 Hz | 16 / 17 | 16 / 17 | 0 / 0 |
| Display-linked repair | 19 / 17 | 19 / 17 | 0 / 0 |
| Inset-cover occlusion | 19 / 19 | 19 / 19 | 0 / 0 |
| Interior sentinel | 17 / 18 | 17 / 18 | 0 / 0 |
| Permanently elevated | 0 / 0 | 0 / 0 | 21 / 21 |
| Elevated with 45 Hz mask | 0 / 0 | 9 / 8 | 8 / 9 |
| Elevated with 120 Hz mask | 0 / 0 | 1 / 4 | 0 / 1 |
| Native child control | 0 / 0 | 0 / 0 | 0 / 0 |

Bare-image holds in the normal/display-linked/occlusion strategies reached 33.33 ms in each corrected native run. The permanently elevated panel's spill persisted up to 333.33 ms while the neighbor was frontmost. The 45 Hz mask had missing-paper and spill holds up to 33.33 ms; the 120 Hz mask still had 16.67 ms failures. The earlier valid baseline control also recorded a 50 ms bare hold; those controls are retained separately.

These are owned-fixture image results, not signed-app acceptance. The baseline confirms that the problem survives real input; the child control confirms that this capture/classification method can observe continuous correct target and neighbor coverage. The elevated strategies' zero bare-target counters hide defects inside the overlap; they are failed candidates.

A following native display-link attempt is inconclusive: it posted twenty clicks but logged no key-window changes. A read-only modifier-state diagnostic found Command still set after the preceding synthetic shortcuts. The harness now posts genuine modifier press/release events, gives mouse events explicit empty flags, records click modifier state and retains the input validity result before checking recorder exit. The repeat control delivered all twenty transitions and confirmed no Command bit in any subsequent click. The invalid trial and its constant-image partial recording are retained; neither is a display-link success or failure.

Swift 6.1.2 also rejected a pre-existing `CGFloat` slope assigned to a `Double`
tuple member in `MinimizeFade`. An explicit `Double` conversion supports that
declared toolchain without changing the detection formula. `swift build`
passed, and the unchanged full-Xcode suite passed **95 tests with zero
failures**. This build correction is independent of activation coverage.

## Synthesis

The cover's image remains intact while its target can move in front of it. The current public metadata loop observes a changed order after the target app has acted. Keeping paper above normal windows changes which window receives the paper; clipping moves the synchronization problem to mask updates. Native child attachment addresses the relationship itself, but the present application does not own the external parent.

No code or evidence in this investigation qualifies a zero-flash correction. The guarded occlusion and display-synchronized probes reproduce visible failures under native clicks and window cycling. Elevating paper preserves order over the target but affects an uncovered neighbor; clipping preserves the target patch outside the overlap while losing paper inside it. Faster mask updates reduce those failures to one refresh interval and still fail the requirement.

The directional conclusion is to keep the current per-window release blocked and revisit the independent-panel architecture. A persistent relationship eliminates the race in the owned-child control, but no supported foreign-parent attachment route was established. This is a measured limit of the investigated approaches, not proof that every unexamined public technique is impossible. No privacy promise or feature scope was changed.

## Recommendations

1. Keep uninterrupted click/cycle coverage as a release blocker. Do not promote geometry alignment, eventual restacking or a zero-`under` masked-panel counter to a visual pass.
2. Require an architecture proposal to explain how target order and paper coverage remain synchronized, using the native-child control as the working relationship model. Another repair loop must beat this failing test before any signed-app integration is presented as a correction.
3. Require one- and two-window cases, covered/uncovered neighbors, overlap, programmatic raises, app activation, close/quit, screenshot picking, Spaces/full screen and the existing idle/paused CPU gates. Acceptance requires no bare paper patches, no neighbor spill and continuous coverage in consecutive encoded frames at the available display/capture cadence.
4. The tested techniques do not meet those criteria. Release can remain deferred while attachment routes are investigated, or per-window mode can be deferred while whole-screen mode receives its own launch qualification. The recommendation is to keep per-window release blocked; no feature has been removed or disabled.
5. Treat AX observers and input interception as changes to the existing product contract. Neither is authorized for production by the investigation request; neither should be claimed to guarantee every external ordering operation without testing.

## Decision points

- The console prerequisite has been satisfied for the guarded runs; a ready session alone is still insufficient if native input or capture controls fail.
- No feature or privacy change is authorized by these measurements. The remaining choice is an architecture/launch-scope decision; faster polling or a zero-`under` counter does not satisfy the demonstrated visual requirement.

## Open questions

- Can a supported persistent relationship be established for an uncooperative external app without changing the current product promises? No such route was demonstrated.
- Does a future candidate survive a sole covered window, translucent/custom-shaped targets, programmatic ordering and the existing performance gates? No candidate has reached that qualification stage; the failed variants were not promoted to CPU or signed-app passes.
- How do callback timing and actual presentation vary on older supported macOS versions and other display refresh rates?
- The tested display reported 1920×1080 at 60 Hz and scale one; its physical-versus-virtual attachment was not established. These are captured compositor images, not optical high-speed camera measurements. Neither that limitation nor clean owned-child patches qualifies an external-cover candidate.

## SDK references

The Carbon and display-link header declarations were inspected in the Apple
macOS SDK. Resolve the SDK with `xcrun --show-sdk-path`; the relevant relative
paths are:

- `System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/MacWindows.h`
- `System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/CarbonEvents.h`
- `System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSScreen.h`
- `System/Library/Frameworks/AppKit.framework/Versions/C/Headers/NSWindow.h`
