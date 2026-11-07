# Releasing WordNest

This document describes the maintainers' distribution process. A build script or workflow being present does not mean a signed release has already been produced or published. Publishing a release is a separate maintainer action.

## Product metadata and build modes

`config/product.env` is the shared source for the product version, build number, public bundle identifier, minimum macOS version and architecture. The current candidate is v26.1.0 build 1. Preview and release builds use `io.github.albort12138.wordnest`; default development builds use `io.github.albort12138.wordnest.development` to keep Launch Services and TCC identities separate. The executable remains `SubtitleLookup`. Current packages target Apple Silicon (`arm64`), not Intel. The first signed public release is still pending; these instructions do not establish a published download.

```sh
# Local development, including explicitly gated test/preview commands.
bash scripts/build.sh --development

# Production code paths, but ad-hoc signed and not notarized.
bash scripts/build.sh --preview

# Signed production code paths; certificate must already be installed.
SUBTITLE_LOOKUP_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  bash scripts/build.sh --release
```

Default app output is `work/build/WordNest.app`. `SUBTITLE_LOOKUP_APP_DIR` and `SUBTITLE_LOOKUP_BUILD_DIR` remain supported; app output must be named `WordNest.app` inside this checkout's `work/` directory. The builder refuses to overwrite existing apps that lack its managed-build marker and the identity expected for the selected mode. Use separate app output paths when changing between development and preview/release identities. Existing authorized prototype packages are preserved. To retain a new build, choose another output path before the next build.

Development builds define `WORDNEST_DEVELOPMENT`. Preview and release builds do not include development-only entry points. Only release mode requires Developer ID, enables hardened runtime, adds a secure timestamp and applies `config/WordNest.entitlements` for Apple Events. User permissions are still required; entitlements do not grant TCC access.

Do not loosen signature requirements, disable Gatekeeper, rewrite TCC databases or create permissive code requirements to avoid setup. Development signatures can change after each build; use the setup flow to review the current installed build's permissions.

## Version policy

Product versions use `YY.feature.fix`, with `26.1.0` as the first public baseline. The year is the actual release year. Increase the feature number for new capabilities or substantial interaction changes and reset the fix number to zero; increase the fix number for corrections and small refinements. For a mixed release, use the feature increment. The first release in a new year starts at `YY.1.0`; a calendar change alone does not require a release. Numbers are not zero-padded.

`WORDNEST_VERSION` becomes `CFBundleShortVersionString`. `WORDNEST_BUILD_NUMBER` becomes `CFBundleVersion`. Public build numbering starts at `1` for `26.1.0`; this is a one-time transition from private `0.x` previews, not an annual reset. The initial unpublished candidate remains `26.1.0` build `1` while its first-release scope is being finalized. After the first public release, every later distributed build increments that number, including rebuilds of the same product version. Do not reset it when the feature, fix or year changes. This is a calendar-based product policy, not a semantic-versioning API compatibility contract.

Use `v26.1.0` for the first public Git tag and `WordNest-26.1.0-build1-macos-arm64` as the package basename. Installers, ZIP archives, source snapshots, checksums and release descriptions must identify the same product version and build. A candidate label or assigned version never means the release has already been published.

## Local validation

```sh
for script in scripts/*.sh; do bash -n "$script"; done
bash scripts/check-source-policy.sh
bash scripts/test.sh
bash scripts/build.sh --development
work/build/WordNest.app/Contents/MacOS/SubtitleLookup --ui-self-test
```

These checks do not establish real fullscreen compatibility, correct source capture in every app, or successful Notes writes. Dictionary and speech system checks are optional local checks using the documented test flags. Notes integration tests require an explicitly selected isolated test destination, not a personal vocabulary notebook. Never grant unattended CI access to personal Notes or captured screens.

