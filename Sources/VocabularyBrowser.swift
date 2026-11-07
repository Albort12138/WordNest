import AppKit
import UniformTypeIdentifiers

/// Refresh from the chosen Notes folder; search and category filters apply only to that read snapshot.
@MainActor final class VocabularyBrowser: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let client: AppleNotesClient
    private let speaker: WordSpeaker
    private let onOpen: (BookRow) -> Void
    private let isTest: Bool
    private var destination: NotesDestination?
    private var library = VocabularyLibrary()
    private var visible: [BookRow] = []
    private var revision = 0
    private let search = NSSearchField()
    private let letters = NSPopUpButton()
    private let sources = NSPopUpButton()
    private let exportButton = NSButton(title: L("Export analysis data…"), target: nil, action: nil)
    private let refreshButton = NSButton(title: L("Refresh"), target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: L("The notebook has not been read yet."))
    private let table = NSTableView()
    private let detail = NSTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 150))
    private let speakButton = NSButton(title: L("Pronounce word"), target: nil, action: nil)
    private let openButton = NSButton(title: L("View entry"), target: nil, action: nil)

    init(client: AppleNotesClient, speaker: WordSpeaker, isTest: Bool = false, onOpen: @escaping (BookRow) -> Void) {
        self.client = client
        self.speaker = speaker
        self.isTest = isTest
        self.onOpen = onOpen
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = isTest ? L("My vocabulary · Table test") : L("My vocabulary · Apple Notes")
        window.minSize = NSSize(width: 760, height: 530)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let root = window.contentView else { return }
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)
        ])
        let toolbar = NSStackView()
        toolbar.spacing = 10
        letters.addItem(withTitle: L("All categories"))
        // Display names are localized; filtering must retain the persisted category identifiers.
        for category in BookRow.pageNames {
            letters.menu?.addItem(NSMenuItem(title: Self.categoryTitle(category), action: nil, keyEquivalent: ""))
            letters.lastItem?.representedObject = category
        }
        letters.target = self
        letters.action = #selector(filterChanged)
        letters.setAccessibilityLabel(L("Filter by letter or script"))
        letters.widthAnchor.constraint(equalToConstant: 120).isActive = true
        toolbar.addArrangedSubview(letters)
        sources.addItems(withTitles: [L("All sources"), L("No source recorded")])
        sources.lastItem?.representedObject = ""
        sources.target = self; sources.action = #selector(filterChanged)
        sources.setAccessibilityLabel(L("Filter by video or webpage source"))
        sources.widthAnchor.constraint(equalToConstant: 220).isActive = true
        toolbar.addArrangedSubview(sources)
        search.placeholderString = L("Search words, definitions, context, or sources")
        search.delegate = self
        search.target = self
        search.action = #selector(filterChanged)
        search.sendsSearchStringImmediately = true
        toolbar.addArrangedSubview(search)
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        toolbar.addArrangedSubview(refreshButton)
        stack.addArrangedSubview(toolbar)
        toolbar.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.isSelectable = true
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        table.dataSource = self
        table.delegate = self
        table.style = .plain
        table.rowHeight = 34
        // AppKit intercell spacing adds width; the default window should show both the word and count.
        table.intercellSpacing = NSSize(width: 4, height: 4)
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsMultipleSelection = false
        table.target = self
        table.doubleAction = #selector(openSelected)
        let columns: [(String, String, CGFloat)] = [("word", L("Word"), 145), ("meaning", L("Definition"), 255), ("count", L("Collections"), 80), ("context", L("Original text"), 300), ("date", L("First collected"), 135)]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = id == "count" ? 65 : 90
            table.addTableColumn(column)
        }
        scroll.documentView = table
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
        let details = NSScrollView()
        details.hasVerticalScroller = true
        detail.isEditable = false
        detail.isSelectable = true
        detail.font = .systemFont(ofSize: 13)
        detail.textContainerInset = NSSize(width: 10, height: 10)
        detail.isVerticallyResizable = true
        detail.isHorizontallyResizable = false
        detail.autoresizingMask = [.width]
        detail.textContainer?.widthTracksTextView = true
        detail.textContainer?.lineBreakMode = .byWordWrapping
        details.documentView = detail
        stack.addArrangedSubview(details)
        details.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        details.heightAnchor.constraint(equalToConstant: 150).isActive = true
        let buttons = NSStackView()
        buttons.spacing = 10
        for (button, action) in [(speakButton, #selector(speakSelected)), (openButton, #selector(openSelected))] {
            button.target = self
            button.action = action
            button.isEnabled = false
            buttons.addArrangedSubview(button)
        }
        stack.addArrangedSubview(buttons)
        exportButton.target = self; exportButton.action = #selector(exportAnalysis)
        exportButton.isEnabled = false
        buttons.addArrangedSubview(exportButton)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present(destination: NotesDestination) {
        self.destination = destination
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        refresh()
    }

    @objc private func refresh() {
        guard let destination else { return }
        revision += 1
        let version = revision
        library = VocabularyLibrary()
        rebuildSources()
        applyFilter()
        refreshButton.isEnabled = false
        status.stringValue = L("Reading \(destination.displayName)…")
        AppleNotesClient.prepare()
        Task { @MainActor in
            do {
                let result = try await client.readVocabulary(from: destination, isTest: isTest)
                guard revision == version else { return }
                library = result
                rebuildSources()
                applyFilter()
            } catch {
                guard revision == version else { return }
                status.stringValue = error.localizedDescription
            }
            if revision == version { refreshButton.isEnabled = true }
        }
    }

    @objc private func filterChanged() { applyFilter() }
    private var selectedSource: String? { sources.selectedItem?.representedObject as? String }
    private static func categoryTitle(_ category: String) -> String {
        switch category {
        case LegacyNotesText.value("Han characters"): return L("Han characters")
        case LegacyNotesText.value("Kana"): return L("Kana")
        case LegacyNotesText.value("Hangul"): return L("Hangul")
        case LegacyNotesText.value("Cyrillic"): return L("Cyrillic")
        case LegacyNotesText.value("Greek"): return L("Greek")
        case LegacyNotesText.value("Arabic script category"): return L("Arabic script category")
        case LegacyNotesText.value("Thai script category"): return L("Thai script category")
        case LegacyNotesText.value("Other scripts"): return L("Other scripts")
        default: return category
        }
    }
    /// NSPopUpButton.addItems merges duplicate titles. Bind sources by URL, not by title or menu index.
    static func sourceMenu(_ summaries: [SourceSummary]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (title, identifier) in [(L("All sources"), Optional<String>.none), (L("No source recorded"), Optional(""))]
            + summaries.map({ (L("\($0.title) · \($0.wordCount) words / \($0.collectionCount) collections · \($0.identityURL)"), Optional($0.identityURL)) }) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = identifier
            item.toolTip = identifier
            menu.addItem(item)
        }
        return menu
    }
    private func rebuildSources() {
        let previous = selectedSource
        let summaries = library.sourceSummaries
        sources.menu = Self.sourceMenu(summaries)
        sources.selectItem(at: sources.itemArray.firstIndex(where: { ($0.representedObject as? String) == previous }) ?? 0)
        exportButton.isEnabled = !library.rows.isEmpty
    }
    func controlTextDidChange(_ notification: Notification) { applyFilter() }
    private func applyFilter() {
        let letter = letters.selectedItem?.representedObject as? String
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visible = library.filtered(letter: letter, query: query).filter { $0.collectionCount(in: selectedSource) > 0 }
        sources.toolTip = selectedSource
        table.tableColumns.first(where: { $0.identifier.rawValue == "count" })?.title = selectedSource == nil ? L("Collections") : L("From this source")
        // Filtering may assign the same row index to a different word; clear stale selection, details, and button state.
        table.deselectAll(nil)
        table.reloadData()
        detail.string = library.warnings.isEmpty ? L("Select a word to view its definition, context, and collection times and sources. Source filters count deliberate collections, not every unknown word in a video or how often it was watched.")
            : L("Reading notices:\n") + library.warnings.joined(separator: "\n")
        speakButton.isEnabled = false
        openButton.isEnabled = false
        let prefix = destination.map { $0.displayName + " · " } ?? ""
        let summary = L("\(prefix)Total: \(library.rows.count) words / \(library.rows.reduce(0) { $0 + $1.count }) collections · Filtered: \(visible.count) words / \(visible.reduce(0) { $0 + $1.collectionCount(in: selectedSource) }) collections")
        status.stringValue = summary + (library.rows.isEmpty ? L("\nNo vocabulary tables were found here. For a Smart Folder, check that its filters include notes in the save location.") : "")
            + (library.warnings.isEmpty ? "" : "\n" + library.warnings.prefix(2).joined(separator: "\n"))
            + (library.warnings.count > 2 ? L("\n\(library.warnings.count) notices in total; see below for details.") : "")
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visible.indices.contains(row), let column = tableColumn else { return nil }
        let item = visible[row]
        let text: String
        switch column.identifier.rawValue {
        case "word": text = item.word
        case "meaning": text = DictionaryPresentation(entry: DictionaryEntry(query: item.word, text: item.definition)).meaning
        case "count": text = String(item.collectionCount(in: selectedSource))
        case "context": text = item.sentences.replacingOccurrences(of: "\n", with: " / ")
        default: text = item.firstAdded
        }
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 13, weight: column.identifier.rawValue == "word" ? .semibold : .regular)
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = text
        return field
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard visible.indices.contains(table.selectedRow) else { return }
        let row = visible[table.selectedRow]
        detail.string = L("\(row.word)    Total collections: \(row.count)\n\(row.pronunciation)\n\n\(row.definition)\n\nOriginal text:\n\(row.sentences)\n\nCollection sources:\n\(row.sourceDescription)")
        speakButton.isEnabled = true
        openButton.isEnabled = true
    }
    @objc private func speakSelected() {
        guard visible.indices.contains(table.selectedRow) else { return }
        let row = visible[table.selectedRow]
        if let message = speaker.speak(row.word, context: row.sentences) { status.stringValue = message }
    }
    @objc private func openSelected() {
        guard visible.indices.contains(table.selectedRow) else { return }
        speaker.stop()
        onOpen(visible[table.selectedRow])
    }
    @objc private func exportAnalysis() {
        guard !library.rows.isEmpty, let window else { return }
        let snapshot = library
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = L("WordNest-collection-sources.json")
        panel.message = L("Export all entries, collection history, and source statistics in the notebook snapshot, regardless of current filters. The file is saved where you choose and is not uploaded.")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do { try snapshot.analysisJSON().write(to: url, options: .atomic); self?.status.stringValue = L("Analysis data exported: \(url.lastPathComponent)") }
            catch { self?.status.stringValue = L("Export incomplete: \(error.localizedDescription)") }
        }
    }
    func windowWillClose(_ notification: Notification) {
        revision += 1
        speaker.stop()
    }
}
