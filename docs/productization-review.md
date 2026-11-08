# WordNest productization review

Initial review: 2026-11-04. Licensing and contribution requirements updated on 2026-11-07 for the MIT open-source model. The 2026-11-08 distribution decision selects explicitly labeled unnotarized packages without paid developer membership; the release criteria below reflect that route. Findings and release criteria follow. Recommendations are not evidence that a feature or distribution step has shipped.

## Marketing and positioning review

### Positioning

The primary audience is Mac users learning vocabulary while watching subtitled videos or reading nonselectable text. The workflow is pointer-directed lookup followed by deliberate collection into the user's Apple Notes notebook.

Recommended promise: **Look up words where you find them. Keep them in Apple Notes.**

Screen OCR, local dictionary and speech services, original-line retention, native Notes tables, and source history together form the product story. No comparative research establishes uniqueness. Avoid “first,” “best,” universal support, or measured accuracy without a reproducible study.

### Priority findings

| Priority | Finding | Release requirement |
| --- | --- | --- |
| P0 | Licensing must match the open-source promise. | Use MIT consistently in the repository, app, source export and installers, with required notices and no separate authorization fee. |
| P0 | “Completely local” can hide Notes synchronization. | Separate WordNest's local processing from provider-controlled Notes sync. Explain On My Mac versus iCloud. |
| P0 | A download link can imply an installer exists. | Mark the first public download pending until published and tested; disclose unnotarized status before download. |
| P1 | Candidate paths and test histories obscure user workflow. | Lead with scenario, install, setup, use, privacy, compatibility, and licensing. Keep evidence in developer docs. |
| P1 | English docs can imply English UI. | Document system-default, English and Simplified Chinese interface selection. Provide equivalent English and Chinese READMEs. |
| P1 | Multilingual OCR can imply multilingual Chinese translation. | Describe OCR models, installed dictionaries, and system voices separately. |
| P1 | Grouping links can imply universal video integration. | Separate Safari-specific acquisition from normalization. Count saved words/events, not inferred viewing or spoken occurrences. |
| P1 | Build targets can imply tested compatibility. | Distinguish Apple Silicon/macOS 14+ target from M3/macOS 26 development evidence. |
| P2 | Contributions need clear and accessible terms. | Accept contributions under MIT without copyright assignment or a separate contributor agreement. Preserve third-party notices. |

### Documentation decisions

English is the default README with an equivalent Chinese version. Neither includes personal paths or private collection examples. PRIVACY.md explains capture scope, source metadata, Notes account sync, local transaction metadata, exports, permissions, and removal.

The DMG workflow defaults to an explicitly unnotarized draft; the first public download is pending. Source builds are explicitly ad-hoc signed. No price, support SLA, compatibility certification, or publication result is invented.

### Evidence and sources

Reviewed the capture/lookup pipeline, Safari/Dock source adapters, runtime language selection, local dictionary and voice usage, Notes tables, write journal, source export, build target, and development evidence. Support descriptions separate implementation scope from real-use tests.

