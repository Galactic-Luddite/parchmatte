# Security Audit: Phase 1 Findings

Run 2026-09-23 on macOS 26 (Apple silicon), against branch `v2`. Checks map
to `docs/SECURITY_PLAN.md`. Scripts referenced are in `Tests/Harness/`.

## Summary

| ID | Severity | Finding | Status |
|---|---|---|---|
| F1 | Medium | The free build (`scripts/build.sh`) had no App Sandbox and no hardened runtime | **Fixed:** signed with `Resources/Parchmatte-Free.entitlements` and `--options runtime` |
| F2 | Low | The store Release build carried `com.apple.security.get-task-allow` (Xcode's debugger entitlement) | **Fixed:** `CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO` for Release in `project.yml` |
| F3 | Low | GitHub repo: no branch protection, secret scanning, push protection or Dependabot | **Open (launch):** these are paid features on a private repo in a free org; enable them when the repo goes public |
| F4 | Low | The first commit's author email is a personal Gmail address; the other 19 use a placeholder | **Fixed (2026-09-25 check):** every commit in this repo is now authored with the GitHub no-reply address. The companion website repo still carries four commits under the personal address (release audit R4, owner decision) |
| F5 | Info | Hotkeys registered with `RegisterEventHotKey` still fire while Secure Input is on | **Accepted:** the API delivers only "this registered combination was pressed". No key data, no observation of typing. The plan's wording is updated below |
| F6 | Info | The prefs fuzz covers launching, not every menu path with bad data | **Accepted:** menu builders read through type-checked, clamped `Settings` accessors (`as? … ?? default`) |
| F7 | Info | The binary is reproducible only when built in the same folder (absolute paths are embedded) | **Accepted and documented:** the LC_UUID matches across folders |

No Critical or High findings.

## Evidence

### S1: Overlay and UI deception
- Opacity capped at 60% (`AppInfo.maxOpacity`) and enforced at every layer.
  See the commit "Cap cover opacity at 60%".
- **E1/E2 passed:** the owner confirmed that the lock screen, password
  prompts and permission dialogs are easy to read under a 60% cover.

### S2: Screen content and privacy (PASS)
- `grep -rnE "kCGWindowName\b|CGWindowListCreateImage|ScreenCaptureKit|SCStream|SCShareableContent|CGDisplayCreateImage|CGDisplayStream" Sources/`
  returns **no matches**.
- Window data read: bounds, window number, owner PID, owner application
  name, layer and the on-screen flag only (`CoverManager.swift`). No
  contents, no titles. `docs/PRIVACY.md` lists the same fields.
  **Correction (release audit R2, 2026-09-25):** the owner application name
  (`kCGWindowOwnerName`, compared against "Dock" to detect Mission Control)
  was read by the code but missing from this list, the plan and the privacy
  policy. All four now name it.
- Entitlements, both builds: exactly `com.apple.security.app-sandbox`
  (`codesign -d --entitlements -`).
- No permission prompts. No Screen Recording or Accessibility use in the
  code.

### S3: Input (PASS)
- `grep -rnE "CGEvent|tapCreate|addGlobalMonitorForEvents|addLocalMonitorForEvents|IOHIDManager|IOHID|AXUIElement|AXIsProcessTrusted" Sources/`
  returns **no matches**.
- The only keyboard API is `RegisterEventHotKey` (`HotKeys.swift`), for 10
  fixed combinations (Control-Option with O, P, T, L, S, G and the four
  arrows; updated for build 3, was 7). Keylogging is not a capability of this binary.
- Re-checked on branch v2: commit `8df64ee` briefly added an
  `NSEvent.addGlobalMonitorForEvents` mouse-down monitor for cover
  restacking. It was removed in the following commit; restacking now uses
  only app-activation notifications and the window list. The grep above
  (plus `AXObserver`) again returns no matches.

### S4: Network (PASS)
- `grep -rnE "URLSession|NWConnection|NWListener|socket\(|CFStream|NSURLConnection|WKWebView" Sources/`
  returns **no matches**. The only URL is `AppInfo.privacyPolicyURL`,
  opened in the user's browser via `NSWorkspace.open`.
- Neither build has a `network.client` entitlement, so the sandbox
  enforces no networking.
- Runtime: `Tests/Harness/netwatch.sh 32` ran 16 samples while cycling
  lamps and textures and toggling whole screen. It saw **0 sockets**.
- **Pending:** a longer soak (phase 3, H4).

### S5: Preferences as input (PASS)
- `Tests/Harness/fuzz_prefs.sh` (build 3: 14 keys × 12 values = 168
  launches, 0 crashes; adds `restackWatchHz` and two colliding over-long
  excluded-app keys, which crashed build 2, release review C1). Original
  run: 13 keys × 11 hostile values (wrong
  types, ±1e308, NaN, inf, int extremes, arrays, dicts, a 5,000-character
  string). **143 launches, 0 crashes.** It runs against the debug build's
  separate defaults domain.
- Excluded apps and display names are only compared (dictionary lookups
  and set membership). They are never executed or used as paths.
- `zone.tab` is a root-owned system file read with `try?`. A missing or
  malformed file falls back to an offset-derived longitude, or 7:00/19:00.

### S6: Signing, runtime and supply chain (PASS after F1, F2)
- Hardened runtime on in both builds (`flags=0x10002(adhoc,runtime)`).
- No third-party dependencies in the app: `Package.swift` declares none.
- ~~`scripts/*.py` import only `math`, `random`, `struct`, `zlib` and
  `pathlib`.~~ **WITHDRAWN (release review, 2026-09-23):** true of the art
  scripts only. `scripts/asc_api.py` (release tooling, not shipped)
  imports the third-party `jwt` (PyJWT, line 21). It is now pinned with
  hashes, together with cryptography, cffi and pycparser, in
  `scripts/requirements-release.txt`; install with
  `pip install --require-hashes -r scripts/requirements-release.txt`.
  The script also refuses a `.p8` key that is group- or world-readable.
- Reproducible: two clean release builds in the same folder produced an
  identical SHA-256, `0fac75b2…5871`.
- The history secret scan found 0 hits for AWS, GitHub, OpenAI, Anthropic,
  Slack or Google keys, or for private-key blocks, across 6,528 lines of
  `git log -p --all`. (`gitleaks` is installed as an x86_64 binary and
  can't run without Rosetta.)
- Static analysis: `xcodebuild analyze` reported **ANALYZE SUCCEEDED, 0
  warnings**.

### S7: Failure safety (PASS)
- **Hang:** `kill -STOP` on Parchmatte with a whole-screen cover over the
  menu bar, then a real click on the Apple menu (`Tests/Harness/click.swift`)
  opened it. Clicks pass through a frozen Parchmatte because the window
  server does the hit-testing.
  - The first attempt read the menu state too early (a test-timing false
    negative). The repeat, and the unfrozen baseline, both passed.
- **Crash:** `kill -9` leaves 0 covers on screen, 0 Parchmatte processes
  and 0 launchd jobs.
- Launch at Login registers only `SMAppService.mainApp`. There are no
  helpers or agents in the bundle.

### S8: Independent review (done 2026-09-23, commit `b9dc015`)

**Independent reviewer (source review):** **releasable.**
- S2–S5 independently confirmed from the code. S6/S7 confirmed at source
  level, relying on phase 1 for the live evidence.
- One open item (PM-1, Medium): the legibility of system security UI under a
  whole-screen cover must be checked before submission. See E1/E2 below.
- The texture caches and the Space-cover pool are bounded. The privacy
  manifest is accurate.

**Second reviewer (adversarial pass):**

| ID | Severity | Finding | Status |
|---|---|---|---|
| X1 | High | The Desk Lamp tint composited on top of the 60% texture cap (about 73% at Late Night + Warm) | **Fixed `04d3147`:** the cap now bounds texture + lamp together |
| X2 | Medium | Whole-screen covers above system UI with no suppression | **Closed:** owner confirmed security UI is easy to read at the 60% cap (E1/E2) |
| X3 | Medium | Cover pools keyed by display name, so identical monitors collide | **Fixed `04d3147`:** keyed by hardware display ID |
| X4 | Medium | A continuously moving covered window keeps tracking at 60 Hz | **Accepted:** only windows the user chose to cover; measured about 6–8% of one core while moving, 1–3% idle |
| X5 | Low | Tab re-association trusts PID + geometry, so another window of the same app could take a cover | **Accepted:** same-app only, 250 ms settle, never while waiting on another Space; a stronger identity needs window titles, which Parchmatte deliberately doesn't read |
| X6 | Low | `excludedApps` unbounded in a doctored prefs file | **Fixed `04d3147`:** capped at 100 entries of 256 characters |

No Critical findings. The only High is fixed.

### E1/E2: security UI legibility (PASS, owner check 2026-09-23)

The owner checked by eye, at the 60% cap with Chalkboard, the lock screen, an
administrator password prompt and a privacy permission dialog: all easy to
read. This closes PM-1 and X2.

History:

An automated attempt (an admin password prompt under 60% Chalkboard plus the
Late Night lamp, Warm glow) couldn't be judged: macOS excludes security
prompts from screen capture. The owner should check by eye, at 60% with the
darkest texture, the lock screen, an administrator password prompt and a
privacy permission dialog.

## Plan corrections

- S3's line "the hotkeys don't fire while secure input is on" is replaced
  by F5. Carbon hotkeys are delivered during Secure Input by design, which
  is harmless because they carry no keystroke data.
- Enabling the free build's sandbox moves its preferences into
  the app container (`Library/Containers/com.galacticluddite.parchmatte` in the user's home folder), the same container
  as the store build. There are no public users yet, so no migration is
  needed.
