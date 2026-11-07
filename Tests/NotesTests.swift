import AppKit
import Carbon

/// A save-interface fake with fixed content and controlled results; never connects to user Notes.
actor TestNotesClient: NotesSaving {
    enum Mode { case success, denied, uncertain, hold }
    private var mode: Mode = .success
    private var pending: CheckedContinuation<VocabularyReceipt, Error>?
    private var lookup: VocabularyReceipt?
    private(set) var saves = 0
    private(set) var finds = 0

    func setMode(_ value: Mode) { mode = value }
    func setLookup(_ value: VocabularyReceipt?) { lookup = value }
    func release() { pending?.resume(returning: VocabularyReceipt(noteID: "test-note")); pending = nil }
    func save(_ entry: VocabularyEntry, to destination: NotesDestination) async throws -> VocabularyReceipt {
        saves += 1
        switch mode {
        case .success: return VocabularyReceipt(noteID: "test-note")
        case .denied: throw NotesFailure.permissionDenied
        case .uncertain: throw NotesFailure.uncertain(SampleText.value("Simulated timeout"))
        case .hold: return try await withCheckedThrowingContinuation { pending = $0 }
        }
    }
    func find(_ entry: VocabularyEntry, in destination: NotesDestination) throws -> VocabularyReceipt? {
        finds += 1
        if case .denied = mode { throw NotesFailure.permissionDenied }
        return lookup
    }
}

