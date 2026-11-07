import Foundation

@MainActor func runProductTests() async {
    check(ProductRuntime.launchMode(arguments: ["WordNest"], allowsDevelopment: false) == .normal, "production normal launch is accepted")
    for flag in ProductRuntime.developmentCommands {
        check(ProductRuntime.launchMode(arguments: ["WordNest", flag], allowsDevelopment: false) == .invalid,
              "production rejects development entry point: \(flag)")
        check(ProductRuntime.launchMode(arguments: ["WordNest", flag], allowsDevelopment: true) == .development(flag),
              "explicit development build accepts one known entry point: \(flag)")
    }
    check(ProductRuntime.launchMode(arguments: ["WordNest", "--unknown"], allowsDevelopment: true) == .invalid, "unknown arguments cannot silently launch setup")
    check(ProductRuntime.launchMode(arguments: ["WordNest", "--ui-self-test", "--alphabet-integration-test"], allowsDevelopment: true) == .invalid,
          "ambiguous safe and writable development commands are rejected")
    check(ProductRuntime.launchMode(arguments: ["WordNest", "--source-readback-test", "--source-test-bundle=fixture"], allowsDevelopment: true)
          == .development("--source-readback-test"), "development parameters require a known primary command")
    let appURL = URL(fileURLWithPath: "/Applications/WordNest.app")
    let parent = RestartParentCandidate(processID: 123, bundleIdentifier: "fixture.wordnest", bundleURL: appURL)
    func restartParent(_ raw: String, candidate: RestartParentCandidate = parent) -> Int32? {
        RestartHandoff.parentProcess(environment: [RestartHandoff.parentPIDKey: raw], ownPID: 456,
                                     bundleIdentifier: "fixture.wordnest", bundleURL: appURL, candidates: [candidate])
    }
    check(restartParent("123") == 123, "restart handoff accepts only the identified copy of the same application")
    check(restartParent("not-a-pid") == nil && restartParent("0") == nil && restartParent("456") == nil,
          "restart rejects malformed, invalid and self process IDs")
    check(restartParent("123", candidate: RestartParentCandidate(processID: 123, bundleIdentifier: "other.app", bundleURL: appURL)) == nil,
          "restart cannot wait on an unrelated bundle")
    check(restartParent("123", candidate: RestartParentCandidate(processID: 123, bundleIdentifier: "fixture.wordnest", bundleURL: URL(fileURLWithPath: "/Volumes/Other/WordNest.app"))) == nil,
          "restart cannot substitute another installation with the same bundle ID")
    check(restartParent("789") == nil, "restart ignores a parent that has already disappeared from running applications")
    check(ProductRuntime.launchMode(arguments: ["WordNest", "--restart", "--ui-self-test"], allowsDevelopment: false) == .invalid,
          "production restart metadata adds no development launch exception")
    // A controlled child stays alive until explicitly terminated; no app launch or consent is involved.
    let child = Process()
    let input = Pipe()
    child.executableURL = URL(fileURLWithPath: "/bin/cat")
    child.standardInput = input
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    do {
        try child.run()
        let timedOut = await RestartHandoff.waitForExit(processID: child.processIdentifier, timeout: 0.02)
        check(!timedOut && child.isRunning, "restart waiting is bounded when the old process does not terminate")
        let exitWait = Task { await RestartHandoff.waitForExit(processID: child.processIdentifier, timeout: 2) }
        await Task.yield()
        child.terminate()
        let observedExit = await exitWait.value
        check(observedExit, "restart continuation proceeds only after the observed old process exits")
        child.waitUntilExit()
        let alreadyExited = await RestartHandoff.waitForExit(processID: child.processIdentifier, timeout: 0.1)
        check(alreadyExited,
              "restart handles an old process that exited before observation")
    } catch { check(false, "restart process-exit fixture launched: \(error)") }
    if child.isRunning { child.terminate(); child.waitUntilExit() }
    let oldName = "WordNest.MigrationOld.\(UUID().uuidString)"
    let newName = "WordNest.MigrationNew.\(UUID().uuidString)"
    let old = UserDefaults(suiteName: oldName)!, current = UserDefaults(suiteName: newName)!
    defer { old.removePersistentDomain(forName: oldName); current.removePersistentDomain(forName: newName) }
    let target = NotesDestination(accountID: "fixture-account", accountName: "Local", folderID: "fixture-folder", folderName: "Vocabulary")
    let data = try! JSONEncoder().encode(NotesConfiguration(storage: target))
    old.set(data, forKey: "vocabulary.appleNotes.configuration.v2")
    old.set("fr-FR", forKey: "lookup.sourceLanguage.v1")
    old.set(true, forKey: SetupPreferences.completedKey)
    LegacyPreferences.migrate(from: old, to: current)
    check(current.data(forKey: "vocabulary.appleNotes.configuration.v2") == data, "validated legacy Notes configuration migrates without rewriting Notes")
    check(current.string(forKey: "lookup.sourceLanguage.v1") == "fr-FR", "legacy recognition language is retained")
    check(!SetupPreferences.hasCompleted(in: current), "new public bundle cannot inherit stale permission or onboarding claims")
    current.set("ja-JP", forKey: "lookup.sourceLanguage.v1")
    LegacyPreferences.migrate(from: old, to: current)
    check(current.string(forKey: "lookup.sourceLanguage.v1") == "ja-JP", "existing product preferences win over prototype settings")
    current.removePersistentDomain(forName: newName)
    old.set(Data("invalid".utf8), forKey: "vocabulary.appleNotes.configuration.v2")
    old.set("not-a-language", forKey: "lookup.sourceLanguage.v1")
    LegacyPreferences.migrate(from: old, to: current)
    check(current.object(forKey: "vocabulary.appleNotes.configuration.v2") == nil && current.object(forKey: "lookup.sourceLanguage.v1") == nil,
          "corrupt legacy settings do not become product configuration")
}
