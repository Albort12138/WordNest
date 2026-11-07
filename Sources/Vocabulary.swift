import Foundation

/// Collection content for one lookup; its identity belongs to that event rather than merging all contexts for a word.
struct VocabularyEntry: Equatable {
    let id: UUID
    let word: String
    var definition: String?
    var definitionFormat: DictionaryEntryFormat
    let sentence: String
    let createdAt: Date
    let isTestEntry: Bool
    var source: CollectionSource?

    init(id: UUID = UUID(), word: String, definition: String?, sentence: String, createdAt: Date = Date(), isTestEntry: Bool = false, source: CollectionSource? = nil,
         definitionFormat: DictionaryEntryFormat = .system) {
        self.id = id
        self.word = word
        self.definition = definition
        self.definitionFormat = definitionFormat
        self.sentence = sentence
        self.createdAt = createdAt
        self.isTestEntry = isTestEntry
        self.source = source
    }

    var marker: String { "SL-" + id.uuidString }

    /// Use one completeness rule after creation and during reconciliation; an ID without expected content is insufficient.
    func isPresent(in readBack: String) -> Bool {
        let required = [word, definition ?? "", sentence, marker]
            .flatMap { $0.components(separatedBy: .newlines) }.filter { !$0.isEmpty }
        return required.allSatisfy { readBack.contains($0) }
    }

    /// Notes accepts HTML; escape all user/dictionary text before inserting it into fixed templates.
    /// Never embed scripts, remote images, or unvalidated source links.
    var notesHTML: String {
        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\n", with: "<br>")
        }
        var sections = ["<h1>\(isTestEntry ? LegacyNotesText.value("Single entry test prefix") : "")\(escape(word))</h1>"]
        if let definition, !definition.isEmpty {
            let entry = DictionaryEntry(query: word, text: definition, format: definitionFormat)
            let presentation = DictionaryPresentation(entry: entry)
            if let phonetics = entry.pronunciation { sections.append("<p>\(escape(phonetics))</p>") }
            sections.append(LegacyNotesText.value("Definition heading HTML"))
            if let grammar = presentation.grammar { sections.append("<p>\(escape(grammar))</p>") }
            sections.append("<p>\(escape(presentation.meaning))</p>")
            if !presentation.examples.isEmpty {
                sections.append(LegacyNotesText.value("Dictionary examples heading HTML"))
                sections += presentation.examples.map { "<p>\(escape($0))</p>" }
            }
            // Retain complete raw content for later verification; unfamiliar formatting must not discard information.
            sections += [LegacyNotesText.value("Complete entry heading HTML"), "<p>\(escape(definition))</p>"]
        } else {
            sections.append(LegacyNotesText.value("Missing definition HTML"))
        }
        if !sentence.isEmpty { sections += [LegacyNotesText.value("Original line heading HTML"), "<p>\(escape(sentence))</p>"] }
        let date = ISO8601DateFormatter().string(from: createdAt)
        sections.append(LegacyNotesText.format("Single entry metadata HTML", [String(describing: date), String(describing: marker)]))
        return sections.joined(separator: "\n")
    }
}

/// Locate accounts and folders by stable system ID; display names must never redirect writes to a namesake.
struct NotesDestination: Codable, Hashable {
    let accountID: String
    let accountName: String
    let folderID: String
    let folderName: String
    var displayName: String { "\(accountName) / \(folderName)" }
}

struct NotesAccount {
    let id: String
    let name: String
    let folders: [NotesDestination]
}

/// Separate physical storage from browsing views. Smart folders reference notes and cannot be creation destinations.
struct NotesConfiguration: Codable, Equatable {
    let storage: NotesDestination
    var browsing: NotesDestination? = nil
    var readingDestination: NotesDestination { browsing ?? storage }
}

struct VocabularyReceipt: Equatable {
    let noteID: String
    var collectionCount: Int? = nil
}

enum NotesFailure: Error, LocalizedError {
    case permissionDenied
    case targetMissing
    case invalidResponse
    case smartFolderReadOnly
    case automation(Int, String)
    case uncertain(String)

