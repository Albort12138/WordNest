# Development status

Updated: 2026-11-08. Current product version: **26.1.0 public test release, build 1**. This document describes implementation and release readiness; it is not a release announcement.

## First public test release — 2026-11-08

[WordNest 26.1.0 build 1](https://github.com/Albort12138/WordNest/releases/tag/v26.1.0) is publicly available as a GitHub Pre-release. Tag `v26.1.0` points to `0be5b7cb31a31013ff31a5c32535b89d3143c2cd`; the published ad-hoc-signed, unnotarized DMG/ZIP have not been replaced by later documentation changes.

The release commit's [macOS 15 arm64 CI](https://github.com/Albort12138/WordNest/actions/runs/42431734176) passed 7 distribution-policy tests, 463 logic/fixture checks, compilation and 110 fixed-data UI checks. Real arm64 binary/signature integrity, DMG verification, matching DMG/ZIP contents, license/install payloads and final checksums passed locally. All four public assets were also downloaded without authentication and compared byte for byte with the verified local candidate.

On the existing M3 development Mac running macOS 26.6.2, an actual browser download retained quarantine, the installed app matched the candidate, and the user approved the app-specific Open Anyway prompt. Launch from Applications was observed. The user confirmed real shortcut lookup and dictionary output, then isolated Notes save/read-back with one row and deliberate collection count 1 → 2. These interactive outcomes are user-reported; the final lookup card and Notes table were not independently inspected by automation. Fresh-machine setup, other Macs and broader permission/restart/fullscreen configurations remain untested; this is a limited public test release.

## Unnotarized distribution policy

The maintainer selected free, explicitly unnotarized public distribution without paid Apple developer membership. Public package mode `--unsigned` forces ad-hoc signing, requires a clean committed source tree and includes bilingual installation guides, a warning file and `-unnotarized` artifact names. The manual GitHub draft workflow defaults to this mode without Apple secrets. Optional Developer ID signing/notarization still fails closed if explicitly selected without credentials. Public download and existing-Mac installation/core-workflow results are recorded above. Clean-machine Gatekeeper approval and broader permission/upgrade acceptance remain pending; packaging support does not establish those results.

## GitHub CI and local demonstration follow-up

On 2026-11-07, the macOS 15 arm64 [CI validation run](https://github.com/Albort12138/WordNest/actions/runs/42383300718) passed 463 logic/fixture checks, the development app build and 110 fixed-data UI checks. The localization test now reads semantic control titles, allowing the intentionally native Chinese language name without depending on AppKit's internal `NSButtonTextField` hierarchy. Five regression checks preserve rejection of genuinely untranslated labels and button titles. On the development Mac, 463 logic checks and 105 UI checks passed; counts differ with platform-specific checks.

A real local lookup recognized `happiness` and its original line from a self-authored pixel subtitle page. Pronunciation, one collection in an isolated Notes folder, WordNest read-back and the native single-row Notes table were verified. The example source was entered manually. The everyday destination was restored. See [capture notes](../Assets/Documentation/README.md) for the edited screenshot walkthrough and its limits. This does not establish clean-machine permission acceptance, Apple notarization or an official release.

## Implemented scope

- Pointer-directed lookup from visible subtitles and text, using a global shortcut and on-device OCR.
- Selectable system and imported MDX 2.x dictionary providers, persistent local library, in-card text definitions, explicit pronunciation playback, and correction of the recognized word.
- Vocabulary collection into selected Apple Notes folders, alphabet/script pages, repeated-collection counts, context history, and readback.
- Per-collection source metadata, Safari and Safari Dock web-app adapters, manual source editing, filtering, and local JSON export.
- Branded first-launch setup with the existing owl mascot, five progress steps, compact permission cards, adaptive appearance, optional integrations, resumable progress, and recovery through settings.
- Dedicated first-page language selection with three expanded choices: follow system preferences by default and show the resolved language, or choose Simplified Chinese or English. OCR language and stored vocabulary remain independent.
- Permission-handoff checkpoints and startup recovery of unfinished settings even after an earlier deferred completion. Development app identity is separate from the installed product.
- Free, MIT-licensed open-source distribution with matching source/app/package notices and no separate paid authorization or contributor agreement.
- English and Chinese public documentation, English code comments, source policy checks, and release packaging infrastructure.
- English-only application/test/script/configuration source, with English interface keys, bilingual text catalogs, and separate multilingual sample and legacy Notes-format resources.

## Evidence boundaries

Earlier development builds were exercised on an M3 Mac running macOS 26, including a real Safari Dock web-app lookup and isolated native Notes table read/write checks. Synthetic OCR, parsing, write-state, source grouping and UI fixtures were also exercised. These observations support the core workflow on that development setup; they do not establish a universal accuracy rate or compatibility guarantee.

The productization changes introduce a new product identity and first-run flow. Earlier successful checks do not certify the new installer, permission migration, signing identity, or clean-machine experience.

## Current candidate validation

The final pre-publication review reran the source-export workflow from a clean tree outside the development checkout: **487 regression checks** and **105 fixed-data AppKit checks** passed. Notes HTML now explicitly disables external entities, matching MDX text rendering; self-authored temporary-file probes cover both paths without accessing user data. Source scripts work when invoked from another directory. Official packaging rejects dirty or uncommitted source, preview metadata labels source state and content digest, and a source change during packaging prevents outputs. Workflow YAML and local documentation links were checked; checkout is pinned to a specific v6.0.2 commit. These are local checks, not a claim that GitHub Actions or Apple notarization has run.


The local-dictionary update passed **485 regression checks** (including real local system-dictionary and speech checks, synthetic OCR and independent-writer MDX fixtures) and **105 fixed-data AppKit checks**. MDX fixtures cover UTF-8, UTF-16LE, GBK and Big5 text; raw/zlib blocks; standard encrypted key indexes; linked/cyclic entries; corruption, truncation and header limits; import rollback; persisted selection; missing managed files; removal; and unchanged Notes table text/count behavior. Native interaction in an isolated preview confirmed file-chooser import of an encrypted-index fixture, its definition and dictionary name inside the card, and retention of the original context and source URL. No user screen was captured and no personal Notes were read or written for these checks. Actual user-supplied dictionaries and a fresh end-to-end subtitle-to-Notes acceptance remain separate validation.

The provider seam uses pure Swift plus macOS zlib, without Python/Node or a hosted service at runtime. Eudic's installed application is not queried for definitions; users explicitly import authorized MDX files. Unsupported versions, LZO and password protection are reported. Images/audio/custom HTML layouts are excluded. See README for size limits and `THIRD-PARTY-NOTICES.md` for compatible MIT references.

Earlier candidate evidence follows for provenance:

During the earlier candidate stage, the product remained unreleased at `26.1.0` build `1`. The language-selection refinement is included in this initial candidate; it does not create a separate release. Before local MDX support, the regression suite passed **387 checks**, including three expanded language choices, a visible resolved system language, immediate bilingual switching, saved selection before simulated consent, five-step layout in both appearances and interrupted-setup restoration. These are generated-data and injected-permission checks, not a new real macOS consent run. A separate fixed-data AppKit run passed **87 checks** without a Notes connection. Interactive checks in an isolated setup preview confirmed a Chinese system default, immediate switching to English and back, and preserving the selection when navigating to the screen-permission page and returning. No real permissions were requested. The English-source and bilingual-resource policy passed. Single-table native Notes evidence below remains earlier validation; personal notebooks were not accessed for this UI change.

The 2026-11-07 licensing update adopts MIT for the unreleased candidate and removes separate paid authorization and contributor-agreement requirements. At that stage, application/test sources were unchanged from the language-first implementation except for the About credit text. The earlier regression and AppKit counts above are retained evidence, not rerun claims for this notice-only change. Build, license-payload and archive checks are recorded separately against the refreshed local candidate.

## Private build 17 evidence

Build 17 writes one seven-column table per category page. Each word occupies one row; its collection-history cell contains the recorded times, source titles/URLs, original contexts and event IDs. Legacy six-column and two-table pages remain readable. The next deliberate save converts an eligible managed legacy page to the single-table layout; rendering/reconciliation does not add a collection or invent missing history.

The regression suite passed **382 checks**, including exact legacy digest preservation, single-row history round trips, multiline field-like subtitle text, cross-word duplicate event IDs and an injected write-success/lost-receipt scenario through the real Notes adapter. The latter verifies the old two-attachment precondition, one-table output and retry/reopen behavior without a second write. These tests use generated data and injected Notes responses. A separate native Notes check passed nine assertions in a uniquely named test folder: legacy two-table import, digest preservation, migration on a new event, retry/reopen deduplication, one native table with one row per word, editable readback, multiline/source preservation, retention of earlier events, and notebook browsing. The everyday vocabulary pages were not modified. Packaging/signature verification is recorded separately from those Notes checks.

## Earlier build 16 validation

Build 16 passed **394 regression checks** and **87 fixed-data AppKit checks**. A differential fixture compiled both the committed build 15 source and the updated source: stored single-note/table HTML, category identifiers, semantic digests, deliberate collection counts, source descriptions and analysis exports matched in both interface languages. This comparison used generated data and did not access Notes. Source policy, bilingual catalog parity and the **73-file** public manifest passed.

Separate development and production-preview apps were built and their signatures verified. All eight interface catalogs, the legacy Notes-format catalog and the sample catalog were compared byte for byte against the checked-in resources in both apps. The preview rejected a write-capable development command with exit code 2 before accessing Notes. These are ad-hoc local builds, not notarized public installers; existing build 15 packages were not replaced.

The local verification process explicitly paired Command Line Tools with its matching SDK because the inherited `SDKROOT` pointed to a different Xcode SDK. No global developer settings or license state were changed.

## Earlier build 15 evidence

Build 15 was compiled and checked locally on an Apple Silicon development Mac:

- **390 regression checks passed**, including synthetic multilingual OCR, dictionary/speech checks, collection and source fixtures, setup language/layout/recovery, preference migration, production launch restrictions and restart handoff. Language changes preserved exact managed Notes HTML and existing table readback counts. No user screen was captured and no personal Notes writes were performed.
- **87 fixed-data AppKit checks passed**, covering Chinese and English menu/card controls and notebook headers, without connecting to Notes.
- Setup fixtures exercise all five English pages, language choice persistence before simulated consent, and restoration after an earlier deferred introduction. Interactive build 15 checks confirmed immediate switching from the system-default Chinese interface to English and back. The app's Restart button launched a replacement process from the same executable path, restored the screen-permission step, and retained English. Real Screen Recording consent and macOS's system-driven Quit & Reopen remain pending acceptance; the in-app restart check does not validate that separate system flow.
- Local **Apple Development-signed preview DMG and ZIP** were generated from the exact build 15 app. The DMG was mounted read-only and its app compared byte for byte, including four bundled language catalogs. Signature integrity, disk-image verification and SHA-256 checks passed. These packages are not Developer ID-signed or notarized public releases.
- Shell syntax, English source-comment policy, translation placeholder/conflict checks and a 66-file explicit source manifest passed. An earlier exporter version also passed 13 isolated safety scenarios; current source snapshots include the build number to distinguish preview revisions.

These are local candidate checks, not a notarized release, a completed GitHub Actions run, an independent user study or clean-machine installation acceptance.

| Area | Status |
| --- | --- |
| Build target | Apple Silicon, macOS 14 or later |
| Earlier real-use environment | M3 Mac, macOS 26, Safari and a Safari Dock web app |
| Interface language | System default, Simplified Chinese and English implemented; fixture/layout checks passed; interactive Chinese/English switching and language persistence across in-app restart passed |
| New first-launch UI | Same-path in-app restart restored the saved step and language; real consent, system-driven restart and clean-machine acceptance pending |
| Local preview packages | Development-signed DMG/ZIP generated and locally verified; not official distribution |
| Developer ID signing and notarization | Optional future route; not used for the first unnotarized distribution |
| Fresh-machine download/install/upgrade | Pending |
| Player fullscreen and native macOS fullscreen | Experimental; no general guarantee |
| External displays and alternate scaling | Pending acceptance matrix |
| Intel Macs | No binary or compatibility claim |
| Notion integration | Not implemented |
| Automatic application updates | Not implemented |

## Before subsequent distribution

Complete the five-step manual gate in [validation-plan.md](validation-plan.md), run the current build/test workflow, and record results against the exact artifact. Publish only the declared distribution mode after installation checks. The chosen public route must be explicitly labeled unnotarized; local dirty previews remain distinct from public packages. Signed mode additionally requires Developer ID and Apple notarization.

Keep test notebooks, captures, exports, personal paths, signing diagnostics and credentials out of source control. Private development history and local artifacts are excluded from public documentation. Do not publish source or releases solely because packaging scripts exist.
