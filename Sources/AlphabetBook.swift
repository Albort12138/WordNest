import Foundation
import CryptoKit
import Darwin

enum BookError: Error, LocalizedError {
    case format(String)
    var errorDescription: String? { if case .format(let message) = self { return message }; return nil }
}

/// Notes tables are the vocabulary data source. Reading, writing, and display share this schema without a second database.
struct BookRow: Codable, Equatable {
    var word: String
    var pronunciation: String
    var definition: String
    var sentences: String
    var count: Int
    var firstAdded: String
    var occurrences: [CollectionOccurrence] = []

    // Keep legacy six-field encoding when no events exist so pending transaction digests remain comparable.
    private enum CodingKeys: String, CodingKey { case word, pronunciation, definition, sentences, count, firstAdded, occurrences }
    init(word: String, pronunciation: String, definition: String, sentences: String, count: Int, firstAdded: String, occurrences: [CollectionOccurrence] = []) {
        self.word = word; self.pronunciation = pronunciation; self.definition = definition
        self.sentences = sentences; self.count = count; self.firstAdded = firstAdded; self.occurrences = occurrences
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        word = try values.decode(String.self, forKey: .word)
        pronunciation = try values.decode(String.self, forKey: .pronunciation)
        definition = try values.decode(String.self, forKey: .definition)
        sentences = try values.decode(String.self, forKey: .sentences)
        count = try values.decode(Int.self, forKey: .count)
        firstAdded = try values.decode(String.self, forKey: .firstAdded)
        occurrences = try values.decodeIfPresent([CollectionOccurrence].self, forKey: .occurrences) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(word, forKey: .word); try values.encode(pronunciation, forKey: .pronunciation)
        try values.encode(definition, forKey: .definition); try values.encode(sentences, forKey: .sentences)
        try values.encode(count, forKey: .count); try values.encode(firstAdded, forKey: .firstAdded)
        if !occurrences.isEmpty { try values.encode(occurrences, forKey: .occurrences) }
    }

    var key: String { Self.key(word) }
    static func key(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'").lowercased().precomposedStringWithCanonicalMapping
    }
    static let scriptPages = [LegacyNotesText.value("Han characters"), LegacyNotesText.value("Kana"), LegacyNotesText.value("Hangul"), LegacyNotesText.value("Cyrillic"), LegacyNotesText.value("Greek"), LegacyNotesText.value("Arabic script category"), LegacyNotesText.value("Thai script category"), LegacyNotesText.value("Other scripts")]
    static let pageNames = (65...90).map { String(UnicodeScalar($0)!) } + scriptPages

    /// Retain legacy method names and A-Z page lookup; use stable script categories rather than inferred language.
    /// Group accented Latin words by their base letter, but preserve accents in merge keys: resume and résumé differ.
    static func letter(_ value: String) throws -> String {
        guard let first = key(value).first, LanguageSupport.hasLetters(String(first)) else {
            throw BookError.format(L("Look up a word that starts with a letter before collecting."))
        }
        let character = String(first)
        let basic = character.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let special = ["ø": "o", "ł": "l", "đ": "d", "ð": "d", "þ": "t", "æ": "a", "œ": "o", "ß": "s", "ı": "i"]
        let initial = special[basic] ?? basic
        if let ascii = initial.first, ascii >= "a", ascii <= "z" { return String(ascii).uppercased() }
        for (pattern, page) in [("\\p{Han}", LegacyNotesText.value("Han characters")), ("[\\p{Hiragana}\\p{Katakana}]", LegacyNotesText.value("Kana")), ("\\p{Hangul}", LegacyNotesText.value("Hangul")),
            ("\\p{Cyrillic}", LegacyNotesText.value("Cyrillic")), ("\\p{Greek}", LegacyNotesText.value("Greek")), ("\\p{Arabic}", LegacyNotesText.value("Arabic script category")), ("\\p{Thai}", LegacyNotesText.value("Thai script category"))] {
            if character.range(of: pattern, options: .regularExpression) != nil { return page }
        }
        return LegacyNotesText.value("Other scripts")
    }
    static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n").replacingOccurrences(of: "\u{2029}", with: "\n")
            .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "\n").precomposedStringWithCanonicalMapping
    }
    static func from(_ entry: VocabularyEntry) -> BookRow {
        let dictionary = entry.definition.map { DictionaryEntry(query: entry.word, text: $0, format: entry.definitionFormat) }
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.dateFormat = "yyyy-MM-dd HH:mm"
        return BookRow(word: clean(entry.word), pronunciation: clean(dictionary?.pronunciation ?? ""),
            definition: clean(entry.definition ?? LegacyNotesText.value("Missing dictionary definition")), sentences: clean(entry.sentence),
            count: 1, firstAdded: date.string(from: entry.createdAt), occurrences: [CollectionOccurrence(entry: entry)])
    }
    mutating func collect(_ entry: VocabularyEntry) throws {
        if occurrences.contains(where: { $0.id == entry.id }) { return }
        guard count < 1_000_000 else { throw BookError.format(L("The collection count exceeds the supported range. Check the table in Notes.")) }
        count += 1
        let incoming = Self.from(entry)
        if !incoming.sentences.isEmpty {
            var contexts = sentences.components(separatedBy: "\n").filter { !$0.isEmpty }
            for context in incoming.sentences.components(separatedBy: "\n") where !contexts.contains(context) { contexts.append(context) }
            sentences = contexts.joined(separator: "\n")
        }
        // Preserve both old and new definitions, including meanings the user may have edited manually.
        if !incoming.definition.isEmpty && !definition.contains(incoming.definition) {
            definition = Self.clean(definition + "\n" + incoming.definition)
        }
        if pronunciation.isEmpty { pronunciation = incoming.pronunciation }
        occurrences.append(CollectionOccurrence(entry: entry))
    }
}

