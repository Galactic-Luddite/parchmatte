# Mac App Store Release Guide

This is Galactic Luddite's first App Store release. Everything below is
checked against the App Review Guidelines as published at
<https://developer.apple.com/app-store/review/guidelines/> (fetched
2026-09-30). The [resubmission research](design/app-store-resubmission-research-2026-09-30.md)
records the current requirements and remaining evidence gaps. Re-check before
each submission; Apple updates them often.

## Owner to-do (only you can do these)

Status 2026-10-07: Parchmatte 1.0 (24) is Ready for Sale at
https://apps.apple.com/us/app/parchmatte/id6815385110?mt=12. App Store Connect declares the privacy policy URL as
`https://parchmatte.com/privacy/`, and the support and marketing URLs as
`https://parchmatte.com/`. The unchecked items below are the ones not yet
confirmed by anything an agent can read.

- [x] **Apple Developer Program** membership ($99/year), enrolled as the legal
      owner of the app (an individual, or an organization with a D-U-N-S
      number if you want "Galactic Luddite" as the seller name).
- [ ] **Paid Apps agreement**, plus tax forms and banking, in App Store Connect →
      Business. The app is on sale, which implies they are in effect, but the
      API does not expose agreement state; confirm in App Store Connect →
      Business that nothing is pending or expiring.
- [x] **Host the privacy policy** (`docs/PRIVACY.md`) at a public URL, and set
      `AppInfo.privacyPolicyURL` in `Sources/Parchmatte/Surfaces.swift` to match.
      The in-app menu item and the App Store Connect field must both link to it.
- [ ] **Support URL and email**: the declared Support URL is the home page,
      which shows `support@parchmatte.com`. The domain's MX records point at
      Mailgun; send a test message and confirm it arrives.
- [x] **Confirm the name**: search App Store Connect for "Parchmatte" when
      creating the app record. Names are unique store-wide.
- [x] **Screenshots** (see below; build 24 set recorded).
- [ ] Decide whether the free build gets a **GitHub Release** (a zipped
      `dist/Parchmatte.app`), or stays source-only.

## Build and submit

1. Accept the current Developer Program License Agreement in App Store
   Connect (account holder only). An unaccepted update blocks creating an
   app record with no useful error.
2. Register the App ID `com.galacticluddite.parchmatte` at developer.apple.com
   (Certificates, Identifiers & Profiles). Xcode does not do this for you.
3. In App Store Connect, create the app record (bundle ID above, SKU
   `parchmatte-mac`). The upload in step 6 fails with "App record not
   found" until this exists; that error is not a signing problem.
4. `xcodegen generate && open Parchmatte.xcodeproj`. Target Parchmatte →
   Signing & Capabilities: choose your Team. Keep **App Sandbox** on, with
   no other capabilities.
5. Product → Archive.
6. Organizer → Distribute App → App Store Connect → Upload.
7. Back in App Store Connect: fill in the listing below, set the price to
   the **$2.99 tier**, choose all territories, add the privacy answers
   ("Data Not Collected"), attach the build and submit for review.
6. **Review notes** (paste into "Notes for Review"; the full six-point
   version under "Replying to 2.1 Information Needed" below supersedes
   this short one):
   > Parchmatte is a menu-bar utility (no Dock icon). Click the page icon in
   > the menu bar to open its menu. "Paper Whole Screen" shows a subtle
   > texture overlay; raise the slider to see it clearly. "Paper <App>
   > Window" covers only the frontmost window. Overlays ignore all mouse
   > input. No account, network access or special permissions are needed.

## Replying to "2.1 Information Needed" (original request on build 1.0.0 (5))

App Review held the first submission on 2026-09-24 under Guideline 2.1
because the developer account has "a limited App Review history". It is a
request for information, not a finding against the app. Reply in App Store
Connect with the recording and the six answers below, and paste the answers
into App Review Information → Notes as well, so the next submission carries
them. Nothing below mentions GitHub, the free build or prices elsewhere
(3.1.1 and 2.3.10); keep it that way.