    /// Translate exact application-defined script diagnostics only; preserve unrecognized native errors verbatim.
    private static func localizedDiagnostic(_ message: String) -> String {
        switch message {
        case "The selected Notes account does not exist.": return L("The selected Notes account does not exist.")
        case "The selected Notes folder does not exist.": return L("The selected Notes folder does not exist.")
        case "Choose a folder that is not shared.": return L("Choose a folder that is not shared.")
        case "Multiple folders have the same name. Choose one manually.": return L("Multiple folders have the same name. Choose one manually.")
        case "Multiple notes have the same collection identifier. Inspect them in Notes.": return L("Multiple notes have the same collection identifier. Inspect them in Notes.")
        case "The note left the selected folder during reconciliation.": return L("The note left the selected folder during reconciliation.")
        case "The readback is missing the collection identifier.": return L("The readback is missing the collection identifier.")
        case "The readback is not in the selected folder.": return L("The readback is not in the selected folder.")
        case "Multiple category pages have the same name. Resolve the duplicates first.": return L("Multiple category pages have the same name. Resolve the duplicates first.")
        case "The category page is locked. Unlock it first.": return L("The category page is locked. Unlock it first.")
        case "The category page was created elsewhere. Refresh and try again.": return L("The category page was created elsewhere. Refresh and try again.")
        case "The category page changed. Refresh and try again.": return L("The category page changed. Refresh and try again.")
        case "The category page identity changed.": return L("The category page identity changed.")
        case "The category page is locked.": return L("The category page is locked.")
        case "Shared category pages cannot be updated.": return L("Shared category pages cannot be updated.")
        case "The note changed before writing. Refresh and try again.": return L("The note changed before writing. Refresh and try again.")
        case "The category page attachments changed. Nothing was updated.": return L("The category page attachments changed. Nothing was updated.")
        default: return message
        }
    }

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return L("Notes access is not allowed. Allow WordNest to access Notes in System Settings > Privacy & Security > Automation, then try again.")
        case .targetMissing:
            return L("The selected account or folder could not be found. Choose the notebook location again; nothing will be saved elsewhere.")
        case .invalidResponse:
            return L("Notes did not return a verifiable result. Reconnect and check the selected location.")
        case .smartFolderReadOnly:
            return L("New notes cannot be assigned directly to a Smart Folder. Notes may already have created an unmatched page, so the result needs reconciliation. The deduplication record is retained and further writes to this location are blocked. Choose an ordinary save folder in notebook settings, select the Smart Folder separately for browsing, and inspect the original page in Notes.")
        case .automation(let code, let message):
            return L("The Notes operation did not complete (\(code)): \(Self.localizedDiagnostic(message))")
        case .uncertain(let message):
            return L("Collection result needs confirmation: \(Self.localizedDiagnostic(message)) Click Reconcile; no duplicate will be created automatically.")
        }
    }
}

/// Callers submit collection content and receive results; implementations handle accounts, escaping, deduplication, and readback.
/// Notes is the only real backend today; add a concrete implementation and configuration when integrating Notion.
protocol NotesSaving {
    func save(_ entry: VocabularyEntry, to destination: NotesDestination) async throws -> VocabularyReceipt
    func find(_ entry: VocabularyEntry, in destination: NotesDestination) async throws -> VocabularyReceipt?
}

enum CollectionState: Equatable {
    case idle
    case saving
    case saved(VocabularyReceipt)
    case failed(String)
    case needsConfiguration(String)
    case uncertain(String)
}

/// Preserve event state across card refreshes to prevent duplicate clicks; unknown outcomes permit reconciliation, never blind writes.
@MainActor final class VocabularyCollector {
    private struct Key: Hashable {
        let id: UUID
        let accountID: String
        let folderID: String
        init(id: UUID, destination: NotesDestination) {
            self.id = id
            self.accountID = destination.accountID
            self.folderID = destination.folderID
        }
    }
    var onStateChanged: (() -> Void)?
    private var states: [Key: CollectionState] = [:] { didSet { onStateChanged?() } }
    private let client: any NotesSaving

    init(client: any NotesSaving) { self.client = client }

    func state(for entry: VocabularyEntry, destination: NotesDestination) -> CollectionState {
        states[Key(id: entry.id, destination: destination)] ?? .idle
    }

    func collect(_ entry: VocabularyEntry, to destination: NotesDestination) async {
        let key = Key(id: entry.id, destination: destination)
        let previous = states[key] ?? .idle
        if case .saving = previous { return }
        if case .saved = previous { return }
        guard !entry.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, entry.word.count <= 100 else {
            states[key] = .failed(L("Look up a word or phrase of 1–100 characters before collecting."))
            return
        }
        states[key] = .saving
        do {
            if case .uncertain = previous {
                if let receipt = try await client.find(entry, in: destination) {
                    states[key] = .saved(receipt)
                } else {
                    states[key] = .uncertain(L("The matching note has not been found. Reconcile again later or inspect the destination folder."))
                }
            } else {
                states[key] = .saved(try await client.save(entry, to: destination))
            }
        } catch {
            // Failed reconciliation remains unknown; never turn it into an ordinary failure that permits creating again.
            if case .uncertain = previous { states[key] = .uncertain(error.localizedDescription) }
            else if case NotesFailure.smartFolderReadOnly = error { states[key] = .needsConfiguration(error.localizedDescription) }
            else if case NotesFailure.uncertain(let message) = error { states[key] = .uncertain(message) }
            else { states[key] = .failed(error.localizedDescription) }
        }
    }
}

enum NotesPreferences {
    private static let key = "vocabulary.appleNotes.destination.v1"
    private static let configurationKey = "vocabulary.appleNotes.configuration.v2"
    static func configuration() -> NotesConfiguration? {
        if let data = UserDefaults.standard.data(forKey: configurationKey) {
            return try? JSONDecoder().decode(NotesConfiguration.self, from: data)
        }
        guard let data = UserDefaults.standard.data(forKey: key),
              let target = try? JSONDecoder().decode(NotesDestination.self, from: data) else { return nil }
        return NotesConfiguration(storage: target)
    }
    static func load() -> NotesDestination? {
        configuration()?.storage
    }
    static func save(_ destination: NotesDestination) {
        save(NotesConfiguration(storage: destination))
    }
    static func save(_ configuration: NotesConfiguration) {
        if let data = try? JSONEncoder().encode(configuration) { UserDefaults.standard.set(data, forKey: configurationKey) }
    }
}
