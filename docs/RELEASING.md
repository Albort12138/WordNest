# Releasing WordNest

WordNest is free and open source. The selected first-release route is **explicitly unnotarized distribution**, requiring no paid Apple developer membership or Apple signing secrets. Developer ID signing and notarization remain optional. A packaging script, candidate version or draft is not a published download.

## Product identity and build modes

`config/product.env` defines version **26.1.0**, build **1**, Apple Silicon (`arm64`), minimum macOS **14.0** and bundle identifier `io.github.albort12138.wordnest`. Default development builds append `.development` to isolate fixture launches from the installed app. The executable remains `SubtitleLookup`.

```sh
# Local development: separate identity and gated fixture entry points.
bash scripts/build.sh --development

# Production app code paths, ad-hoc signed, without development entry points.
bash scripts/build.sh --preview
```

The public unnotarized package uses preview build mode internally: this selects production app code paths, not development-only commands. Its package metadata independently records `package_mode=unsigned`, `signing=ad-hoc`, and `notarized=no`. An ad-hoc signature checks local code integrity; it does not verify publisher identity or provide Apple malware review.

The builder writes `work/build/WordNest.app` by default and refuses to replace unmanaged apps. Build and app paths can be changed with `SUBTITLE_LOOKUP_BUILD_DIR` and `SUBTITLE_LOOKUP_APP_DIR`; app output must be named `WordNest.app` under this checkout's `work/`. Preserve existing authorized installations. User consent is always required for TCC permissions, regardless of packaging mode. Ad-hoc updates may require renewed grants.

## Version policy

Product versions use `YY.feature.fix`, with `26.1.0` as the first public baseline. The year is the actual release year. Increase the feature number for new capabilities or substantial interaction changes and reset the fix number to zero; increase the fix number for corrections and small refinements. For a mixed release, use the feature increment. The first release in a new year starts at `YY.1.0`; a calendar change alone does not require a release. Numbers are not zero-padded.

`WORDNEST_VERSION` becomes `CFBundleShortVersionString`. `WORDNEST_BUILD_NUMBER` becomes `CFBundleVersion`. Public build numbering starts at `1` for `26.1.0`; this is a one-time transition from private `0.x` previews, not an annual reset. The initial unpublished candidate remains `26.1.0` build `1` while its first-release scope is being finalized. After the first public release, every later distributed build increments that number, including rebuilds of the same product version. Do not reset it when the feature, fix or year changes. This is a calendar-based product policy, not a semantic-versioning API compatibility contract.

Use `v26.1.0` for the first public Git tag and `WordNest-26.1.0-build1-macos-arm64` as the package basename. Installers, ZIP archives, source snapshots, checksums and release descriptions must identify the same product version and build. A candidate label or assigned version never means the release has already been published.

## Local validation

```sh
for script in scripts/*.sh; do bash -n "$script"; done
bash scripts/check-source-policy.sh
bash scripts/export-source.sh --check-only
python3 Tests/ReleasePackagingTests.py
bash scripts/test.sh
bash scripts/build.sh --development
work/build/WordNest.app/Contents/MacOS/SubtitleLookup --ui-self-test
```

Core/UI fixtures do not establish real fullscreen behavior, permission approval, Notes writes or downloaded installation. Packaging tests use isolated fixture tools, never personal certificates or Notes. The actual packaging pass separately builds a real arm64 binary and verifies its signature, DMG and checksums. CI uses GitHub's `macos-15` arm64 runner and verifies `uname -m`.

## Public unnotarized packaging

Commit the reviewed source first; public packages require a clean committed checkout. Then run:

```sh
bash scripts/release.sh --unsigned
```

No Apple account, signing certificate, notarization profile or paid membership is used. This mode forces an ad-hoc signature even if signing variables are set. Outputs under `work/releases/` are:

- `WordNest-26.1.0-build1-macos-arm64-unnotarized.dmg`
- The matching `.zip`, `-SHA256SUMS.txt`, and `-build-info.txt`

Both archives contain the same app, Applications shortcut, `UNNOTARIZED.txt`, English and Chinese installation guides, `LICENSE`, `NOTICE`, `PRIVACY.md`, `THIRD-PARTY-NOTICES.md` and `WordNest-artwork-LICENSE.txt`. The app itself retains code, artwork and privacy notices in Resources after it is dragged out of the DMG. Code is MIT; owl artwork has separately reserved rights under `Assets/Branding/LICENSE`.

The app may be blocked by Gatekeeper on first launch. Link [INSTALL.md](INSTALL.md) and [INSTALL.zh-CN.md](INSTALL.zh-CN.md) prominently. Explain Apple's app-specific Open Anyway option only for a trusted download when offered. Never disable Gatekeeper/SIP, remove quarantine attributes or treat malware/damage warnings as ordinary unidentified-developer prompts. Clean-machine acceptance remains required and may reveal unsupported environments. A checksum does not authenticate the publisher or replace Apple review.