The build 5 response and recording were sent on 2026-09-27. The owner then
chose to replace build 5 with build 6; the earlier submission was canceled.
For build 6, record and attach the exact newly uploaded build, replace the
screenshots showing old menu names, and update Notes and the response to
identify build 6. Do not rely on the earlier build 5 recording as proof of
the new build.

Before replying, fix the website's privacy page (audit R2: add the owning
application's name to the list of window fields read). The reviewer will
open the privacy URL, and it should match the code when they do. No new
build is needed for that.

### The screen recording

Apple wants a capture on a physical Mac on the latest macOS, starting with
the launch and showing the typical flow. Two things will ruin it:

- **Hide from Screenshots is on by default.** With it on, the paper is
  invisible to the recording and the app looks like it does nothing. Before
  recording: open the menu, turn **Hide from Screenshots off**, then quit,
  so the recording can begin with a launch.
- **The default strength is 15%.** Subtle on purpose; on a compressed video
  it can vanish. Raise Strength to about 45–60% early in the recording.

Record the build under review (install it from TestFlight for Mac, or the
exported archive), not a local debug build. Use ⌘⇧5 → Record Entire Screen,
a clean desktop, and a TextEdit window with a few paragraphs of plain
placeholder text. Aim for 90 seconds to two minutes. No narration is needed;
the reviewer follows the cursor.

| Step | Do | Shows |
|---|---|---|
| 1 | Launch Parchmatte from /Applications. Point at the page icon that appears in the menu bar. | It is a menu-bar app with no Dock icon |
| 2 | Open the menu. Show "Active" at the top and "Paper Whole Screen" checked. | Paper is on from first launch |
| 3 | Drag Strength up to about 60%, pause, back to about 35%. | The grain is visible over the whole screen |
| 4 | Texture ▸ Chalkboard, then Denim. Orientation ▸ Flipped Horizontally, then back to Normal (or press ⌃⌥I four times). Drag Softness. | Textures, the grain's direction, and softness |
| 5 | Page Light ▸ Candlelight, then Glow: Warm, then Page Light ▸ Off. | The tint |
| 6 | Click in the TextEdit window and type a sentence; scroll it. | Input passes through the paper |
| 7 | Untick Paper Whole Screen. With TextEdit in front, choose "Paper TextEdit Window" (or press ⌃⌥P). Drag and resize the window. | A single-window cover that follows |
| 8 | Open the menu: the "This Window — TextEdit" section. Change its texture. | Per-window style |
| 9 | "Remove Paper from TextEdit Window". Tick Paper Whole Screen again. | Removal |
| 10 | Snooze ▸ 5 minutes: show the badge on the menu-bar icon and "Snoozed until…"; then Snooze ▸ Resume Now. | Snooze |
| 11 | Hover Schedule, Displays and Excluded Apps so each submenu opens. | The remaining settings |
| 12 | Privacy Policy…: the browser opens parchmatte.com/privacy/. | The policy link required by 5.1.1 |
| 13 | Quit Parchmatte. The paper disappears with it. | Nothing is left behind |

Turn Hide from Screenshots back on afterwards if you want it; it is the
shipped default either way.

### The six answers (paste into the reply and into Notes for Review)

