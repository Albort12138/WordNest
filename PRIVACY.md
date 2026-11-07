# WordNest privacy and permissions

WordNest performs word lookup on your Mac. It does not operate a backend, require a WordNest account, send telemetry, or call a hosted dictionary, translation, or AI service. The application itself makes no network requests.

This document describes the app workflow. macOS services, Apple Notes accounts, websites you open, and resources you download have their own behavior and privacy policies.

## Screen capture

When you invoke lookup, WordNest fixes the pointer position and captures a single frame of the display containing it. The full display frame exists briefly in memory, then the area near the pointer is cropped for local Vision OCR. The app excludes its own windows from capture.

Frames are not written to disk or uploaded. There is no continuous recording, background screen history, or audio capture. Capture is triggered by the lookup shortcut. Screen Recording permission is required because macOS protects access to other applications' visible content.

The recognized word and original line appear in the lookup card. They are saved to Notes only when you collect them. Diagnostic fixtures used by developer tests are separate from normal screen capture.

## Definitions and pronunciation

Definitions come from enabled local macOS Dictionary resources or your selected imported MDX file. Importing explicitly chosen MDX files creates managed copies under `~/Library/Application Support/<bundle identifier>/Dictionaries/`; the source files are not changed. WordNest stores dictionary names, identifiers, entry counts and the selected source in local preferences. Removing an imported dictionary removes its managed copy, without changing saved Notes entries. MDX HTML is converted to text without executing scripts or loading external resources. No external application is controlled to obtain definitions. Pronunciation uses a matching macOS voice through AVFoundation. WordNest does not automatically download additional dictionaries, voices, or language models.

Installing those resources through macOS may require a network connection. Dictionary coverage, OCR languages, and voices vary by system configuration.

## Page titles and source links

On lookup, WordNest can read the frontmost supported page's title and URL and associate them with that lookup. It checks the application, window, and pointer location, then checks that the source did not change during recognition. Saving does not replace it with a page opened later.

- **Regular Safari:** Apple Events read the current tab's title, URL, and window bounds. Requires Automation permission for Safari.
- **Safari website apps added to the Dock:** Accessibility reads the active application's window, element roles and geometry, and root web area's URL, title, and description. Traversal stops at the web area instead of reading the page body. Requires Accessibility permission.

The implementation does not enumerate browser history, read cookies or credentials, inspect background tabs, or simulate typing to retrieve an address. Accessibility is an application-level macOS permission, broader than URL-only access; WordNest limits its usage to the metadata path described here.

If the page cannot be confirmed, the source stays unavailable. You can add, change, or clear it before collecting. URLs may contain private paths or query parameters. The original accepted URL is retained; a separate normalized URL groups sources. Review links before saving or exporting.

## Apple Notes storage

Collected words, available phonetics and definitions, original lines, counts, timestamps, and source records are stored in managed Notes tables. Automation lists accounts and folders, reads the selected WordNest notebook, and creates or updates managed pages. WordNest does not directly access the private Notes database.

Choose an ordinary folder for saving. You can select a separate ordinary or Smart Folder in the same account for browsing. Browsing reads matching vocabulary pages, not arbitrary ordinary-note bodies. Updates are rejected when content cannot safely be recognized or a write remains unconfirmed.

**Your Notes account determines synchronization:**

- **On My Mac:** Apple Notes stores vocabulary locally.
- **iCloud or another network-backed account:** Notes may send and synchronize notes through the account provider. WordNest does not control this or guarantee when another device receives a note.

Local processing does not mean an iCloud-backed notebook never leaves your Mac. Choose On My Mac for local-only storage. Account services have their providers' terms and privacy settings.

## Settings and write journal

Local preferences include imported-dictionary configuration, interface-language choice, OCR source-language selection, Notes destination identifiers, and setup progress. Interface language can follow system preferences or be explicitly set to Simplified Chinese or English. It is independent of OCR and does not translate or modify vocabulary, dictionary entries, user content, or persisted Notes schemas. Unsupported system language preferences fall back to English; unknown system diagnostics may follow the OS language.

Preview and release apps use bundle identifier `io.github.albort12138.wordnest`; default development builds use `io.github.albort12138.wordnest.development`. Where no current choice exists, validated notebook and OCR-language preferences can be imported from the earlier `local.subtitlelookup.prototype` preference domain. Permission grants and setup-completion claims are not imported; each identity's permissions must be checked independently. The executable remains `SubtitleLookup`, and the shared write journal keeps the earlier support-directory name for duplicate prevention.

`~/Library/Application Support/SubtitleLookup/notes-writes-v1.json` contains minimal write state: event UUIDs, destination identifiers, category, expected count, content digest, note identifiers, and confirmation or rejection state. A sibling lock file coordinates local writers. The journal does not contain word, definition, or original-line bodies. Digests and identifiers are still local metadata, not a claim of anonymity.

The journal prevents uncertain writes from becoming duplicate collections. Deleting it removes duplicate-prevention history; it is not a routine permission or save-error remedy.

## Export and external services

JSON export includes the notebook snapshot you have read: vocabulary, definitions, original lines, timestamps, source URLs and titles, and coverage warnings. It is written only to your chosen location, which may itself be synchronized by another service.

WordNest does not upload exports or send them to models. Sharing an export, attaching content to an issue, opening a source website, or sending it to an AI service is outside the local lookup pipeline. Review private content first.

## Permission choices and revocation

First-launch setup explains permissions for the functions you choose. macOS controls the actual grants; an installer cannot approve them for you.

Open **Settings… / 设置…** from the menu bar to resume setup, change interface language, review permissions, or change the notebook location. Setup completion records that you dismissed the introduction, not that every permission remains granted. An unfinished saved step is resumed even if an earlier introduction was completed.

The language preference is persisted, and the current step is checkpointed before permission requests, opening relevant system settings, and a permission-related restart. macOS may close the app without relaunching it after Quit & Reopen. Reopen the same app copy to continue; no automatic system relaunch is guaranteed.

Screen Recording is needed for lookup; Notes automation for notebook integration; Safari automation and Accessibility for their respective automatic-source paths. OCR itself does not require Accessibility. Automatic source capture can be omitted, with links entered manually.

Revoke permissions in **System Settings → Privacy & Security**. This can disable the corresponding function. Rebuilt ad-hoc-signed apps may need new authorization because their code identity changes. Official releases are intended to use stable signing.

## Removing WordNest

Deleting the app does not delete vocabulary in Apple Notes. Manage or delete those notes in Notes. Removing local preferences and the support directory deletes settings and the journal; keep WordNest closed and preserve those files while investigating unresolved writes. There is no WordNest cloud account to close.

## Questions

Maintainer: Albort. Contact [albort.yao.xue@gmail.com](mailto:albort.yao.xue@gmail.com). Omit private screen content, notes, and source URLs from public reports unless you intend to share them.

Updated: 2026-11-05.