The CI workflow uses the standard `macos-15` GitHub-hosted arm64 runner label and verifies `uname -m`. GitHub currently lists `macos-15` and `macos-26` as arm64; `macos-15-arm64` is not the standard workflow label. See [GitHub's runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) and [official runner images](https://github.com/actions/runner-images).

## Local packaging preview

```sh
bash scripts/release.sh --unsigned-preview
```

This builds production code paths using an ad-hoc signature and creates a DMG, ZIP, SHA-256 checksums and build metadata in `work/releases/`. Filenames include `unsigned-preview`, and the payload contains an explicit warning. It is a local packaging check, not an official signed distribution. It may be rejected by normal Gatekeeper policy. Do not disable system protections to make the preview installable.

The DMG contains `WordNest.app`, an Applications shortcut, `LICENSE`, `NOTICE`, `PRIVACY.md`, `THIRD-PARTY-NOTICES.md` and `WordNest-artwork-LICENSE.txt`. The code is MIT-licensed; the bundled owl artwork has separately reserved rights. The MIT license, artwork license, third-party attributions, copyright notice and privacy document also remain inside the app's Resources folder after installation. Modified distributors must replace the artwork with authorized assets or obtain written permission under `Assets/Branding/LICENSE`. The ZIP contains the same app and documentation. Existing output filenames are never overwritten. To rerun packaging, select a new `WORDNEST_RELEASE_DIR` inside `work/`, or deliberately archive/remove only the previous generated outputs.

## Reviewable source export

```sh
bash scripts/export-source.sh --check-only
bash scripts/export-source.sh
```

The explicit `config/source-files.txt` manifest lists reviewed public inputs. Update it deliberately when adding public files. The exporter rejects unexpected files under public source directories, missing inputs, symlinks and existing outputs. It creates a source archive, a per-file SHA-256 manifest and archive checksums in `work/source-distribution/`. It excludes the Git index/history, compiled apps and private development history; exporting does not commit, push or publish anything. Review that snapshot before the first public repository import.

Preview build metadata records `source_state` (clean, dirty, or exported), `source_revision`, and a SHA-256 digest of the exact public-source manifest contents. The script rejects source changes during packaging. Official release packaging additionally requires a clean committed checkout, so an old Git revision cannot be presented as the source of uncommitted changes. The GitHub workflows pin checkout to a reviewed commit; update the pin deliberately when upgrading it.

## Signed and notarized packaging

Before running production packaging, the maintainer needs an Apple Developer Program account, a valid **Developer ID Application** certificate and its private key, and Apple notarization credentials. The build refuses to fall back to ad-hoc signing if these are missing. Apple describes the requirements in [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Store notarization credentials in Keychain using `xcrun notarytool store-credentials`; follow its interactive prompts rather than writing passwords into a repository or shell history. Then run:

```sh
SUBTITLE_LOOKUP_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
WORDNEST_NOTARY_PROFILE='YourNotaryProfile' \
  bash scripts/release.sh
```

The script:

1. Builds a Developer ID-signed app with hardened runtime and a timestamp.
2. Submits an app ZIP to Apple; requires an `Accepted` result.
3. Staples and validates the app ticket, verifies code integrity and runs Gatekeeper assessment.
4. Creates the final ZIP and DMG from that app, with the license and privacy notice.
5. Signs, notarizes and staples the DMG; requires Gatekeeper acceptance.
6. Writes final SHA-256 checksums after stapling and records version, build, architecture, mode and source revision.

The release script never uploads to GitHub. If any stage fails, it stops without moving final artifacts to the release directory. Apple notarization itself is a network operation performed by the maintainer; it is not part of WordNest's runtime vocabulary workflow. Signing/notarization and packaging are a repeatable process, not a claim of bit-for-bit reproducible signed binaries.

## Manual GitHub draft workflow

`.github/workflows/release.yml` runs only through `workflow_dispatch` on this repository's `main` branch. It requires an existing `vYY.FEATURE.FIX` tag whose version matches `config/product.env`; it creates a **draft**, never an automatically published release. There is no unsigned public fallback. A maintainer must separately authorize repository publication, tagging and workflow execution.

Configure the `release` GitHub environment, restrict it to trusted maintainers, and add these secrets:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Base64-encoded certificate and private-key export |
| `DEVELOPER_ID_P12_PASSWORD` | Password protecting that export |
| `DEVELOPER_ID_APPLICATION` | Exact `Developer ID Application: ...` signing identity |
| `APPLE_ID` | Apple account used for notarization |
| `APPLE_TEAM_ID` | Developer team identifier |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |

All must be configured. Before executing repository scripts, the workflow verifies that the tagged commit belongs to both `origin/main` and the trusted main revision that dispatched it. Signing secrets are scoped to the steps that need them. The workflow imports signing material into an ephemeral runner keychain, stores a temporary notarization profile, builds/verifies packages, attaches them to a draft release, and deletes the temporary signing files and keychain. It does not run on pull requests and does not execute a contributor's branch with release secrets. Review the tagged code before dispatching; release credentials must never be placed in source files or logs.

## Before publishing the draft

Download the DMG through a browser on a clean test Mac, so the actual quarantine/Gatekeeper path is tested. Verify checksums, open the image, drag to Applications, launch the app, and complete first-run setup. Test denied and granted permissions, relaunch, normal/video fullscreen lookup, source/title capture, dictionary/voice availability, and Notes collection/readback/count preservation in a dedicated test notebook.

Validate first-launch language selection before requesting any permission: System default, 简体中文, and English must be expanded on the first page, with System default selected and its resolved language shown. Switching must update the whole page before continuing to permission setup. Check the explicit choice survives permission-related termination and reopening. If macOS Quit & Reopen only closes the app, manually reopening the same copy must resume the saved setup step, including when an earlier introduction had already been marked complete. Do not advertise guaranteed automatic relaunch. Exercise menus, cards, notebook settings, browsing, and recovery messages in both interface languages. Check that changing interface language leaves dictionary/user data and persisted Notes schemas unchanged; unknown system diagnostics may retain OS language. Keep bilingual UI checks and real permission/restart acceptance evidence distinct; neither is implied by a passing core suite.

Also verify upgrade behavior from the previous supported release without changing its bundle identity, migration behavior from prototypes where applicable, privacy/license links, English and Chinese README links, correct architecture/minimum OS labels, and the published artifact names. A successful build is not a substitute for this acceptance pass. Document untested systems and source applications honestly in release notes.

Only publish after those checks and the maintainer's review. Contact: [Albort](mailto:albort.yao.xue@gmail.com).
