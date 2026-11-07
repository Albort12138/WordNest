import AppKit

/// Save to a physical folder; browsing may use a separate smart folder. List non-shared folders without reading ordinary notes.
@MainActor final class NotesSettingsController: NSWindowController {
    private let client: AppleNotesClient
    private let onSelected: (NotesConfiguration) -> Void
    private var accounts: [NotesAccount] = []
    private let accountPopup = NSPopUpButton()
    private let folderPopup = NSPopUpButton()
    private let browsingPopup = NSPopUpButton()
    private let separateBrowsing = NSButton(checkboxWithTitle: L("Use a separate browsing location (Smart Folders supported)"), target: nil, action: nil)
    private let browsingRow = NSStackView()
    private let guidance = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let connectButton = NSButton(title: L("Connect to Notes"), target: nil, action: nil)
    private let createButton = NSButton(title: L("Create vocabulary folder"), target: nil, action: nil)
    private let selectButton = NSButton(title: L("Save settings"), target: nil, action: nil)
    private let stack = NSStackView()
    private var working = false

    init(client: AppleNotesClient, onSelected: @escaping (NotesConfiguration) -> Void) {
        self.client = client
        self.onSelected = onSelected
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("Notebook settings · Apple Notes")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let root = window.contentView else { return }
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20)
        ])
        let heading = NSTextField(labelWithString: L("Save and browse vocabulary"))
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(heading)
        let explanation = NSTextField(wrappingLabelWithString: L("One page per category, one row per word. Collecting again updates the count and adds new context. Save to an ordinary folder; browse with a Smart Folder if desired. On My Mac stays local; Apple handles iCloud sync."))
        explanation.font = .systemFont(ofSize: 13)
        explanation.textColor = .secondaryLabelColor
        stack.addArrangedSubview(explanation)
        explanation.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        connectButton.target = self
        connectButton.action = #selector(connect)
        stack.addArrangedSubview(connectButton)
        addPopup(accountPopup, label: L("Account"))
        addPopup(folderPopup, label: L("Save to"))
        accountPopup.target = self
        accountPopup.action = #selector(accountChanged)
        createButton.target = self
        createButton.action = #selector(createFolder)
        stack.addArrangedSubview(createButton)
        separateBrowsing.target = self
        separateBrowsing.action = #selector(browsingChanged)
        separateBrowsing.state = NotesPreferences.configuration()?.browsing == nil ? .off : .on
        stack.addArrangedSubview(separateBrowsing)
        addPopup(browsingPopup, label: L("Browse"), row: browsingRow)
        guidance.font = .systemFont(ofSize: 12)
        guidance.textColor = .secondaryLabelColor
        stack.addArrangedSubview(guidance)
        guidance.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.isSelectable = true
        if let configuration = NotesPreferences.configuration() {
            status.stringValue = L("Currently saving to: \(configuration.storage.displayName)\nCurrently browsing: \(configuration.readingDestination.displayName)")
        } else { status.stringValue = L("macOS may ask whether WordNest can access Notes when you connect. Please review and approve the system prompt yourself.") }
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let buttons = NSStackView()
        buttons.spacing = 12
        selectButton.target = self
        selectButton.action = #selector(selectDestination)
        buttons.addArrangedSubview(selectButton)
        buttons.addArrangedSubview(NSButton(title: L("Automation settings"), target: self, action: #selector(openPermissions)))
        stack.addArrangedSubview(buttons)
        browsingChanged()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func addPopup(_ popup: NSPopUpButton, label: String, row suppliedRow: NSStackView? = nil) {
        let row = suppliedRow ?? NSStackView()
        row.spacing = 12
        let title = NSTextField(labelWithString: label)
        title.widthAnchor.constraint(equalToConstant: 52).isActive = true
        row.addArrangedSubview(title)
        row.addArrangedSubview(popup)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        popup.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -64).isActive = true
        popup.setAccessibilityLabel(label)
    }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func updateEnabled() {
        connectButton.isEnabled = !working
        accountPopup.isEnabled = !working && !accounts.isEmpty
        folderPopup.isEnabled = !working && folderPopup.numberOfItems > 0
        browsingPopup.isEnabled = !working && browsingPopup.numberOfItems > 0
        separateBrowsing.isEnabled = !working
        createButton.isEnabled = !working && accountPopup.indexOfSelectedItem >= 0
        selectButton.isEnabled = !working && folderPopup.indexOfSelectedItem >= 0
            && (separateBrowsing.state == .off || browsingPopup.indexOfSelectedItem >= 0)
    }

    @objc private func browsingChanged() {
        browsingRow.isHidden = separateBrowsing.state == .off
        guidance.stringValue = separateBrowsing.state == .on
            ? L("Smart Folders filter existing notes and cannot receive new notes directly. In Notes, edit the filter to include the save folder above. New notes must also match any other conditions. WordNest does not add tags or change filters.")
            : L("Browsing uses the save location by default. If a folder was converted to a Smart Folder, choose an ordinary save folder, then enable separate browsing above.")
        updateEnabled()
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.setContentSize(NSSize(width: 560, height: max(500, stack.fittingSize.height + 48)))
    }

    @objc private func connect() {
        guard !working else { return }
        working = true
        status.stringValue = L("Connecting to Notes… Please review any system permission prompt.")
        updateEnabled()
        AppleNotesClient.prepare()
        Task { @MainActor in
            defer { working = false; updateEnabled() }
            do {
                accounts = try await client.targets()
                accountPopup.removeAllItems()
                accountPopup.addItems(withTitles: accounts.map { $0.name })
                if let target = NotesPreferences.load(), let index = accounts.firstIndex(where: { $0.id == target.accountID }) {
                    accountPopup.selectItem(at: index)
                }
                accountChanged()
                status.stringValue = accounts.isEmpty ? L("No Notes accounts are available. Set up an account in Notes first.") : L("Choose an ordinary folder for saving. Select a Smart Folder separately for browsing if desired. Shared folders are not shown.")
            } catch {
                accounts = []
                accountPopup.removeAllItems()
                folderPopup.removeAllItems()
                browsingPopup.removeAllItems()
                status.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func accountChanged() {
        folderPopup.removeAllItems()
        browsingPopup.removeAllItems()
        guard accounts.indices.contains(accountPopup.indexOfSelectedItem) else { updateEnabled(); return }
        let folders = accounts[accountPopup.indexOfSelectedItem].folders
        folderPopup.addItems(withTitles: folders.map { $0.folderName })
        browsingPopup.addItems(withTitles: folders.map { $0.folderName })
        if let configuration = NotesPreferences.configuration() {
            if let index = folders.firstIndex(where: { $0.folderID == configuration.storage.folderID }) { folderPopup.selectItem(at: index) }
            if let index = folders.firstIndex(where: { $0.folderID == configuration.readingDestination.folderID }) { browsingPopup.selectItem(at: index) }
        }
        updateEnabled()
    }

    @objc private func createFolder() {
        guard !working, accounts.indices.contains(accountPopup.indexOfSelectedItem) else { return }
        let account = accounts[accountPopup.indexOfSelectedItem]
        working = true
        status.stringValue = L("Preparing the vocabulary save folder in \(account.name)…")
        updateEnabled()
        Task { @MainActor in
            defer { working = false; updateEnabled() }
            do {
                let target = try await client.createVocabularyFolder(in: account)
                accounts = try await client.targets()
                accountPopup.removeAllItems()
                accountPopup.addItems(withTitles: accounts.map { $0.name })
                if let index = accounts.firstIndex(where: { $0.id == target.accountID }) { accountPopup.selectItem(at: index) }
                accountChanged()
                if let current = accounts.first(where: { $0.id == target.accountID }),
                   let index = current.folders.firstIndex(where: { $0.folderID == target.folderID }) { folderPopup.selectItem(at: index) }
                status.stringValue = L("The save folder is ready. Click Save settings to use it.")
            } catch { status.stringValue = error.localizedDescription }
        }
    }

    @objc private func selectDestination() {
        guard !working, accounts.indices.contains(accountPopup.indexOfSelectedItem) else { return }
        let folders = accounts[accountPopup.indexOfSelectedItem].folders
        guard folders.indices.contains(folderPopup.indexOfSelectedItem),
              separateBrowsing.state == .off || folders.indices.contains(browsingPopup.indexOfSelectedItem) else { return }
        let target = folders[folderPopup.indexOfSelectedItem]
        let reading = separateBrowsing.state == .on ? folders[browsingPopup.indexOfSelectedItem] : nil
        let configuration = NotesConfiguration(storage: target, browsing: reading)
        NotesPreferences.save(configuration)
        onSelected(configuration)
        status.stringValue = L("Settings saved\nSave to: \(target.displayName)\nBrowse: \(configuration.readingDestination.displayName)")
        browsingChanged()
    }

    @objc private func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
    }
}