struct AlphabetPage {
    static let headers = [LegacyNotesText.value("Word"), LegacyNotesText.value("Pronunciation column"), LegacyNotesText.value("Definition"), LegacyNotesText.value("Original text"), LegacyNotesText.value("Collections"), LegacyNotesText.value("First collected")]
    static let occurrenceHeaders = [LegacyNotesText.value("Word"), LegacyNotesText.value("Recorded time column"), LegacyNotesText.value("Source kind column"), LegacyNotesText.value("Source title column"), LegacyNotesText.value("Source URL column"), LegacyNotesText.value("Original text"), LegacyNotesText.value("Event ID column")]
    static let inlineHeaders = headers + [LegacyNotesText.value("Collection history column")]
    // Track the layout actually read from Notes for attachment checks before an update.
    // New output always puts each word and its event history in the same row.
    enum Layout { case legacySummary, legacyHistory, inlineHistory }
    let letter: String
    let isTest: Bool
    var rows: [BookRow]
    var editable = true
    var layout: Layout = .inlineHistory
    var tableCount: Int { layout == .legacyHistory ? 2 : 1 }
    var title: String { isTest ? LegacyNotesText.format("Alphabet test page title", [String(describing: letter)]) : letter }
    var owner: String { LegacyNotesText.format("Notebook ownership marker", [String(describing: BookRow.scriptPages.contains(letter) ? LegacyNotesText.value("Multilingual notebook marker") : LegacyNotesText.value("English notebook marker")), String(describing: letter)]) }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
    var html: String {
        func cell(_ value: String) -> String {
            "<td>" + value.components(separatedBy: "\n").map { "<div>\(Self.escape($0))</div>" }.joined() + "</td>"
        }
        let heading = "<tr>" + Self.inlineHeaders.map { "<th>\(Self.escape($0))</th>" }.joined() + "</tr>"
        let contents = sortedRows.map { row in
            let summary = [row.word, row.pronunciation, row.definition, row.sentences, String(row.count), row.firstAdded].map(cell).joined()
            // Prefix every line, including continuation lines, so subtitle text cannot impersonate another field.
            // Use visible text rather than HTML attributes or hidden payloads that Notes may discard.
            let records = row.occurrences.map { record in
                let values = [record.recordedAt, record.source?.kind ?? LegacyNotesText.value("Unrecorded occurrence kind"),
                    record.source?.title ?? "", record.source?.url ?? "", record.sentence, record.id.uuidString]
                return zip(Self.occurrenceHeaders.dropFirst(), values).flatMap { label, value in
                    value.components(separatedBy: "\n").map { "\(label): \($0)" }
                }.joined(separator: "\n")
            }.joined(separator: "\n")
            return "<tr>" + summary + cell(records) + "</tr>"
        }.joined()
        return "<h1>\(Self.escape(title))</h1><p>\(Self.escape(owner))</p><table border=\"1\"><tbody>\(heading)\(contents)</tbody></table>"
    }
    var sortedRows: [BookRow] { rows.sorted { $0.key < $1.key } }
    var digest: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(sortedRows)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    mutating func collect(_ entry: VocabularyEntry) throws -> Int {
        guard try BookRow.letter(entry.word) == letter else { throw BookError.format(L("The word does not match its category page.")) }
        let key = BookRow.key(entry.word)
        guard !rows.contains(where: { $0.key != key && $0.occurrences.contains(where: { $0.id == entry.id }) }) else { throw BookError.format(L("The collection identifier belongs to another word. The count was not increased.")) }
        layout = .inlineHistory
        if let index = rows.firstIndex(where: { $0.key == key }) {
            try rows[index].collect(entry)
            return rows[index].count
        }
        rows.append(BookRow.from(entry))
        return 1
    }

