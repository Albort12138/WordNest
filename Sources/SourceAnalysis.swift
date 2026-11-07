import Foundation

struct SourceSummary {
    let identityURL: String
    let title: String
    let wordCount: Int
    let collectionCount: Int
}

extension BookRow {
    var collectionsWithoutSource: Int { count - occurrences.filter { $0.source != nil }.count }
    var legacyCollectionCount: Int { count - occurrences.count }
    func collectionCount(in source: String?) -> Int {
        guard let source else { return count }
        if source.isEmpty { return collectionsWithoutSource }
        return occurrences.filter { $0.source?.identityURL == source }.count
    }
    var sourceDescription: String {
        var lines: [String] = []
        if legacyCollectionCount > 0 { lines.append(L("\(legacyCollectionCount) earlier collections have no per-collection source history; their links cannot be recovered.")) }
        for record in occurrences {
            lines.append("\(record.recordedAt) · \(UILocalization.key(record.source?.kind ?? LegacyNotesText.value("Source missing")))")
            if let source = record.source { lines += [source.displayName, source.url] }
            if !record.sentence.isEmpty { lines.append(L("Original text: \(record.sentence)")) }
            lines.append("")
        }
        return lines.isEmpty ? L("No source history yet.") : lines.joined(separator: "\n")
    }
}

extension VocabularyLibrary {
    var sourceSummaries: [SourceSummary] {
        let sources = rows.flatMap(\.occurrences).compactMap(\.source)
        return Dictionary(grouping: sources, by: \.identityURL).map { identity, entries in
            SourceSummary(identityURL: identity, title: entries.first(where: { !$0.title.isEmpty })?.title ?? identity,
                wordCount: rows.filter { $0.collectionCount(in: identity) > 0 }.count, collectionCount: entries.count)
        }.sorted { $0.collectionCount == $1.collectionCount ? $0.identityURL < $1.identityURL : $0.collectionCount > $1.collectionCount }
    }

    /// Export the complete read snapshot and collection history for user-directed analysis; never upload it.
    func analysisJSON(exportedAt: Date = Date()) throws -> Data {
        struct ExportReference: Encodable {
            let url: String; let canonicalURL: String; let title: String; let kind: String
        }
        struct ExportOccurrence: Encodable {
            let id: UUID; let recordedAt: String; let sentence: String; let source: ExportReference?
        }
        struct ExportWord: Encodable {
            let word: String; let definition: String; let pronunciation: String; let sentences: String
            let collectionCount: Int; let legacyCollectionCount: Int; let collectionsWithoutSource: Int
            let occurrences: [ExportOccurrence]
        }
        struct ExportSource: Encodable {
            let url: String; let title: String; let distinctWordCount: Int; let collectionCount: Int; let words: [String: Int]
        }
        struct Export: Encodable {
            let schemaVersion: Int; let exportedAt: String; let scope: String; let warnings: [String]
            let distinctWordCount: Int; let collectionCount: Int; let collectionsWithoutSource: Int
            let sources: [ExportSource]; let words: [ExportWord]
        }
        let summary = sourceSummaries.map { source in
            ExportSource(url: source.identityURL, title: source.title, distinctWordCount: source.wordCount, collectionCount: source.collectionCount,
                words: Dictionary(uniqueKeysWithValues: rows.filter { $0.collectionCount(in: source.identityURL) > 0 }.map { ($0.word, $0.collectionCount(in: source.identityURL)) }))
        }
        let result = Export(schemaVersion: 1, exportedAt: ISO8601DateFormatter().string(from: exportedAt),
            scope: LegacyNotesText.value("Analysis export scope"), warnings: warnings,
            distinctWordCount: rows.count, collectionCount: rows.reduce(0) { $0 + $1.count }, collectionsWithoutSource: rows.reduce(0) { $0 + $1.collectionsWithoutSource }, sources: summary,
            words: rows.map { ExportWord(word: $0.word, definition: $0.definition, pronunciation: $0.pronunciation, sentences: $0.sentences,
                collectionCount: $0.count, legacyCollectionCount: $0.legacyCollectionCount, collectionsWithoutSource: $0.collectionsWithoutSource,
                occurrences: $0.occurrences.map { record in
                    ExportOccurrence(id: record.id, recordedAt: record.recordedAt, sentence: record.sentence,
                        source: record.source.map { ExportReference(url: $0.url, canonicalURL: $0.identityURL, title: $0.title, kind: $0.kind) })
                }) })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(result)
    }
}
