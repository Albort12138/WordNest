import Foundation

func runAlphabetTests() {
    // External entities must never inject file contents into local vocabulary.
    let probe = FileManager.default.temporaryDirectory.appendingPathComponent("WordNest.EntityProbe." + UUID().uuidString)
    let sentinel = "PRIVATE_ENTITY_PROBE_" + UUID().uuidString
    do {
        try Data(sentinel.utf8).write(to: probe)
        defer { try? FileManager.default.removeItem(at: probe) }
        let entry = VocabularyEntry(word: "hello", definition: "ENTITY_PLACEHOLDER", sentence: "Fixed context")
        let body = AlphabetPage(letter: "H", isTest: false, rows: [BookRow.from(entry)]).html
            .replacingOccurrences(of: "ENTITY_PLACEHOLDER", with: "&external;")
        let input = #"<!DOCTYPE html [<!ENTITY external SYSTEM "\#(probe.absoluteString)">]>"# + body
        if let parsed = try? AlphabetPage.parse(html: input, letter: "H", isTest: false, attachmentCount: 1) {
            check(!parsed.rows.contains { $0.definition.contains(sentinel) }, "Notes HTML does not expand external file entities")
        } else { check(true, "Notes HTML rejects external-entity input") }
        check(!DictionaryText.plainText(input).contains(sentinel), "dictionary HTML does not expand external file entities")
    } catch { check(false, "external-entity fixture: \(error)") }
    func rejects(_ label: String, _ operation: () throws -> Void) {
        do { try operation(); check(false, label) } catch { check(true, label) }
    }
    check((try? BookRow.letter(" Happiness ")) == "H", "letter classification ignores case and surrounding spaces")
    check((try? BookRow.letter("don't")) == "D", "apostrophe word goes into its first letter page")
    check((try? BookRow.letter(SampleText.value("Chinese sample word"))) == SampleText.value("Han characters"), "Han initial uses its own script page")
    rejects("blank initial is rejected") { _ = try BookRow.letter(" ") }
    let fixed = Date(timeIntervalSince1970: 1_730_000_000)
    let first = VocabularyEntry(word: "happiness", definition: SampleText.value("Happiness HTML escape entry"), sentence: "I found happiness.", createdAt: fixed)
    let second = VocabularyEntry(word: "Happiness", definition: first.definition, sentence: "Happiness matters.")
    var page = AlphabetPage(letter: "H", isTest: false, rows: [])
    do {
        let firstCount = try page.collect(first)
        let firstDate = page.rows[0].firstAdded
        let secondCount = try page.collect(second)
        check(firstCount == 1 && secondCount == 2 && page.rows.count == 1, "same word retains one row and increments total count")
        check(page.rows[0].sentences == first.sentence + "\n" + second.sentence, "new context is appended without replacing prior context")
        _ = try page.collect(VocabularyEntry(word: second.word, definition: second.definition, sentence: second.sentence))
        check(page.rows[0].count == 3 && page.rows[0].sentences.components(separatedBy: "\n").count == 2, "another occurrence increments while identical context remains unique")
        check(page.rows[0].firstAdded == firstDate, "recollection preserves first collection date")
        let parsed = try AlphabetPage.parse(html: page.html, letter: "H", isTest: false, attachmentCount: 1)
        check(parsed.rows == page.rows && parsed.digest == page.digest && parsed.editable, "generated single table round trips through HTML parser")
        // Simulate native Notes wrappers and missing entity semicolons; all content must still round-trip.
        let native = page.html.replacingOccurrences(of: "<table", with: "<div><object><table")
            .replacingOccurrences(of: "</table>", with: "</table></object><br></div>")
            .replacingOccurrences(of: "&amp;", with: "&amp ")
        let normalizedNative = native.replacingOccurrences(of: "&amp  ", with: "&amp ")
        let nativeParsed = try AlphabetPage.parse(html: normalizedNative, letter: "H", isTest: false, attachmentCount: 1)
        check(nativeParsed.rows[0].definition.contains("&") && nativeParsed.rows.count == 1, "native object table and entity normalization are readable")
        check(nativeParsed.editable, "native table attachment is allowed without allowing other attachments")
        let withAttachment = try AlphabetPage.parse(html: page.html, letter: "H", isTest: false, attachmentCount: 2)
        check(!withAttachment.editable, "page with extra attachment is read only")
        let withComment = try AlphabetPage.parse(html: page.html + "<p>Keep my separate note</p>", letter: "H", isTest: false, attachmentCount: 1)
        check(!withComment.editable && withComment.rows.count == 1, "manual text outside table is readable but protected from overwrite")
        let tagged = try AlphabetPage.parse(html: page.html + SampleText.value("Additional notebook tag HTML"), letter: "H", isTest: false, attachmentCount: 1)
        check(!tagged.editable && tagged.rows == page.rows, "tag text is readable without allowing a body rewrite that could remove Smart Folder membership")
        let unowned = try AlphabetPage.parse(html: page.html.replacingOccurrences(of: page.owner, with: "my own vocabulary"), letter: "H", isTest: false, attachmentCount: 1)
        check(!unowned.editable, "unmanaged page is never silently adopted for writes")
        rejects("plain text object placeholder is not mistaken for table cells") { _ = try AlphabetPage.parse(html: "H\n\u{fffc}", letter: "H", isTest: false, attachmentCount: 1) }
        rejects("wrong columns are rejected rather than truncating data") { _ = try AlphabetPage.parse(html: page.html.replacingOccurrences(of: SampleText.value("Collections"), with: "other"), letter: "H", isTest: false, attachmentCount: 1) }
        rejects("invalid count cannot overflow or reset silently") { _ = try AlphabetPage.parse(html: page.html.replacingOccurrences(of: "<div>3</div>", with: "<div>-1</div>"), letter: "H", isTest: false, attachmentCount: 1) }
        rejects("letter mismatch never moves a row implicitly") { _ = try AlphabetPage.parse(html: page.html, letter: "A", isTest: false, attachmentCount: 1) }
        let row = page.rows[0]
        rejects("duplicate words in a manually edited page require review") { _ = try AlphabetPage.parse(html: AlphabetPage(letter: "H", isTest: false, rows: [row, row]).html, letter: "H", isTest: false, attachmentCount: 1) }
        let malicious = VocabularyEntry(word: "hello<script>", definition: "\"quoted\" & <div>not markup</div>", sentence: "a < b & b > c")
        var injected = AlphabetPage(letter: "H", isTest: false, rows: [])
        _ = try injected.collect(malicious)
        let safe = try AlphabetPage.parse(html: injected.html, letter: "H", isTest: false, attachmentCount: 1)
        check(!injected.html.contains("<script>") && safe.rows[0].word == malicious.word, "table fields are escaped and literal text survives")
        let apple = BookRow.from(VocabularyEntry(word: "apple", definition: SampleText.value("Apple meaning"), sentence: "An apple a day."))
        let library = VocabularyLibrary(rows: page.rows + [apple])
        check(library.filtered(letter: "A", query: "").map(\.word) == ["apple"], "library filters by initial")
        check(library.filtered(letter: nil, query: "HAPPINESS").count == 1, "library word search ignores case")
        check(library.filtered(letter: nil, query: SampleText.value("Happiness meaning")).count == 1, "library searches Chinese meaning")
        check(library.filtered(letter: nil, query: "matters").count == 1, "library searches saved contexts")
        check(library.filtered(letter: "A", query: SampleText.value("Happiness meaning")).isEmpty, "letter and text filters both apply")
    } catch { check(false, "alphabet page operations: \(error)") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("subtitle-journal-test-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let journal = NotesWriteJournal(directory: directory)
    do {
        let event = NotesWriteEvent(entryID: first.id, destinationKey: "test-account/test-folder", letter: "H", isTest: true,
            expectedDigest: page.digest, expectedCount: 3, noteID: "test-note", confirmed: false)
        try journal.locked { events in events.append(event); try journal.persist(events) }
        try NotesWriteJournal(directory: directory).locked { events in
            check(events.count == 1 && events[0].entryID == first.id && !events[0].confirmed, "pending write identity survives journal reopen")
            events[0].confirmed = true
            try journal.persist(events)
        }
        try journal.locked { events in check(events.first?.confirmed == true, "confirmed write is persisted for retry deduplication") }
        let file = directory.appendingPathComponent("notes-writes-v1.json")
        let encoded = try String(contentsOf: file)
        check(!encoded.contains("happiness") && !encoded.contains(SampleText.value("Happiness meaning")), "journal stores transaction metadata rather than a second vocabulary database")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        check(permissions?.intValue == 0o600, "write journal is private to the current user")
        try Data("corrupt journal".utf8).write(to: file)
        rejects("corrupt transaction journal cannot be silently cleared and recount retries") { try journal.locked { _ in } }
    } catch { check(false, "transaction journal checks: \(error)") }
}
