import Foundation

/// Fixtures were written by an independent MIT-licensed Python implementation, not this reader.
@MainActor func runDictionaryTests() async {
    func verify(_ condition: Bool, _ name: String) { check(condition, name) }
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("WordNest.DictionaryTests." + UUID().uuidString)
    let suite = "WordNest.DictionaryTests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: temporary) }
    func fixture(_ name: String) -> URL { fixtures.appendingPathComponent(name + ".mdx") }
    func rejects(_ data: Data, _ label: String, query: String? = nil) {
        do {
            let path = temporary.appendingPathComponent("invalid.mdx")
            try data.write(to: path)
            let reader = try MDXReader(url: path)
            if let query { _ = try reader.lookup(query) }
            verify(false, label)
        } catch { verify(true, label) }
    }
    for (text, expected) in [("", "cdf26213a150dc3ecb610f18f6b38b46"), ("a", "86be7afa339d0fc7cfc785e72f578d33"),
                             ("abc", "c14a12199c66e4ba84636b0f69144c77"),
                             ("message digest", "9e327b3d6e523062afc1132d7df9d1b8")] {
        let digest = RIPEMD128.hash(Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        verify(digest == expected, "RIPEMD-128 published test vector: \(text)")
    }
    do {
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        for name in ["utf8-zlib", "encrypted-index", "utf16-raw", "gbk-zlib", "big5-zlib"] {
            let reader = try MDXReader(url: fixture(name))
            verify(reader.title == "WordNest Test Dictionary", "external writer metadata: \(name)")
            let body = try reader.lookup("HAPPINESS")
            verify(body?.contains("A feeling of joy.") == true, "local definition and case folding: \(name)")
            verify(try reader.lookup("missing") == nil, "missing entry does not substitute another source: \(name)")
            if !name.hasPrefix("gbk"), !name.hasPrefix("big5") {
                verify(body?.contains("Keep the original context.") == true && body?.contains("DO_NOT_DISPLAY") == false,
                      "HTML is text only, without script or image contents: \(name)")
                let alias = try reader.lookup("alias")
                verify(alias == body, "MDX linked entry resolves locally: \(name)")
                verify(try reader.lookup("sample")?.contains(SampleText.value("Happiness short entry")) == true, "UTF dictionary preserves non-ASCII data: \(name)")
                verify(try reader.lookup("literal")?.contains("2 < 3") == true, "plain text comparisons and pipes survive rendering: \(name)")
                do { _ = try reader.lookup("cycle"); verify(false, "cyclic alias rejected") } catch { verify(true, "cyclic alias rejected") }
            } else {
                let text = SampleText.value("Happiness short entry")
                let range = text.range(of: "\\p{Han}+", options: .regularExpression)!
                verify(try reader.lookup("sample") == String(text[range]), "legacy encoding preserves non-ASCII definitions: \(name)")
            }
        }
        let file = try Data(contentsOf: fixture("utf8-zlib"))
        for length in [0, 1, 3, 8, file.count / 2, file.count - 1] { rejects(file.prefix(length), "truncated MDX rejected at \(length)") }
        rejects(try Data(contentsOf: fixture("unsupported-v1")), "MDX 1.x gets an explicit unsupported-version error")
        var corrupt = file; corrupt[10] ^= 1
        rejects(corrupt, "header checksum corruption rejected")
        var huge = file; huge.replaceSubrange(0..<4, with: [0x7f, 0xff, 0xff, 0xff])
        rejects(huge, "declared oversized header rejected before allocation")
        // Change header fields while recomputing the outer checksum to reach semantic validation.
        func changingHeader(_ from: String, _ to: String) throws -> Data {
            let length = file.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            let header = String(data: file.subdata(in: 4..<(4 + length)), encoding: .utf16LittleEndian)!
                .replacingOccurrences(of: from, with: to).data(using: .utf16LittleEndian)!
            let size = UInt32(header.count)
            var output = Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: size >> ($0 * 8)) })
            output.append(header)
            let checksum = MDXReader.adler32(header)
            output.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: checksum >> ($0 * 8)) })
            output.append(file.dropFirst(8 + length))
            return output
        }
        rejects(try changingHeader("Encrypted=\"0\"", "Encrypted=\"1\""), "password-protected dictionary is rejected without prompting for credentials")
        rejects(try changingHeader("Encoding=\"UTF-8\"", "Encoding=\"unknown\""), "unknown encoding is rejected explicitly")
        let noFlag = temporary.appendingPathComponent("no-encryption.mdx")
        try changingHeader("Encrypted=\"0\"", "Encrypted=\"No\"").write(to: noFlag)
        verify(try MDXReader(url: noFlag).lookup("happiness") != nil, "standard Encrypted=No header remains compatible")
        var recordCorrupt = file; recordCorrupt[recordCorrupt.count - 1] ^= 1
        rejects(recordCorrupt, "record decompression/checksum corruption fails lookup", query: "zebra")
        let library = DictionaryLibrary(root: temporary.appendingPathComponent("Library"), defaults: defaults)
        verify(library.selectedSource == .system && library.records.isEmpty, "first launch uses the system adapter")
        let original = try Data(contentsOf: fixture("encrypted-index"))
        let imported = try await library.importMDX(from: fixture("encrypted-index"))
        verify(library.records.count == 1 && library.selectedSource == imported.source, "successful import selects a managed dictionary")
        verify(try Data(contentsOf: fixture("encrypted-index")) == original, "import leaves the user's original file unchanged")
        let response = await library.lookup(DictionaryRequest(text: "happiness"))
        verify(response.source == imported.source && response.entry?.format == .plainText, "provider returns definition and exact source to the card")
        verify(response.entry?.text.contains("A feeling of joy.") == true, "managed copy is queryable")
        let presentation = response.entry.map(DictionaryPresentation.init)
        verify(presentation?.meaning == response.entry?.text && presentation?.examples.isEmpty == true, "MDX definitions bypass system-specific entry splitting")
        let plain = VocabularyEntry(word: "sample", definition: "sample | BrE example | noun retained ▸ still retained", sentence: "Keep context", definitionFormat: .plainText)
        let row = BookRow.from(plain)
        verify(row.pronunciation.isEmpty && row.definition == plain.definition, "collecting MDX text preserves pipes and markers without invented phonetics")
        var page = AlphabetPage(letter: "S", isTest: false, rows: [])
        _ = try page.collect(plain)
        let parsed = try AlphabetPage.parse(html: page.html, letter: "S", isTest: false, attachmentCount: 1)
        verify(parsed.rows.first?.definition == plain.definition && parsed.rows.first?.count == 1, "MDX definitions round-trip through the existing Notes table without duplicate collection")
        let missing = await library.lookup(DictionaryRequest(text: "unlisted"))
        verify(missing.entry == nil && missing.source == imported.source && missing.error == nil, "MDX misses remain misses in the selected dictionary")
        let invalid = await library.lookup(DictionaryRequest(text: ""))
        verify(invalid.entry == nil, "provider rejects an empty query")
        let reopened = DictionaryLibrary(root: temporary.appendingPathComponent("Library"), defaults: defaults)
        let restored = await reopened.lookup(DictionaryRequest(text: "happiness"))
        verify(reopened.selectedSource == imported.source && restored.entry?.text == response.entry?.text, "selection and file remain usable after reopening")
        do { _ = try await library.importMDX(from: fixture("unsupported-v1")); verify(false, "bad import rejected") }
        catch { verify(library.records.count == 1 && library.selectedSource == imported.source, "failed import leaves prior selection and catalog intact") }
        let contents = try FileManager.default.contentsOfDirectory(atPath: temporary.appendingPathComponent("Library").path)
        verify(contents == [imported.id.uuidString + ".mdx"], "failed import leaves no temporary managed files")
        try library.select(DictionarySource.system.id)
        verify(library.selectedSource == .system, "switching back to the system provider persists")
        let frozen = await library.lookup(DictionaryRequest(text: "happiness"), source: imported.source)
        verify(frozen.entry?.text == response.entry?.text, "in-flight lookup uses its snapshotted provider")
        try FileManager.default.removeItem(at: temporary.appendingPathComponent("Library/" + imported.id.uuidString + ".mdx"))
        let absent = DictionaryLibrary(root: temporary.appendingPathComponent("Library"), defaults: defaults)
        try absent.select(imported.source.id)
        let failed = await absent.lookup(DictionaryRequest(text: "happiness"))
        verify(failed.entry == nil && failed.error != nil && failed.source == imported.source, "missing managed file reports an error without a system fallback")
        try library.remove(imported.id)
        verify(library.records.isEmpty && library.selectedSource == .system, "remove clears managed configuration")
        verify(FileManager.default.fileExists(atPath: fixture("encrypted-index").path), "removing a managed copy keeps the original fixture")
    } catch { verify(false, "local dictionary fixtures: \(error)") }
}
