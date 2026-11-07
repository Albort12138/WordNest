import AppKit
import UniformTypeIdentifiers

/// Dictionary management never reads another application's private dictionary storage.
/// Users choose an MDX file explicitly; the library validates and copies it for local use.
@MainActor final class DictionarySettingsController: NSWindowController {
    private let library: DictionaryLibrary
    private let onChange: () -> Void
    private let picker = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let importButton = NSButton(title: "", target: nil, action: nil)
    private let removeButton = NSButton(title: "", target: nil, action: nil)
    private var message: String?
    private var importPending = false

    init(library: DictionaryLibrary, onChange: @escaping () -> Void) {
        self.library = library
        self.onChange = onChange
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("Dictionaries")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -24)
        ])
        func label(_ value: String, size: CGFloat, color: NSColor = .labelColor) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: value)
            field.font = .systemFont(ofSize: size)
            field.textColor = color
            stack.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return field
        }
        _ = label(L("Choose where definitions come from."), size: 23)
        _ = label(L("Import a local MDX file, including one you use in Eudic. Definitions stay in WordNest; the Eudic app is not required."), size: 13, color: .secondaryLabelColor)
        picker.target = self; picker.action = #selector(selectDictionary)
        picker.setAccessibilityLabel(L("Selected dictionary"))
        picker.setAccessibilityIdentifier("dictionary.settings.selection")
        stack.addArrangedSubview(picker)
        picker.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let buttons = NSStackView()
        buttons.spacing = 12
        importButton.title = L("Import MDX…")
        importButton.target = self; importButton.action = #selector(importDictionary)
        importButton.bezelStyle = .rounded
        removeButton.title = L("Remove local copy…")
        removeButton.target = self; removeButton.action = #selector(removeDictionary)
        removeButton.bezelStyle = .rounded
        buttons.addArrangedSubview(importButton); buttons.addArrangedSubview(removeButton)
        stack.addArrangedSubview(buttons)
        status.font = .systemFont(ofSize: 12)
        status.setAccessibilityIdentifier("dictionary.settings.status")
        stack.addArrangedSubview(status)
        status.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        _ = label(L("MDX 2.x · UTF-8, UTF-16LE, GBK and Big5 · zlib or uncompressed blocks. Standard encrypted key indexes are supported. LZO and password-protected dictionaries are not supported yet."), size: 12, color: .secondaryLabelColor)
        _ = label(L("Text definitions only: MDD images, audio and custom HTML layouts are not displayed. Pronunciation uses macOS voices. Import only dictionaries you are authorized to use; your original file is not changed."), size: 12, color: .secondaryLabelColor)
        refresh()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() { refresh(); showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil) }

    private func refresh() {
        picker.removeAllItems()
        for source in library.sources {
            picker.addItem(withTitle: source.displayName)
            picker.lastItem?.representedObject = source.id
            if source.id == library.selectedID { picker.select(picker.lastItem) }
        }
        let busy = library.isImporting || importPending
        picker.isEnabled = !busy
        importButton.isEnabled = !busy
        removeButton.isEnabled = !busy && library.selectedSource.kind == .mdx
        if busy { status.stringValue = L("Importing and validating the local dictionary…") }
        else if let message { status.stringValue = message }
        else if !library.isAvailable(library.selectedSource) { status.stringValue = L("The managed dictionary file is missing. Reimport the MDX file or choose another dictionary.") }
        else if let record = library.records.first(where: { $0.source.id == library.selectedID }) { status.stringValue = L("\(record.entries) entries · Managed local copy · No network requests") }
        else { status.stringValue = L("Uses the dictionaries enabled in macOS Dictionary settings.") }
    }

    @objc private func selectDictionary() {
        guard let id = picker.selectedItem?.representedObject as? String else { return }
        do { try library.select(id); message = nil; onChange() }
        catch { message = error.localizedDescription }
        refresh()
    }

    @objc private func importDictionary() {
        guard let window, !library.isImporting else { return }
        let panel = NSOpenPanel()
        panel.title = L("Import a local MDX dictionary")
        panel.allowedContentTypes = [UTType(filenameExtension: "mdx") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                self.importPending = true
                self.refresh()
                do {
                    let record = try await self.library.importMDX(from: url)
                    self.message = L("Imported “\(record.name)” (\(record.entries) entries). It is now the selected dictionary.")
                    self.onChange()
                } catch { self.message = error.localizedDescription }
                self.importPending = false
                self.refresh()
            }
        }
    }

    @objc private func removeDictionary() {
        guard let record = library.records.first(where: { $0.source.id == library.selectedID }), let window else { return }
        let alert = NSAlert()
        alert.messageText = L("Remove “\(record.name)” from WordNest?")
        alert.informativeText = L("Only WordNest's managed copy is removed. Your original MDX file and saved vocabulary are kept.")
        alert.addButton(withTitle: L("Remove local copy")); alert.addButton(withTitle: L("Cancel"))
        alert.beginSheetModal(for: window) { [weak self] result in
            guard result == .alertFirstButtonReturn, let self else { return }
            do { try self.library.remove(record.id); self.message = nil; self.onChange() }
            catch { self.message = error.localizedDescription }
            self.refresh()
        }
    }
}
