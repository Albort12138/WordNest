# Release validation plan

Record results for the exact build and artifact being tested. Compilation and fixtures are valuable checks; they do not substitute for macOS consent, real video playback, Notes behavior, or downloaded installation.

## Five-step manual release gate

1. **Install and establish trust.** On a clean user profile or test Mac, download the intended GitHub artifact, check its published checksum, open the DMG, move WordNest to Applications and eject the DMG. Launch without disabling Gatekeeper. Verify the artifact's version and declared distribution mode. For public unnotarized builds, confirm the ad-hoc signature, absent notarization, explicit warnings and documented app-specific Open Anyway route when offered. Do not bypass malware/damage alerts or unavailable exceptions. For signed builds, require Developer ID, notarization and normal Gatekeeper acceptance. A dirty local preview is not a public candidate.
2. **Complete and recover setup.** Begin with permissions absent. Check System default on the first page and switch between Simplified Chinese and English without restarting. Confirm that OCR language and notebook selection stay unchanged. Check that welcome explains local processing and optional integrations. Close midway, reopen, and confirm the same unfinished step and language. Repeat after an earlier deferred introduction, including macOS Quit & Reopen during screen authorization. If the OS does not relaunch, manually open the same copy and verify recovery. Decline screen access: setup must allow an honest deferred finish, and lookup must explain the limitation. Grant access through macOS, return or restart as requested, and confirm actual lookup. Optional Accessibility, Safari and Notes consent must follow explicit actions, never installation or passive checks.
3. **Use the lookup card.** Test ordinary webpage text and paused/playing video subtitles. Verify pointer hit, original OCR line, definition, explicit pronunciation, correction, missing dictionary entries, long content, copy and close. Confirm the default action does not autoplay or save. Repeat Bilibili player fullscreen and native macOS fullscreen separately; record unsupported modes rather than generalizing success.
4. **Save and review an isolated notebook.** Explicitly select a dedicated test Notes folder. Save a new word, deliberately collect it again in another context, then refresh/read back. Verify one row, expected count and both contexts. Retry an identical event without increasing the count. Check source title/link retention, manual fallback, filtering and export. Use a physical save folder and optionally a smart browsing view; never test failure writes against a real vocabulary notebook.
5. **Reopen, deny and upgrade.** Restart normally without repeating completed onboarding. Test a second launch, unavailable/deleted destination, revoked permissions and source-read failure. Check that failed or uncertain writes never report success or blindly add another occurrence. Install an upgrade with the intended distribution mode and repeat permission and notebook checks. Ad-hoc signatures may change and require renewed grants; do not promise permission inheritance. Verify uninstall instructions and remaining Notes data are accurate.

## Scenario matrix

| Dimension | Cases to record |
| --- | --- |
| Screen content | Light/dark backgrounds, bilingual subtitles, small text, burned-in and selectable text, empty regions |
| Timing | Paused, stable playback, subtitle transition, rapid repeated shortcut |
| Window mode | Windowed, webpage/player fullscreen, native macOS fullscreen |
| Display | Built-in, external if available, scaling, negative-coordinate arrangements |
| Language | Automatic and explicit language selection, short/mixed text, unavailable dictionary/voice |
| Source | Ordinary Safari, Safari Dock web app, manual link, absent metadata, changed page |
| Storage | Physical folder, smart browsing view, account unavailable, external edits, pending result |
| Privacy | No unsolicited prompts, no automatic capture storage/upload, explicit export location |

## Automated checks

Use the current [contributor workflow](../CONTRIBUTING.md) and build scripts. Logic and fixture tests must not depend on personal Notes content or permission grants. UI fixtures should use injected state to cover granted, denied and unavailable capabilities. Write-capable integration modes belong only in development builds and require an explicitly isolated target.

Check shell syntax and source policy, run regressions, compile the app and run fixed-data UI checks. Report each check as passed, failed or not run. Explicit unsigned packaging must not use Apple credentials and must label the archives and metadata as unnotarized. Signed packaging must still fail when signing/notarization credentials are absent, without an unsigned fallback. Public packaging requires a clean committed tree; dirty previews remain local.

## Evidence record

Record version/build, artifact type, signing mode, macOS version, architecture, source application, display/mode and reproduction steps. Preserve failures and distinguish OCR, pointer selection, subtitle timing, source attribution, dictionary, permissions and Notes errors.

Private logs may contain source links, collection content or account names. Review and redact before sharing. Use neutral test fixtures in public issues; never publish a personal notebook export. Accuracy and latency claims require a defined sample set and measurement procedure, not isolated positive feedback.

Release status is maintained in [development-status.md](development-status.md). This plan is not a statement that its scenarios have passed.

## Imported local dictionaries

In an isolated library, import an authorized MDX 2.x file, verify its title and text against a known entry, switch sources in the card, then restart and verify selection. Test a missing word, missing managed file, unsupported compression/version, and damaged record. Verify the original MDX is untouched and removal preserves saved vocabulary. Capture a real subtitle, switch sources without losing its original line/URL, deliberately collect once, and read back the Notes row/count. Automated fixtures do not certify every third-party dictionary or replace that end-to-end acceptance.
