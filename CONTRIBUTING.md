# Contributing

Parchmatte is a one-person project. The source is here so you can build it
yourself, read what it does, and trust what is running over your screen. The
App Store version is the same app; the $2.99 is a tip that pays for the tools
it is built with.

Here is what helps and what to expect.

## Bug reports

The most useful thing you can do. Open an issue with:

- macOS version and Mac model (Intel or Apple silicon, notch or not)
- Parchmatte version (Parchmatte menu, About Parchmatte), and whether it is
  the App Store build or one you built from source
- what you did, what you expected, what happened
- a screenshot if the paper is in the wrong place, or a short screen
  recording if it flickers

I read every report and fix what I can. Some things, like the way macOS
treats overlays during Mission Control, are hard and may stay open for a
while. The issue list is a bug list, not a to-do list for other people.

## Pull requests

Welcome, never expected. If you want to send one:

- open or find an issue first for anything bigger than a typo, so we agree
  on the shape before you spend time on it
- keep it to one change
- run `scripts/build.sh` and the tests in `Tests/`; the harness scripts
  under `Tests/Harness/` are how behavior gets measured here, and a PR that
  changes cover behavior should say what it measured
- a PR body that says what happens, the cause, the fix and what you
  measured makes review quick; the existing PRs are a fine template

Anything substantial that lands is credited in the release notes. By sending
a change you agree it is released under the MIT license like the rest of the
project, which also means it ships in the App Store build.

## What stays the same

- The source build and the App Store build are the same app. No features
  are held back for the paid one.
- The license stays MIT.
- The App Store price stays a tip, not a subscription.

## Support

Something not working and you are not sure it is a bug? Email
support@parchmatte.com. One person reads it, so give it a day or two.