    /// Notes returns HTML fragments with some missing entity semicolons; repair known entities before parsing.
    /// The plaintext property cannot represent tables: it contains only an object placeholder.
    static func parse(html: String, letter: String, isTest: Bool, attachmentCount: Int) throws -> AlphabetPage {
        // Native Notes may emit &ampt=30 for &amp;t=30, even though letters follow the entity name.
        // Add the semicolon once without recursive decoding; an outer &amp still protects literal entity-like text.
        let entity = try NSRegularExpression(pattern: "&(amp|lt|gt|quot|apos|nbsp)(?!;)")
        let range = NSRange(html.startIndex..., in: html)
        let source = entity.stringByReplacingMatches(in: html, range: range, withTemplate: "&$1;")
        // Notes content is local data; never resolve external DTDs or entities.
        let document = try XMLDocument(xmlString: source, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever])
        let tables = try document.nodes(forXPath: "//table")
        guard [1, 2].contains(tables.count) else { throw BookError.format(L("Page \(letter) must contain a vocabulary table and optional collection history. The original note was not changed.")) }
        func text(_ node: XMLNode) -> String {
            if node.kind == .text { return node.stringValue ?? "" }
            let name = node.name?.lowercased() ?? ""
            if name == "br" { return "\n" }
            let value = (node.children ?? []).map(text).joined()
            return value + (["div", "p", "li"].contains(name) ? "\n" : "")
        }
        let rowNodes = try tables[0].nodes(forXPath: "./tbody/tr | ./thead/tr | ./tr")
        guard let header = rowNodes.first else { throw BookError.format(L("Page \(letter) is missing its table header.")) }
        let headerCells = try header.nodes(forXPath: "./td | ./th").map { BookRow.clean(text($0)) }
        let inline = headerCells == inlineHeaders
        guard (headerCells == headers || inline), !(inline && tables.count != 1) else {
            throw BookError.format(L("Page \(letter) has an incompatible header. Keep the original columns and collection history intact."))
        }
        var rows: [BookRow] = []
        var seen = Set<String>()
        var identifiers = Set<UUID>()
        func occurrence(_ cells: [String]) throws -> CollectionOccurrence {
            guard cells.count == 6, let id = UUID(uuidString: cells[5]), identifiers.insert(id).inserted,
                  ISO8601DateFormatter().date(from: cells[0]) != nil else {
                throw BookError.format(L("Collection history on page \(letter) contains an invalid identifier, time, or word."))
            }
            let source = cells[3].isEmpty ? nil : CollectionSource(url: cells[3], title: cells[2])
            guard (cells[3].isEmpty && cells[2].isEmpty && cells[1] == LegacyNotesText.value("Unrecorded occurrence kind"))
                || (source != nil && source?.kind == cells[1]) else {
                throw BookError.format(L("Page \(letter) contains an invalid source link or type."))
            }
            return CollectionOccurrence(id: id, recordedAt: cells[0], sentence: cells[4], source: source)
        }
        func inlineOccurrences(_ contents: String) throws -> [CollectionOccurrence] {
            if contents.isEmpty { return [] }
            let lines = contents.components(separatedBy: "\n")
            let labels = Array(occurrenceHeaders.dropFirst())
            var cursor = 0
            func hasField(_ index: Int) -> Bool {
                guard cursor < lines.count else { return false }
                let prefix = labels[index] + ":"
                return lines[cursor] == prefix || lines[cursor].hasPrefix(prefix + " ")
            }
            func field(_ index: Int) throws -> String {
                guard hasField(index) else {
                    throw BookError.format(L("Collection history on page \(letter) is incomplete or has an invalid field order. The original note was not changed."))
                }
                defer { cursor += 1 }
                return String(lines[cursor].dropFirst(labels[index].count + 1)).trimmingCharacters(in: .whitespaces)
            }
            var records: [CollectionOccurrence] = []
            while cursor < lines.count {
                var values: [String] = []
                for index in 0..<4 { values.append(try field(index)) }
                var contexts = [try field(4)]
                while hasField(4) { contexts.append(try field(4)) }
                values.append(contexts.joined(separator: "\n"))
                values.append(try field(5))
                records.append(try occurrence(values))
            }
            return records
        }
        for node in rowNodes.dropFirst() {
            let cells = try node.nodes(forXPath: "./td | ./th").map { BookRow.clean(text($0)) }
            if cells.allSatisfy({ $0.isEmpty }) { continue }
            guard cells.count == headerCells.count, !cells[0].isEmpty, let count = Int(cells[4]), count >= 1, count <= 1_000_000 else { throw BookError.format(L("Page \(letter) contains an incomplete row or an invalid collection count.")) }
            guard try BookRow.letter(cells[0]) == letter, seen.insert(BookRow.key(cells[0])).inserted else {
                throw BookError.format(L("Page \(letter) contains a word from another category or a duplicate word. Check it in Notes."))
            }
            rows.append(BookRow(word: cells[0], pronunciation: cells[1], definition: cells[2], sentences: cells[3], count: count, firstAdded: cells[5],
                occurrences: inline ? try inlineOccurrences(cells[6]) : []))
        }
        if tables.count == 2 {
            let recordNodes = try tables[1].nodes(forXPath: "./tbody/tr | ./thead/tr | ./tr")
            guard let recordHeader = recordNodes.first,
                  try recordHeader.nodes(forXPath: "./td | ./th").map({ BookRow.clean(text($0)) }) == occurrenceHeaders else { throw BookError.format(L("The collection-history header on page \(letter) does not match.")) }
            for node in recordNodes.dropFirst() {
                let cells = try node.nodes(forXPath: "./td | ./th").map { BookRow.clean(text($0)) }
                if cells.allSatisfy({ $0.isEmpty }) { continue }
                guard cells.count == 7, let index = rows.firstIndex(where: { $0.key == BookRow.key(cells[0]) }) else {
                    throw BookError.format(L("Collection history on page \(letter) contains an invalid identifier, time, or word."))
                }
                rows[index].occurrences.append(try occurrence(Array(cells.dropFirst())))
            }
        }
        guard rows.allSatisfy({ $0.occurrences.count <= $0.count }) else { throw BookError.format(L("Page \(letter) has more collection events than its total count. The original note was not changed.")) }
        var page = AlphabetPage(letter: letter, isTest: isTest, rows: rows)
        page.layout = tables.count == 2 ? .legacyHistory : (inline ? .inlineHistory : .legacySummary)
        // Only rewrite managed table-only pages; writing Notes HTML could otherwise discard images, tags, or lists.
        func outside(_ node: XMLNode) -> String {
            if node.name?.lowercased() == "table" { return "" }
            if node.kind == .text { return node.stringValue ?? "" }
            return (node.children ?? []).map(outside).joined() + (["div", "p", "h1", "h2"].contains(node.name?.lowercased() ?? "") ? "\n" : "")
        }
        let body = try document.nodes(forXPath: "//body").first ?? document
        let externalText = BookRow.clean(outside(body))
        let disallowed = try document.nodes(forXPath: "//img | //a | //ul | //ol | //input | //object[not(.//table)]")
        page.editable = attachmentCount == page.tableCount
            && externalText == BookRow.clean(page.title + "\n" + page.owner + (page.layout == .legacyHistory ? LegacyNotesText.value("Occurrence heading suffix") : "")) && disallowed.isEmpty
        return page
    }
}

