import AppKit

/// Inspect semantic control titles, not AppKit's OS-dependent internal label views.
@MainActor private func untranslatedEnglishSetupLabels(in view: NSView) -> [String] {
    guard !view.isHidden else { return [] }
    func hasChinese(_ text: String) -> Bool {
        text.range(of: "[\\u3400-\\u9FFF]", options: .regularExpression) != nil
    }
    if let button = view as? NSButton {
        let chineseName = SampleText.value("Simplified Chinese")
        let isLanguageChoice = button.action == NSSelectorFromString("changeInterfaceLanguage:")
        let isAutonym = isLanguageChoice && ((button.tag == 1 && button.title == chineseName)
            || (button.tag == 0 && button.title == "System default — " + chineseName))
        return hasChinese(button.title) && !isAutonym ? [button.title] : []
    }
    if let field = view as? NSTextField {
        return hasChinese(field.stringValue) ? [field.stringValue] : []
    }
    return view.subviews.flatMap { untranslatedEnglishSetupLabels(in: $0) }
}

@MainActor func runSetupTests() async {
    var progress = SetupProgress()
    check(progress.step == .welcome && !progress.canLookUp, "setup begins without assuming screen permission")
    check(progress.completion == .deferred, "setup cannot report ready when screen permission is absent")
    progress.back()
    check(progress.step == .welcome, "setup back navigation stays within the first step")
    progress.advance()
    check(progress.step == .screenCapture, "setup introduces required screen permission before optional integrations")
    progress.advance()
    check(progress.step == .sources && !progress.canLookUp, "denied screen permission does not trap a user in setup")
    progress.advance()
    check(progress.step == .notes, "optional source permissions can be skipped")
    progress.advance()
    check(progress.isLastStep && progress.completion == .deferred, "skipping permissions reaches an explicitly deferred finish")
    progress.advance()
    check(progress.step == .practice, "setup forward navigation stays within the last step")
    progress.screenCapture = .granted
    check(progress.canLookUp && progress.completion == .ready, "screen permission alone enables the lookup capability")
    check(progress.accessibility == .notGranted && progress.notesAutomation == .notGranted && progress.safariAutomation == .notGranted,
          "lookup readiness does not imply optional permissions were granted")
    progress.screenCapture = .unavailable
    check(!progress.canLookUp && progress.completion == .deferred, "unavailable screen permission is never reported ready")
    progress.screenCapture = .notGranted
    progress.accessibility = .granted
    progress.notesAutomation = .granted
    progress.safariAutomation = .granted
    check(!progress.canLookUp, "optional permissions cannot substitute for screen capture permission")

    let suiteName = "WordNest.SetupTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        check(false, "isolated setup preference suite is available")
        return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }
    check(UILanguage.load(in: defaults) == .system, "a fresh setup follows the macOS interface language by default")
    check(!SetupPreferences.hasCompleted(in: defaults), "fresh setup preferences require the introduction")
    check(SetupPreferences.currentStep(in: defaults) == .welcome, "fresh setup begins at welcome")
    SetupPreferences.saveStep(.sources, in: defaults)
    check(SetupPreferences.currentStep(in: defaults) == .sources, "unfinished setup restores its persisted step")
    defaults.set(99, forKey: SetupPreferences.stepKey)
    check(SetupPreferences.currentStep(in: defaults) == .welcome, "invalid persisted setup step safely returns to welcome")
    SetupPreferences.saveStep(.notes, in: defaults)
    SetupPreferences.finish(.deferred, in: defaults)
    check(SetupPreferences.hasCompleted(in: defaults), "explicit deferred finish does not force setup on every launch")
    check(defaults.string(forKey: SetupPreferences.resultKey) == SetupCompletion.deferred.rawValue,
          "deferred setup is persisted distinctly from ready")
    check(SetupPreferences.currentStep(in: defaults) == .welcome, "explicit completion clears the unfinished step")
    check(!SetupProgress().canLookUp, "persisted introduction completion never grants runtime capability")
    SetupPreferences.finish(.ready, in: defaults)
    check(defaults.string(forKey: SetupPreferences.resultKey) == SetupCompletion.ready.rawValue,
          "returning to finish granted setup updates its persisted result")

    // Exercise real AppKit layout using only injected permission checks and callbacks.
    UILanguage.simplifiedChinese.save(in: defaults)
    _ = NSApplication.shared
    var prompts = 0
    var finishCalls = 0
    var notesCalls = 0
    let denied = SetupPermissionAccess(screenCapture: { false }, accessibility: { false }, automation: { _, prompt in
        if prompt { prompts += 1 }
        return .notGranted
    }, requestScreenCapture: { prompts += 1 }, requestAccessibility: { prompts += 1 }, openSettings: { _ in prompts += 1 })
    let window = SetupWindowController(onFinish: { finishCalls += 1 }, onConfigureNotes: { notesCalls += 1 },
                                      onPractice: {}, onRestart: {}, access: denied, defaults: defaults)
    check(prompts == 0 && notesCalls == 0, "setup initialization checks status without prompts or Notes access")
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let originalControls = window.window?.contentView.map { descendants($0).map(ObjectIdentifier.init) }
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
    try? await Task.sleep(nanoseconds: 10_000_000)
    let restoredControls = window.window?.contentView.map { descendants($0).map(ObjectIdentifier.init) }
    check(originalControls == restoredControls, "returning focus with unchanged permissions preserves the current controls")
    check(window.window?.contentView?.bounds.width == 840 && window.window?.contentView?.bounds.height == 650,
          "branded setup uses a consistent MacBook-sized layout")
    for step in SetupStep.allCases {
        if let root = window.window?.contentView {
            root.layoutSubtreeIfNeeded()
            let controls = descendants(root).filter { !$0.isHidden && ($0 is NSTextField || $0 is NSButton) }
            check(controls.allSatisfy { root.bounds.insetBy(dx: -1, dy: -1).contains($0.convert($0.bounds, to: root)) },
                  "setup controls fit the window at step \(step.rawValue)")
            if step == .welcome {
                check(controls.compactMap { ($0 as? NSTextField)?.stringValue }.contains { $0.contains("DMG") && $0.contains(SampleText.value("Applications folder label")) },
                      "setup explains moving out of the disk image before authorizing")
                check(descendants(root).compactMap { $0 as? NSImageView }.contains { $0.bounds.width >= 180 },
                      "welcome keeps a prominent mascot illustration rather than a text-only setup")
            }
        } else { check(false, "setup has a content view at step \(step.rawValue)") }
        if step != .practice { _ = window.perform(NSSelectorFromString("next")) }
    }
    check(prompts == 0 && notesCalls == 0, "all setup navigation remains free of prompts and Notes access")
    check(SetupPreferences.currentStep(in: defaults) == .practice, "navigation persists the unfinished step before closing")
    let resumed = SetupWindowController(onFinish: {}, onConfigureNotes: {}, onPractice: {}, onRestart: {}, access: denied, defaults: defaults)
    let resumedText = resumed.window?.contentView.map { descendants($0).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n") } ?? ""
    check(resumedText.contains(SampleText.value("Deferred lookup heading fragment")), "recreated setup resumes the unfinished denied practice step truthfully")
    resumed.close()
    _ = window.perform(NSSelectorFromString("deferSetup"))
    check(finishCalls == 1 && SetupPreferences.hasCompleted(in: defaults), "explicit defer finishes the introduction once")
    check(defaults.string(forKey: SetupPreferences.resultKey) == SetupCompletion.deferred.rawValue && prompts == 0,
          "denied setup stays deferred without requesting real permissions")

    let granted = SetupPermissionAccess(screenCapture: { true }, accessibility: { true }, automation: { _, prompt in
        if prompt { prompts += 1 }
        return .granted
    }, requestScreenCapture: { prompts += 1 }, requestAccessibility: { prompts += 1 }, openSettings: { _ in prompts += 1 })
    let ready = SetupWindowController(onFinish: {}, onConfigureNotes: {}, onPractice: {}, onRestart: {}, access: granted, defaults: defaults)
    ready.window?.appearance = NSAppearance(named: .darkAqua)
    for step in SetupStep.allCases {
        if let root = ready.window?.contentView {
            root.layoutSubtreeIfNeeded()
            let controls = descendants(root).filter { !$0.isHidden && ($0 is NSTextField || $0 is NSButton) }
            check(controls.allSatisfy { root.bounds.insetBy(dx: -1, dy: -1).contains($0.convert($0.bounds, to: root)) },
                  "granted setup controls fit dark appearance at step \(step.rawValue)")
            if step == .practice {
                check(controls.compactMap { ($0 as? NSTextField)?.stringValue }.contains { $0.contains(SampleText.value("Ready heading fragment")) },
                      "granted final step communicates lookup readiness")
            }
        } else { check(false, "granted setup has a content view") }
        if step != .practice { _ = ready.perform(NSSelectorFromString("next")) }
    }
    check(prompts == 0, "branded setup navigation in both capability states never requests consent")
    ready.close()

    // Reproduce reopening deferred setup, then macOS terminating the app during consent.
    SetupPreferences.finish(.deferred, in: defaults)
    var resumesAfterSystemRelaunch = false
    let permissionHandoff = SetupPermissionAccess(screenCapture: { false }, accessibility: { false }, automation: { _, _ in .notGranted },
        requestScreenCapture: {
            resumesAfterSystemRelaunch = SetupPreferences.shouldPresentOnLaunch(in: defaults)
        }, requestAccessibility: {}, openSettings: { _ in })
    let interrupted = SetupWindowController(onFinish: {}, onConfigureNotes: {}, onPractice: {}, onRestart: {},
        access: permissionHandoff, defaults: defaults)
    _ = interrupted.perform(NSSelectorFromString("next"))
    _ = interrupted.perform(NSSelectorFromString("requestScreen"))
    check(resumesAfterSystemRelaunch, "system permission restart restores unfinished setup even after an earlier deferred completion")
    check(SetupPreferences.currentStep(in: defaults) == .screenCapture, "permission handoff retains the screen step before the system can terminate the app")
    interrupted.close()
    let afterRestart = SetupWindowController(onFinish: {}, onConfigureNotes: {}, onPractice: {}, onRestart: {},
        access: granted, defaults: defaults)
    let restoredText = afterRestart.window?.contentView.map { descendants($0).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n") } ?? ""
    check(restoredText.contains(SampleText.value("Screen lookup heading fragment")) && restoredText.contains(SampleText.value("Granted permission badge fragment")),
          "a replacement process restores the same permission page and checks the new permission state")
    _ = afterRestart.perform(NSSelectorFromString("deferSetup"))
    check(!SetupPreferences.shouldPresentOnLaunch(in: defaults), "explicitly finishing recovered setup stops future automatic presentation")

    var expectedStep = SetupStep.screenCapture
    var handoffs = 0
    func verifyCheckpoint() {
        handoffs += 1
        let persisted = UserDefaults(suiteName: suiteName)!
        check(SetupPreferences.shouldPresentOnLaunch(in: persisted) && SetupPreferences.currentStep(in: persisted) == expectedStep,
              "external permission/settings/restart handoff persists the current step before invoking its callback")
    }
    let checkpointAccess = SetupPermissionAccess(screenCapture: { false }, accessibility: { false }, automation: { _, prompt in
        if prompt { verifyCheckpoint() }
        return .notGranted
    }, requestScreenCapture: { verifyCheckpoint() }, requestAccessibility: { verifyCheckpoint() }, openSettings: { _ in verifyCheckpoint() })
    let checkpoints = SetupWindowController(onFinish: {}, onConfigureNotes: { verifyCheckpoint() }, onPractice: {},
        onRestart: { verifyCheckpoint() }, access: checkpointAccess, defaults: defaults)
    _ = checkpoints.perform(NSSelectorFromString("next"))
    for selector in ["requestScreen", "openScreen", "restart"] {
        defaults.removeObject(forKey: SetupPreferences.stepKey)
        _ = checkpoints.perform(NSSelectorFromString(selector))
    }
    _ = checkpoints.perform(NSSelectorFromString("next"))
    expectedStep = .sources
    for selector in ["requestAccessibility", "requestSafari"] {
        defaults.removeObject(forKey: SetupPreferences.stepKey)
        _ = checkpoints.perform(NSSelectorFromString(selector))
    }
    _ = checkpoints.perform(NSSelectorFromString("next"))
    expectedStep = .notes
    for selector in ["requestNotes", "configureNotes"] {
        defaults.removeObject(forKey: SetupPreferences.stepKey)
        _ = checkpoints.perform(NSSelectorFromString(selector))
    }
    check(handoffs == 8, "all screen, accessibility, browser, Notes, settings and restart handoffs were exercised")
    checkpoints.close()

    // Switch the real welcome selector without presenting a window or requesting system access.
    SetupPreferences.finish(.deferred, in: defaults)
    UILanguage.system.save(in: defaults)
    var persistedEnglishBeforeConsent = false
    var languageRestarts = 0
    let languageAccess = SetupPermissionAccess(screenCapture: { false }, accessibility: { false },
        automation: { _, _ in .notGranted }, requestScreenCapture: {
            let persisted = UserDefaults(suiteName: suiteName)!
            persistedEnglishBeforeConsent = UILanguage.load(in: persisted) == .english
                && SetupPreferences.currentStep(in: persisted) == .screenCapture
        }, requestAccessibility: {}, openSettings: { _ in })
    let translated = SetupWindowController(onFinish: {}, onConfigureNotes: {}, onPractice: {}, onRestart: { languageRestarts += 1 },
        access: languageAccess, defaults: defaults)
    func languageChoices(in controller: SetupWindowController) -> [NSButton] {
        controller.window?.contentView.map { descendants($0).compactMap { $0 as? NSButton }.filter {
            $0.action == NSSelectorFromString("changeInterfaceLanguage:")
        } } ?? []
    }
    let choices = languageChoices(in: translated)
    check(choices.count == 3 && choices.allSatisfy { !$0.isHidden && $0.bounds.width >= 400 && $0.bounds.height >= 44 },
          "all language choices are expanded with prominent full-width targets on the first page")
    check(choices.filter { $0.state == .on }.map(\.tag) == [0],
          "welcome visibly selects only the system language preference by default")
    let systemName = UILanguage.system.resolved() == .simplifiedChinese ? SampleText.value("Simplified Chinese") : "English"
    check(choices.first?.title.hasSuffix(systemName) == true,
          "the system option shows the language that will actually be used")
    check(choices.contains { $0.title == SampleText.value("Simplified Chinese") } && choices.contains { $0.title == "English" },
          "expanded language choices use readable language autonyms")
    choices.first { $0.tag == 2 }?.performClick(nil)
    check(UILanguage.load(in: UserDefaults(suiteName: suiteName)!) == .english,
          "welcome selection persists immediately before navigation or consent")
    let englishText = translated.window?.contentView.map { descendants($0).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n") } ?? ""
    check(englishText.contains("Choose your language.") && englishText.contains("Enable screen lookup"),
          "language selection immediately translates the page and sidebar without restarting")
    check(languageChoices(in: translated).filter { $0.state == .on }.map(\.tag) == [2],
          "the rebuilt language controls keep exactly the explicitly selected option")
    languageChoices(in: translated).first { $0.tag == 1 }?.performClick(nil)
    check(UILanguage.load(in: defaults) == .simplifiedChinese && languageChoices(in: translated).filter { $0.state == .on }.map(\.tag) == [1],
          "switching back to Chinese updates both the saved preference and visible selection")
    languageChoices(in: translated).first { $0.tag == 0 }?.performClick(nil)
    check(UILanguage.load(in: defaults) == .system && languageChoices(in: translated).filter { $0.state == .on }.map(\.tag) == [0],
          "users can restore system language before continuing")
    languageChoices(in: translated).first { $0.tag == 2 }?.performClick(nil)
    check(languageRestarts == 0, "changing interface language never requests an application restart")
    if let root = translated.window?.contentView,
       let autonym = languageChoices(in: translated).first(where: { $0.tag == 1 }),
       let system = languageChoices(in: translated).first(where: { $0.tag == 0 }) {
        // macOS 15 exposes an NSButtonTextField below radio buttons; newer systems may not.
        let internalLabel = NSTextField(labelWithString: autonym.title)
        autonym.addSubview(internalLabel)
        check(untranslatedEnglishSetupLabels(in: root).isEmpty,
              "native language names remain valid when AppKit exposes an internal text field")
        internalLabel.removeFromSuperview()
        let originalSystemTitle = system.title
        system.title = "System default — " + SampleText.value("Simplified Chinese")
        check(untranslatedEnglishSetupLabels(in: root).isEmpty,
              "an English interface can show the system language's native Chinese name")
        system.title = originalSystemTitle
        let unexpected = SampleText.value("Screen lookup heading fragment")
        let label = NSTextField(labelWithString: unexpected)
        root.addSubview(label)
        check(untranslatedEnglishSetupLabels(in: root) == [unexpected],
              "the semantic language check still rejects untranslated ordinary labels")
        label.removeFromSuperview()
        let button = NSButton(title: unexpected, target: nil, action: nil)
        root.addSubview(button)
        check(untranslatedEnglishSetupLabels(in: root) == [unexpected],
              "the semantic language check also rejects untranslated ordinary button titles")
        button.removeFromSuperview()
        let originalAutonym = autonym.title
        autonym.title = unexpected
        check(untranslatedEnglishSetupLabels(in: root) == [unexpected],
              "a language selector does not exempt arbitrary untranslated text")
        autonym.title = originalAutonym
    } else { check(false, "the real welcome controls are available for semantic localization checks") }
    for step in SetupStep.allCases {
        if let root = translated.window?.contentView {
            root.layoutSubtreeIfNeeded()
            let controls = descendants(root).filter { !$0.isHidden && ($0 is NSTextField || $0 is NSButton) }
            check(controls.allSatisfy { root.bounds.insetBy(dx: -1, dy: -1).contains($0.convert($0.bounds, to: root)) },
                  "English setup controls fit at step \(step.rawValue)")
            let untranslated = untranslatedEnglishSetupLabels(in: root)
            check(untranslated.isEmpty,
                  "English setup has no untranslated Chinese labels at step \(step.rawValue): \(untranslated)")
        }
        if step == .screenCapture { _ = translated.perform(NSSelectorFromString("requestScreen")) }
        if step != .practice { _ = translated.perform(NSSelectorFromString("next")) }
    }
    check(persistedEnglishBeforeConsent, "language choice and current step survive a system permission restart handoff")
    translated.close()
    let translatedResume = SetupWindowController(onFinish: {}, onConfigureNotes: {}, onPractice: {}, onRestart: {},
        access: languageAccess, defaults: defaults)
    let resumedEnglish = translatedResume.window?.contentView.map { descendants($0).compactMap { ($0 as? NSTextField)?.stringValue }.joined() } ?? ""
    check(resumedEnglish.contains("Lookup is not ready yet."), "replacement setup keeps the chosen language and unfinished step")
    translatedResume.close()
}
