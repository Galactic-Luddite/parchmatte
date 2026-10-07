# Research: Mac App Store resubmission readiness

**Date:** 2026-09-30
**Issues:** #22, #24
**Question:** What current Apple requirements and remaining evidence gaps govern Parchmatte's next Mac App Store submission after the subtitle rejection and the Denim/Ribbon candidate work?
**Decision:** Prepare the next resubmission package while further activation-flash work is deferred. This report does not authorize submission or launch.

## Sources Consulted

| # | Source | Type |
|---|---|---|
| 1 | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | Apple policy |
| 2 | [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/) | App Store Connect reference |
| 3 | [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/) | App Store Connect reference |
| 4 | [Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/) and [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) | App Store Connect reference |
| 5 | [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy) and [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) | Apple privacy guidance |
| 6 | [Adding a privacy manifest](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) and [required-reason API values](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) | Apple developer documentation |
| 7 | [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds) | App Store Connect reference |
| 8 | [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/) | Apple submission notice |
| 9 | [Choose a build to submit](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit) | App Store Connect reference |

Repository evidence consulted: `docs/APP_STORE.md`, `docs/PRIVACY.md`, `docs/SECURITY_PLAN.md`, `docs/audit/attached-paper-native-trials.md`, `docs/audit/test-results.md`, `docs/design/activation-flash-research-2026-09-30.md`, `project.yml`, `Resources/PrivacyInfo.xcprivacy`, `Resources/Parchmatte.entitlements`, and the relevant source/resource manifests at candidate commit `6b1bc6a`.

## Findings

### Q1: What does the Guideline 5.2.5 subtitle rejection require?

**Answer:** Treat Apple's September 30 rejection as controlling feedback for this app: remove the term **Mac** from every affected App Store subtitle and save `Paper texture and warm tint` in each localization before resubmission. The replacement is 27 characters, within Apple's 30-character subtitle limit ([App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)).

