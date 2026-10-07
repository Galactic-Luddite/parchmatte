# Parchmatte Security Review Plan

Parchmatte draws always-on-top windows over everything a person does on their
Mac. That position demands trust. This plan checks that Parchmatte can't be
used, or fail, in a way that harms the user. Findings are rated Critical,
High, Medium or Low. Critical and High findings block release.

## Threat model

**Assets:** what's on the user's screen, their input (typing, clicks,
passwords), their trust in system UI, their battery and performance, and
their privacy.

**Adversaries and failure sources:**
- a bug in Parchmatte
- a tampered build (a fake copy of the free download, or a compromised
  GitHub release)
- a malicious app on the same Mac trying to use Parchmatte
- a malicious preference file

**What Parchmatte must never do:**
- see or store screen contents
- read keystrokes
- intercept input
- hide or imitate system security UI
- talk to the network
- keep running after being quit

## Review areas

### S1. Overlay and UI deception (clickjacking)

- [x] Every cover has `ignoresMouseEvents = true`, and none can become key or
      main. Test: automated click and keyboard pass-through (test plan D1–D4).
      Evidence: `docs/audit/security-findings.md` S1 and
      `docs/audit/test-results.md`.
- [ ] Covers only ever draw texture plus a tint. There is no code path that
      renders text, images from outside the bundle, or anything that could
      imitate UI.
- [x] **Maximum opacity cap: 60%** (`AppInfo.maxOpacity`). It's enforced in
      the settings getter and setter, the per-window setter, the sliders and
      the final layer assignment. NaN and infinity become 0. Checked
      2026-09-23: `opacity = 5`, `softness = "banana"`, an unknown texture, a
      negative schedule time and a wrong-type excluded-apps list all launch
      cleanly.
- [ ] **Decision (owner, 2026-09-23): whole-screen covers go over everything,
      including the menu bar, Dock and system UI.** The 60% cap is the safety
      net. Verify on each macOS version that password prompts, the lock
      screen, the login window, permission dialogs and Screen Time stay fully
      readable and recognisable under a 60% cover of every texture and lamp.

### S2. Screen content and privacy

- [x] Only window **bounds, window number, owner PID, owner application
      name, layer and on-screen flag** are read (audit S2). The owner name
      identifies system animation UI (Dock and WindowManager) and the native
      screenshot picker (screencapture/Screenshot). The picker check uses only
      its owner, layer, and display-sized bounds to move our own covers out of
      window selection; it neither captures pixels nor observes input. Grep for `kCGWindowName\b` (not `kCGWindowOwnerName`),
      `CGWindowListCreateImage` and ScreenCaptureKit: there must be no hits.
      Any new `kCGWindow*` metadata key must be added here, in
      `docs/PRIVACY.md` and on the website's privacy page in the same commit.
      Public `kCGWindowListOption*` query constants select which windows the
      API returns; they are not metadata read from those windows.
- [ ] No Screen Recording or Accessibility permission is requested. Confirm
      no prompt appears on a clean account.
- [ ] The store entitlements are exactly `com.apple.security.app-sandbox`.
      Confirm with `codesign -d --entitlements -`.
- [ ] `PrivacyInfo.xcprivacy` and `docs/PRIVACY.md` match the code exactly.

### S3. Input

- [ ] Only `RegisterEventHotKey` for 10 fixed Control-Option combinations
      (O, P, T, L, S, G and the four arrows). There are no
      `CGEventTap`, `NSEvent.addGlobalMonitorForEvents`/`addLocalMonitorForEvents`,
      `IOHID` or Accessibility (`AXUIElement`, `AXObserver`) calls. This
      rules out keylogging as a capability, not just a policy. Window covers
      follow stacking changes through NSWorkspace activation notifications
      and CoreGraphics window-list polling only, never input events.
- [ ] Secure Event Input (password fields, the lock screen) is unaffected.
      ~~The hotkeys don't fire while secure input is on.~~ **Withdrawn
      (audit F5, `docs/audit/security-findings.md`):** Carbon hotkeys *do*
      fire while Secure Input is on. That is harmless: the event carries
      only "this registered combination was pressed", no keystroke data,
      and nothing observes typing.

### S4. Network and data

- [ ] No networking code. Grep for `URLSession`, `Network.framework` and
      sockets. The only URL is the privacy-policy link, which the user opens
      in their browser.
- [ ] The store build's sandbox has no `network.client` entitlement, so
      macOS enforces this.
- [ ] Verify at runtime with `nettop` or Little Snitch over a 24-hour soak:
      zero connections.
- [ ] **Free build:** also sign it with the sandbox entitlement (ad-hoc
      signing supports it), so users who build it themselves get the same
      containment.

### S5. Preferences and inputs as attack surface

- [ ] Fuzz every preference key with wrong types, huge numbers, negatives,
      NaN, long strings and unknown enum values. Expect clamping or a default,
      never a crash.
- [ ] The excluded-apps dictionary and display names are only compared, never
      executed or used as paths.
- [ ] Reading `zone.tab` fails safe when the file is missing, malformed or
      huge.

### S6. Code signing, runtime and supply chain

- [ ] Hardened Runtime is on, with no exceptions (no JIT, no unsigned
      executable memory, no library-validation opt-out).
- [ ] No third-party dependencies in the app: `Package.swift` has none, and
      the art scripts use the Python standard library only. Keep it that way,
      and add a CI check. The release tool `scripts/asc_api.py` (not shipped)
      needs PyJWT and cryptography, pinned with hashes in
      `scripts/requirements-release.txt`.
- [x] **Decision (owner, 2026-09-23): the free version is source-only.** No
      downloadable builds, so no unsigned downloads. If that ever changes,
      sign it with a Developer ID and notarize it, and publish SHA-256
      checksums. Don't teach users to click "Open Anyway" on downloads. That
      trains exactly the habit malware relies on. The README's "Open Anyway"
      note should apply only to builds people compiled themselves.
- [ ] Reproducible-build check: two clean builds from the same commit produce
      the same binary hash (or a documented, explained difference).
- [ ] GitHub repo: branch protection on `main`, signed release tags, 2FA,
      Dependabot/secret scanning on, and no secrets in history.

### S7. Failure safety

- [ ] **Hang:** if the main thread stalls, covers stay click-through, so the
      Mac remains usable. Document the recovery (⌘⌥Esc → Parchmatte).
- [ ] **Crash:** covers disappear with the process. Verify there are no
      helper processes or login agents that could keep drawing.
- [ ] **Stuck-visible recovery:** the ⌃⌥O and ⌃⌥S hotkeys always work, even if
      the menu-bar icon is hidden by a crowded menu bar.
- [ ] Launch at Login registers only the main app (`SMAppService.mainApp`),
      with no daemons or agents.

### S8. Independent review

- [ ] A line-by-line security code review by an independent reviewer, using
      this checklist.
- [ ] A second, adversarial pass by a different reviewer that tries to find a
      way for Parchmatte, or another app, to capture content, block input or
      deceive the user.
- [ ] Static analysis: the Xcode Analyzer (`xcodebuild analyze`) with zero
      warnings.

## Evidence

Each checkbox gets a command or test with its output, recorded alongside the
test-plan runs. The final sign-off table lists every finding with its rating
and resolution.