> **1. Screen recording:** attached. Captured on a physical Mac running the
> current macOS, beginning with the app launch. Parchmatte has no accounts,
> no login, no user-generated content and no paid content or features inside
> the app, so none of those flows exist to record. Note for the reviewer:
> the app's "Hide from Screenshots" setting (on by default) asks macOS to
> leave the paper out of captures; it was turned off for this recording so
> the overlay is visible.
>
> **2. Purpose and audience:** Parchmatte is a menu-bar utility for people
> who read and write on a Mac for long stretches. It lays a fine, matte
> paper grain, and optionally a warm Page Light tint, over the display so a
> glossy screen looks and feels more like a page. It can paper the whole
> screen or a single window, with eight textures, a softness control, a
> flip for the grain's direction, lamp tints, schedules (sunset to sunrise,
> or custom hours), snooze, per-display
> control, excluded apps and pause-on-battery. The overlay never takes
> input: clicks, scrolling and typing pass straight through to the apps
> underneath. Its value is comfort and a quieter-looking screen; it makes
> no health claims.
>
> **3. Setup and access:** none required. Launch the app; a page icon
> appears in the menu bar (there is no Dock icon). Paper Whole Screen is on
> from first launch at a subtle 15% strength; raise the Strength slider in
> the menu to see it clearly. "Paper <App> Window" (or Control-Option-P)
> covers only the frontmost window and follows it. Every feature is in that
> one menu. There are no logins, credentials, sample files or onboarding
> steps.
>
> **4. External services:** none. The app has no network access (its only
> entitlement is App Sandbox; it has no network entitlement), no analytics,
> no crash reporting, no authentication, no payments, no AI services and no
> third-party code. Sunrise and sunset times are computed on the device
> from the system time zone; the app does not request location. The only
> outbound link is the Privacy Policy menu item, which opens
> https://parchmatte.com/privacy/ in the user's browser.
>
> **5. Regional differences:** none. The app functions identically in
> every territory. It is English-only in this release.
>
> **6. Regulated industry or protected material:** not applicable. The app
> is a display utility. All textures are generated procedurally by our own
> code, and the icon and name are our own; it contains no third-party
> material, marks or licensed content.

### After the reply

The owner resolved audit R13 by approving the build 6 labels Fine Grain,
Woven, Imprint, Soft Leaf and Page Light. Verify the new screenshots and
recording show these labels before resubmitting.

## Release tooling (App Store Connect API)

`scripts/asc_api.py` talks to the App Store Connect API for build polling
and metadata. It is release tooling only and never ships in the app. Its
dependencies are pinned with hashes; install them into a dedicated
virtualenv. Set `PARCHMATTE_RELEASE_VENV` to its location, then run:

```sh
python3 -m venv "$PARCHMATTE_RELEASE_VENV"
"$PARCHMATTE_RELEASE_VENV/bin/pip" install --require-hashes -r scripts/requirements-release.txt
```

Credentials come from `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_PATH`. The
script refuses to run if the `.p8` key is readable by group or others
(`chmod 600` it).

### Uploading a build

`scripts/upload_store.sh` archives the Store build from the current commit
and uploads it, headlessly, with the same three variables:

```sh
ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=/path/AuthKey_<id>.p8 \
  scripts/upload_store.sh               # archive, sign, upload
  scripts/upload_store.sh --export-only   # signed .pkg only, nothing sent
```

It prints the commit, version, entitlements and executable hash to record
in the private release handoff log. Things to know before running it:

- Bump the build number first ("Build N" commit); App Store Connect rejects
  a build number it has already seen.
- Uploading only adds a build. It does not submit anything for review and
  does not change the build a version has selected, so it is safe while
  another build is in review. Selecting the build and submitting stay with
  the owner.
- The key needs the Admin role: the export has Xcode create the
  distribution certificate and profile on demand. No distribution
  certificate has to be in the keychain beforehand.
- The team is `DEVELOPMENT_TEAM` from `project.yml`, which the script reads.
  The suffix in the development certificate's display name is a different
  identifier; using it fails with "No App Store Connect access for the team".
- Apple processes an upload for a few minutes. Poll
  `/v1/builds?filter[app]=<id>&sort=-uploadedDate` with `asc_api.py` until
  `processingState` is `VALID`.

## Rotating or revoking the App Store Connect key

Do this at once if the `.p8` may have leaked (a lost or shared machine, a
key file with loose permissions, a compromised Python package on the
release machine), and otherwise once a year.

