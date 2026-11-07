import AppKit
import ApplicationServices
import Carbon

/// System requests are injected separately from checks so presenting setup cannot ask for consent.
@MainActor struct SetupPermissionAccess {
    var screenCapture: () -> Bool
    var accessibility: () -> Bool
    var automation: (_ bundleID: String, _ prompt: Bool) -> SetupPermissionState
    var requestScreenCapture: () -> Void
    var requestAccessibility: () -> Void
    var openSettings: (_ pane: String) -> Void

    static var system: SetupPermissionAccess {
        SetupPermissionAccess(
            screenCapture: { CGPreflightScreenCaptureAccess() },
            accessibility: { AXIsProcessTrusted() },
            automation: { bundleID, prompt in
                let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleID)
                guard let descriptorPointer = descriptor.aeDesc else { return .unavailable }
                var target = descriptorPointer.pointee
                let result = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, prompt)
                if result == noErr { return .granted }
                if result == errAEEventNotPermitted || result == errAEEventWouldRequireUserConsent { return .notGranted }
                return .unavailable
            },
            requestScreenCapture: { _ = CGRequestScreenCaptureAccess() },
            requestAccessibility: {
                _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
            },
            openSettings: { pane in
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    NSWorkspace.shared.open(url)
                }
            })
    }
}

/// Semantic brand colors adapt to appearance instead of freezing layer colors at initialization.
private enum SetupPalette {
    static let teal = NSColor(name: "WordNestTeal") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.23, green: 0.75, blue: 0.70, alpha: 1)
            : NSColor(srgbRed: 0.04, green: 0.43, blue: 0.42, alpha: 1)
    }
    static let sidebar = NSColor(name: "WordNestSidebar") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.10, green: 0.20, blue: 0.20, alpha: 1)
            : NSColor(srgbRed: 0.89, green: 0.95, blue: 0.92, alpha: 1)
    }
    static let cream = NSColor(name: "WordNestCream") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.23, green: 0.22, blue: 0.16, alpha: 1)
            : NSColor(srgbRed: 1, green: 0.97, blue: 0.88, alpha: 1)
    }
}

private final class SetupSurface: NSView {
    var fill: NSColor = .controlBackgroundColor
    var radius: CGFloat = 14
    var drawsBorder = true
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        if drawsBorder || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            NSColor.separatorColor.setStroke()
            path.lineWidth = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 2 : 0.7
            path.stroke()
        }
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// Retain native button keyboard/accessibility behavior while giving the primary action a brand fill.
private final class SetupPrimaryButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let color = isEnabled ? SetupPalette.teal : NSColor.disabledControlTextColor
        (isHighlighted ? color.blended(withFraction: 0.16, of: .black)! : color).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let text = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: isDark ? NSColor(srgbRed: 0.03, green: 0.16, blue: 0.16, alpha: 1) : NSColor.white
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill() }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

@MainActor final class SetupWindowController: NSWindowController {
    private let onFinish: () -> Void
    private let onConfigureNotes: () -> Void
    private let onPractice: () -> Void
    private let onRestart: () -> Void
    private let access: SetupPermissionAccess
    private let defaults: UserDefaults
    private let restoredStep: SetupStep?
    private var progress = SetupProgress()
    private var observer: NSObjectProtocol?
    private let content = NSStackView()
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let subtitle = NSTextField(wrappingLabelWithString: "")
    private let stepLabel = NSTextField(labelWithString: "")
    private let bubble = NSTextField(labelWithString: "")
    private let backButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = SetupPrimaryButton(title: "", target: nil, action: nil)
    private let laterButton = NSButton(title: "", target: nil, action: nil)
    private var languageButtons: [NSButton] = []
    private let taglineLabel = NSTextField(labelWithString: "")
    private let privacyLabel = NSTextField(labelWithString: "")
    private let mascotView = NSImageView()
    private let sidebarTitles: [UIString] = ["Choose language", "Enable screen lookup", "Keep source links", "Connect your notebook", "Try your first lookup"]
    private var stepRows: [(SetupSurface, NSTextField, NSTextField)] = []