The [MIT License](https://opensource.org/license/mit) permits use, modification and redistribution, including commercial use, subject to its notice requirements. Repository descriptions and packaged notices must reflect those terms.

Apple documents [iCloud Notes behavior](https://support.apple.com/en-mide/guide/notes/apda3f8513ed/mac). Privacy statements distinguish WordNest's own requests from Notes account synchronization.

### Release acceptance checks

- A first-time visitor understands the scenario and shortcut-to-Notes workflow before implementation details.
- A non-developer can distinguish pending release, unnotarized download, optional notarized installer, and source build.
- Privacy copy does not promise an iCloud notebook remains only on the Mac.
- Compatibility distinguishes targets, tests, and experimental scenarios.
- The MIT License and copyright notice are visible before reuse.
- Public artifacts contain no private collections, personal paths, or fabricated download/test claims.

## Native macOS product review

This perspective reviews the implemented interaction and platform boundaries, not a completed clean-install acceptance test.

| Priority | Finding | Product response / remaining gate |
| --- | --- | --- |
| P0 | Permissions spread across developer-oriented menu actions make first use difficult. | Guide first launch, request consent only through explicit actions, and keep later recovery in settings. Verify actual process capability after returning from macOS settings. |
| P0 | An installed name and enabled switch do not prove the current binary is authorized. | Keep the product identity stable, disclose ad-hoc signature changes, and test renewed grants on a real downloaded installation and upgrade. Developer ID signing remains optional. |
| P0 | Installation cannot approve privacy rights automatically. | Say first-launch setup, retain user-controlled system consent, and allow honest deferred completion. |
| P1 | Sources and Notes are valuable but not necessary to understand the lookup loop. | Make optional integrations skippable; keep lookup usable once capture permission works. |
| P1 | Multiple preview instances can fight for the same shortcut. | A second normal launch should reveal the existing product rather than register another hotkey. Keep development fixtures intentionally separate. |
| P1 | Fullscreen, source attribution and display geometry are application-specific. | Publish a support matrix and check fullscreen/multiple displays separately. |
| P2 | A growing footer and settings surface can bury the collection action. | Preserve one obvious save action, progressive correction controls, and a subtle source/destination summary. |

The first public menu should emphasize vocabulary, settings, help, about and quit. Debug reports and permission repair belong behind settings/help. Shipping priorities are install → first successful lookup → verified collection; additional destinations and cloud features are not required for the preview.

## Open-source community review

This perspective reviews repository expectations and contribution mechanics. It does not substitute for legal advice or third-party asset clearance.

| Priority | Finding | Community requirement |
| --- | --- | --- |
| P0 | An open-source promise requires consistent licensing. | Link the MIT License and include it in source and binary distributions. No separate authorization fee applies. |
| P0 | Contributors need clear inbound terms. | Contributions use MIT; contributors retain copyright. No separate contributor agreement is required. |
| P0 | Public history can expose private diagnostics and notebook content. | Keep captures, exports, local diaries and credentials out of commits and release payloads; inspect staged files and artifacts before publishing. |
| P1 | A clone must be understandable without the author's local workspace. | English-default and Chinese README, reproducible build/test instructions, declared platform scope and versioned public metadata. |
| P1 | Automated checks cannot prove system permission UX. | CI should cover noninteractive fixtures and builds, while release notes separately identify manual acceptance. |
| P1 | Brand assets and system dictionary output need clear provenance and usage boundaries. | Document asset provenance and relevant limitations; do not imply Apple or another product endorses WordNest. |
| P2 | Users need a path to report problems without exposing their notebook. | Issue templates should request versions and minimal reproduction, with redaction guidance and private security reporting. |

Repository readiness means the license, build route, issue route and evidence boundary are visible before a visitor has to inspect source. It does not require committing compiled apps, local fixture exports or personal test history.

## Actual-user journey review

This is a task-based desk review from a prospective user's perspective, not a claim that independent participants completed usability testing.

| Priority | User question / friction | Acceptance criterion |
| --- | --- | --- |
| P0 | “I downloaded it; which app do I authorize?” | Move the app to Applications before setup; identify the running copy and explain macOS consent without asking users to debug signatures. |
| P0 | “I denied a permission. Is the app broken?” | Show the unavailable function precisely, allow a deferred introduction, and offer a clear settings recovery path. |
| P0 | “Did Save work, or will another click add it twice?” | Report verified save state, distinguish a deliberate new collection from retry, and preserve uncertain results for reconciliation. |
| P1 | “Why is there no translation or voice for this language?” | Distinguish OCR support, available dictionaries and installed voices; missing resources must produce understandable guidance. |
| P1 | “Which video will this word belong to?” | Show the fixed current source before saving; do not invent metadata or substitute a later tab. Allow manual correction. |
| P1 | “Where did my words go?” | Display the chosen Notes destination; explain physical storage versus smart views and that iCloud sync belongs to Apple. |
| P1 | “Will this record my screen or send it away?” | Explain shortcut-triggered single-frame local processing before consent; do not autoplay, upload or save captures silently. |
| P2 | “Can I use it without learning another app?” | Keep the core interaction to point, shortcut, review and one save; put advanced options behind settings. |

The release exercise should follow the five-step [manual acceptance gate](validation-plan.md). A successful fixture result is not an independent user-study result. Invite a small external test group only after the downloaded-install path is reproducible and the permission copy matches actual macOS behavior.
