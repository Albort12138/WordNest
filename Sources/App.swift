import AppKit
import Carbon
import ScreenCaptureKit
import ApplicationServices

private let appTitle = "WordNest"

/// A nonactivating panel still needs keyboard focus for selection, copying, and Escape.
/// Fullscreen visibility remains a real-device acceptance requirement.
final class ResultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Coordinates the lifecycle and lookup: hotkey, capture, crop, background OCR, then UI.
/// Algorithms and OCR are separate; menu, permissions, capture, and panels remain here.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var panel: ResultPanel?
    private var setupWindow: SetupWindowController?
    private var practiceOnly = false
    // Retain Carbon registration handles for explicit cleanup on restart and exit.
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    // Serialize captures so repeated shortcuts cannot run competing OCR or replace newer results.
    private var busy = false
    private var lastWord: String?
    private var lastLanguage: String?
    private var lastSentence: String?
    private var lastDefinition: String?
    private var lastDictionarySource = DictionarySource.system
    private var lastDictionaryFormat = DictionaryEntryFormat.system
    private lazy var dictionaryLibrary = DictionaryLibrary()
    private var dictionarySettings: DictionarySettingsController?
    private var dictionarySettingsLanguage: ResolvedUILanguage?
    private var queryField: NSTextField?
    // Invalidate pending lookups whenever the card closes or changes.
    private var cardRevision = 0
    private var cardAnchor = CGPoint.zero
    private var copyButton: NSButton?
    private lazy var speaker = WordSpeaker()
    private var speechStatus: NSTextField?
    private var correctionRow: NSStackView?
    private var correctionButton: NSButton?
    private var cardStack: NSStackView?
    private let notesClient = AppleNotesClient()
    private lazy var collector: VocabularyCollector = {
        let collector = VocabularyCollector(client: notesClient)
        collector.onStateChanged = { [weak self] in self?.refreshCollectionControls() }
        return collector
    }()
    private var notesDestination = NotesPreferences.load()
    private var notesReadingDestination = NotesPreferences.configuration()?.readingDestination
    private var notesSettings: NotesSettingsController?
    private var activeVocabulary: VocabularyEntry?
    private var collectionButton: NSButton?
    private var collectionStatus: NSTextField?
    private var cardLoading = false
    private var vocabularyBrowser: VocabularyBrowser?
    private var knownCollectionCount: Int?
    private var sourceLanguage = SourceLanguage.load()
    private let pageReader = PageSourceReader()
    private var sourceStatusMessage = L("No link captured. Click Source… to add one.")
    private var sourceSummary: NSTextField?
    private var sourceButton: NSButton?
    private var sourceEditor: SourceEditorController?
    private let languageMenu = NSMenu()
    private var interfaceLanguageObserver: NSObjectProtocol?
    private var notesSettingsLanguage: ResolvedUILanguage?
    private var vocabularyBrowserLanguage: ResolvedUILanguage?
    // SLKP identifies this app's hotkey events; it is not the configurable shortcut.
    private let hotKeySignature: OSType = 0x534C4B50
    private var restartInProgress = false
    private var exitedRestartParent: Int32?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let launch = ProductRuntime.launchMode(arguments: CommandLine.arguments)
        guard launch != .invalid else {
            fputs("Unsupported launch arguments. Development commands are disabled in distribution builds.\n", stderr)
            exit(2)
        }
        if launch == .normal, let identifier = Bundle.main.bundleIdentifier,
           let parent = RestartHandoff.parentProcess(environment: ProcessInfo.processInfo.environment,
                ownPID: ProcessInfo.processInfo.processIdentifier, bundleIdentifier: identifier,
                bundleURL: Bundle.main.bundleURL, candidates: NSWorkspace.shared.runningApplications.map {
                    RestartParentCandidate(processID: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier, bundleURL: $0.bundleURL)
                }) {
            Task { @MainActor in
                if await RestartHandoff.waitForExit(processID: parent) { self.exitedRestartParent = parent }
                self.finishLaunching(launch)
            }
            return
        }
        finishLaunching(launch)
    }

    private func finishLaunching(_ launch: ProductLaunchMode) {
        if launch == .normal {
            guard activateExistingInstanceIfNeeded() == false else { NSApp.terminate(nil); return }
            LegacyPreferences.migrateIfNeeded()
            notesDestination = NotesPreferences.load()
            notesReadingDestination = NotesPreferences.configuration()?.readingDestination
            sourceLanguage = SourceLanguage.load()
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "WordNest-menu", withExtension: "png"), let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 20, height: 20)
            statusItem.button?.image = image
        }
        refreshStatusIcon()
        rebuildMenu()
        if interfaceLanguageObserver == nil {
            interfaceLanguageObserver = NotificationCenter.default.addObserver(forName: .wordNestInterfaceLanguageDidChange,
                object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshInterfaceLanguage() }
            }
        }
        #if WORDNEST_DEVELOPMENT
        if case .development(let command) = launch { runDevelopmentMode(command); return }
        #endif
        registerHotKey()
        if SetupPreferences.shouldPresentOnLaunch() { showSettings() }
    }

    private func rebuildMenu() {
        // AppKit permits a submenu to belong to only one menu item at a time.
        for item in statusItem.menu?.items ?? [] where item.submenu === languageMenu { item.submenu = nil }
        statusItem.button?.toolTip = L("WordNest · Point at a word and press Control + Option + D")
        statusItem.button?.setAccessibilityLabel(L("WordNest menu"))
        let menu = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("Unknown")
        add("WordNest · v\(version)", to: menu, enabled: false)
        add(L("Point at a word, then press ⌃⌥D"), to: menu, enabled: false)
        menu.addItem(.separator())
        add(L("My vocabulary…"), action: #selector(showVocabulary), to: menu)
        add(L("Settings…"), action: #selector(openSettings), to: menu)
        add(L("Dictionaries…"), action: #selector(showDictionaries), to: menu)
        let languageItem = add(L("Text recognition language"), to: menu)
        languageItem.submenu = languageMenu
        languageMenu.removeAllItems()
        languageMenu.autoenablesItems = false
        let availableLanguages = try? TextRecognizer.availableSourceLanguages()
        for (index, language) in SourceLanguage.allCases.enumerated() {
            let item = add(language.title, action: #selector(selectSourceLanguage), to: languageMenu)
            item.tag = index
            item.state = language == sourceLanguage ? .on : .off
            item.isEnabled = availableLanguages?.contains(language) ?? true
            if !item.isEnabled { item.toolTip = L("Vision on this Mac does not support this language yet") }
        }
        menu.addItem(.separator())
        add(L("Help"), action: #selector(showHelp), to: menu)
        add(L("About WordNest"), action: #selector(showAbout), to: menu)
        add(L("Quit"), action: #selector(quit), to: menu)
        statusItem.menu = menu
    }

    private func refreshInterfaceLanguage() {
        rebuildMenu()
        if panel?.isVisible == true, !cardLoading, let word = lastWord, let sentence = lastSentence {
            let hit = LookupWord(text: word, sentence: sentence, bounds: .zero, confidence: 1, language: lastLanguage)
            show(title: word, body: "", at: cardAnchor, word: hit, definition: lastDefinition,
                 dictionarySource: lastDictionarySource, dictionaryFormat: lastDictionaryFormat)
        }
        if notesSettings?.window?.isVisible == true { showNotesSettings() }
        if vocabularyBrowser?.window?.isVisible == true { showVocabulary() }
        if dictionarySettings?.window?.isVisible == true { showDictionaries() }
    }

    /// Only normal launches participate; explicit development fixtures never compete for a hotkey.
    private func activateExistingInstanceIfNeeded() -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownID = Bundle.main.bundleIdentifier ?? "io.github.albort12138.wordnest"
        let candidates = NSWorkspace.shared.runningApplications.filter {
            // Workspace removal can lag the process-exit event during a restart.
            !$0.isTerminated && $0.processIdentifier != ownPID && $0.processIdentifier != exitedRestartParent
                && [$0.bundleIdentifier].compactMap { $0 }.contains(where: {
                $0 == ownID || $0 == "local.subtitlelookup.prototype"
            })
        }
        guard let existing = candidates.first else { return false }
        if existing.bundleIdentifier == ownID, let url = existing.bundleURL {
            // A normal reopen reaches applicationShouldHandleReopen and reveals the accessory's settings.
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        }
        else {
            let alert = NSAlert()
            alert.messageText = L("WordNest is already running")
            alert.informativeText = L("Quit the older WordNest from its menu before opening this version, so the lookup shortcut is registered only once. Your vocabulary and system permissions will not be changed.")
            alert.addButton(withTitle: L("OK"))
            alert.runModal()
        }
        return true
    }

    @objc private func openSettings() { showSettings() }

    private func showSettings(step: SetupStep? = nil) {
        if setupWindow == nil {
            setupWindow = SetupWindowController(onFinish: {}, onConfigureNotes: { [weak self] in self?.showNotesSettings() },
                onPractice: { [weak self] in self?.showPractice() }, onRestart: { [weak self] in self?.relaunch() })
        }
        setupWindow?.present(step: step)
    }

    /// Practice uses fixed text and cannot read or write the configured notebook.
    private func showPractice() {
        practiceOnly = true
        let word = LookupWord(text: "hello", sentence: "Hello, WordNest.", bounds: .zero, confidence: 1, language: "en-US")
        sourceStatusMessage = L("Demo card · No screen or page source was read.")
        show(title: word.text, body: "", at: NSEvent.mouseLocation, word: word, definition: SampleText.value("Welcome card entry"))
        collectionButton?.isEnabled = false
        sourceButton?.isEnabled = false
        queryField?.isEnabled = false
        correctionButton?.isEnabled = false
        collectionStatus?.stringValue = L("Demo only: nothing is saved. Return to a video, point at a word and press ⌃⌥D to look it up.")
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "WordNest", .applicationVersion: version,
            .credits: NSAttributedString(string: "© 2026 Albort · Code: MIT · Artwork: separate license")])
        NSApp.activate(ignoringOtherApps: true)
    }

    #if WORDNEST_DEVELOPMENT
    private func runDevelopmentMode(_ command: String) {
        switch command {
        case "--smoke-test":
            print("SMOKE_OK: menu initialized; no screen capture requested")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        case "--ui-self-test": runCardSelfChecks()
        case "--local-dictionary-preview":
            // An explicit fixture command never changes everyday dictionary preferences or accesses Notes.
            notesDestination = nil
            notesReadingDestination = nil
            let suite = "WordNest.DictionaryPreview.\(UUID().uuidString)"
            dictionaryLibrary = DictionaryLibrary(root: FileManager.default.temporaryDirectory.appendingPathComponent(suite),
                                                  defaults: UserDefaults(suiteName: suite)!)
            practiceOnly = true
            lookupAndShow(LookupWord(text: "happiness", sentence: "Keep the original video context.", bounds: .zero, confidence: 1),
                          at: NSEvent.mouseLocation, source: CollectionSource(url: "https://example.com/wordnest-test", title: "Fixed video source"))
            showDictionaries()
        case "--setup-preview":
            let suite = "WordNest.SetupPreview.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let access = SetupPermissionAccess(screenCapture: { false }, accessibility: { false }, automation: { _, _ in .notGranted },
                requestScreenCapture: {}, requestAccessibility: {}, openSettings: { _ in })
            setupWindow = SetupWindowController(onFinish: { defaults.removePersistentDomain(forName: suite); NSApp.terminate(nil) },
                onConfigureNotes: {}, onPractice: { [weak self] in self?.showPractice() }, onRestart: {}, access: access, defaults: defaults)
            setupWindow?.present()
        case "--notes-readback-test": runNotesReadbackCheck()
        case "--alphabet-integration-test": runAlphabetIntegrationCheck()
        case "--multilingual-integration-test": runMultilingualIntegrationCheck()
        case "--alphabet-library-preview": showVocabulary()
        case "--multilingual-preview":
            lookupAndShow(LookupWord(text: SampleText.value("Japanese study word"), sentence: SampleText.value("Japanese study context"), bounds: .zero, confidence: 1, language: "ja-JP"), at: NSEvent.mouseLocation)
        case "--dictionary-preview", "--notes-integration-preview":
            let sentence = command == "--notes-integration-preview" ? SampleText.value("Notes integration context") : "path to happiness was/succ"
            lookupAndShow(LookupWord(text: "happiness", sentence: sentence, bounds: .zero, confidence: 1), at: NSEvent.mouseLocation)
        case "--notes-settings-preview": showNotesSettings()
        case "--source-permission-preview": openWebAppSourcePermissions(); runSourceReadbackCheck()
        case "--source-readback-test": runSourceReadbackCheck()
        default: exit(2)
        }
    }
    #endif

    @objc private func selectSourceLanguage(_ sender: NSMenuItem) {
        guard SourceLanguage.allCases.indices.contains(sender.tag) else { return }
        sourceLanguage = SourceLanguage.allCases[sender.tag]
        sourceLanguage.save()
        for item in languageMenu.items { item.state = item.tag == sender.tag ? .on : .off }
    }

    /// Keep the owl visible during processing and append an ellipsis.
    private func refreshStatusIcon(processing: Bool = false) {
        guard let button = statusItem.button else { return }
        button.title = processing ? "…" : (button.image == nil ? "W" : "")
        button.imagePosition = processing ? .imageLeading : (button.image == nil ? .noImage : .imageOnly)
    }

    @discardableResult
    private func add(_ title: String, action: Selector? = nil, to menu: NSMenu,
                     enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    /// Register a system hotkey without monitoring all input or requiring Accessibility access.
    private func registerHotKey() {
        var specification = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        // Recover AppDelegate through an unretained pointer because C callbacks cannot capture Swift objects.
        // The main entry point keeps the delegate alive throughout the event loop.
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard read == noErr, identifier.signature == 0x534C4B50,
                  identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            // Dispatch UI work to the main thread; never run OCR inside the event callback.
            DispatchQueue.main.async { owner.captureAtPointer() }
            return noErr
        }, 1, &specification, context, &eventHandler)
        let identifier = EventHotKeyID(signature: hotKeySignature, id: 1)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey),
                                             identifier, GetApplicationEventTarget(), 0, &hotKey)
        if installed != noErr || registered != noErr {
            show(title: L("Shortcut registration failed"), body: L("Another app may be using ⌃⌥D. Quit that app and restart WordNest.\n\nStatus: \(installed) / \(registered)"), at: NSEvent.mouseLocation)
        }
    }

    @objc private func relaunch() {
        guard !restartInProgress else { return }
        restartInProgress = true
        // Release the old hotkey before launching its replacement to avoid a registration collision.
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.environment = [RestartHandoff.parentPIDKey: String(ProcessInfo.processInfo.processIdentifier)]
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if error == nil { NSApp.terminate(nil) }
                else {
                    self.restartInProgress = false
                    self.registerHotKey()
                }
            }
        }
    }

    @objc private func showHelp() {
        show(title: appTitle, body: L("Look up a new word where you find it. Keep it with its original context in Notes.\n\nPoint at a subtitle or on-screen word and press Control + Option + D (⌃⌥D). Click Pronounce to hear it; use Edit word if recognition needs correction.\n\nFirst-launch setup guides permissions and notebook selection. Open Settings… later to recover permissions or change the save location. Screen Recording enables lookup; source capture and Apple Notes are optional. Choose an interface language on the first setup page.\n\nDefinitions use the selected local dictionary; pronunciation uses macOS voices. Open Dictionaries… to import an MDX file. Not every language has Chinese definitions; choose the text recognition language from the menu when needed.\n\nCollections retain the word, original line, and available page title and URL. Another deliberate collection increases its count. Check Source… before saving. Vocabulary supports source filtering and JSON export; statistics cover only collections you made.\n\nWordNest does not upload captures, entries or analytics and does not use cloud translation. On My Mac Notes storage stays local; Apple handles synchronization for iCloud accounts.\n\nFullscreen, protected video and some windows may prevent capture or source reading. Links can be entered manually. Notion is not connected. Press Esc to close."), at: NSEvent.mouseLocation)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func openDictionary() {
        if lastDictionarySource.kind == .mdx { showDictionaries(); return }
        // Use the system Dictionary app without third-party dependencies or private enumeration APIs.
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Dictionary.app"),
                                           configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showDictionaries() {
        if dictionarySettings == nil || dictionarySettingsLanguage != UILocalization.currentLanguage {
            dictionarySettings?.close()
            dictionarySettings = DictionarySettingsController(library: dictionaryLibrary) { [weak self] in self?.dictionaryChanged() }
            dictionarySettingsLanguage = UILocalization.currentLanguage
        }
        dictionarySettings?.present()
    }

    @objc private func selectCardDictionary(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        do { try dictionaryLibrary.select(id); dictionaryChanged() }
        catch { showDictionaries() }
    }

    /// Selection reuses the frozen lookup context and URL. It never captures again or collects a word.
    private func dictionaryChanged() {
        guard panel?.isVisible == true, let text = lastWord else { return }
        let word = LookupWord(text: text, sentence: lastSentence ?? "", bounds: .zero, confidence: 1, language: lastLanguage)
        lookupAndShow(word, at: cardAnchor, source: activeVocabulary?.source, sourceMessage: sourceStatusMessage)
    }

    /// Freeze the pointer and display at the shortcut; later pointer motion must not select another word.
    /// Capture takes the next frame without pausing playback, so subtitle changes can race it.
    private func captureAtPointer() {
        guard !busy else { return }
        practiceOnly = false
        speaker.stop()
        cardRevision += 1
        let revision = cardRevision
        let mouse = NSEvent.mouseLocation
        guard CGPreflightScreenCaptureAccess() else {
            showSettings(step: .screenCapture)
            return
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let screenFrame = screen.frame
        let language = sourceLanguage
        let foreground = NSWorkspace.shared.frontmostApplication
        let sourceContext = SourceCaptureContext(bundleID: foreground?.bundleIdentifier ?? "",
            pointer: mouse, primaryScreenTop: NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY, processID: foreground?.processIdentifier)
        if sourceContext.bundleID == "com.apple.Safari" { AppleNotesClient.prepare() }
        let scale = screen.backingScaleFactor
        let displayID = number.uint32Value
        let started = ProcessInfo.processInfo.systemUptime
        // Hide the previous card and exclude this app from capture to avoid recognizing its own UI.
        panel?.orderOut(nil)
        busy = true
        refreshStatusIcon(processing: true)
        Task { @MainActor in
            // Restore state on every outcome so one failure cannot disable later lookups.
            defer {
                self.busy = false
                self.refreshStatusIcon()
            }
            do {
                // Capture page metadata before showing UI; never substitute a later tab at save time.
                let sourceCapture = await self.pageReader.capture(sourceContext)
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw NSError(domain: "Lookup", code: 1, userInfo: [NSLocalizedDescriptionKey: L("The display under the pointer could not be found. Please try again.")])
                }
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                let config = SCStreamConfiguration()
                // Convert AppKit points to ScreenCaptureKit output pixels using this display's scale.
                // Crop against the returned image dimensions rather than assuming the requested size.
                config.width = Int((screenFrame.width * scale).rounded())
                config.height = Int((screenFrame.height * scale).rounded())
                config.showsCursor = false
                // Keep the display frame in memory only; do not write, upload, or capture audio.
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                guard let region = CaptureRegion.make(screen: screenFrame, mouse: mouse,
                                                      imageWidth: image.width, imageHeight: image.height),
                      let cropped = image.cropping(to: region.pixels) else {
                    throw NSError(domain: "Lookup", code: 2, userInfo: [NSLocalizedDescriptionKey: L("The captured image could not be cropped. Please try again.")])
                }
                // Run synchronous Vision work away from the main thread to keep the UI responsive.
                // Return to the main thread for hit testing and presentation.
                let result = try await Task.detached(priority: .userInitiated) {
                    try TextRecognizer.recognize(cropped, language: language)
                }.value
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                guard revision == self.cardRevision else { return }
                if let word = WordSelection.hit(words: result.words, pointer: region.pointer) {
                    // Discard automatic attribution if the page changes during capture.
                    let currentPage = sourceCapture.source == nil ? sourceCapture : await self.pageReader.capture(sourceContext)
                    let stable = sourceCapture.source?.identityURL == currentPage.source?.identityURL
                    self.lookupAndShow(word, at: mouse, source: stable ? sourceCapture.source : nil,
                        sourceMessage: stable ? sourceCapture.message : L("The page changed during lookup. Please check the source link manually."))
                } else {
                    self.presentMiss(result, elapsed: elapsed, mouse: mouse)
                }
            } catch {
                guard revision == self.cardRevision else { return }
                let systemError = error as NSError
                if systemError.domain == SCStreamErrorDomain && systemError.code == SCStreamError.Code.userDeclined.rawValue {
                    self.showSettings(step: .screenCapture)
                    return
                }
                self.show(title: L("Lookup incomplete"), body: L("\(error.localizedDescription)\n\nCheck Screen Recording permission and whether the video permits capture. Try ordinary webpage text first."), at: mouse)
            }
        }
    }

    /// Show the recognized word before dictionary loading so users can verify OCR immediately.
    private func lookupAndShow(_ word: LookupWord, at mouse: CGPoint, source: CollectionSource? = nil,
                               sourceMessage: String = L("No link captured. Click Source… to add one.")) {
        knownCollectionCount = nil
        sourceEditor?.close()
        sourceStatusMessage = sourceMessage
        // Integration previews can reuse a test ID for cross-process deduplication; normal lookups use new IDs.
        #if WORDNEST_DEVELOPMENT
        let id = CommandLine.arguments.contains("--notes-integration-preview") ? testEntryID() ?? UUID() : UUID()
        let isTest = CommandLine.arguments.contains("--notes-integration-preview") || CommandLine.arguments.contains("--multilingual-preview")
        #else
        let id = UUID()
        let isTest = false
        #endif
        activeVocabulary = VocabularyEntry(id: id, word: word.text, definition: nil, sentence: word.sentence, isTestEntry: isTest, source: source)
        let heading = word.text.isEmpty ? L("Lookup word") : String(word.text.prefix(100))
        let selectedDictionary = dictionaryLibrary.selectedSource
        show(title: heading, body: L("Looking up the local dictionary…"),
             at: mouse, word: word, loading: true, dictionarySource: selectedDictionary)
        let revision = cardRevision
        Task { @MainActor in
            let definition = await self.dictionaryLibrary.lookup(DictionaryRequest(text: word.text, sourceLanguage: word.language), source: selectedDictionary)
            // Discard results after closing, replacing, or editing a query; never reopen the old card.
            guard revision == self.cardRevision else { return }
            self.show(title: heading,
                      body: definition.entry == nil ? definition.message : "",
                      at: mouse, word: word, definition: definition.entry?.text,
                      pronunciation: definition.entry?.pronunciation,
                      dictionarySource: definition.source, dictionaryFormat: definition.entry?.format ?? .plainText)
            self.readKnownCollectionCount()
        }
    }

    @objc private func lookupEditedWord() {
        guard let query = queryField?.stringValue else { return }
        let word = LookupWord(text: query.trimmingCharacters(in: .whitespacesAndNewlines),
                              sentence: lastSentence ?? "", bounds: .zero, confidence: 1, language: lastLanguage ?? sourceLanguage.hint)
        lookupAndShow(word, at: cardAnchor, source: activeVocabulary?.source, sourceMessage: sourceStatusMessage)
    }

    /// Total time includes capture and crop; result.elapsed measures OCR alone.
    private func presentMiss(_ result: LookupResult, elapsed: TimeInterval, mouse: CGPoint) {
        let timing = String(format: L("Total %.2f s · OCR %.2f s"), elapsed, result.elapsed)
        // Show recognized text to distinguish missing OCR from a pointer miss.
        let text = result.lines.isEmpty ? L("No nearby text was recognized.") : result.lines.prefix(6).joined(separator: "\n")
        show(title: L("No word selected"),
             body: L("Point directly at the target text and try again, avoiding spaces between words. Choose the text recognition language from the menu if automatic detection is inaccurate.\n\nNearby text:\n\(text)\n\n\(timing)\n\nThe subtitle may have changed, or capture may be unavailable."),
             at: mouse)
    }

    /// Show one card at a time, constrained to the pointer display's visible frame.
    /// Fullscreen collection behaviors still require real Safari acceptance testing.
    private func show(title: String, body: String, at mouse: CGPoint, word: LookupWord? = nil,
                      definition: String? = nil, pronunciation: String? = nil, loading: Bool = false,
                      dictionarySource: DictionarySource = .system, dictionaryFormat: DictionaryEntryFormat = .system) {
        cardRevision += 1
        // Preserve speech while the same word finishes loading; stop it when the content changes.
        if lastWord != word?.text { speaker.stop() }
        panel?.delegate = nil
        panel?.close()
        cardAnchor = mouse
        lastWord = word?.text
        lastLanguage = word?.language
        lastSentence = word?.sentence
        lastDefinition = definition
        lastDictionarySource = dictionarySource
        lastDictionaryFormat = dictionaryFormat
        queryField = nil
        speechStatus = nil
        correctionRow = nil
        correctionButton = nil
        collectionButton = nil
        collectionStatus = nil
        sourceSummary = nil
        sourceButton = nil
        cardLoading = loading
        if let word {
            if activeVocabulary?.word != word.text || activeVocabulary?.sentence != word.sentence {
                activeVocabulary = VocabularyEntry(word: word.text, definition: definition, sentence: word.sentence)
            } else { activeVocabulary?.definition = definition }
            activeVocabulary?.definitionFormat = dictionaryFormat
        } else { activeVocabulary = nil }
        let window = ResultPanel(contentRect: NSRect(x: 0, y: 0, width: 490, height: 360),
                                 styleMask: [.titled, .closable, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        window.title = appTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        let root = NSView()
        window.contentView = root
        let stack = NSStackView()
        cardStack = stack
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18)
        ])
        let heading = NSTextField(wrappingLabelWithString: title)
        heading.font = .systemFont(ofSize: 30, weight: .semibold)
        heading.isSelectable = true
        heading.setContentCompressionResistancePriority(.required, for: .vertical)
        if word != nil {
            let titleRow = NSStackView()
            titleRow.alignment = .centerY
            titleRow.spacing = 12
            heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            heading.setContentHuggingPriority(.required, for: .horizontal)
            titleRow.addArrangedSubview(heading)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            titleRow.addArrangedSubview(spacer)
            let play = NSButton(title: L("Pronounce"), target: self, action: #selector(speakWord))
            play.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: L("Pronounce word"))
            play.imagePosition = .imageLeading
            play.bezelStyle = .rounded
            play.toolTip = L("Read the word in its source language; click again to replay")
            play.setAccessibilityLabel(L("Pronounce word"))
            play.setContentHuggingPriority(.required, for: .horizontal)
            play.setContentCompressionResistancePriority(.required, for: .horizontal)
            titleRow.addArrangedSubview(play)
            stack.addArrangedSubview(titleRow)
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if let pronunciation {
                let display = pronunciation.replacingOccurrences(of: "BrE ", with: L("BrE  "))
                    .replacingOccurrences(of: ", AmE ", with: L("    AmE  "))
                    .replacingOccurrences(of: "AmE ", with: L("AmE  "))
                let phonetics = NSTextField(wrappingLabelWithString: display)
                phonetics.font = .systemFont(ofSize: 13)
                phonetics.textColor = .secondaryLabelColor
                phonetics.isSelectable = true
                stack.addArrangedSubview(phonetics)
                phonetics.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            let status = NSTextField(wrappingLabelWithString: "")
            status.font = .systemFont(ofSize: 11)
            status.textColor = .secondaryLabelColor
            stack.addArrangedSubview(status)
            status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            speechStatus = status
            speaker.onSpeakingChanged = { [weak self] _ in self?.updateSpeechStatus() }
            updateSpeechStatus()
        } else {
            stack.addArrangedSubview(heading)
            heading.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        if word != nil {
            let picker = NSPopUpButton()
            for source in dictionaryLibrary.sources {
                picker.addItem(withTitle: source.displayName)
                picker.lastItem?.representedObject = source.id
                if source.id == dictionarySource.id { picker.select(picker.lastItem) }
            }
            picker.target = self
            picker.action = #selector(selectCardDictionary(_:))
            picker.isEnabled = !loading && !dictionaryLibrary.isImporting
            picker.setAccessibilityLabel(L("Selected dictionary"))
            picker.setAccessibilityIdentifier("dictionary.card.selection")
            stack.addArrangedSubview(picker)
            picker.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        // Use selectable, scrollable native text for long dictionary entries.
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 446, height: 240))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.drawsBackground = false
        text.font = .systemFont(ofSize: 14)
        text.textContainerInset = NSSize(width: 4, height: 6)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.string = body
        scroll.documentView = text
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        if word != nil {
            let document = LookupCardBody(width: 446, definition: definition, message: body, word: word,
                                          format: dictionaryFormat, source: dictionarySource)
            scroll.documentView = document
            scroll.heightAnchor.constraint(equalToConstant: min(310, max(180, document.frame.height))).isActive = true
        } else {
            scroll.heightAnchor.constraint(equalToConstant: 240).isActive = true
        }
        if let word {
            let editRow = NSStackView()
            editRow.spacing = 8
            // Collapse correction controls initially so definitions and pronunciation remain prominent.
            editRow.isHidden = true
            correctionRow = editRow
            let field = NSTextField(string: word.text)
            // Disable editing during initial dictionary loading to protect in-progress corrections.
            field.isEnabled = !loading
            field.placeholderString = L("Edit the word and look it up again")
            field.target = self
            field.action = #selector(lookupEditedWord)
            field.widthAnchor.constraint(equalToConstant: 270).isActive = true
            editRow.addArrangedSubview(field)
            let lookup = NSButton(title: L("Look up"), target: self, action: #selector(lookupEditedWord))
            lookup.isEnabled = !loading
            lookup.bezelStyle = .rounded
            editRow.addArrangedSubview(lookup)
            stack.addArrangedSubview(editRow)
            queryField = field
            let sourceRow = NSStackView()
            sourceRow.spacing = 8
            let sourceLabel = NSTextField(wrappingLabelWithString: "")
            sourceLabel.font = .systemFont(ofSize: 11)
            sourceLabel.textColor = .secondaryLabelColor
            sourceLabel.maximumNumberOfLines = 2
            sourceLabel.heightAnchor.constraint(equalToConstant: 32).isActive = true
            sourceLabel.lineBreakMode = .byTruncatingMiddle
            sourceLabel.setAccessibilityLabel(L("Collection source label"))
            sourceRow.addArrangedSubview(sourceLabel)
            let editSource = NSButton(title: L("Source…"), target: self, action: #selector(editCollectionSource))
            sourceRow.addArrangedSubview(editSource)
            stack.addArrangedSubview(sourceRow)
            sourceRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            sourceLabel.widthAnchor.constraint(equalTo: sourceRow.widthAnchor, constant: -85).isActive = true
            editSource.widthAnchor.constraint(equalToConstant: 77).isActive = true
            sourceSummary = sourceLabel
            sourceButton = editSource
            let saveRow = NSStackView()
            saveRow.spacing = 10
            let save = NSButton(title: L("Set up notebook…"), target: self, action: #selector(collectWord))
            save.bezelStyle = .rounded
            save.contentTintColor = .controlAccentColor
            saveRow.addArrangedSubview(save)
            collectionButton = save
            let location = NSButton(title: L("Location…"), target: self, action: #selector(showNotesSettings))
            location.bezelStyle = .rounded
            saveRow.addArrangedSubview(location)
            let browse = NSButton(title: L("View vocabulary"), target: self, action: #selector(showVocabulary))
            browse.bezelStyle = .rounded
            saveRow.addArrangedSubview(browse)
            stack.addArrangedSubview(saveRow)
            let status = NSTextField(wrappingLabelWithString: "")
            status.font = .systemFont(ofSize: 11)
            status.textColor = .secondaryLabelColor
            status.isSelectable = true
            stack.addArrangedSubview(status)
            status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            collectionStatus = status
            refreshCollectionControls(loading: loading)
        }
        let buttons = NSStackView()
        buttons.spacing = 10
        if word != nil {
            let copy = NSButton(title: definition == nil ? L("Copy word") : L("Copy entry"), target: self, action: #selector(copyResult))
            copy.isEnabled = !loading
            copy.bezelStyle = .rounded
            buttons.addArrangedSubview(copy)
            copyButton = copy
            let correction = NSButton(title: L("Edit word"), target: self, action: #selector(toggleCorrection))
            correction.bezelStyle = .rounded
            correction.isEnabled = !loading
            buttons.addArrangedSubview(correction)
            correctionButton = correction
            let dictionary = NSButton(title: L("Dictionaries…"), target: self, action: #selector(showDictionaries))
            dictionary.bezelStyle = .rounded
            buttons.addArrangedSubview(dictionary)
        }
        let close = NSButton(title: L("Close (Esc)"), target: self, action: #selector(closePanel))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"
        buttons.addArrangedSubview(close)
        stack.addArrangedSubview(buttons)
        root.layoutSubtreeIfNeeded()
        if let document = scroll.documentView as? LookupCardBody {
            document.resizeToFit(width: scroll.contentSize.width)
        }
        let height = max(250, min(700, stack.fittingSize.height + 44))
        window.setContentSize(NSSize(width: 490, height: height))
        let visible = NSScreen.screens.first(where: { $0.frame.contains(mouse) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1000, height: 800)
        let x = max(visible.minX + 8, min(mouse.x + 18, visible.maxX - window.frame.width - 8))
        let y = max(visible.minY + 8, min(mouse.y - window.frame.height - 16, visible.maxY - window.frame.height - 8))
        window.setFrameOrigin(NSPoint(x: x, y: y))
        panel = window
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func speakWord() {
        guard let lastWord else { return }
        if let message = speaker.speak(lastWord, language: lastLanguage, context: lastSentence ?? "") { speechStatus?.stringValue = message }
    }

    @objc private func showNotesSettings() {
        if notesSettingsLanguage != UILocalization.currentLanguage {
            notesSettings?.close()
            notesSettings = nil
            notesSettingsLanguage = UILocalization.currentLanguage
        }
        if notesSettings == nil {
            notesSettings = NotesSettingsController(client: notesClient) { [weak self] configuration in
                self?.notesDestination = configuration.storage
                self?.notesReadingDestination = configuration.readingDestination
                self?.knownCollectionCount = nil
                self?.refreshCollectionControls()
                self?.readKnownCollectionCount()
                if self?.vocabularyBrowser?.window?.isVisible == true {
                    self?.vocabularyBrowser?.present(destination: configuration.readingDestination)
                }
            }
        }
        notesSettings?.present()
    }

    @objc private func showVocabulary() {
        guard AutomationConsent.state(for: "com.apple.Notes") == .granted else { showSettings(step: .notes); return }
        guard let target = notesReadingDestination ?? notesDestination else { showNotesSettings(); return }
        cardRevision += 1
        panel?.orderOut(nil)
        speaker.stop()
        if vocabularyBrowserLanguage != UILocalization.currentLanguage {
            vocabularyBrowser?.close()
            vocabularyBrowser = nil
            vocabularyBrowserLanguage = UILocalization.currentLanguage
        }
        let isTest = CommandLine.arguments.contains("--alphabet-library-preview") || CommandLine.arguments.contains("--multilingual-preview")
        if vocabularyBrowser == nil {
            vocabularyBrowser = VocabularyBrowser(client: notesClient, speaker: speaker, isTest: isTest) { [weak self] row in
                guard let self else { return }
                self.practiceOnly = false
                let word = LookupWord(text: row.word, sentence: row.sentences, bounds: .zero, confidence: 1)
                self.activeVocabulary = VocabularyEntry(word: row.word, definition: row.definition, sentence: row.sentences, isTestEntry: isTest)
                self.sourceStatusMessage = L("Opened from vocabulary. View existing sources in its details; a new collection can have its own source.")
                self.knownCollectionCount = row.count
                self.show(title: row.word, body: "", at: NSEvent.mouseLocation, word: word, definition: row.definition,
                          pronunciation: row.pronunciation.isEmpty ? nil : row.pronunciation)
            }
        }
        vocabularyBrowser?.present(destination: target)
    }

    private func readKnownCollectionCount() {
        guard !practiceOnly, AutomationConsent.state(for: "com.apple.Notes") == .granted,
              !cardLoading, let entry = activeVocabulary, let target = notesDestination else { return }
        Task { @MainActor in
            let row = try? await notesClient.existingWord(entry.word, in: target, isTest: entry.isTestEntry)
            guard activeVocabulary?.id == entry.id, notesDestination == target else { return }
            knownCollectionCount = row?.count
            refreshCollectionControls()
        }
    }

    #if WORDNEST_DEVELOPMENT
    private func testEntryID() -> UUID? {
        let prefix = "--notes-entry-id="
        return CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }).flatMap { UUID(uuidString: String($0.dropFirst(prefix.count))) }
    }

    /// Read back the specified test entry, then resubmit its ID to check deduplication; never create a missing entry.
    /// Leave existing notes unchanged and do not request screen capture.
    /// Reports contain checks only, excluding accounts, note bodies, and system identifiers.
    private func runNotesReadbackCheck() {
        AppleNotesClient.prepare()
        Task { @MainActor in
            var report = "FAIL: missing explicit test entry ID or configured destination"
            if let id = testEntryID(), let target = notesDestination {
                let definition = await Task.detached { SystemDictionary.lookup("happiness").entry?.text }.value
                let entry = VocabularyEntry(id: id, word: "happiness", definition: definition,
                    sentence: SampleText.value("Notes integration context"), isTestEntry: true)
                do {
                    if let original = try await notesClient.find(entry, in: target) {
                        // Resubmitting the ID must reuse the note; read it back to verify identity and content.
                        let repeated = try await notesClient.save(entry, to: target)
                        let after = try await notesClient.find(entry, in: target)
                        report = original == repeated && after == original
                            ? "PASS: full readback, repeated save reused original note, and final readback matched"
                            : "FAIL: repeated save did not preserve the same note"
                    } else { report = "FAIL: the explicit test entry was not found; no new note was created" }
                } catch { report = "FAIL: " + error.localizedDescription }
            }
            let file = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("notes-integration-result.txt")
            do { try report.write(to: file, atomically: true, encoding: .utf8) }
            catch { print("Could not write integration report: \(error.localizedDescription)") }
            print(report)
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    /// Exercise only marked A/H fixture pages; do not migrate or rewrite ordinary notes.
    private func runAlphabetIntegrationCheck() {
        AppleNotesClient.prepare()
        Task { @MainActor in
            var results: [String] = []
            func expect(_ value: Bool, _ name: String) { results.append((value ? "PASS: " : "FAIL: ") + name) }
            if let target = notesDestination {
                do {
                    let initial = try await notesClient.readVocabulary(from: target, isTest: true)
                    let baseline = initial.rows.first { $0.key == "happiness" }?.count ?? 0
                    let stamp = String(UUID().uuidString.prefix(8))
                    let definition = await Task.detached { SystemDictionary.lookup("happiness").entry?.text }.value
                    let first = VocabularyEntry(word: "happiness", definition: definition, sentence: "First table context \(stamp).", isTestEntry: true)
                    let receipt = try await notesClient.save(first, to: target)
                    expect(receipt.collectionCount == baseline + 1, "first occurrence increases count exactly once")
                    let duplicate = try await notesClient.save(first, to: target)
                    expect(duplicate == receipt, "retry of same occurrence reuses count and page")
                    let second = VocabularyEntry(word: "Happiness", definition: definition, sentence: "Another context \(stamp).", isTestEntry: true)
                    let repeated = try await notesClient.save(second, to: target)
                    expect(repeated.noteID == receipt.noteID && repeated.collectionCount == baseline + 2, "same word uses same H page and increments count")
                    let third = VocabularyEntry(word: "happiness", definition: definition, sentence: second.sentence, isTestEntry: true)
                    let again = try await notesClient.save(third, to: target)
                    expect(again.collectionCount == baseline + 3, "new occurrence increments even when context repeats")
                    let hello = VocabularyEntry(word: "hello", definition: SampleText.value("Hello meaning"), sentence: "Hello from table test.", isTestEntry: true)
                    let helloReceipt = try await notesClient.save(hello, to: target)
                    expect(helloReceipt.noteID == receipt.noteID, "another H word adds a row to the same page")
                    let apple = VocabularyEntry(word: "apple", definition: SampleText.value("Apple meaning"), sentence: "An apple a day.", isTestEntry: true)
                    let appleReceipt = try await notesClient.save(apple, to: target)
                    expect(appleReceipt.noteID != receipt.noteID, "A word creates a different letter page")
                    let loaded = try await notesClient.readVocabulary(from: target, isTest: true)
                    let row = loaded.rows.first { $0.key == "happiness" }
                    expect(loaded.warnings.isEmpty && row?.count == baseline + 3, "library reads native table cells and current count")
                    expect(row?.sentences.contains(first.sentence) == true && row?.sentences.contains(second.sentence) == true, "new contexts are preserved")
                    expect(row?.sentences.components(separatedBy: "\n").filter { $0 == second.sentence }.count == 1, "identical context is not duplicated")
                    let reopened = AppleNotesClient()
                    let persisted = try await reopened.save(first, to: target)
                    expect(persisted.collectionCount == baseline + 3, "new client reads persisted event journal and does not increment retry")
                    let found = try await reopened.find(second, in: target)
                    expect(found?.collectionCount == baseline + 3, "reconciliation returns current count without adding an occurrence")
                } catch { results.append("FAIL: " + error.localizedDescription) }
            } else { results.append("FAIL: no configured Notes destination") }
            let report = results.joined(separator: "\n")
            try? report.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("alphabet-integration-result.txt"), atomically: true, encoding: .utf8)
            print(report)
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    /// Write only marked script-category fixtures to test Unicode, legacy A-Z data, and persistent deduplication.
    private func runMultilingualIntegrationCheck() {
        AppleNotesClient.prepare()
        Task { @MainActor in
            var results: [String] = []
            func expect(_ value: Bool, _ name: String) { results.append((value ? "PASS: " : "FAIL: ") + name) }
            if let target = notesDestination {
                do {
                    let initial = try await notesClient.readVocabulary(from: target, isTest: true)
                    var written: [VocabularyEntry] = []
                    for (word, context) in [("école", "Une école près de chez moi."), (SampleText.value("Japanese study word"), SampleText.value("Japanese study context")),
                        ("ありがとう", SampleText.value("Japanese thanks context")), ("안녕하세요", "안녕하세요. 만나서 반갑습니다."),
                        ("привет", "Я сказал привет другу."), ("مرحبا", "مرحبا بك في البيت.")] {
                        let baseline = initial.rows.first { $0.key == BookRow.key(word) }?.count ?? 0
                        let entry = VocabularyEntry(word: word, definition: nil, sentence: context, isTestEntry: true)
                        let receipt = try await notesClient.save(entry, to: target)
                        let duplicate = try await AppleNotesClient().save(entry, to: target)
                        expect(receipt.collectionCount == baseline + 1 && duplicate == receipt, "Unicode save and persisted retry: \(word)")
                        written.append(entry)
                    }
                    let loaded = try await notesClient.readVocabulary(from: target, isTest: true)
                    expect(loaded.warnings.isEmpty, "all script pages are readable without warnings")
                    for entry in written {
                        let row = loaded.rows.first { $0.key == BookRow.key(entry.word) }
                        expect(row?.sentences.contains(entry.sentence) == true, "original context round trips: \(entry.word)")
                    }
                    expect(initial.rows.filter { ["happiness", "hello", "apple"].contains($0.key) }.allSatisfy { old in loaded.rows.contains(old) }, "legacy A-Z rows and counts remain unchanged")
                } catch { results.append("FAIL: " + error.localizedDescription) }
            } else { results.append("FAIL: no configured Notes destination") }
            let report = results.joined(separator: "\n")
            try? report.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("multilingual-integration-result.txt"), atomically: true, encoding: .utf8)
            print(report)
            fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    #endif

    @objc private func collectWord() {
        guard !practiceOnly else { return }
        guard AutomationConsent.state(for: "com.apple.Notes") == .granted else { showSettings(step: .notes); return }
        guard !cardLoading else { return }
        guard let entry = activeVocabulary else { return }
        guard let target = notesDestination else { showNotesSettings(); return }
        if case .needsConfiguration = collector.state(for: entry, destination: target) { showNotesSettings(); return }
        AppleNotesClient.prepare()
        // Disable immediately on the main thread before a second click can enter the event queue.
        collectionButton?.isEnabled = false
        updateSourceControls()
        Task { @MainActor in
            // Refresh only the current card; an older save must not reopen or replace a newer lookup.
            await collector.collect(entry, to: target)
            if CommandLine.arguments.contains("--notes-integration-preview"), case .saved = collector.state(for: entry, destination: target) {
                print("NOTES_SAVE_OK: saved and read back generated entry; destination not logged")
                fflush(stdout)
            }
        }
    }

    private func refreshCollectionControls(loading: Bool = false) {
        defer { updateSourceControls() }
        guard let button = collectionButton, let label = collectionStatus, let entry = activeVocabulary else { return }
        button.isEnabled = !practiceOnly && !loading && !cardLoading
        label.textColor = .secondaryLabelColor
        guard let target = notesDestination else {
            button.title = L("Set up notebook…")
            label.stringValue = L("Choose a Notes account and folder to save this word.")
            return
        }
        switch collector.state(for: entry, destination: target) {
        case .idle:
            button.title = (knownCollectionCount ?? 0) > 0 ? L("Collect again") : L("Save to Notes")
            label.stringValue = target.displayName + (knownCollectionCount.map { L(" · Collected \($0) times") } ?? "")
        case .saving:
            button.title = L("Saving…")
            button.isEnabled = false
            label.stringValue = L("Saving to \(target.displayName)")
        case .saved(let receipt):
            button.title = L("Saved ✓")
            button.isEnabled = false
            label.stringValue = L("Saved to \(target.displayName)") + (receipt.collectionCount.map { L(" · \($0) collections total") } ?? "")
        case .failed(let message):
            button.title = L("Retry save")
            label.stringValue = message
            label.textColor = .systemRed
        case .needsConfiguration(let message):
            button.title = L("Set save location…")
            label.stringValue = message
            label.textColor = .systemRed
        case .uncertain(let message):
            button.title = L("Verify save")
            label.stringValue = L("\(message) Verification does not add another collection.")
            label.textColor = .systemOrange
        }
        // Resize for multiline errors without pushing the close button outside the window.
        if let panel, let root = panel.contentView, let stack = cardStack, stack.superview === root {
            root.layoutSubtreeIfNeeded()
            let top = panel.frame.maxY
            panel.setContentSize(NSSize(width: 490, height: max(250, min(700, stack.fittingSize.height + 44))))
            let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: max(visible.minY + 8, top - panel.frame.height)))
        }
    }

    private var canEditCollectionSource: Bool {
        guard !practiceOnly, !cardLoading, collectionButton?.isEnabled != false, let entry = activeVocabulary else { return false }
        guard let target = notesDestination else { return true }
        switch collector.state(for: entry, destination: target) {
        case .idle, .failed: return true
        default: return false
        }
    }

    private func updateSourceControls() {
        if let source = activeVocabulary?.source {
            let heading = "\(UILocalization.key(source.kind)) · " + (source.title.isEmpty ? L("Title unavailable") : source.title)
            sourceSummary?.stringValue = heading + "\n" + source.url
            sourceSummary?.toolTip = source.title.isEmpty ? source.url : source.title + "\n" + source.url
        } else {
            sourceSummary?.stringValue = sourceStatusMessage
            sourceSummary?.toolTip = sourceStatusMessage
        }
        sourceButton?.isEnabled = canEditCollectionSource
    }

    @objc private func editCollectionSource() {
        guard canEditCollectionSource, let entry = activeVocabulary else { return }
        sourceEditor = SourceEditorController(source: entry.source) { [weak self] source in
            guard let self, self.canEditCollectionSource, self.activeVocabulary?.id == entry.id else { return false }
            self.activeVocabulary?.source = source
            self.sourceStatusMessage = source == nil ? L("No source link for this collection.") : L("Source set for this collection.")
            self.updateSourceControls()
            return true
        }
        sourceEditor?.present()
    }

    #if WORDNEST_DEVELOPMENT
    @objc private func openWebAppSourcePermissions() {
        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
        show(title: trusted ? L("Website app source access is enabled") : L("Allow source links from website apps"),
             body: L("Bilibili website apps in the Dock expose their current page URL through Accessibility. Enable this app in the Accessibility list, return to your video, and point at a subtitle word to look it up.\n\nReading happens only during lookup and is limited to the active website window's page URL and title. macOS controls this permission; you can still enter a source manually without it.\n\nCurrent app path:\n\(Bundle.main.bundleURL.path)"), at: NSEvent.mouseLocation)
    }

    /// Interactive acceptance reads a foreground Dock web app without capture, Notes writes, or hotkey registration.
    /// Test the final bundle so permission granted to a diagnostic copy cannot produce a false pass.
    private func runSourceReadbackCheck() {
        let prefix = "--source-test-bundle="
        let expectedBundle = CommandLine.arguments.first(where: { $0.hasPrefix(prefix) }).map { String($0.dropFirst(prefix.count)) }
        Task { @MainActor in
            let deadline = ProcessInfo.processInfo.systemUptime + 120
            var report = "UNVERIFIED: Enable Accessibility and bring the Dock Bilibili video window forward, with the pointer over the video."
            while ProcessInfo.processInfo.systemUptime < deadline {
                if AXIsProcessTrusted(), let foreground = NSWorkspace.shared.frontmostApplication,
                   let bundle = foreground.bundleIdentifier, bundle.hasPrefix("com.apple.Safari.WebApp."), expectedBundle == nil || expectedBundle == bundle {
                    let context = SourceCaptureContext(bundleID: bundle, pointer: NSEvent.mouseLocation,
                        primaryScreenTop: NSScreen.screens.first?.frame.maxY ?? 0, processID: foreground.processIdentifier)
                    let result = await pageReader.capture(context)
                    if let source = result.source {
                        report = "PASS: Read back the current Dock website app URL and title.\nKind: \(source.kind)\nTitle: \(source.title)\nURL: \(source.url)"
                        break
                    }
                    report = "UNVERIFIED: " + result.message
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            let file = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("source-capture-result.txt")
            try? report.write(to: file, atomically: true, encoding: .utf8)
            print(report); fflush(stdout)
            NSApp.terminate(nil)
        }
    }

    #endif

    @objc private func toggleCorrection() {
        guard let row = correctionRow, let panel, let root = panel.contentView, let stack = cardStack else { return }
        row.isHidden.toggle()
        correctionButton?.title = row.isHidden ? L("Edit word") : L("Hide editor")
        let top = panel.frame.maxY
        root.layoutSubtreeIfNeeded()
        panel.setContentSize(NSSize(width: 490, height: max(250, min(700, stack.fittingSize.height + 44))))
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: max(visible.minY + 8, top - panel.frame.height)))
        if !row.isHidden { queryField?.selectText(nil) }
    }

    private func updateSpeechStatus() {
        if speaker.isSpeaking {
            speechStatus?.stringValue = L("Speaking… · Click to replay")
        } else if let voice = speaker.voiceForWord(lastWord ?? "", language: lastLanguage, context: lastSentence ?? "") {
            let accent = voice.language == "en-US" ? L("American English") : voice.language == "en-GB" ? L("British English") : LanguageSupport.displayName(voice.language)
            speechStatus?.stringValue = L("\(accent) · Click Pronounce to listen")
        } else {
            speechStatus?.stringValue = L("No matching system voice was found. Add one in System Settings.")
        }
    }

    /// Write the clipboard only on an explicit Copy action; lookup never takes over its contents.
    @objc private func copyResult() {
        guard let lastWord, let lastSentence else { return }
        NSPasteboard.general.clearContents()
        let content = [lastWord, lastDefinition, lastSentence].compactMap { $0 }.joined(separator: "\n\n")
        NSPasteboard.general.setString(content, forType: .string)
        copyButton?.title = L("Copied")
    }

    @objc private func closePanel() {
        cardRevision += 1
        speaker.stop()
        panel?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // The title-bar close button must invalidate pending results just like Escape.
        cardRevision += 1
        speaker.stop()
    }

    /// Exercise real AppKit layouts for long, missing, and loading entries using fixed data.
    /// These layout checks do not replace the complete Safari workflow acceptance test.
    #if WORDNEST_DEVELOPMENT
    private func runCardSelfChecks() {
        let previousLanguage = UILocalization.languageOverride
        UILocalization.languageOverride = .simplifiedChinese
        defer { UILocalization.languageOverride = previousLanguage }
        rebuildMenu()
        // Layout checks must not connect to Notes or change saved destinations.
        notesDestination = nil
        var failures: [String] = []
        var checks = 0
        func expect(_ condition: Bool, _ label: String) {
            checks += 1
            if !condition { failures.append(label) }
        }
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let word = LookupWord(text: "reluctant", sentence: "I was reluctant to accept the offer.",
                              bounds: .zero, confidence: 1)
        let longText = String(repeating: SampleText.value("Long card definition fragment"), count: 60)
        show(title: word.text, body: longText, at: NSEvent.mouseLocation, word: word, definition: longText)
        if let root = panel?.contentView {
            root.layoutSubtreeIfNeeded()
            let views = descendants(root)
            let scroll = views.compactMap { $0 as? NSScrollView }.first
            let document = scroll?.documentView
            let labels = document.map(descendants)?.compactMap { $0 as? NSTextField } ?? []
            expect(labels.contains { $0.stringValue == longText.trimmingCharacters(in: .whitespacesAndNewlines) }, "long definition remains intact in structured card")
            expect(scroll?.hasVerticalScroller == true, "dictionary card has vertical scrolling")
            expect((document?.frame.height ?? 0) > (scroll?.contentView.bounds.height ?? .greatestFiniteMagnitude),
                   "long dictionary document exceeds viewport and can scroll")
            let buttons = views.compactMap { $0 as? NSButton }
            expect(buttons.count == 11, "card includes a dictionary picker alongside source, speech and collection controls")
            let previewSource = PageSourceReader.sourceFromWebArea(url: "https://example.com/wordnest-test", title: "",
                description: "Fixed source preview", windowTitle: "WordNest")!
            activeVocabulary?.source = previewSource
            updateSourceControls()
            expect(sourceSummary?.stringValue.contains(previewSource.url) == true && sourceButton?.isEnabled == true, "ready card shows and allows editing its frozen source URL")
            expect(sourceSummary?.stringValue.contains("Fixed source preview") == true, "title recovered from WebArea metadata reaches the visible card")
            activeVocabulary?.source = CollectionSource(url: previewSource.url)
            updateSourceControls()
            expect(sourceSummary?.stringValue == SampleText.value("Untitled webpage source summary") + previewSource.url && sourceSummary?.toolTip == previewSource.url,
                   "an untitled source shows its URL once and does not invent a stored title")
            activeVocabulary?.source = previewSource
            updateSourceControls()
            for button in buttons where !button.isHiddenOrHasHiddenAncestor {
                expect(root.bounds.insetBy(dx: -1, dy: -1).contains(button.convert(button.bounds, to: root)),
                       "button stays inside card: \(button.title)")
            }
            expect(queryField?.isEnabled == true && copyButton?.isEnabled == true, "ready card allows editing and copying")
            expect(collectionButton?.title == SampleText.value("Set up notebook…"), "unconfigured collection leads to setup rather than claiming saved")
            notesDestination = NotesDestination(accountID: "test-account", accountName: SampleText.value("Test account name"), folderID: "test-folder", folderName: SampleText.value("Test vocabulary folder name"))
            refreshCollectionControls()
            expect(collectionButton?.title == SampleText.value("Save to Notes") && collectionStatus?.stringValue == SampleText.value("Configured test notebook display"), "configured collection shows exact target")
            knownCollectionCount = 3
            refreshCollectionControls()
            expect(collectionButton?.title == SampleText.value("Collect again") && collectionStatus?.stringValue.contains(SampleText.value("Existing collection counter")) == true, "existing word displays count before deliberate recollection")
            knownCollectionCount = nil
            refreshCollectionControls()
            expect(correctionRow?.isHidden == true, "correction input is collapsed for reading")
            toggleCorrection()
            expect(correctionRow?.isHidden == false && panel?.firstResponder != nil, "correction action reveals editable query")
            toggleCorrection()
        } else {
            expect(false, "result card content view exists")
        }
        let frozenSource = activeVocabulary?.source
        show(title: word.text, body: longText, at: cardAnchor, word: word, definition: longText)
        expect(activeVocabulary?.source == frozenSource && sourceSummary?.stringValue.contains("https://example.com/wordnest-test") == true, "dictionary card replacement preserves the lookup source snapshot")
        // Use the reported dictionary entry to verify visual hierarchy, not merely text presence.
        let happiness = LookupWord(text: "happiness", sentence: "path to happiness was/succ", bounds: .zero, confidence: 1)
        let entry = SampleText.value("Happiness complete entry")
        show(title: happiness.text, body: "", at: cardAnchor, word: happiness, definition: entry,
             pronunciation: DictionaryEntry(query: happiness.text, text: entry).pronunciation)
        if let root = panel?.contentView {
            let labels = descendants(root).compactMap { $0 as? NSTextField }
            expect(labels.contains { $0.stringValue == SampleText.value("Noun · uncountable") }, "grammar is a separate label")
            expect(labels.contains { $0.stringValue == SampleText.value("Happiness meaning with pinyin") }, "Chinese meaning has a dedicated field")
            expect(labels.contains { $0.stringValue == SampleText.value("Happiness first example display") }, "dictionary example separates English and Chinese")
            expect(labels.contains { $0.stringValue == happiness.sentence }, "subtitle source remains separate and unchanged")
            let context = labels.first { $0.stringValue == happiness.sentence }
            let range = (happiness.sentence as NSString).range(of: happiness.text)
            let color = context?.attributedStringValue.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
            expect(color == NSColor.controlAccentColor, "query word is highlighted in subtitle source")
            expect(speaker.isSpeaking == false, "showing lookup card does not automatically speak")
        }
        show(title: word.text, body: SampleText.value("Loading card text"), at: cardAnchor, word: word, loading: true)
        expect(queryField?.isEnabled == false && copyButton?.isEnabled == false, "loading state protects input from asynchronous replacement")
        expect(collectionButton?.isEnabled == false, "dictionary loading cannot save an incomplete entry")
        if let root = panel?.contentView {
            let play = descendants(root).compactMap { $0 as? NSButton }.first { $0.action == #selector(speakWord) }
            expect(play?.isEnabled == true, "word can be spoken while dictionary is loading")
        }
        show(title: word.text, body: DictionaryLookup.notFound(word.text).displayText, at: cardAnchor, word: word)
        expect(queryField?.isEnabled == true, "missing definition allows correcting query")
        expect(lastDefinition == nil, "missing definition never reuses previous definition")
        let revision = cardRevision
        panel?.close()
        expect(cardRevision > revision, "titlebar close invalidates pending dictionary results")
        let titles = statusItem.menu?.items.map(\.title) ?? []
        expect(titles.contains(SampleText.value("Settings…")) && !titles.contains(where: { $0.contains(SampleText.value("Permission label fragment")) || $0.contains(SampleText.value("Screen recording label fragment")) }), "public menu consolidates permission actions into Settings")
        showPractice()
        expect(collectionButton?.isEnabled == false && practiceOnly, "setup practice cannot collect a fixed fixture into the real notebook")
        practiceOnly = false
        let settings = NotesSettingsController(client: notesClient) { _ in }
        if let root = settings.window?.contentView {
            root.layoutSubtreeIfNeeded()
            let views = descendants(root)
            let buttons = views.compactMap { $0 as? NSButton }
            let connect = buttons.first { $0.title == SampleText.value("Connect to Notes") }
            let choose = buttons.first { $0.title == SampleText.value("Save settings") }
            expect(connect?.isEnabled == true && choose?.isEnabled == false, "settings waits for explicit connection and selection")
            expect(views.compactMap { $0 as? NSPopUpButton }.allSatisfy { $0.numberOfItems == 0 }, "settings initialization does not query Notes")
            expect(views.compactMap { $0 as? NSPopUpButton }.count == 3, "settings separates storage and browsing folder choices")
            expect(buttons.contains { $0.title == SampleText.value("Use a separate browsing location (Smart Folders supported)") }, "Smart Folder browsing is an explicit optional selection")
            for button in buttons where !button.isHiddenOrHasHiddenAncestor {
                expect(root.bounds.insetBy(dx: -1, dy: -1).contains(button.convert(button.bounds, to: root)), "settings control stays inside window: \(button.title)")
            }
        } else { expect(false, "notes settings content exists") }
        let browser = VocabularyBrowser(client: notesClient, speaker: speaker) { _ in }
        if let root = browser.window?.contentView {
            root.layoutSubtreeIfNeeded()
            let views = descendants(root)
            let table = views.compactMap { $0 as? NSTableView }.first
            expect((table?.frame.width ?? .infinity) <= (table?.enclosingScrollView?.contentView.bounds.width ?? 0), "all browser columns fit the default window")
            expect(table?.tableColumns.map { $0.title } == [SampleText.value("Word"), SampleText.value("Definition"), SampleText.value("Collections"), SampleText.value("Original text"), SampleText.value("First collected")], "browser exposes word, meaning, count, context and date columns")
            expect(table?.numberOfRows == 0, "browser initialization does not connect to Notes")
            expect(views.compactMap { $0 as? NSPopUpButton }.first?.numberOfItems == BookRow.pageNames.count + 1, "browser offers alphabet and non-Latin script filters")
            expect(views.contains { $0 is NSSearchField }, "browser offers vocabulary search")
            expect(views.compactMap { $0 as? NSPopUpButton }.count == 2, "browser offers an independent source filter")
            expect(views.compactMap { $0 as? NSButton }.first(where: { $0.title == SampleText.value("Export analysis data…") })?.isEnabled == false, "export waits for a successfully read vocabulary snapshot")
            for button in views.compactMap({ $0 as? NSButton }) where !button.isHiddenOrHasHiddenAncestor {
                expect(root.bounds.insetBy(dx: -1, dy: -1).contains(button.convert(button.bounds, to: root)), "browser control stays inside window: \(button.title)")
            }
        } else { expect(false, "vocabulary browser content exists") }
        let sameTitleSources = VocabularyBrowser.sourceMenu([
            SourceSummary(identityURL: "https://example.com/first", title: SampleText.value("Same title video sample"), wordCount: 1, collectionCount: 1),
            SourceSummary(identityURL: "https://example.com/second", title: SampleText.value("Same title video sample"), wordCount: 1, collectionCount: 1)
        ])
        expect(sameTitleSources.items.count == 4, "same-titled videos remain separate source menu items")
        expect((sameTitleSources.items[2].representedObject as? String) != (sameTitleSources.items[3].representedObject as? String), "source selection is bound to URL rather than menu title or shifted index")
        let sourceEditor = SourceEditorController(source: CollectionSource(url: "https://example.com/test", title: "Test source")) { _ in true }
        if let root = sourceEditor.window?.contentView {
            root.layoutSubtreeIfNeeded()
            let fields = descendants(root).compactMap { $0 as? NSTextField }
            expect(fields.contains { $0.stringValue == "https://example.com/test" }, "manual source editor starts with current snapshot")
            for button in descendants(root).compactMap({ $0 as? NSButton }) {
                expect(root.bounds.insetBy(dx: -1, dy: -1).contains(button.convert(button.bounds, to: root)), "source editor button stays inside window: \(button.title)")
            }
        } else { expect(false, "source editor content exists") }
        expect(languageMenu.items.count == SourceLanguage.allCases.count, "source language menu exposes every preset")
        expect(languageMenu.items.filter { $0.state == .on }.count == 1, "exactly one source language is selected")
        let japaneseWord = LookupWord(text: SampleText.value("Japanese study word"), sentence: SampleText.value("Japanese study context"), bounds: .zero, confidence: 1, language: "ja-JP")
        show(title: SampleText.value("Japanese study word"), body: "", at: cardAnchor, word: japaneseWord, definition: SampleText.value("Japanese card explanation"))
        if let root = panel?.contentView {
            let labels = descendants(root).compactMap { $0 as? NSTextField }
            expect(labels.contains { $0.stringValue == SampleText.value("Japanese card explanation") }, "Japanese dictionary text remains intact")
            expect(labels.contains { $0.stringValue.contains(SampleText.value("Unconfirmed Chinese definition guidance")) }, "Japanese dictionary text is not presented as a Chinese translation")
            expect(speechStatus?.stringValue.contains(SampleText.value("Japanese")) == true || speechStatus?.stringValue.contains(SampleText.value("Missing resource guidance fragment")) == true, "Japanese card chooses Japanese voice or reports a missing voice")
            expect(!speaker.isSpeaking, "multilingual lookup does not automatically speak")
        } else { expect(false, "Japanese card content exists") }
        UILocalization.languageOverride = .english
        rebuildMenu()
        expect(statusItem.menu?.items.contains { $0.title == "Settings…" } == true, "language change updates the app menu without restart")
        show(title: word.text, body: "", at: cardAnchor, word: word, definition: SampleText.value("Reluctant entry body"))
        if let root = panel?.contentView {
            root.layoutSubtreeIfNeeded()
            let views = descendants(root)
            let buttons = views.compactMap { $0 as? NSButton }.filter { !$0.isHiddenOrHasHiddenAncestor }
            expect(buttons.contains { $0.title == "Pronounce" }, "English card offers translated pronunciation control")
            expect(views.compactMap { $0 as? NSTextField }.contains { $0.stringValue == SampleText.value("Reluctant meaning") }, "English interface never translates dictionary content")
            for button in buttons {
                expect(root.bounds.insetBy(dx: -1, dy: -1).contains(button.convert(button.bounds, to: root)), "English card control fits: \(button.title)")
            }
        } else { expect(false, "English card content exists") }
        let englishBrowser = VocabularyBrowser(client: notesClient, speaker: speaker) { _ in }
        if let root = englishBrowser.window?.contentView {
            let table = descendants(root).compactMap { $0 as? NSTableView }.first
            expect(table?.tableColumns.first?.title == "Word", "English notebook headers are translated without rewriting Notes")
            expect(table?.numberOfRows == 0, "English notebook fixture does not read Notes")
        }
        englishBrowser.close()
        let localText = "A | B; BrE is ordinary text here.\nKeep every definition ▸ and example."
        let localSource = DictionarySource(id: "fixture", name: "WordNest Test Dictionary", kind: .mdx)
        for language in [ResolvedUILanguage.english, .simplifiedChinese] {
            UILocalization.languageOverride = language
            show(title: word.text, body: "", at: NSEvent.mouseLocation, word: word, definition: localText,
                 dictionarySource: localSource, dictionaryFormat: .plainText)
            if let root = panel?.contentView {
                let fields = descendants(root).compactMap { $0 as? NSTextField }
                expect(fields.contains { $0.stringValue == localText }, "MDX card retains complete plain text in \(language.rawValue)")
                expect(fields.contains { $0.stringValue.contains(localSource.name) }, "MDX card labels the actual source in \(language.rawValue)")
                expect(activeVocabulary?.definitionFormat == .plainText, "MDX collection retains its format without rewriting the Notes schema")
            }
            let suite = "WordNest.DictionaryLayout.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let settings = DictionarySettingsController(library: DictionaryLibrary(defaults: defaults), onChange: {})
            if let root = settings.window?.contentView {
                root.layoutSubtreeIfNeeded()
                for field in descendants(root).compactMap({ $0 as? NSTextField }) {
                    expect(root.bounds.insetBy(dx: -1, dy: -1).contains(field.convert(field.bounds, to: root)), "dictionary settings text fits: \(language.rawValue)")
                }
            }
            settings.close()
            defaults.removePersistentDomain(forName: suite)
        }
        print("UI_SELF_TEST: \(checks) checks; \(failures.count) failures; fixed data only, no Notes connection")
        for failure in failures { print("FAIL: \(failure)") }
        fflush(stdout)
        if failures.isEmpty { NSApp.terminate(nil) }
        else { exit(1) }
    }

    #endif

    func applicationWillTerminate(_ notification: Notification) {
        speaker.stop()
        // Unregister global events before the Swift owner of the C callback is destroyed.
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

@main
struct PrototypeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // NSApplication does not retain its delegate; keep it alive throughout the blocking event loop.
        withExtendedLifetime(delegate) { app.run() }
    }
}
