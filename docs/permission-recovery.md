# Permissions and recovery

WordNest guides permission setup on first launch. Installation cannot approve macOS privacy prompts for you. Later, open **Settings…** from the menu-bar icon to review permissions or return to setup.

The first welcome page lets you choose System default, 简体中文 or English. This controls application UI, independently of the language of the text you recognize. Unsupported system-language preferences fall back to English. Your selection is saved before permission-related restarts; unknown system diagnostics can still use the OS language.

| Permission | Purpose | Required? |
| --- | --- | --- |
| Screen recording | Capture a frame when you invoke OCR lookup | Required for screen text lookup |
| Accessibility | Read foreground Safari Dock web-app page metadata | Optional; manual source links remain available |
| Safari automation | Read the current ordinary Safari page title/link | Optional |
| Notes automation | Read/write the vocabulary location you choose | Optional until Notes features are used |

WordNest does not request microphone access or keyboard input monitoring for its global shortcut. System permission labels may differ between macOS versions. Each protected integration remains subject to your approval in macOS.

## Before granting permission

If installing from a DMG, drag WordNest into Applications, eject the image, and run `/Applications/WordNest.app`. Grant access to the copy you intend to use. Avoid running multiple previews with the same name; an enabled entry may belong to a different build.

If you decline, the setup remains truthful about which functions are unavailable. You can finish the introduction and return later. Optional source/Notes permissions are requested only when you choose their corresponding setup action.

Default source builds have the development identity `io.github.albort12138.wordnest.development`; preview/release packages use `io.github.albort12138.wordnest`. Although both display WordNest, their system registrations are separate. Grant permissions to the intended copy rather than assuming a grant to a development build applies to a preview or release.

## An enabled switch but unavailable capability

1. Quit other WordNest instances and confirm the running version and location.
2. Return to WordNest settings and inspect the current capability status.
3. Open System Settings → Privacy & Security and the relevant permission category. Check the exact intended WordNest copy.
4. If a stale development entry is confirmed, remove only that WordNest entry, add the current app, and enable it yourself. Leave other applications untouched.
5. Follow macOS's restart instruction. If Quit & Reopen closes WordNest but does not launch it again, manually reopen the same copy. The app checkpoints the current step before permission requests, system-settings actions and restart actions; reopening resumes that unfinished step even if an earlier introduction was completed. Then verify the actual operation: lookup, source metadata, or explicitly selected Notes access.

Ad-hoc source builds can change code identity when rebuilt. A stable identifier alone does not guarantee authorization inheritance. The current public route is explicitly unnotarized and ad-hoc signed, so updates may require renewed permission grants. If Developer ID distribution is added later, keep its identity consistent and still test permission retention on upgrade. Do not reset TCC, disable Gatekeeper/SIP, or loosen signing requirements as a workaround.

## Read-only development diagnostics

The repository provides a local signature diagnostic:

```sh
SUBTITLE_LOOKUP_APP_DIR=/Applications/WordNest.app bash scripts/diagnose-permission.sh
```

Inspect the script's current usage before comparing two builds. Signature validity proves bundle integrity, not user consent, successful capture, or valid Notes access. Diagnostics should remain local unless reviewed for identifying paths and other sensitive details.

Relevant Apple guidance: [Accessibility access](https://support.apple.com/guide/mac-help/mh43185/mac), [code signing requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), and [Developer ID distribution](https://developer.apple.com/developer-id/).