1. App Store Connect → Users and Access → Integrations → App Store Connect
   API → Team Keys. Generate a new key with the narrowest role that works
   (App Manager covers uploads and metadata). Download the `.p8`; Apple
   only offers it once.
2. Store it in a dedicated credential directory outside this repository with
   `chmod 600`, and set `ASC_KEY_ID` / `ASC_KEY_PATH` (and the
   `-authenticationKeyID` /
   `-authenticationKeyPath` arguments used with `xcodebuild`).
3. Check it works: `python3 -c "from asc_api import ASC; print(ASC().get('/v1/apps')['data'][0]['id'])"`
   from `scripts/`.
4. **Revoke** the old key on the same page. Tokens it already signed stop
   working immediately (they last at most 20 minutes anyway).
5. Delete the old `.p8` from disk and from any backups you control, and
   check Users and Access → activity for anything you did not do.

## Draft listing

**Name:** Parchmatte
**Subtitle** (30 characters max): `Paper texture and warm tint`

Issue [#24](https://github.com/Galactic-Luddite/parchmatte/issues/24) tracks
the build 6 subtitle rejection under Guideline 5.2.5. On 2026-09-30, the
original review message was inspected and this 27-character subtitle was
saved in App Store Connect. A page reload confirmed the exact value in
English (U.S.), the sole configured localization; the other languages were
not localized. Recheck localizations if any are added before submission.

The correction went out with build 21 (Waiting for Review since
2026-10-02), whose review notes disclose the per-window activation flash as
a limitation. Build 22 removes that limitation (PR #26: covers rest one
level above ordinary windows while nothing overlaps them); its review notes
must drop the disclosure, and its signed Store audit, exact-build media and
build selection are prepared under the current section of
the private release handoff log.

**Category:** Utilities (secondary: Productivity)
**Price:** $2.99

**Promotional text:**
> Make your glossy screen feel like real paper.

**Description:**
> Parchmatte gives your Mac's display the look and feel of real paper: a fine,
> matte grain with an optional warm Page Light tint, so long days of reading and
> writing feel a little gentler on the eyes.
>
> • Eight real-paper textures: Parchmatte, Fine Grain, Chalkboard, Woven, Imprint, Soft Leaf, Felt and Denim, with a softness control and a flip for the grain's direction
> • Page Light tints, from Candlelight to Aurora, with adjustable glow
> • Paper the whole screen, or just one window. Paper follows the window as it
>   moves, resizes, switches tabs and goes full screen
> • Give each window its own texture, light, strength and softness
> • Schedules: sunset to sunrise, sunrise to sunset, or your own hours
> • Snooze, per-display control, excluded apps and pause on battery
> • Global hotkeys for everything
>
> Parchmatte never gets in your way: clicks, scrolling and typing pass straight
> through. It collects no data, needs no account and asks for no permissions.
>
> Parchmatte is open source.

**Keywords** (100 characters max; no health claims such as "eye comfort", no competitor marks, and never "paperlike"):
`paper,texture,grain,overlay,woven,imprint,soft leaf,denim,page light,tint,menu bar,focus`

**Screenshots:** six captioned 2880x1800 frames, each built from a real capture with an enlarged crop of the open menu:

Before submitting a new build, compare every visible menu label in the
screenshots, website gallery, listing, recording, and App Review notes with
the signed build selected in App Store Connect. Replace any image or text
that still shows an earlier build's labels; then verify the uploaded files
and selected build number in App Store Connect. Keep the original captured
frames and the encoded review video locally until review finishes.
1. Your screen, with the feel of real paper
2. Strength and softness, right in the menu bar
3. Eight real-paper textures
4. Page Light for evening work
5. Give each window its own paper
6. Turns on at sunset, off at sunrise

> **Do not** mention GitHub, free builds, other stores, prices elsewhere or
> "build it yourself" in any App Store metadata or in the app itself. The
> "buy it or build it" message lives only in the README and on the Galactic
> Luddite site. See 3.1.1 and 2.3.10 below. "Open source" as a plain fact is
> fine.

## Screenshots

Mac App Store screenshots: 16:10 at 1280×800, 1440×900, 2560×1600 or
2880×1800, 1 to 10 images, flattened RGB with no alpha. Before capturing,
turn **Hide from Screenshots** off, and use a clean desktop with a neutral
document. No work content, names or other apps' branding.

The six frames are the captioned list under "Draft listing" above; that
list is the single source of truth for order and captions. Each frame is a
real capture with an enlarged crop of the open menu, so the screenshot
shows the actual app in use (guideline 2.3.3).

## Guideline compliance

| Rule | Requirement | Parchmatte | Status |
|---|---|---|---|
| 2.4.5(i) | Must be sandboxed | App Sandbox is the only entitlement (`project.yml`). All features were tested in the sandboxed build. | Pass |
| 2.4.5(ii) | Xcode-packaged, self-contained | A single app bundle archived in Xcode; installs nothing elsewhere. | Pass |
| 2.4.5(iii) | No launch at login without consent | Launch at Login is off by default and opt-in via `SMAppService`. | Pass |
| 2.4.5(iv) | No downloading code | No network access at all. | Pass |
| 2.4.5(v) | No root escalation | None. | Pass |
| 2.4.5(vi) | No license screens or keys | None. | Pass |
| 2.4.5(vii) | Updates only via the App Store | No updater in the store build. | Pass |
| 2.5.1 | Public APIs only | `CGWindowListCopyWindowInfo`, `CGWindowListCreateDescriptionFromArray`, `CGWindowListCreate` (called through its typed public `CGWindow.h` declaration in `WindowListBridge` because Swift does not import the raw-number array), `RegisterEventHotKey`, `IOPSNotificationCreateRunLoopSource`, `SMAppService` and `NSWindow.sharingType` are all public. The experimental per-window Ribbon uses public `CAMetalLayer`, `CAMetalDisplayLink` (macOS 14+; older systems retain the existing fade), and Metal texture/render pipeline APIs to deform only the app's own styled bundled material; it adds no capture API or entitlement. No private window-server calls. | Pass |
| 2.3.10 | No other platforms or marketplaces in metadata | The listing above names none. | Pass |
| 3.1.1 | No calls to action toward purchasing outside the store (outside the US storefront) | The app and metadata never mention the free build. | Pass |
| 4.1 | Copycats: don't copy a popular app's idea, name or UI | Screen-texture overlays already exist on the store. Parchmatte has an original name, icon, textures and code, and differs with Page Light tints, per-window covers with individual strength, and schedules. The description leads with what's distinctive. | **Risk: moderate.** If rejected, reply to App Review listing the differentiators. |
| 4.2 | Minimum functionality | A full utility with many settings, not a wrapper. | Pass |
| 5.1.1(i) | Privacy policy linked in the listing **and in the app** | Menu → "Privacy Policy…" opens `AppInfo.privacyPolicyURL`. | **Pass once the URL is hosted** |
| 5.1.2 | Privacy manifest / data use | `PrivacyInfo.xcprivacy`: no tracking, no data collected, UserDefaults reason CA92.1. | Pass |
| 5.2.1 | Intellectual property | Original name (checked; no App Store match on 2026-09-23), code, icon and procedurally generated textures. No third-party marks. | Pass |

## Sandbox notes

Every feature works under App Sandbox with no extra entitlements:

- Reading window positions (`CGWindowListCopyWindowInfo`) returns bounds
  without Screen Recording permission. Parchmatte never reads titles or
  contents.
- Carbon global hotkeys need no Accessibility permission.
- Sunrise/sunset reads the system time-zone table
  (`/usr/share/zoneinfo/zone.tab`, readable in the sandbox) and needs no
  location access.
