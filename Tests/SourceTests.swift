import AppKit
import CryptoKit

@MainActor func runSourceTests() async {
    let firstURL = "https://www.bilibili.com/video/BV1xx411c7mD/?spm_id_from=333.1007&t=30"
    let videoA = CollectionSource(url: firstURL, title: "Video A <&>\nlesson")!
    let sameA = CollectionSource(url: "https://m.bilibili.com/video/BV1xx411c7mD?p=1&vd_source=test")!
    let videoB = CollectionSource(url: "https://www.bilibili.com/video/BV1xx411c7mD/?p=2", title: "Video B")!
    check(videoA.url == firstURL && videoA.identityURL == sameA.identityURL, "original video URL is retained while tracking and time variants group together")
    check(videoA.identityURL != videoB.identityURL && videoA.kind == SampleText.value("Video"), "different Bilibili parts remain separate sources")
    check(videoA.title == "Video A <&> lesson", "page title is normalized without injecting markup")
    // Replay observed window metadata: the WebArea title is absent or empty, but another field has the video title.
    // Use the same metadata entry point as the real adapter; an injected webAppTransport would bypass it.
    let capturedTitle = SampleText.value("Bilibili source title")
    let recovered = PageSourceReader.sourceFromWebArea(url: firstURL, title: "", description: nil, windowTitle: capturedTitle)!
    check(recovered.title == capturedTitle, "empty WebArea title falls back to the current window title")
    check(PageSourceReader.sourceFromWebArea(url: firstURL, title: " \n\t", description: nil, windowTitle: capturedTitle)?.title == capturedTitle, "whitespace-only WebArea title also falls back")
    check(PageSourceReader.sourceFromWebArea(url: firstURL, title: nil, description: capturedTitle, windowTitle: "Bilibili")?.title == capturedTitle, "WebArea description supplies the page title before a generic window title")
    check(PageSourceReader.sourceFromWebArea(url: firstURL, title: "Exact page title", description: capturedTitle, windowTitle: "Window title")?.title == "Exact page title", "a nonempty WebArea title retains priority")
    check(PageSourceReader.sourceFromWebArea(url: firstURL, title: nil, description: " \n", windowTitle: " \t")?.title == "", "missing metadata keeps the stored title empty rather than inventing one")
    do {
        var titlePage = AlphabetPage(letter: "T", isTest: true, rows: [])
        let entry = VocabularyEntry(word: "title", definition: SampleText.value("Title meaning"), sentence: "Title capture regression.", isTestEntry: true, source: recovered)
        _ = try titlePage.collect(entry); _ = try titlePage.collect(entry)
        let reread = try AlphabetPage.parse(html: titlePage.html, letter: "T", isTest: true, attachmentCount: 1)
        check(reread.rows[0].occurrences[0].source?.title == capturedTitle && reread.rows[0].count == 1, "recovered title reaches the collection table and survives readback without double counting")
        let exported = try JSONSerialization.jsonObject(with: VocabularyLibrary(rows: reread.rows).analysisJSON()) as? [String: Any]
        let summaries = exported?["sources"] as? [[String: Any]]
        let words = exported?["words"] as? [[String: Any]]
        let records = words?.first?["occurrences"] as? [[String: Any]]
        let reference = records?.first?["source"] as? [String: Any]
        check(summaries?.first?["title"] as? String == capturedTitle && reference?["title"] as? String == capturedTitle,
              "recovered title survives both per-video summaries and occurrence JSON export")
    } catch { check(false, "recovered source title round trip: \(error)") }
    check(PageSourceReader.sourceFromWebArea(url: firstURL, title: "", description: "e\u{301}cole\n lesson", windowTitle: "Window")?.title == "école lesson", "fallback title applies the same Unicode and whitespace normalization as a regular title")
    check(PageSourceReader.sourceFromWebArea(url: "file:///private/test", title: "", description: capturedTitle, windowTitle: capturedTitle) == nil, "title fallback cannot bypass source URL validation")
    check(CollectionSource(url: firstURL, title: "e\u{301}cole\t\t lesson")?.title == "école lesson", "title whitespace and Unicode normalization remain stable through native Notes HTML")
    check(CollectionSource(url: "https://youtu.be/abc_X-123?t=20")?.identityURL == CollectionSource(url: "https://www.youtube.com/watch?v=abc_X-123&feature=share")?.identityURL, "YouTube share and watch URLs group by video")
    check(CollectionSource(url: "https://example.com/article?chapter=2&utm_source=test#section")?.identityURL == "https://example.com/article?chapter=2#section", "unknown sites retain semantic query and fragment")
    for invalid in ["javascript:alert(1)", "file:///private/test", "relative/path", "https://user:password@example.com", "https://example.com\nsecond"] {
        check(CollectionSource(url: invalid) == nil, "invalid or credential-bearing source is rejected: \(invalid.components(separatedBy: ":").first ?? "")")
    }
    let date = Date(timeIntervalSince1970: 1_730_000_000)
    let one = VocabularyEntry(word: "happiness", definition: SampleText.value("Happiness meaning"), sentence: "First <&> context.", createdAt: date, source: videoA)
    let two = VocabularyEntry(word: "Happiness", definition: SampleText.value("Happiness meaning"), sentence: "Same word, another occurrence.", createdAt: date, source: sameA)
    let three = VocabularyEntry(word: "happiness", definition: SampleText.value("Happiness meaning"), sentence: "Video B context.", createdAt: date, source: videoB)
    var book = AlphabetPage(letter: "H", isTest: false, rows: [])
    do {
        _ = try book.collect(one); _ = try book.collect(two); _ = try book.collect(three)
        _ = try book.collect(two)
        check(book.rows.count == 1 && book.rows[0].count == 3 && book.rows[0].occurrences.count == 3, "each distinct event is stored once, including retry within page model")
        let rendered = try XMLDocument(xmlString: book.html, options: [.documentTidyHTML])
        let tables = try rendered.nodes(forXPath: "//table")
        check(tables.count == 1, "a word and all its collection history occupy one table")
        let renderedRows = try rendered.nodes(forXPath: "//table//tr")
        check(renderedRows.count == 2, "repeated collections remain in the same word row")
        let parsed = try AlphabetPage.parse(html: book.html, letter: "H", isTest: false, attachmentCount: 1)
        check(parsed.rows == book.rows && parsed.digest == book.digest && parsed.editable, "one word row round trips with source and event association intact")
        check(!book.html.contains("Video A <&>") && parsed.rows[0].occurrences[0].source?.title == videoA.title, "source title and query ampersands survive escaped HTML")
        let nativeEntities = book.html.replacingOccurrences(of: "&amp;", with: "&amp").replacingOccurrences(of: "&lt;", with: "&lt").replacingOccurrences(of: "&gt;", with: "&gt")
        let nativeParsed = try AlphabetPage.parse(html: nativeEntities, letter: "H", isTest: false, attachmentCount: 1)
        check(nativeParsed.rows == book.rows && nativeParsed.digest == book.digest, "native Notes entity without semicolon preserves URL ampersands followed by letters")
        var literalPage = AlphabetPage(letter: "H", isTest: false, rows: [])
        _ = try literalPage.collect(VocabularyEntry(word: "hello", definition: "literal &amp and &lttext", sentence: "Literal entity names remain text.", source: CollectionSource(url: "https://example.com/?x=1&ampt=30", title: "Literal &ampt &ltname")))
        let literalNative = literalPage.html.replacingOccurrences(of: "&amp;", with: "&amp")
        let literalParsed = try AlphabetPage.parse(html: literalNative, letter: "H", isTest: false, attachmentCount: 1)
        check(literalParsed.rows == literalPage.rows, "Notes entity repair runs once and cannot corrupt literal entity-like text or query names")
        let row = parsed.rows[0]
        check(row.collectionCount(in: videoA.identityURL) == 2 && row.collectionCount(in: videoB.identityURL) == 1, "same word distribution is A twice and B once")
        let legacyHTML = SampleText.value("Legacy H page HTML")
        var legacy = try AlphabetPage.parse(html: legacyHTML, letter: "H", isTest: false, attachmentCount: 1)
        let oldCanonical = SampleText.value("Legacy H page canonical data")
        let oldDigest = SHA256.hash(data: Data(oldCanonical.utf8)).map { String(format: "%02x", $0) }.joined()
        check(legacy.editable && legacy.tableCount == 1 && legacy.digest == oldDigest, "legacy single-table bytes retain their old transaction digest")
        check(legacy.rows[0].legacyCollectionCount == 5 && legacy.rows[0].occurrences.isEmpty, "legacy source history is unknown rather than fabricated")
        _ = try legacy.collect(one)
        let upgraded = try AlphabetPage.parse(html: legacy.html, letter: "H", isTest: false, attachmentCount: 1)
        check(upgraded.rows[0].count == 6 && upgraded.rows[0].legacyCollectionCount == 5 && upgraded.rows[0].occurrences.count == 1 && upgraded.editable, "first new collection safely upgrades legacy page and retains five unattributed collections")
        let unknown = BookRow.from(VocabularyEntry(word: "hope", definition: nil, sentence: "No URL available."))
        var oldWord = legacy.rows[0]; oldWord.word = "history"; oldWord.occurrences = []; oldWord.count = 5
        let library = VocabularyLibrary(rows: [row, unknown, oldWord])
        let summaries = library.sourceSummaries
        check(summaries.count == 2 && summaries.first?.wordCount == 1 && summaries.first?.collectionCount == 2, "per-source stats distinguish unique words and collection events")
        check(unknown.collectionsWithoutSource == 1 && oldWord.collectionsWithoutSource == 5, "unknown includes both uncaptured new events and legacy totals")
        check(library.filtered(letter: nil, query: "Video B").count == 1, "library searches page titles alongside words")
        let exported = try JSONSerialization.jsonObject(with: library.analysisJSON(exportedAt: date)) as? [String: Any]
        check(exported?["collectionCount"] as? Int == 9 && exported?["collectionsWithoutSource"] as? Int == 6, "analysis export reports totals and missing source coverage")
        check((exported?["sources"] as? [[String: Any]])?.count == 2 && (exported?["words"] as? [[String: Any]])?.count == 3, "analysis export includes source summaries and complete word event data")
        let duplicated = book.html.replacingOccurrences(of: three.id.uuidString, with: one.id.uuidString)
        do { _ = try AlphabetPage.parse(html: duplicated, letter: "H", isTest: false, attachmentCount: 1); check(false, "duplicate occurrence IDs cannot be silently counted") }
        catch { check(true, "duplicate occurrence IDs cannot be silently counted") }
        let protected = try AlphabetPage.parse(html: book.html + "<p>#keep-tag</p>", letter: "H", isTest: false, attachmentCount: 1)
        check(!protected.editable && protected.rows == book.rows, "single-table page with tag text remains readable and protected")
    } catch { check(false, "source record round trip and legacy upgrade: \(error)") }

    do {
        // Captured from the pre-migration renderer, not reconstructed using the new implementation.
        var legacy = try AlphabetPage.parse(html: SampleText.value("Legacy history H page HTML"), letter: "H", isTest: false, attachmentCount: 2)
        let original = legacy.rows
        check(legacy.editable && legacy.tableCount == 2 && legacy.digest == SampleText.value("Legacy history H page digest"),
              "old two-table pages keep their exact event data and pending-write digest")
        let rendered = try AlphabetPage.parse(html: legacy.html, letter: "H", isTest: false, attachmentCount: 1)
        check(rendered.rows == original && rendered.digest == legacy.digest && rendered.editable,
              "rendering an old page as one table preserves counts and event IDs without collecting")
        let prior = original[0].occurrences[0]
        let retry = VocabularyEntry(id: prior.id, word: original[0].word, definition: original[0].definition,
            sentence: prior.sentence, createdAt: ISO8601DateFormatter().date(from: prior.recordedAt)!, source: prior.source)
        let count = try legacy.collect(retry)
        check(count == original[0].count && legacy.rows == original && legacy.tableCount == 1,
              "migrating the same event never increments its count or duplicates history")
        let multiline = LegacyNotesText.value("Event ID column") + ": fake\n" + LegacyNotesText.value("Recorded time column") + ": not a record\nActual context <&>."
        let next = VocabularyEntry(word: "happiness", definition: nil, sentence: multiline, source: videoB)
        _ = try legacy.collect(next)
        let updated = try AlphabetPage.parse(html: legacy.html, letter: "H", isTest: false, attachmentCount: 1)
        check(updated.rows == legacy.rows && updated.rows[0].count == original[0].count + 1,
              "new collection appends to the migrated word row and preserves all earlier sources")
        check(updated.rows[0].occurrences.last?.sentence == multiline,
              "multiline subtitle text cannot impersonate an inline history field")
        let empty = VocabularyEntry(word: "hello", definition: nil, sentence: "")
        _ = try legacy.collect(empty)
        let noSource = try AlphabetPage.parse(html: legacy.html, letter: "H", isTest: false, attachmentCount: 1)
        check(noSource.rows == legacy.rows, "empty context and missing source survive inline history readback")
        var other = BookRow.from(VocabularyEntry(word: "hope", definition: nil, sentence: "Other word."))
        other.occurrences = [updated.rows[0].occurrences[0]]
        let duplicate = AlphabetPage(letter: "H", isTest: false, rows: [updated.rows[0], other])
        do { _ = try AlphabetPage.parse(html: duplicate.html, letter: "H", isTest: false, attachmentCount: 1); check(false, "event IDs are unique across inline word rows") }
        catch { check(true, "event IDs are unique across inline word rows") }
        let broken = legacy.html.replacingOccurrences(of: LegacyNotesText.value("Event ID column") + ":", with: "broken:")
        do { _ = try AlphabetPage.parse(html: broken, letter: "H", isTest: false, attachmentCount: 1); check(false, "incomplete inline history cannot be silently discarded") }
        catch { check(true, "incomplete inline history cannot be silently discarded") }
    } catch { check(false, "single-row history migration: \(error)") }

    var reads = 0
    let reader = PageSourceReader {
        reads += 1
        let result = NSAppleEventDescriptor.list()
        for (index, field) in [videoA.url, videoA.title, "0", "0", "1000", "900"].enumerated() { result.insert(NSAppleEventDescriptor(string: field), at: index + 1) }
        return result
    }
    let accepted = await reader.capture(SourceCaptureContext(bundleID: "com.apple.Safari", pointer: CGPoint(x: 500, y: 400), primaryScreenTop: 900))
    check(accepted.source == videoA, "Safari capture returns current tab inside current window")
    let outside = await reader.capture(SourceCaptureContext(bundleID: "com.apple.Safari", pointer: CGPoint(x: -500, y: 400), primaryScreenTop: 900))
    check(outside.source == nil, "pointer outside front Safari window never gets an unrelated tab URL")
    let unsupported = await reader.capture(SourceCaptureContext(bundleID: "example.player", pointer: .zero, primaryScreenTop: 900))
    check(unsupported.source == nil && reads == 2, "unsupported app cannot trigger background Safari reads")
    var webAppReads = 0
    let webAppReader = PageSourceReader(webAppTransport: { _ in webAppReads += 1; return .captured(videoB) })
    let webContext = SourceCaptureContext(bundleID: "com.apple.Safari.WebApp.fixture", pointer: CGPoint(x: 500, y: 400), primaryScreenTop: 900, processID: 123)
    let webResult = await webAppReader.capture(webContext)
    check(webResult.source == videoB && webAppReads == 1, "Dock website windows dispatch to their own reader rather than Safari tabs")
    let candidate = PageSourceReader.WebPageCandidate(source: videoB, bounds: CGRect(x: 100, y: 100, width: 800, height: 700))
    check(PageSourceReader.selectWebPage([candidate], context: webContext).source == videoB, "web app source must contain the pointer in top-left screen coordinates")
    let otherCandidate = PageSourceReader.WebPageCandidate(source: videoA, bounds: candidate.bounds)
    check(PageSourceReader.selectWebPage([candidate, otherCandidate], context: webContext).source == nil, "multiple visible page URLs cannot be assigned arbitrarily")
    let outsideContext = SourceCaptureContext(bundleID: webContext.bundleID, pointer: CGPoint(x: -900, y: 400), primaryScreenTop: 900)
    check(PageSourceReader.selectWebPage([candidate], context: outsideContext).source == nil, "web app pointer outside the page falls back to manual source")
    var compileError: NSDictionary?
    let compiled = NSAppleScript(source: PageSourceReader.scriptSource)?.compileAndReturnError(&compileError)
    check(compiled == true, "Safari metadata script compiles without sending a browser event: \(compileError?.description ?? "ok")")
}
