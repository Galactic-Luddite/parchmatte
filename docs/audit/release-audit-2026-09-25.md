# Historical release audit — September 25, 2026

This is a historical static review of the macOS app and website. It did not
compile or run the app, inspect a live desktop, or measure performance. Findings
refer to the September 25 snapshot and must not be read as the current release
status. See [test-results.md](test-results.md) for later test results and
the private release handoff log for the current release handoff.

Parchmatte is a macOS 13+ menu-bar utility; there was no iOS target in this audit.

## Findings retained from the audit

| ID | Severity | Finding at the time |
| --- | --- | --- |
| R1 | Blocker | Source and store download availability needed verification before launch. |
| R2 | High | Privacy documentation omitted the owning application's name from its list of window fields, although the code read `kCGWindowOwnerName` for system-overview detection. |
| R3 | High | Several cited evidence commits could not be resolved; audit evidence needed stable, verifiable references. |
| R4 | Medium | Repository author/contact metadata and the associated hygiene finding needed review before sharing. |
| R5 | Medium | Pure logic lacked a fast unit-test tier; the existing GUI harness required a logged-in desktop and manual setup. |
| R6 | Medium | App and website changes lacked automated pull-request validation. |
| R7 | Low | Schedule evaluation repeatedly read `zone.tab`, including when the schedule was Always. |
| R8 | Low | The softened-texture cache cleared all entries at its limit, potentially causing repeated rendering during slider changes. |
| R9 | Low | The public-API compliance table omitted `CGWindowListCreate` and `CGWindowListCreateDescriptionFromArray`. |
| R10 | Low | Menu sliders lacked accessibility labels. |
| R11 | Low | Launch at Login failures were logged without an explanation visible to the user. |
| R12 | Low | Free/store build identifiers, screenshot lists, self-build instructions and schedule-function references disagreed across documents. |
| R13 | Medium | Visible texture and tint names needed differentiation before store submission. |
| W1 | Medium | Website canonical URLs, structured data, sitemap and related discovery metadata were incomplete. |
| W2 | Low | Screenshot and background-image transfer sizes warranted optimization. |
| W3 | Low | The static website could state its resource policy with a content-security-policy declaration. |

The original audit proposed fast tests for solar calculations, clamping, texture
cycling, opacity budgeting, schedule edges and system-overlay detection. It also
proposed build, syntax, entitlement/privacy and dependency checks in CI, while
retaining a local GUI harness for window behavior.

For performance, it recommended caching schedule coordinates by time zone,
returning early for Always, and evicting softened tiles individually rather than
clearing the whole cache. No runtime improvement was measured by this audit.

## Historical security checks

Static inspection at the time found sandbox-only entitlements, no app networking
or third-party dependencies, a combined opacity cap of 0.6, and no input event
taps or accessibility control in app sources. Test-only input automation was
separate from the app. Plists, entitlement files, JSON and shell scripts parsed.
These are historical observations; later code and permissions require their own
checks and must not inherit this audit's conclusion automatically.

The audit quoted existing CPU and memory results rather than measuring them.
Those historical numbers do not qualify a later build or resolve the activation
flash documented in subsequent trials.

## Follow-up recorded at the time

Later on September 25, source changes addressed privacy-field wording, a unit-test
target and schedule test seam, CI, schedule caching, texture-cache eviction,
public-API documentation, slider accessibility, Launch at Login feedback and
release-document inconsistencies. Website discovery metadata and its resource
policy were also updated. The audit did not compile or execute those changes;
subsequent Mac build and test results provide that evidence.

On September 27, the visible names Fine Grain, Woven, Imprint, Soft Leaf and Page
Light were approved for Build 6. Stored texture identifiers stayed stable.
Subsequent Build 21 work adds Denim; this historical audit does not certify that
build or its current website media.

Launch availability, image transfer sizes and any remaining functional defects
must be judged against the current release documents and live results.
