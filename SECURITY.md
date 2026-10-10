# Security policy

## Reporting a vulnerability

Email support@parchmatte.com, or use GitHub's private vulnerability reporting on this repository ("Report a vulnerability" under the Security tab). Please do not open a public issue for a security problem until it is fixed.

You will get a reply within a week. Fixes ship as a new App Store build and a tagged release here; the report is credited in the release notes if you want it to be.

## Supported versions

The current Mac App Store release and the matching tag on `main`. Older builds are not patched; update instead.

## What the app does and does not do

Parchmatte is a sandboxed Mac app that draws paper-texture windows over the screen. It reads public window geometry only, registers fixed hotkeys, collects no data, makes no network requests, and asks for no permissions. The full control list, with the audit findings behind it, is in [docs/SECURITY_PLAN.md](docs/SECURITY_PLAN.md) and [docs/audit/security-findings.md](docs/audit/security-findings.md).