@MainActor func runNotesTests() async {
    let entry = VocabularyEntry(id: UUID(uuidString: "3BB06504-331D-4C28-BA81-82B605385911")!,
        word: "don't <script>", definition: SampleText.value("Multiline definition input"), sentence: SampleText.value("Subtitle HTML escape input"), createdAt: Date(timeIntervalSince1970: 0))
    check(entry.notesHTML.contains("don&#39;t &lt;script&gt;"), "note title is HTML escaped")
    check(!entry.notesHTML.contains("<script>"), "word cannot inject HTML elements")
    check(entry.notesHTML.contains(SampleText.value("Multiline definition escaped")), "definition preserves escaped multiline text")
    check(entry.notesHTML.contains(SampleText.value("Subtitle HTML escaped")), "subtitle text is escaped independently")
    check(entry.notesHTML.contains("1970-01-01T00:00:00Z") && entry.notesHTML.contains(entry.marker), "note has stable entry marker and creation date")
    let testEntry = VocabularyEntry(word: "happiness", definition: SampleText.value("Happiness meaning"), sentence: "fixed test only", isTestEntry: true)
    check(testEntry.notesHTML.contains(SampleText.value("Single test note heading")), "integration test note is clearly labeled")
    let complete = SampleText.format("Complete note readback", [String(describing: testEntry.marker)])
    check(testEntry.isPresent(in: complete), "readback requires all vocabulary fields")
    check(!testEntry.isPresent(in: testEntry.marker), "entry marker alone cannot confirm complete save")
    check(!testEntry.isPresent(in: complete.replacingOccurrences(of: SampleText.value("Happiness meaning"), with: "")), "missing meaning is not accepted during reconciliation")
    check(!testEntry.isPresent(in: complete.replacingOccurrences(of: "fixed test only", with: "")), "missing source sentence is not accepted during reconciliation")
    let second = VocabularyEntry(word: entry.word, definition: entry.definition, sentence: "other context")
    check(second.id != entry.id, "separate lookup context has independent collection identity")
    let payload = SampleText.value("AppleScript argument injection fixture")
    let event = AppleNotesClient.event(handler: "saveEntry", arguments: [payload, entry.notesHTML])
    let arguments = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
    check(arguments?.atIndex(1)?.stringValue == payload && arguments?.atIndex(2)?.stringValue == entry.notesHTML,
          "Apple Event transports untrusted content as data rather than source code")
    // Compile fixed Notes scripts to validate syntax and terminology without executing any handler.
    AppleNotesClient.prepare()
    var compileError: NSDictionary?
    let compiled = NSAppleScript(source: AppleNotesClient.scriptSource + "\n" + AlphabetNotesScript.source)?.compileAndReturnError(&compileError)
    check(compiled == true, "Notes object script compiles without executing or requesting Notes access: \(compileError?.description ?? "ok")")
    let target = NotesDestination(accountID: "account-1", accountName: "test", folderID: "folder-1", folderName: SampleText.value("Vocabulary folder name"))
    let duplicateName = NotesDestination(accountID: "account-2", accountName: "test", folderID: "folder-2", folderName: SampleText.value("Vocabulary folder name"))
    check(target != duplicateName, "same-named destinations remain distinct by account and folder IDs")
    let roundTrip = try? JSONDecoder().decode(NotesDestination.self, from: JSONEncoder().encode(target))
    check(roundTrip == target, "destination configuration round trips without credentials or vocabulary data")

    let client = TestNotesClient()
    let collector = VocabularyCollector(client: client)
    await client.setMode(.hold)
    let first = Task { await collector.collect(entry, to: target) }
    while await client.saves == 0 { await Task.yield() }
    check(collector.state(for: entry, destination: target) == .saving, "collection reports saving before completion")
    await collector.collect(entry, to: target)
    let pendingSaves = await client.saves
    check(pendingSaves == 1, "duplicate click while pending does not issue another save")
    await client.release()
    await first.value
    check(collector.state(for: entry, destination: target) == .saved(VocabularyReceipt(noteID: "test-note")), "confirmed receipt changes collection to saved")
    await collector.collect(entry, to: target)
    let savedCount = await client.saves
    check(savedCount == 1, "saved card cannot create duplicate note")
    let renamed = NotesDestination(accountID: target.accountID, accountName: "renamed", folderID: target.folderID, folderName: "renamed")
    check(collector.state(for: entry, destination: renamed) == .saved(VocabularyReceipt(noteID: "test-note")), "renaming a destination does not reset its saved state")

    await client.setMode(.denied)
    await collector.collect(second, to: target)
    if case .failed(let message) = collector.state(for: second, destination: target) {
        check(message.contains(SampleText.value("Automation guidance fragment")), "permission denial produces actionable failure rather than success")
    } else { check(false, "permission denial produces failure") }
    await client.setMode(.success)
    await collector.collect(second, to: target)
    check(collector.state(for: second, destination: target) == .saved(VocabularyReceipt(noteID: "test-note")), "known failed save can be retried")
    await collector.collect(second, to: duplicateName)
    check(collector.state(for: second, destination: duplicateName) == .saved(VocabularyReceipt(noteID: "test-note")), "new destination has independent save state")

    let unknown = VocabularyEntry(word: "happiness", definition: SampleText.value("Happiness meaning"), sentence: "test sentence")
    await client.setMode(.uncertain)
    await collector.collect(unknown, to: target)
    if case .uncertain = collector.state(for: unknown, destination: target) { check(true, "timeout after write is marked uncertain") }
    else { check(false, "timeout after write is marked uncertain") }
    let beforeFind = await client.saves
    await collector.collect(unknown, to: target)
    let afterFind = await client.saves
    check(beforeFind == afterFind, "reconciling unknown result never creates a second note")
    if case .uncertain = collector.state(for: unknown, destination: target) { check(true, "not found yet does not silently re-enable creation") }
    else { check(false, "not found yet remains uncertain") }
    await client.setMode(.denied)
    await collector.collect(unknown, to: target)
    if case .uncertain = collector.state(for: unknown, destination: target) { check(true, "failed reconciliation preserves unknown state") }
    else { check(false, "failed reconciliation preserves unknown state") }
    await client.setMode(.success)
    await client.setLookup(VocabularyReceipt(noteID: "late-result"))
    await collector.collect(unknown, to: target)
    check(collector.state(for: unknown, destination: target) == .saved(VocabularyReceipt(noteID: "late-result")), "readback confirms late result without another write")
    let blank = VocabularyEntry(word: " ", definition: nil, sentence: "")
    let beforeBlank = await client.saves
    await collector.collect(blank, to: target)
    let afterBlank = await client.saves
    check(beforeBlank == afterBlank, "empty word is rejected before destination write")

    // Replay the system boundary: assignment rejection may still create a page; preserve the transaction and block writes.
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("wordnest-smart-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let journal = NotesWriteJournal(directory: temporary)
    do {
        // Replay a legacy page through the real save/readback boundary, including a lost write receipt.
        let migrationJournal = NotesWriteJournal(directory: temporary.appendingPathComponent("inline-history"))
        var storedHTML = SampleText.value("Legacy history H page HTML")
        var attachments = 2
        var writes = 0
        let legacy = try AlphabetPage.parse(html: storedHTML, letter: "H", isTest: false, attachmentCount: attachments)
        let oldEvent = NotesWriteEvent(entryID: legacy.rows[0].occurrences.last!.id,
            destinationKey: target.accountID + "\n" + target.folderID, letter: "H", isTest: false,
            expectedDigest: legacy.digest, expectedCount: legacy.rows[0].count, noteID: "existing-note", confirmed: false)
        try migrationJournal.locked { events in events = [oldEvent]; try migrationJournal.persist(events) }
        let migrationClient = AppleNotesClient(journal: migrationJournal) { handler, arguments in
            let fields: [String]
            if handler == "bookSnapshot" { fields = ["existing-note", storedHTML, String(attachments)] }
            else if handler == "putBook" {
                writes += 1
                check(arguments[6] == "2", "migration checks the original two native table attachments before writing")
                check(arguments[4] == storedHTML, "migration checks the exact original Notes body before writing")
                storedHTML = arguments[5]
                attachments = 1
                let native = try XMLDocument(xmlString: storedHTML, options: [.documentTidyHTML])
                let tables = try native.nodes(forXPath: "//table")
                check(tables.count == 1, "real Notes adapter writes one table during legacy migration")
                fields = ["writeError", "-1712", "Simulated lost migration receipt", "update"]
            } else { throw NotesFailure.invalidResponse }
            let result = NSAppleEventDescriptor.list()
            for (i, value) in fields.enumerated() { result.insert(NSAppleEventDescriptor(string: value), at: i + 1) }
            return result
        }
        let incoming = VocabularyEntry(word: "happiness", definition: nil, sentence: "A new migration context.",
            source: CollectionSource(url: "https://example.com/video", title: "Migration source"))
        do { _ = try await migrationClient.save(incoming, to: target); check(false, "lost migration receipt stays uncertain") }
        catch NotesFailure.uncertain { check(true, "lost migration receipt stays uncertain") }
        let recovered = try await migrationClient.save(incoming, to: target)
        let reopened = AppleNotesClient(journal: migrationJournal) { _, _ in
            let result = NSAppleEventDescriptor.list()
            for (i, value) in ["existing-note", storedHTML, "1"].enumerated() { result.insert(NSAppleEventDescriptor(string: value), at: i + 1) }
            return result
        }
        let afterRestart = try await reopened.find(incoming, in: target)
        let migrated = try AlphabetPage.parse(html: storedHTML, letter: "H", isTest: false, attachmentCount: 1)
        check(writes == 1 && recovered.collectionCount == legacy.rows[0].count + 1 && afterRestart == recovered,
              "retry and reopened journal confirm a migrated collection without another write or count increase")
        check(migrated.rows[0].occurrences.dropLast() == legacy.rows[0].occurrences[...],
              "migration preserves every legacy source event before appending the new event")
        try migrationJournal.locked { events in
            check(events.count == 2 && events.allSatisfy(\.confirmed), "legacy and new pending writes reconcile across the table layout change")
        }
    } catch { check(false, "single-table adapter migration: \(error)") }

    var smartWrites = 0
    let smartClient = AppleNotesClient(journal: journal) { handler, _ in
        let fields: [String]
        if handler == "bookSnapshot" { fields = ["", "", "0"] }
        else { smartWrites += 1; fields = ["writeError", "-10000", SampleText.value("Native smart folder full error"), "create"] }
        let result = NSAppleEventDescriptor.list()
        for (i, field) in fields.enumerated() { result.insert(NSAppleEventDescriptor(string: field), at: i + 1) }
        return result
    }
    do {
        _ = try await smartClient.save(testEntry, to: target)
        check(false, "Smart Folder rejection is not success")
    } catch {
        check(!error.localizedDescription.contains(SampleText.value("Uncertain save guidance fragment")) && error.localizedDescription.contains(SampleText.value("Ordinary folder guidance fragment")),
              "Smart Folder creation rejection gives configuration guidance rather than uncertain result")
    }
    do { try journal.locked { check($0.count == 1 && !$0[0].confirmed && $0[0].destinationRejected == true, "Smart Folder assignment rejection retains pending transaction and blocks target") } }
    catch { check(false, "Smart Folder rejection journal readback: \(error)") }

    let smartCollector = VocabularyCollector(client: smartClient)
    await smartCollector.collect(testEntry, to: target)
    if case .needsConfiguration = smartCollector.state(for: testEntry, destination: target) {
        check(true, "Smart Folder rejection routes the card to destination settings")
    } else { check(false, "Smart Folder rejection routes the card to destination settings") }
    let anotherEntry = VocabularyEntry(word: "another", definition: nil, sentence: "A separate query.", isTestEntry: true)
    await smartCollector.collect(anotherEntry, to: target)
    check(smartWrites == 1, "same and new queries cannot repeat a rejected Smart Folder write")

    // Other errors sharing the generic code, update-stage rejections, and timeouts must not become safe retries.
    for (index, failure) in [
        ["-10000", SampleText.value("Unrecognized native system error"), "create"],
        ["-10000", SampleText.value("Native smart folder short error"), "update"],
        ["-1712", SampleText.value("Native smart folder short error"), "create"]
    ].enumerated() {
        let pendingJournal = NotesWriteJournal(directory: temporary.appendingPathComponent("uncertain-\(index)"))
        var writes = 0
        let uncertainClient = AppleNotesClient(journal: pendingJournal) { handler, _ in
            let fields: [String]
            if handler == "bookSnapshot" { fields = ["", "", "0"] }
            else { writes += 1; fields = ["writeError"] + failure }
            let result = NSAppleEventDescriptor.list()
            for (i, field) in fields.enumerated() { result.insert(NSAppleEventDescriptor(string: field), at: i + 1) }
            return result
        }
        for _ in 0..<2 {
            do { _ = try await uncertainClient.save(testEntry, to: target); check(false, "unknown write cannot report saved") }
            catch NotesFailure.uncertain { check(true, "unconfirmed write remains uncertain (\(index))") }
            catch { check(false, "unconfirmed write error type: \(error)") }
        }
        check(writes == 1, "retry does not issue a second unconfirmed write (\(index))")
        do { try pendingJournal.locked { check($0.count == 1 && !$0[0].confirmed, "unconfirmed transaction is retained (\(index))") } }
        catch { check(false, "pending journal readback: \(error)") }
    }

    let split = NotesConfiguration(storage: target, browsing: duplicateName)
    check(split.readingDestination == duplicateName && split.storage == target, "browsing selection cannot redirect the save destination")
    check(NotesConfiguration(storage: target).readingDestination == target, "ordinary folder setup reads its own storage by default")
    check((try? JSONDecoder().decode(NotesConfiguration.self, from: JSONEncoder().encode(split))) == split,
          "independent storage and browsing destinations survive configuration round trip")
}