Existing output files are never overwritten. Use a new `WORDNEST_RELEASE_DIR` under `work/` for another candidate. Metadata records the exact public-source digest, commit and state; changes during packaging prevent final output.

## Local packaging preview

```sh
bash scripts/release.sh --unsigned-preview
```

This allows uncommitted source for local packaging checks. Filenames contain `-unsigned-preview`, metadata reports the source state honestly, and `UNSIGNED-PREVIEW.txt` marks it as a local test. Do not upload a dirty preview as the public candidate. No package command uploads to GitHub.

## Source export

```sh
bash scripts/export-source.sh --check-only
bash scripts/export-source.sh
```

The explicit `config/source-files.txt` manifest lists reviewed inputs. The exporter rejects missing/unreviewed files, symlinks and existing outputs. Source archives and checksums go to `work/source-distribution/`; Git history, local builds, personal captures and the private code guide are excluded. An export does not publish anything.

## Optional signed and notarized packaging

This route requires paid Apple Developer Program membership, a Developer ID Application identity with its local private key, and notarization credentials. These are not requirements of the chosen unnotarized route. Store credentials interactively with `xcrun notarytool store-credentials`, not in source or shell history.

```sh
SUBTITLE_LOOKUP_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
WORDNEST_NOTARY_PROFILE='YourNotaryProfile' \
  bash scripts/release.sh --signed
```

For compatibility, invoking `release.sh` without a mode still selects the signed route and fails if credentials are absent. It never silently downgrades to unsigned. Only explicit `--unsigned` or `--unsigned-preview` selects ad-hoc packaging.

Signed mode enables hardened runtime, secure timestamps and `config/WordNest.entitlements`; it requires Apple Accepted results for app and DMG, staples and validates tickets, verifies code integrity, and runs Gatekeeper assessments. Checksums are written after stapling. Signing/notarization is a maintainer network operation, not part of WordNest's local runtime workflow. See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Manual GitHub draft workflow

`.github/workflows/release.yml` runs only through `workflow_dispatch` on this repository's `main` branch. It needs an existing `vYY.FEATURE.FIX` tag matching product metadata and reviewed main history. The `distribution` input defaults to **unsigned**. Configure a `release` GitHub environment with appropriate maintainer access; unsigned mode needs **no secrets** and skips certificate import, notarization and signing-keychain cleanup. It creates a **draft** with explicit bilingual unnotarized warnings and clearly named assets, never an automatically published release.

The optional **signed** input uses these secrets only in the relevant steps:

| Secret | Purpose |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Encoded certificate and private-key export |
| `DEVELOPER_ID_P12_PASSWORD` | Password protecting that export |
| `DEVELOPER_ID_APPLICATION` | Exact Developer ID Application identity |
| `APPLE_ID` | Notarization account |
| `APPLE_TEAM_ID` | Developer team identifier |
| `APPLE_APP_PASSWORD` | App-specific notarization password |

Signed mode requires every secret, imports into an ephemeral runner keychain and removes signing material afterward. Neither mode runs on pull requests or arbitrary contributor branches. Publication, tagging and workflow execution remain separate maintainer actions.

## Before publishing the draft

Download the DMG through a browser on a clean test Mac, so the actual quarantine/Gatekeeper path is tested. For unnotarized builds, record the initial block and any app-specific Open Anyway flow; record malware/damage warnings or unavailable exceptions as failures instead of bypassing them. For signed builds, additionally verify notarization and normal Gatekeeper acceptance. Verify checksums, open the image, drag to Applications, launch the app, and complete first-run setup. Test denied and granted permissions, relaunch, normal/video fullscreen lookup, source/title capture, dictionary/voice availability, and Notes collection/readback/count preservation in a dedicated test notebook.

Validate first-launch language selection before requesting any permission: System default, 简体中文, and English must be expanded on the first page, with System default selected and its resolved language shown. Switching must update the whole page before continuing to permission setup. Check the explicit choice survives permission-related termination and reopening. If macOS Quit & Reopen only closes the app, manually reopening the same copy must resume the saved setup step, including when an earlier introduction had already been marked complete. Do not advertise guaranteed automatic relaunch. Exercise menus, cards, notebook settings, browsing, and recovery messages in both interface languages. Check that changing interface language leaves dictionary/user data and persisted Notes schemas unchanged; unknown system diagnostics may retain OS language. Keep bilingual UI checks and real permission/restart acceptance evidence distinct; neither is implied by a passing core suite.

Also verify upgrade behavior from the previous supported release without changing its bundle identity, migration behavior from prototypes where applicable, privacy/license links, English and Chinese README links, correct architecture/minimum OS labels, and the published artifact names. A successful build is not a substitute for this acceptance pass. Document untested systems and source applications honestly in release notes.

Only publish after those checks and the maintainer's review. Contact: [Albort](mailto:albort.yao.xue@gmail.com).