    init(onFinish: @escaping () -> Void,
         onConfigureNotes: @escaping () -> Void,
         onPractice: @escaping () -> Void,
         onRestart: @escaping () -> Void,
         access: SetupPermissionAccess? = nil,
         defaults: UserDefaults = .standard) {
        self.onFinish = onFinish
        self.onConfigureNotes = onConfigureNotes
        self.onPractice = onPractice
        self.onRestart = onRestart
        self.access = access ?? .system
        self.defaults = defaults
        progress.step = SetupPreferences.currentStep(in: defaults)
        restoredStep = defaults.object(forKey: SetupPreferences.stepKey) != nil ? progress.step : nil
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 650),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = L("Welcome to WordNest", language: UILanguage.load(in: defaults).resolved())
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        super.init(window: window)
        buildLayout()
        refresh()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh(forceRender: false) }
        }
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func present(step: SetupStep? = nil) {
        if let step {
            progress.step = step
        }
        SetupPreferences.checkpoint(progress.step, in: defaults)
        refresh()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Window fixtures resolve their injected preferences without consulting or mutating global UI state.
    private func T(_ value: UIString) -> String {
        L(value, language: UILanguage.load(in: defaults).resolved())
    }

    private func buildLayout() {
        guard let root = window?.contentView else { return }
        let sidebar = SetupSurface()
        sidebar.fill = SetupPalette.sidebar
        sidebar.radius = 0
        sidebar.drawsBorder = false
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor), sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 244)
        ])
        buildSidebar(sidebar)
        let main = NSStackView()
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 12
        main.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(main)
        NSLayoutConstraint.activate([
            main.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 34),
            main.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),
            main.topAnchor.constraint(equalTo: root.topAnchor, constant: 48)
        ])
        stepLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        stepLabel.textColor = SetupPalette.teal
        main.addArrangedSubview(stepLabel)
        heading.font = .systemFont(ofSize: 28, weight: .bold)
        main.addArrangedSubview(heading)
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        main.addArrangedSubview(subtitle)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        main.addArrangedSubview(content)
        main.setCustomSpacing(23, after: subtitle)
        for view in [heading, subtitle, content] { view.widthAnchor.constraint(equalTo: main.widthAnchor).isActive = true }
        let footer = NSStackView()
        footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(footer)
        backButton.target = self
        backButton.action = #selector(back)
        backButton.isBordered = false
        footer.addArrangedSubview(backButton)
        let later = laterButton
        later.target = self
        later.action = #selector(deferSetup)
        later.isBordered = false
        later.contentTintColor = .secondaryLabelColor
        footer.addArrangedSubview(later)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(spacer)
        nextButton.target = self
        nextButton.action = #selector(next)
        nextButton.isBordered = false
        nextButton.keyEquivalent = "\r"
        footer.addArrangedSubview(nextButton)
        NSLayoutConstraint.activate([
            footer.leadingAnchor.constraint(equalTo: main.leadingAnchor), footer.trailingAnchor.constraint(equalTo: main.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -26),
            nextButton.widthAnchor.constraint(equalToConstant: 144), nextButton.heightAnchor.constraint(equalToConstant: 38),
            main.bottomAnchor.constraint(lessThanOrEqualTo: footer.topAnchor, constant: -18)
        ])
    }

    private func buildSidebar(_ sidebar: NSView) {
        let brand = NSTextField(labelWithString: "WordNest")
        brand.font = .systemFont(ofSize: 29, weight: .bold)
        brand.textColor = SetupPalette.teal
        let tagline = taglineLabel
        tagline.font = .systemFont(ofSize: 12)
        tagline.textColor = .secondaryLabelColor
        let art = NSView()
        let halo = SetupSurface()
        halo.fill = SetupPalette.cream
        halo.radius = 95
        halo.drawsBorder = false
        let image = mascotView
        image.image = Bundle.main.url(forResource: "WordNest-mascot", withExtension: "png").flatMap(NSImage.init(contentsOf:))
            ?? NSImage(named: NSImage.applicationIconName)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityLabel(T("WordNest owl mascot"))
        let speech = SetupSurface()
        speech.radius = 11
        speech.fill = .controlBackgroundColor
        bubble.font = .systemFont(ofSize: 11, weight: .medium)
        bubble.textColor = SetupPalette.teal
        for view in [halo, image, speech] { view.translatesAutoresizingMaskIntoConstraints = false; art.addSubview(view) }
        bubble.translatesAutoresizingMaskIntoConstraints = false
        speech.addSubview(bubble)
        NSLayoutConstraint.activate([
            art.heightAnchor.constraint(equalToConstant: 200),
            halo.centerXAnchor.constraint(equalTo: art.centerXAnchor), halo.bottomAnchor.constraint(equalTo: art.bottomAnchor, constant: -8),
            halo.widthAnchor.constraint(equalToConstant: 165), halo.heightAnchor.constraint(equalToConstant: 165),
            image.centerXAnchor.constraint(equalTo: art.centerXAnchor), image.bottomAnchor.constraint(equalTo: art.bottomAnchor),
            image.widthAnchor.constraint(equalToConstant: 184), image.heightAnchor.constraint(equalToConstant: 184),
            speech.centerXAnchor.constraint(equalTo: art.centerXAnchor), speech.topAnchor.constraint(equalTo: art.topAnchor),
            bubble.leadingAnchor.constraint(equalTo: speech.leadingAnchor, constant: 12), bubble.trailingAnchor.constraint(equalTo: speech.trailingAnchor, constant: -12),
            bubble.topAnchor.constraint(equalTo: speech.topAnchor, constant: 7), bubble.bottomAnchor.constraint(equalTo: speech.bottomAnchor, constant: -7)
        ])
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 48)
        ])
        stack.addArrangedSubview(brand)
        stack.addArrangedSubview(tagline)
        stack.setCustomSpacing(10, after: tagline)
        stack.addArrangedSubview(art)
        art.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(10, after: art)
        for (index, title) in sidebarTitles.enumerated() {
            let row = SetupSurface()
            row.radius = 9
            row.drawsBorder = false
            let number = NSTextField(labelWithString: "\(index + 1)")
            number.alignment = .center
            number.font = .systemFont(ofSize: 12, weight: .semibold)
            let text = NSTextField(labelWithString: T(title))
            text.font = .systemFont(ofSize: 12)
            for view in [number, text] { view.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(view) }
            stack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 30), row.widthAnchor.constraint(equalTo: stack.widthAnchor),
                number.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8), number.widthAnchor.constraint(equalToConstant: 20),
                number.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                text.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 7), text.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                text.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -6)
            ])
            stepRows.append((row, number, text))
        }
        let privacy = privacyLabel
        privacy.font = .systemFont(ofSize: 11, weight: .medium)
        privacy.textColor = SetupPalette.teal
        privacy.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(privacy)
        NSLayoutConstraint.activate([
            privacy.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 29),
            privacy.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -30),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: privacy.topAnchor, constant: -18)
        ])
    }

    private func refresh(forceRender: Bool = true) {
        let previous = progress
        progress.screenCapture = access.screenCapture() ? .granted : .notGranted
        progress.accessibility = access.accessibility() ? .granted : .notGranted
        progress.safariAutomation = access.automation("com.apple.Safari", false)
        progress.notesAutomation = access.automation("com.apple.Notes", false)
        // Returning focus without a permission change must not replace the focused controls.
        if forceRender || progress != previous { render() }
    }

    private func render() {
        for view in content.arrangedSubviews { content.removeArrangedSubview(view); view.removeFromSuperview() }
        languageButtons.removeAll()
        window?.title = T("Welcome to WordNest")
        backButton.title = T("Back")
        laterButton.title = T("Set up later")
        taglineLabel.stringValue = T("A home for every new word.")
        privacyLabel.stringValue = T("◈  On-device. In your control.")
        mascotView.setAccessibilityLabel(T("WordNest owl mascot"))
        stepLabel.stringValue = T("GET STARTED / \(progress.step.rawValue + 1) OF 5") + (restoredStep == progress.step ? T(" · Resuming setup") : "")
        for (index, item) in stepRows.enumerated() {
            let selected = index == progress.step.rawValue
            item.0.fill = selected ? .controlBackgroundColor : .clear
            item.0.needsDisplay = true
            item.1.stringValue = index < progress.step.rawValue ? "✓" : "\(index + 1)"
            item.1.textColor = selected || index < progress.step.rawValue ? SetupPalette.teal : .secondaryLabelColor
            item.2.textColor = selected ? .labelColor : .secondaryLabelColor
            item.2.font = .systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
            item.2.stringValue = T(sidebarTitles[index])
        }
        backButton.isEnabled = progress.step != .welcome
        nextButton.title = progress.isLastStep ? (progress.canLookUp ? T("Get started  →") : T("Finish later")) : T("Continue  →")
        nextButton.needsDisplay = true
        switch progress.step {
        case .welcome:
            heading.stringValue = T("Choose your language.")
            subtitle.stringValue = T("WordNest follows your Mac's language by default. Choose another language if you prefer; you can change it later in Settings.")
            bubble.stringValue = T("Hello. Let's begin.")
            languageChoices()
            note(T("Installing from a DMG? Move WordNest.app to Applications, open it there, then grant permissions."), symbol: "folder", cream: true)
        case .screenCapture:
            heading.stringValue = T("Words on screen, within reach.")
            subtitle.stringValue = T("Screen recording enables lookup. You approve access in macOS.")
            bubble.stringValue = T("One frame, on your request.")
            card(T("Screen lookup"), symbol: "viewfinder", state: progress.screenCapture,
                 body: T("Only the shortcut captures a frame, cropped and recognized in memory. No continuous recording or audio capture."),
                 actions: [(T("Allow screen recording…"), #selector(requestScreen)), (T("Open System Settings"), #selector(openScreen))])
            note(progress.canLookUp ? T("This process has screen access. Try a real lookup next.") : T("Subtitles are not accessible yet. Continue setup or grant access later."), symbol: progress.canLookUp ? "checkmark.circle" : "info.circle", cream: !progress.canLookUp)
            card(T("macOS asks you to reopen?"), symbol: "arrow.clockwise", body: T("Choose Later in the system prompt to continue, or restart now. Your step is saved. Reopen WordNest if it does not return automatically."),
                 actions: [(T("Restart WordNest"), #selector(restart))])
        case .sources:
            heading.stringValue = T("Keep the story behind a word.")
            subtitle.stringValue = T("Optional · Save the current page title and link with each collection.")
            bubble.stringValue = T("Find that video again.")
            card(T("Safari web apps in the Dock"), symbol: "macwindow", state: progress.accessibility,
                 body: T("For sites such as Bilibili added to the Dock from Safari. Reads only foreground page metadata, without traversing page content."),
                 actions: [(T("Allow Accessibility…"), #selector(requestAccessibility))])
            card(T("Regular Safari pages"), symbol: "safari", state: progress.safariAutomation,
                 body: T("Read the current page title and link to keep with this deliberate collection."),
                 actions: [(T("Allow Safari automation…"), #selector(requestSafari))])
            note(T("Lookup works without this; add links manually. Accessibility is an app-wide macOS permission."), symbol: "hand.raised")
        case .notes:
            heading.stringValue = T("Your words. Your Notes.")
            subtitle.stringValue = T("Optional · No new vocabulary app or account to manage.")
            bubble.stringValue = T("Your words live in Notes.")
            card(T("Connect Apple Notes"), symbol: "note.text", state: progress.notesAutomation,
                 body: T("Writes happen only when you save. Permission checks do not read or change vocabulary."),
                 actions: [(T("Allow Notes automation…"), #selector(requestNotes))])
            card(T("Choose a home for your words"), symbol: "folder.badge.plus", body: T("Save in a regular folder, grouped by initial or script. Save a word again to count it and keep new context and sources."),
                 actions: [(T("Choose notebook…"), #selector(configureNotes))])
            note(T("Set this up later if you like. Apple may sync notes in an iCloud account."), symbol: "icloud")
        case .practice:
            heading.stringValue = progress.canLookUp ? T("Ready for your next word.") : T("Lookup is not ready yet.")
            subtitle.stringValue = progress.canLookUp ? T("Start growing your vocabulary, one lookup at a time.") : T("Screen access is not effective yet. Return through Settings to finish later.")
            bubble.stringValue = progress.canLookUp ? T("Go find your first word!") : T("I'll be here when you return.")
            card(T("Point at a word. Press ⌃⌥D."), symbol: "cursorarrow.rays", body: T("Point at a word in a video or article. In the card, hear it, correct recognition, then decide whether to save."),
                 actions: [(T("Preview a lookup card"), #selector(practice))])
            note(T("The demo uses fixed text, without capture or collection. Finishing setup does not grant permission."), symbol: "play.circle", cream: true)
            card(T("Learn at your own pace"), symbol: "leaf", body: T("Uses installed dictionaries and voices; Chinese definitions are not available for every language. Connect sources and Notes later if you prefer."))
        }
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    /// Make language the first visible choice, while keeping the existing welcome-step checkpoint stable.
    /// Native radio controls expose selection and keyboard behavior without requiring a popup to discover the options.
    private func languageChoices() {
        let surface = SetupSurface()
        surface.fill = SetupPalette.sidebar
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        let selected = UILanguage.load(in: defaults)
        let systemName = UILanguage.system.resolved() == .simplifiedChinese ? T("language.nativeChinese") : "English"
        for (index, language) in UILanguage.allCases.enumerated() {
            let title: String
            switch language {
            case .system: title = T("System default") + " — " + systemName
            case .simplifiedChinese: title = T("language.nativeChinese")
            case .english: title = "English"
            }
            let button = NSButton(radioButtonWithTitle: title, target: self, action: #selector(changeInterfaceLanguage(_:)))
            button.tag = index
            button.font = .systemFont(ofSize: 16, weight: .medium)
            button.controlSize = .large
            button.state = language == selected ? .on : .off
            button.setAccessibilityIdentifier("setup.language." + language.rawValue)
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            languageButtons.append(button)
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -14)
        ])
        content.addArrangedSubview(surface)
        surface.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }

    private func card(_ title: String, symbol: String, state: SetupPermissionState? = nil,
                      body: String, actions: [(String, Selector)] = []) {
        let surface = SetupSurface()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 11
        stack.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(stack)
        let header = NSStackView()
        header.spacing = 9
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = SetupPalette.teal
        icon.widthAnchor.constraint(equalToConstant: 19).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 19).isActive = true
        header.addArrangedSubview(icon)
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        header.addArrangedSubview(label)
        if let state {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            header.addArrangedSubview(spacer)
            let badge = NSTextField(labelWithString: state == .granted ? T("✓ Allowed") : (state == .unavailable ? T("Unconfirmed") : T("Not enabled")))
            badge.font = .systemFont(ofSize: 11, weight: .medium)
            badge.textColor = state == .granted ? SetupPalette.teal : .secondaryLabelColor
            header.addArrangedSubview(badge)
        }
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let detail = NSTextField(wrappingLabelWithString: body)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        stack.addArrangedSubview(detail)
        detail.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        if !actions.isEmpty {
            let row = NSStackView()
            row.spacing = 10
            for (title, action) in actions {
                let button = NSButton(title: title, target: self, action: action)
                button.bezelStyle = .rounded
                button.controlSize = .regular
                row.addArrangedSubview(button)
            }
            stack.addArrangedSubview(row)
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 17), stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -17),
            stack.topAnchor.constraint(equalTo: surface.topAnchor, constant: 15), stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -15)
        ])
        content.addArrangedSubview(surface)
        surface.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }

    private func note(_ text: String, symbol: String, cream: Bool = false) {
        let surface = SetupSurface()
        surface.fill = cream ? SetupPalette.cream : .clear
        surface.drawsBorder = cream
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = SetupPalette.teal
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        for view in [icon, label] { view.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(view) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 13), icon.topAnchor.constraint(equalTo: surface.topAnchor, constant: 13),
            icon.widthAnchor.constraint(equalToConstant: 15), icon.heightAnchor.constraint(equalToConstant: 15),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9), label.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -13),
            label.topAnchor.constraint(equalTo: surface.topAnchor, constant: 12), label.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -12)
        ])
        content.addArrangedSubview(surface)
        surface.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }

    @objc private func next() {
        if progress.isLastStep { finish(progress.completion) }
        else { progress.advance(); SetupPreferences.saveStep(progress.step, in: defaults); refresh() }
    }
    @objc private func changeInterfaceLanguage(_ sender: NSButton) {
        guard UILanguage.allCases.indices.contains(sender.tag) else { return }
        UILanguage.allCases[sender.tag].save(in: defaults)
        refresh()
        window?.makeFirstResponder(languageButtons.first { $0.state == .on })
    }
    @objc private func back() { progress.back(); SetupPreferences.saveStep(progress.step, in: defaults); refresh() }
    @objc private func deferSetup() { finish(progress.completion) }
    private func finish(_ completion: SetupCompletion) {
        SetupPreferences.finish(completion, in: defaults)
        close()
        onFinish()
    }
    @objc private func requestScreen() {
        SetupPreferences.checkpoint(progress.step, in: defaults)
        access.requestScreenCapture()
        refresh()
    }
    @objc private func openScreen() {
        SetupPreferences.checkpoint(progress.step, in: defaults)
        access.openSettings("Privacy_ScreenCapture")
    }
    @objc private func requestAccessibility() {
        SetupPreferences.checkpoint(progress.step, in: defaults)
        access.requestAccessibility()
        if !access.accessibility() { access.openSettings("Privacy_Accessibility") }
        refresh()
    }
    @objc private func requestSafari() {
        SetupPreferences.checkpoint(progress.step, in: defaults)
        _ = access.automation("com.apple.Safari", true)
        refresh()
    }
    @objc private func requestNotes() {
        SetupPreferences.checkpoint(progress.step, in: defaults)
        _ = access.automation("com.apple.Notes", true)
        refresh()
    }
    @objc private func configureNotes() {
        SetupPreferences.checkpoint(progress.step, in: defaults)
        onConfigureNotes()
    }
    @objc private func practice() { onPractice() }
    @objc private func restart() {
        SetupPreferences.checkpoint(progress.step, in: defaults)
        onRestart()
    }
}