struct VocabularyLibrary {
    var rows: [BookRow] = []
    var warnings: [String] = []
    func filtered(letter: String?, query: String) -> [BookRow] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            (letter == nil || (try? BookRow.letter(row.word)) == letter)
                && (query.isEmpty || ([row.word, row.definition, row.sentences] + row.occurrences.compactMap(\.source).flatMap { [$0.title, $0.url] }).contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }
}

/// Persist event IDs, digests, and expected counts for retry deduplication; vocabulary stays in Notes.
struct NotesWriteEvent: Codable {
    let entryID: UUID
    let destinationKey: String
    let letter: String
    let isTest: Bool
    let expectedDigest: String
    let expectedCount: Int
    var noteID: String?
    var confirmed: Bool
    // Notes may create a page before rejecting a smart-folder assignment. Keep the transaction and block this target.
    var destinationRejected: Bool? = nil
}

struct NotesWriteJournal {
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SubtitleLookup", isDirectory: true)
    }
    func locked<T>(_ body: (inout [NotesWriteEvent]) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent("notes-writes.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw BookError.format(L("The local write-state file could not be created. Nothing was written to Notes.")) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw BookError.format(L("Another instance is collecting a word. Try again later.")) }
        defer { flock(fd, LOCK_UN) }
        let file = directory.appendingPathComponent("notes-writes-v1.json")
        var events: [NotesWriteEvent]
        if FileManager.default.fileExists(atPath: file.path) { events = try JSONDecoder().decode([NotesWriteEvent].self, from: Data(contentsOf: file)) }
        else { events = [] }
        return try body(&events)
    }
    func persist(_ events: [NotesWriteEvent]) throws {
        let data = try JSONEncoder().encode(events)
        let file = directory.appendingPathComponent("notes-writes-v1.json")
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
