import Foundation
import CoreServices

/// A general system dictionary entry, not necessarily the meaning intended by the current subtitle.
enum DictionaryEntryFormat: Sendable, Equatable { case system, plainText }

struct DictionaryEntry: Sendable {
    /// The actual query text, possibly adjusted for curly apostrophes or letter case.
    let query: String
    let text: String
    var format: DictionaryEntryFormat = .system

    /// A Chinese display hint, not a translation-language guarantee; mixed kana or Hangul prevents assuming Chinese.
    var containsChinese: Bool {
        text.range(of: "\\p{Han}", options: .regularExpression) != nil
            && text.range(of: "[\\p{Hiragana}\\p{Katakana}\\p{Hangul}]", options: .regularExpression) == nil
    }

    /// Extract only explicitly labeled British/American IPA at the start; leave unknown formats unsplit.
    /// Never generate IPA from spelling or treat later definitions/examples as pronunciation; retain the complete entry.
    var pronunciation: String? {
        guard format == .system else { return nil }
        let parts = text.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count <= 100 else { return nil }
        let pronunciation = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pronunciation.isEmpty, pronunciation.count <= 180,
              !pronunciation.contains("\n"),
              pronunciation.hasPrefix("BrE ") || pronunciation.hasPrefix("AmE ") else { return nil }
        return pronunciation
    }
}

/// Split conservatively for the card, using only explicit system-dictionary IPA separators and example markers.
/// Display unrecognized content as body text; copying always uses the complete original entry.
struct DictionaryPresentation {
    let grammar: String?
    let meaning: String
    let examples: [String]

    /// Localize only the grammar badge; keep grammar stable for legacy Notes rendering.
    var displayGrammar: String? { grammar.map { UILocalization.key($0) } }

    init(entry: DictionaryEntry) {
        if entry.format == .plainText {
            grammar = nil; meaning = entry.text; examples = []
            return
        }
        let parts = entry.text.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        let body = entry.pronunciation != nil && parts.count == 3 ? String(parts[2]) : entry.text
        let sections = body.components(separatedBy: "▸")
        let lead = (sections.first ?? body).trimmingCharacters(in: .whitespacesAndNewlines)
        examples = sections.dropFirst().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        // Extract only a known part-of-speech prefix so an English definition is not accidentally hidden.
        let labels = [
            "noun": LegacyNotesText.value("Noun"), "noun uncountable": LegacyNotesText.value("Noun · uncountable"), "noun countable": LegacyNotesText.value("Noun · countable"),
            "adjective": LegacyNotesText.value("Adjective"), "adverb": LegacyNotesText.value("Adverb"), "verb": LegacyNotesText.value("Verb"),
            "transitive verb": LegacyNotesText.value("Transitive verb"), "intransitive verb": LegacyNotesText.value("Intransitive verb"),
            "pronoun": LegacyNotesText.value("Pronoun"), "preposition": LegacyNotesText.value("Preposition"), "conjunction": LegacyNotesText.value("Conjunction"),
            "exclamation": LegacyNotesText.value("Exclamation"), "determiner": LegacyNotesText.value("Determiner"), "modal verb": LegacyNotesText.value("Modal verb")
        ]
        if let han = lead.range(of: "\\p{Han}", options: .regularExpression) {
            let prefix = String(lead[..<han.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let label = labels[prefix] {
                grammar = label
                meaning = String(lead[han.lowerBound...])
                return
            }
        }
        grammar = nil
        meaning = lead
    }
}

enum DictionaryLookup: Sendable {
    case found(DictionaryEntry)
    case notFound(String)
    case invalidQuery

    var entry: DictionaryEntry? {
        if case .found(let entry) = self { return entry }
        return nil
    }

    /// Retain the complete system entry; the display scrolls rather than truncating long definitions.
    var displayText: String {
        switch self {
        case .found(let entry):
            let language = entry.containsChinese ? L("System dictionary entry (contains Han characters)") : L("System dictionary entry (Chinese meaning not confirmed)")
            let guidance = entry.containsChinese ? "" : L("\n\nThe current dictionary did not return Chinese. Check its language resources in Dictionary settings; multilingual recognition does not mean a Chinese dictionary is installed for every language.")
            return L("\(language):\n\(entry.text)\(guidance)\n\nThis is a general dictionary definition, not a meaning selected from the subtitle context.")
        case .notFound(let query):
            return L("The system dictionary returned no definition for “\(query)”.\nCheck the word and make sure the corresponding dictionary is downloaded and enabled. You can still save the original word and context without a Chinese definition.")
        case .invalidQuery:
            return L("Enter a word or phrase of 1–100 characters and look it up again.")
        }
    }
}

/// Use enabled local system dictionaries only; never download data, change preferences, or send network requests.
/// Lookup is synchronous and belongs in a background task so initial dictionary loading does not block AppKit.
enum SystemDictionary {
    /// Inject the lookup function for tests; the production default calls real Dictionary Services.
    /// Test input normalization and result states at the real boundary without requiring a particular installed dictionary.
    static func lookup(_ rawQuery: String,
                       definitionFor: (String) -> String? = copyDefinition) -> DictionaryLookup {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 100 else { return .invalidQuery }

        // Try the OCR spelling first, then apostrophe/case variants only after a miss; retain the actual query text.
        let normalized = query.replacingOccurrences(of: "’", with: "'")
        var attempted = Set<String>()
        for candidate in [query, normalized, normalized.lowercased()] {
            guard attempted.insert(candidate).inserted else { continue }
            guard let raw = definitionFor(candidate) else { continue }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return .found(DictionaryEntry(query: candidate, text: text)) }
        }
        return .notFound(query)
    }

    private static func copyDefinition(_ query: String) -> String? {
        let text = query as CFString
        // CFRange counts UTF-16 code units, not Swift Characters.
        let range = CFRange(location: 0, length: CFStringGetLength(text))
        // The public dictionary parameter is reserved for future use and must be nil.
        // The API returns the first active/default dictionary match; it cannot select a specific bilingual dictionary.
        guard let value = DCSCopyTextDefinition(nil, text, range) else { return nil }
        // Transfer the Copy-rule +1 reference to ARC to avoid leaking an entry on every lookup.
        return value.takeRetainedValue() as String
    }
}
