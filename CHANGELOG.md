# Changelog

This log describes source changes, not a guarantee that a signed binary has been published. See [GitHub Releases](https://github.com/Albort12138/wordnest/releases) for actual downloadable artifacts and their release notes.

## 26.1.0 (1) — First public release candidate

- Support explicitly unnotarized public DMG/ZIP packages without paid Apple developer membership or Apple signing secrets; include English/Chinese installation guides, warning labels, checksums and distribution metadata. Keep signed/notarized packaging as an explicit optional route. Updates using ad-hoc signatures may require renewed privacy grants.

- Add selectable local dictionary providers and managed MDX 2.x import, with definitions inside the lookup card, persistent selection, explicit failures and no network service. Keep imported definitions intact when collecting into the existing Notes table.

- Release the initial candidate under the MIT License, with free use, modification and redistribution, including commercial use; remove separate paid authorization and contributor-agreement requirements.
- Make language selection the main task on the first setup page, with three expanded choices instead of a corner popup.
- Select System default initially, show the resolved language, and update the whole page immediately when the choice changes.
- Keep existing permission-step checkpoints and saved language preferences across setup recovery.

- Adopt year-based product versions: `YY.feature.fix`, starting with `26.1.0`.
- Start public build numbering at `1`; earlier `0.x` builds are private development history. Increment the build for every later distributed artifact, without resetting it for a new product version or year.
- Include the product version and build in installer and source archive filenames.
- Carry forward the local lookup, speech, single-row Notes vocabulary and source-history features validated in the private previews below.

This number identifies the first public release candidate. Unnotarized installation acceptance and GitHub publication remain separate release steps. Developer ID signing and notarization are optional future distribution steps.

## 0.8.0 — Private preview

First source baseline prepared for version control. Earlier entries describe development milestones; they do not indicate published releases.

### Productization

- Keep each word, summary and per-collection source history in one table row; read legacy layouts without resetting counts or duplicating event IDs (build 17).

- Use English throughout application, test, script and configuration source; move Chinese UI text, multilingual samples and stable legacy Notes identifiers into dedicated bundled resources (build 16).
- Keep both interface languages and the existing Notes serialization format while changing source text; check catalog parity and reject untranslated source literals.
- Offer System default, Simplified Chinese and English interface selection on the first setup page; preserve OCR language and stored Notes schemas independently.
- Restore interrupted permission setup even when an earlier introduction was deferred; checkpoint state before external permission/settings/restart actions.
- Isolate development app registrations and fix submenu ownership when changing interface language without restarting.
- Add first-launch guided setup with explicit macOS consent, optional integrations, deferred completion and resumable progress.
- Consolidate routine configuration and permission recovery into settings rather than separate authorization commands in the main menu.
- Introduce public product metadata, safer development output paths and separate development/distribution launch modes.
- Add DMG/ZIP packaging, checksums and a release workflow requiring Developer ID signing and notarization for official packages.
- Allow source-manifest checks after an archive already exists while continuing to reject archive overwrites.
- Provide English-default and Chinese READMEs, privacy/contributor/security guidance and MIT licensing.
- Standardize explanatory code comments in English and remove private development diaries from public docs.

### Release status

Fresh-machine installation, signed release publication and the new first-run experience remain release acceptance gates. The preview target is Apple Silicon/macOS 14+; earlier real-use evidence is limited to an M3/macOS 26 setup. Fullscreen support is not guaranteed across applications or modes.

## 0.7.1 — Development build

- Recover a usable page title when a Safari Dock web area's title is empty, including fallbacks to available metadata and window title.
- Show missing title state without repeating the URL.
- Preserve recovered titles through collection tables and analysis exports; do not silently backfill older records.

## 0.7.0 — Development build

- Record the original line and optional page URL/title for each deliberate collection event.
- Support ordinary Safari and compatible Safari Dock web-app source capture, with manual editing when metadata is unavailable.
- Browse vocabulary by source and export a local analysis snapshot.
- Preserve legacy collection counts with explicitly missing source history and maintain retry deduplication.
