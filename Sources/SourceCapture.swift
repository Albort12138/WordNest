import AppKit
import ApplicationServices

struct SourceCaptureContext {
    let bundleID: String
    let pointer: CGPoint
    let primaryScreenTop: CGFloat
    var processID: Int32? = nil
}

enum SourceCaptureResult {
    case captured(CollectionSource)
    case unavailable(String)
    var source: CollectionSource? { if case .captured(let source) = self { return source }; return nil }
    var message: String { if case .unavailable(let message) = self { return message }; return L("Page link captured at lookup time") }
}

/// Read ordinary Safari tabs through its object interface; use authorized Accessibility for Dock webapp root WebArea URLs.
/// Both paths bind to the foreground window and pointer. UI calls capture without browser-specific implementation details.
actor PageSourceReader {
    static let scriptSource = #"""
    on currentPage()
        with timeout of 4 seconds
            if application id "com.apple.Safari" is not running then return {}
            tell application id "com.apple.Safari"
                if frontmost is false or (count of windows) is 0 then return {}
                set w to front window
                set t to current tab of w
                set pageBounds to bounds of w
                return {URL of t as text, name of t as text, item 1 of pageBounds as text, item 2 of pageBounds as text, item 3 of pageBounds as text, item 4 of pageBounds as text}
            end tell
        end timeout
    end currentPage
    """#
    private let transport: (() throws -> NSAppleEventDescriptor)?
    private let webAppTransport: ((SourceCaptureContext) -> SourceCaptureResult)?
    init(transport: (() throws -> NSAppleEventDescriptor)? = nil,
         webAppTransport: ((SourceCaptureContext) -> SourceCaptureResult)? = nil) {
        self.transport = transport; self.webAppTransport = webAppTransport
    }

    func capture(_ context: SourceCaptureContext) -> SourceCaptureResult {
        if context.bundleID.hasPrefix("com.apple.Safari.WebApp.") {
            return webAppTransport?(context) ?? captureWebApp(context)
        }
        guard context.bundleID == "com.apple.Safari" else {
            return .unavailable(L("This window does not support automatic links. Use Source… to paste a video or webpage link."))
        }
        // A lookup must not trigger a first-use Automation dialog and steal the video focus.
        // Explicit setup actions request consent; injected fixtures never consult system permissions.
        if transport == nil && AutomationConsent.state(for: "com.apple.Safari") != .granted {
            return .unavailable(L("Safari source access is not allowed. Enable it in Settings… or enter the link manually."))
        }
        do {
            let result: NSAppleEventDescriptor
            if let transport { result = try transport() }
            else {
                guard let script = NSAppleScript(source: Self.scriptSource) else { return .unavailable(L("The source could not be read. You can enter the link manually.")) }
                var error: NSDictionary?
                result = script.executeAppleEvent(AppleNotesClient.event(handler: "currentPage", arguments: []), error: &error)
                if let error {
                    let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
                    if code == -1743 { return .unavailable(L("Safari page-link access is not allowed. Enter it manually or allow access in Automation settings.")) }
                    return .unavailable(L("The Safari page link is unavailable. You can enter it manually."))
                }
            }
            guard result.numberOfItems == 6, let url = result.atIndex(1)?.stringValue,
                  let title = result.atIndex(2)?.stringValue,
                  let x1 = result.atIndex(3)?.stringValue.flatMap(Double.init), let y1 = result.atIndex(4)?.stringValue.flatMap(Double.init),
                  let x2 = result.atIndex(5)?.stringValue.flatMap(Double.init), let y2 = result.atIndex(6)?.stringValue.flatMap(Double.init),
                  x2 > x1, y2 > y1,
                  CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1).contains(CGPoint(x: context.pointer.x, y: context.primaryScreenTop - context.pointer.y)),
                  let source = CollectionSource(url: url, title: title) else {
                return .unavailable(L("The pointer is outside the current Safari window, or the page has no web link. You can enter it manually."))
            }
            return .captured(source)
        } catch { return .unavailable(L("The page link could not be read. You can enter it manually.")) }
    }

    struct WebPageCandidate {
        let source: CollectionSource
        let bounds: CGRect
    }

    /// WebKit may put the page name in AXDescription while returning an empty AXTitle.
    /// Whitespace is not a title: normalize each candidate before falling back, rather than checking only nil with ??.
    /// This entry point also replays observed metadata; never read page body text or fetch a title over the network.
    static func sourceFromWebArea(url: String, title: String?, description: String?, windowTitle: String) -> CollectionSource? {
        guard let untitled = CollectionSource(url: url) else { return nil }
        for candidate in [title, description, windowTitle] {
            guard let candidate, let source = CollectionSource(url: url, title: candidate), !source.title.isEmpty else { continue }
            return source
        }
        return untitled
    }
    static func selectWebPage(_ candidates: [WebPageCandidate], context: SourceCaptureContext) -> SourceCaptureResult {
        let point = CGPoint(x: context.pointer.x, y: context.primaryScreenTop - context.pointer.y)
        let matches = candidates.filter { $0.bounds.contains(point) }
        guard let candidate = matches.first, Set(matches.map { $0.source.url }).count == 1 else {
            return .unavailable(L("A single page link could not be confirmed for this web app. Enter the source manually."))
        }
        return .captured(candidate.source)
    }

    /// Read roles, children, geometry, titles, and URLs only; stop at root WebAreas without traversing content or sending keys.
    private func captureWebApp(_ context: SourceCaptureContext) -> SourceCaptureResult {
        guard AXIsProcessTrusted() else {
            return .unavailable(L("Reading links from a Dock web app requires Accessibility permission. Enable it in Settings… or enter the source manually."))
        }
        guard let pid = context.processID, let running = NSRunningApplication(processIdentifier: pid),
              running.bundleIdentifier == context.bundleID, running.isActive else {
            return .unavailable(L("The active web-app window changed. Look up the word again or enter the source manually."))
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.25)
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
        }
        func bounds(_ element: AXUIElement) -> CGRect? {
            guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
                  let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
            let p = position as! AXValue, s = size as! AXValue
            guard AXValueGetType(p) == .cgPoint, AXValueGetType(s) == .cgSize else { return nil }
            var point = CGPoint.zero, dimensions = CGSize.zero
            guard AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0 else { return nil }
            return CGRect(origin: point, size: dimensions)
        }
        guard let rawWindow = attribute(application, kAXFocusedWindowAttribute), CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
            return .unavailable(L("The current web-app page is unavailable. You can enter the source manually."))
        }
        let window = rawWindow as! AXUIElement
        let point = CGPoint(x: context.pointer.x, y: context.primaryScreenTop - context.pointer.y)
        guard bounds(window)?.contains(point) == true else { return .unavailable(L("The pointer is outside the web-app window. Point at the video and look up the word again.")) }
        let windowTitle = attribute(window, kAXTitleAttribute) as? String ?? ""
        let deadline = ProcessInfo.processInfo.systemUptime + 1.5
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited: [AXUIElement] = []
        var candidates: [WebPageCandidate] = []
        while !queue.isEmpty && visited.count < 150 && ProcessInfo.processInfo.systemUptime < deadline {
            let (element, depth) = queue.removeFirst()
            if visited.contains(where: { CFEqual($0, element) }) { continue }
            visited.append(element)
            if attribute(element, kAXRoleAttribute) as? String == "AXWebArea" {
                let raw = attribute(element, kAXURLAttribute)
                let url = (raw as? URL)?.absoluteString ?? raw as? String ?? ""
                let source = Self.sourceFromWebArea(url: url, title: attribute(element, kAXTitleAttribute) as? String,
                    description: attribute(element, kAXDescriptionAttribute) as? String, windowTitle: windowTitle)
                if let source, let frame = bounds(element) {
                    candidates.append(WebPageCandidate(source: source, bounds: frame))
                }
                continue
            }
            if depth < 8 {
                let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
                queue += children.prefix(150).map { ($0, depth + 1) }
            }
        }
        guard running.isActive else { return .unavailable(L("The active window changed while reading. Look up the word again.")) }
        guard queue.isEmpty else { return .unavailable(L("The page structure could not be read completely. You can enter the source link manually.")) }
        return Self.selectWebPage(candidates, context: context)
    }
}

@MainActor final class SourceEditorController: NSWindowController {
    private let urlField = NSTextField()
    private let titleField = NSTextField()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let onApply: (CollectionSource?) -> Bool

    init(source: CollectionSource?, onApply: @escaping (CollectionSource?) -> Bool) {
        self.onApply = onApply
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 295), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = L("Source for this collection")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        guard let root = window.contentView else { return }
        root.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -22), stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20)])
        let help = NSTextField(wrappingLabelWithString: L("Save the video or article link to review vocabulary by source later. Leave the link empty to collect without a source. This link belongs to the current lookup."))
        stack.addArrangedSubview(help); help.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        for (label, field, placeholder) in [(L("Link"), urlField, "https://…"), (L("Title"), titleField, L("Optional video or article title"))] {
            stack.addArrangedSubview(NSTextField(labelWithString: label))
            field.placeholderString = placeholder; field.setAccessibilityLabel(label)
            stack.addArrangedSubview(field); field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        urlField.stringValue = source?.url ?? ""; titleField.stringValue = source?.title ?? ""
        message.font = .systemFont(ofSize: 11); message.textColor = .systemRed
        stack.addArrangedSubview(message); message.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let buttons = NSStackView(); buttons.spacing = 10
        buttons.addArrangedSubview(NSButton(title: L("Use for this collection"), target: self, action: #selector(apply)))
        buttons.addArrangedSubview(NSButton(title: L("Cancel"), target: self, action: #selector(cancel)))
        stack.addArrangedSubview(buttons)
        root.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 540, height: max(295, stack.fittingSize.height + 40)))
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() { showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil); urlField.selectText(nil) }
    @objc private func cancel() { close() }
    @objc private func apply() {
        let value = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = value.isEmpty ? nil : CollectionSource(url: value, title: titleField.stringValue)
        guard value.isEmpty || source != nil else { message.stringValue = L("Enter a valid http or https webpage link."); return }
        if onApply(source) { close() } else { message.stringValue = L("This collection was submitted or the lookup changed. Set the source on a new lookup.") }
    }
}
