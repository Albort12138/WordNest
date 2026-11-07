# Code guide

WordNest is a native Swift/AppKit menu-bar application built with Apple's system frameworks. Application and test source, comments, scripts and configuration use English. User-interface strings use English keys and bilingual resource catalogs. Multilingual examples and stable persisted Notes identifiers belong to separate data resources; user/dictionary content retains its original format. Do not mechanically translate storage strings.

## A first reading path

1. Read `LookupWord`, `CaptureRegion` and `WordSelection` in [LookupCore.swift](../Sources/LookupCore.swift): the word, coordinates and pointer-selection rules.
2. Follow [TextRecognizer.swift](../Sources/TextRecognizer.swift) to see how Vision fills those types.
3. Read the small `DictionaryProvider` contract in [DictionaryProvider.swift](../Sources/DictionaryProvider.swift), then its system and MDX adapters.
4. Follow one `VocabularyEntry` from [Vocabulary.swift](../Sources/Vocabulary.swift) into [AlphabetBook.swift](../Sources/AlphabetBook.swift) and the verified Notes writer.
5. Return to `captureAtPointer`, `lookupAndShow` and `collectWord` in [App.swift](../Sources/App.swift) to see how the pieces are connected.

The README includes an illustrated workflow and architecture diagram. This guide explains ownership and invariants so contributors can change one part without accidentally changing collection counts or stored Notes content.

## Modules

| Source | Responsibility |
| --- | --- |
| [`ProductRuntime.swift`](../Sources/ProductRuntime.swift) | Build-mode dispatch, permission preflight and legacy preference import |
| [`SetupCoordinator.swift`](../Sources/SetupCoordinator.swift), [`SetupWindow.swift`](../Sources/SetupWindow.swift) | Pure setup progress, persisted introduction state and explicit consent UI |
| [`InterfaceLanguage.swift`](../Sources/InterfaceLanguage.swift), [`Assets/Localization/*.json`](../Assets/Localization/) | Independent interface-language preference, English literal/interpolated UI keys and bilingual catalogs |
| [`TextResources.swift`](../Sources/TextResources.swift), [`Assets/Compatibility/`](../Assets/Compatibility/), [`Assets/Fixtures/`](../Assets/Fixtures/) | Bundled resource loading, unchanged legacy Notes identifiers and multilingual sample data |
| [`App.swift`](../Sources/App.swift) | Lifecycle, menu, global shortcut, capture orchestration and lookup card |
| [`LookupCore.swift`](../Sources/LookupCore.swift), [`TextRecognizer.swift`](../Sources/TextRecognizer.swift) | Geometry, segmentation, pointer hit testing and Vision OCR |
| [`LanguageSupport.swift`](../Sources/LanguageSupport.swift) | Source-language preference and local language inference |
| [`DictionaryProvider.swift`](../Sources/DictionaryProvider.swift), [`DictionarySettings.swift`](../Sources/DictionarySettings.swift) | Provider contract, managed local library, persisted selection and import UI |
| [`MDXReader.swift`](../Sources/MDXReader.swift), [`RIPEMD128.swift`](../Sources/RIPEMD128.swift) | Bounded MDX 2.x container/index/record decoding and standard key-index transform |
| [`SystemDictionary.swift`](../Sources/SystemDictionary.swift), [`WordSpeaker.swift`](../Sources/WordSpeaker.swift) | System dictionary adapter, definition presentation and matching local speech |
| [`LookupCardBody.swift`](../Sources/LookupCardBody.swift) | Structured definition and context layout |
| [`CollectionSource.swift`](../Sources/CollectionSource.swift), [`SourceCapture.swift`](../Sources/SourceCapture.swift) | Validated source snapshots, canonical grouping and Safari/AX adapters |
| [`Vocabulary.swift`](../Sources/Vocabulary.swift), [`AlphabetBook.swift`](../Sources/AlphabetBook.swift) | Collection events, Notes configuration, table model/parser and write journal |
| [`AppleNotes.swift`](../Sources/AppleNotes.swift), [`AlphabetNotes.swift`](../Sources/AlphabetNotes.swift) | Serialized Apple Events, selected-folder operations, verified read/write |
| [`NotesSettings.swift`](../Sources/NotesSettings.swift), [`VocabularyBrowser.swift`](../Sources/VocabularyBrowser.swift) | Destination configuration, snapshot browsing/filtering and pronunciation |
| [`SourceAnalysis.swift`](../Sources/SourceAnalysis.swift) | Collection-based source summaries and explicit local JSON export |

## Lookup flow

The shortcut freezes pointer/display and foreground-source context. ScreenCaptureKit obtains a frame; the app crops it in memory and runs synchronous Vision recognition away from the main thread. Visual-line grouping preserves original observations for word geometry. A pointer hit chooses the word; dictionary loading fills the card asynchronously. Revision checks prevent old results from reopening or overwriting a newer card.

AppKit uses global logical points with an upward y-axis; image cropping uses pixels; Vision uses normalized coordinates. `CaptureRegion.make` centralizes conversion, including display scaling and off-center edge crops. OCR confidence is not a calibrated accuracy percentage. The app does not pause video, so subtitle transitions can race capture.

## Dictionary boundary