The current published text of [Guideline 5.2.5](https://developer.apple.com/app-store/review/guidelines/#apple-products) prohibits confusing similarity to Apple products and interfaces and certain unauthorized Apple content. It does not state a blanket rule that the word “Mac” can never appear in a subtitle. The app-specific rejection still must be followed; the narrower conclusion avoids inventing a general policy that Apple has not published. [Guideline 2.3.7](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) independently requires accurate, relevant metadata and limits app names to 30 characters.

**Completed verification:** The original Apple review message for build 1.0.0 (6) was inspected in App Store Connect. The subtitle was changed from `Real paper feel for your Mac` to `Paper texture and warm tint`, saved, then read back after a page reload on 2026-09-30. English (U.S.) was the sole configured localization; all other languages were not localized. Verify any newly added localizations before submission.

**Confidence:** Confirmed for Apple's public rules, the app-specific rejection and the saved subtitle.

### Q2: Is the latest Denim/Ribbon implementation ready to submit?

**Answer:** The candidate contains materially newer implementation evidence than the first section of the private release handoff log reflects. Builds 18 and 19 bundle the selected Pale Wash Denim texture. Repository evidence records deterministic generation, 1x/2x resource checks, softness and opacity coverage, actual-menu selection, rendered inspection, 95 passing Swift tests, and focused native passes for window, Spaces, full-screen, performance, screenshot-picker, and lifecycle behavior (`docs/audit/attached-paper-native-trials.md`; `project.yml`; `Sources/Parchmatte/Surfaces.swift`). Ribbon is the latest owner-selected animation implementation candidate.

That evidence does **not** establish a release-qualified submission. Same-app click-to-raise and window cycling still expose a brief bare-window flash. The follow-up research records that all fourteen external-cover native trials failed continuous-coverage qualification; the two owned-child controls passed but do not represent covers over another application's windows (`docs/design/activation-flash-research-2026-09-30.md`). The owner has deferred more activation-flash work. Deferral preserves the known failure and does not constitute acceptance by Apple or a visual pass.

[Guideline 2.1](https://developer.apple.com/app-store/review/guidelines/#app-completeness) requires a final, on-device-tested app without obvious technical problems. [Guidelines 2.3 and 2.3.1](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) require current metadata and specific Notes for Review for new functionality. If per-window paper and Ribbon remain in the submitted scope and listing, the activation flash remains a release-readiness gap. If the owner later changes launch scope, the binary, description, screenshots, recording, and review notes must all describe that same scope; this report does not authorize such a change.

**Confidence:** Confirmed from repository evidence and Apple policy.

### Q3: What build, sandbox, and public-API rules apply?

**Answer:** Mac App Store apps must be appropriately sandboxed, Xcode-packaged, self-contained, consent-based for login launch, and distributed without an alternate updater. Apps may use only public APIs and must run on the current shipping OS ([Guidelines 2.4.5 and 2.5.1](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility)).

The checked-in Store target has only `com.apple.security.app-sandbox`, bundles its resources, declares macOS 13 as its minimum, and describes public AppKit, CoreGraphics, QuartzCore, Metal, Carbon hotkey, power, and service-management APIs (`project.yml`; `Resources/Parchmatte.entitlements`; `docs/APP_STORE.md`). These are strong source-level indicators, but the final archive remains the review artifact. Its entitlements, linked frameworks, bundle contents, minimum OS, signatures, and absence of quarantine attributes must be inspected after archiving. Apple has rejected macOS uploads containing `com.apple.quarantine` since February 18, 2025 ([Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)).

Apple's current [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds) table says App Store Connect uploads require Xcode 14 or later starting in 2026 and still lists macOS apps as buildable/uploadable with Xcode 6 or later. The separate Xcode 26 SDK mandate names iOS, iPadOS, tvOS, visionOS, and watchOS, not macOS ([Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)). Therefore, “Xcode 26 is required for this macOS submission” is not verified by Apple's current pages. Using the current stable Xcode and macOS SDK is a prudent project recommendation because 2.5.1 requires current-OS operation; record the exact Xcode build and SDK used.

**Confidence:** Confirmed for the published requirements; likely for source compliance pending final-archive inspection.

### Q4: Are “Data Not Collected,” window-owner metadata, and the privacy manifest consistent?

**Answer:** Yes, based on the described implementation, with final-binary and live-policy verification still required. Apple defines App Privacy “collection” as transmitting data off device in a way that lets the developer or a partner access it beyond the real-time request ([App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)). Reading window bounds, window number, owner process identifier, owning application name, layer, and onscreen state locally and transiently is therefore compatible with **Data Not Collected** when none of it leaves the device.

The repository privacy policy names those fields, says they are not stored or transmitted, and discloses local preferences. The manifest declares no tracking, no collected-data types, and UserDefaults reason `CA92.1`. Apple permits `CA92.1` for app-only preferences and rejects invalid manifest structures ([required-reason API values](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype); [adding a privacy manifest](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)).

[Guideline 5.1.1(i)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) requires a privacy-policy link in App Store Connect and an easily accessible link in the app. Apple also requires accurate, current App Privacy answers ([Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)). Before submission, verify the live policy still includes owning application name, the in-app link opens that page, App Store Connect shows **Data Not Collected**, and the final archive embeds the checked manifest. Generate and inspect the archive privacy report or equivalent release scan for every required-reason API category; the source manifest alone cannot prove the final binary has no additional category.

**Confidence:** Strong, pending final-archive and live-page evidence.

### Q5: What exact-build and screenshot evidence is required?

**Answer:** Apple associates an upload through bundle ID, version number, and build string, and allows only one build to be selected for a submitted app version ([Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds); [Choose a build to submit](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit)). The release record should therefore bind every artifact to the exact selected build: source commit, version/build string, archive identity, upload timestamp and processing result, TestFlight-installed identity, signed executable hash, OS/hardware used for testing, screenshots, review recording, review notes, and the App Store Connect build-selection read-back.

Apple requires screenshots and says they must show the app in use and accurately reflect the current experience ([Guideline 2.3.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)). Mac listings accept one to ten screenshots at specified 16:10 dimensions, including 2880x1800 ([upload guidance](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/); [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)). The existing build 6 media and recording do not prove build 19 or any later combined release. Replace every affected asset with evidence from the exact selected build, visibly include Denim wherever the listing claims eight textures, and ensure all labels match. The review recording should begin at launch on a physical Mac running the current macOS and demonstrate the reviewer path described in `docs/APP_STORE.md`; that recording is a prudent response to the prior 2.1 information request, while exact-build accuracy follows Apple's 2.1/2.3 requirements.

**Confidence:** Confirmed for Apple's metadata/build association; strong for the project evidence prescription.

## Synthesis

The subtitle correction is saved and verified: the sole configured localization reads `Paper texture and warm tint` after reload. Denim is implemented and has focused build 19 evidence; the release handoff now records that progress. The owner froze this implementation for Build 20. Ribbon has substantial focused validation, but the same-app activation flash remains a demonstrated user-visible failure and fourteen external-cover trials did not correct it. Apple has not approved this candidate.

Preparation can proceed without submission: build the final archive from the chosen revision, inspect it, update all metadata and media to that exact build, run the full Store qualification, and assemble the review package. With further activation work deferred, the owner still needs a launch-scope decision before submission if per-window behavior remains exposed. That decision must be reflected consistently across code and every Store surface; simply omitting the known failure from review notes would conflict with the completeness and metadata rules.

## Recommendations

1. **Finish the metadata check.** The subtitle correction is saved and verified in English (U.S.), the sole configured localization. Recheck any newly added localizations, name, keywords, category, privacy URL, support URL, age-rating responses, price/availability, and release setting before submission.
2. **Choose one exact release candidate and freeze its identity.** Increment the build from 19 if any source, resource, metadata-bearing bundle content, or signing input changes. Record commit, version/build, Xcode/SDK, archive identifier, signed binary hash, and App Store Connect upload/selection state.
3. **Resolve submission scope before calling the candidate ready.** Because the owner deferred more flash work, retain the activation evidence as an open gap. Submit only after the owner explicitly accepts a scope whose binary and metadata are mutually accurate. No current evidence qualifies the existing per-window activation path as visually continuous.
4. **Run release qualification on the final signed Store build.** Run the complete Store audit and required focused Denim/Ribbon cases, including same-app click and cycling, minimize/restore, 1x/2x displays, current macOS, performance, screenshot picker, preference restore, entitlements, signatures, privacy manifest/report, and quarantine-attribute scan. Preserve raw results with the exact build identity.
5. **Replace build 6 evidence.** Capture the required Store screenshots and the App Review demonstration from the exact uploaded/TestFlight-installed candidate. Include Denim and current labels, inspect the encoded video, and confirm overlays are visible during capture.
6. **Make review notes specific.** Identify the exact build; explain menu-bar launch and how to reveal the subtle overlay; name Denim and the Ribbon behavior actually present; state that no account or permissions are required; provide the privacy-policy path; and give reproducible steps for every advertised feature.
7. **Perform a final App Store Connect read-back.** Verify the selected build, all localizations, screenshot order, privacy response, review attachments, Notes for Review, contact data, and manual release after saving. Stop before submission until the owner authorizes it.

## Decision Points

- [ ] **Submission scope:** retain per-window mode with the known activation flash, qualify a corrected implementation later, or authorize a separately specified scope change. The current evidence supports continued preparation but not an unqualified “ready to submit” claim.
- [ ] **Owner visual acceptance:** accept or reject the exact final Denim/Ribbon Store build after reviewing the recorded same-app activation behavior and the replacement Store media.

## Verified Status and Open Gaps

| Item | Status | Evidence needed next |
|---|---|---|
| Corrected subtitle | Saved and read back after reload in the sole configured localization | Recheck if localizations change before submission |
| Denim bundled in build 19 | Verified | Final signed Store-build identity and full audit |
| Ribbon focused behavior | Verified for recorded focused cases | Final Store build, current-OS full audit, owner acceptance |
| Same-app activation continuity | **Failed / open** | A qualifying correction or explicit owner scope decision; fourteen external-cover trials failed |
| Sandbox-only source configuration | Verified | Entitlements extracted from final archive |
| Public-API design | Strong | Final linked-framework/symbol review and current-OS execution |
| Data Not Collected consistency | Strong | Final archive privacy report, network/static scan, live policy and App Store Connect read-back |
| Privacy policy URL | Verified in source | Live-page content and in-app link from final build |
| Required-reason API declaration | Verified in source | Embedded manifest and final archive scan/report |
| Current toolchain compliance | Partially verified | Exact Xcode/SDK receipt from final archive; current Apple upload warning review |
| Screenshots and review recording | Stale for next build | Replacement exact-build assets showing current labels and Denim |
| App Review acceptance | Unknown | Apple review after an owner-authorized submission |

## Open Questions

- The September 30 rejection and saved subtitle were inspected in App Store Connect. Selected build, App Privacy response, complete age-rating answers, support URL, release mode and uploaded screenshots still need final pre-submission read-back.
- No final Store archive newer than the local build 19 candidate was inspected, and no complete final Store audit was found for the combined Denim/Ribbon revision.
- The exact current Xcode and macOS SDK intended for the archive are not recorded. Apple's current pages do not impose the Xcode 26 SDK rule on macOS apps, but the final upload can still produce build-specific warnings that must be reviewed.
- Apple alone determines acceptance. Repository checks, TestFlight processing, and owner acceptance cannot be represented as App Review approval.