The provider contract is quoted directly from [DictionaryProvider.swift](../Sources/DictionaryProvider.swift):

```swift
protocol DictionaryProvider: Sendable {
    var source: DictionarySource { get }
    func lookup(_ request: DictionaryRequest) async throws -> DictionaryLookup
}
```

`DictionaryProvider` returns a typed lookup result for a request and stable source identity. `DictionaryLibrary` owns managed files, persisted selection, validation and cached immutable readers. `SystemDictionaryProvider` wraps Dictionary Services; `MDXDictionaryProvider` returns local text without applying system-specific grammar/IPA splitting. The app snapshots the selected source before awaiting and checks the card revision before displaying the response. Selection changes retain frozen page context and never save a collection automatically. The library never reads Eudic private storage or launches it for definitions. See README for supported MDX variants, resource limits and local storage behavior.

`VocabularyEntry.definitionFormat` is transient presentation metadata used to prevent MDX text from being mistaken for system IPA when saving. Existing Notes schemas and counts remain unchanged; full definition text is saved. Dictionary identifiers are not added to the existing Notes schema.

## Sources and local boundaries

`PageSourceReader` encapsulates ordinary Safari Apple Events and Safari Dock web-app Accessibility metadata. Both verify the foreground context and pointer geometry. AX traversal is bounded and stops at the root web area without walking webpage body content. Permission/metadata failures leave the source empty for manual editing. Normalization groups known video URL variants without making network requests or resolving short links.

The source is fixed for the lookup event, retained through correction, and locked when saving starts. A later tab must not replace the original source. Empty page titles fall back through available root metadata/window title; fully absent titles remain absent rather than becoming invented descriptions.

## Collection invariants

Each deliberate collection has an event UUID; each word row has a normalized key. A new event can increment an existing word, while retrying the same event cannot. New output uses one seven-column table: the original six summary fields plus inline collection history in the same word row. Every history line is labeled, including multiline context continuations, so user content cannot impersonate a record boundary. The parser still accepts legacy six-column summary pages and the earlier two-table layout. Rendering or migrating a page preserves its semantic digest; a deliberate new event alone increments its count. Legacy counts without recorded occurrences remain explicitly unattributed.

Notes is the content source of truth. Before writing, the client journals minimal transaction metadata and checks the current page. After writing, it parses native tables and verifies a semantic digest. Unknown results are reconciled instead of blindly retried. Existing extra content and incompatible structures are protected against automatic replacement.

A smart folder is a computed view, not a physical save destination. Save configuration and optional browsing configuration are separate. A rejected creation may still have had effects; keep uncertain/rejected transaction state until it is safely resolved. The local lock/journal does not provide a distributed transaction with iCloud or manual edits.

## Development and release modes

Use [README.md](../README.md) for build commands, [CONTRIBUTING.md](../CONTRIBUTING.md) for policies and [validation-plan.md](validation-plan.md) for acceptance. Build metadata is centralized in `config/product.env`. Development modes expose controlled fixtures; distribution modes reject those launch commands.

Initialization, setup presentation and permission preflight must not ask for consent. Explicit Setup actions request protected access; returning to the application refreshes status without polling. Persisted onboarding completion never proves permission.

An unfinished setup-step checkpoint takes precedence over an earlier completion flag. Checkpoint before every permission request, system-settings action and permission restart; persist the interface-language choice before the OS can terminate the process. The system's Quit & Reopen action is not assumed to relaunch WordNest. Opening the same app copy must resume its saved step. Development builds use `io.github.albort12138.wordnest.development`; preview/release builds retain `io.github.albort12138.wordnest` so their Launch Services and TCC registrations are distinct.

## Interface localization

The welcome page offers System default, Simplified Chinese and English before any permission request. `UILanguage` resolves supported macOS preferences with English fallback, independent of `SourceLanguage` for OCR. `L` accepts English `UIString` literals/interpolation; keys retain numbered slots while interpolated words, definitions, sentences and names remain data. English and Simplified Chinese catalogs use the same English keys. The language picker intentionally shows the native Chinese language name through a resource key. `UILocalization.key` maps explicitly classified legacy category/grammar values to their English display keys before localization; it must not change the values persisted to Notes.

`TextResources` reads signed app resources, or checked-in assets for standalone test binaries. `LegacyNotesText` preserves the original Notes table headers, page names, ownership markers and compatibility fragments; `SampleText` provides fixed multilingual examples and expected fixture text. A missing required resource is a packaging error and fails explicitly instead of silently creating a different Notes format. Build scripts bundle all three resource directories, and the public source manifest includes them.

Menus, lookup cards, settings, browsing, and application-owned status messages use the selected interface language. Dictionary content, user data, parser/schema constants and existing Notes tables are not translated. Unknown diagnostics emitted by system services may follow the OS language. Presentation-only grammar localization must use `displayGrammar`, keeping persisted grammar unchanged. Validate catalogs and both UI languages separately from the core model suite and real system-permission acceptance.

Keep generated apps, caches, captures, notebook exports and diagnostics under ignored local directories. Source tests use injected platform boundaries; actual Notes writes require dedicated integration targets. Signatures, fixture checks and real-user acceptance are separate kinds of evidence.
