import Foundation

/// A dictionary instance has its own stable identity, independent of its display title or file name.
struct DictionarySource: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case system, mdx }
    let id: String
    let name: String
    let kind: Kind
    static let system = DictionarySource(id: "system", name: "macOS system dictionary", kind: .system)
    var displayName: String { kind == .system ? L("macOS system dictionary") : name }
}

struct DictionaryRequest: Sendable {
    let text: String
    var sourceLanguage: String? = nil
}

/// Providers return definitions without changing selection, presenting UI, or collecting vocabulary.
/// The caller snapshots a provider before awaiting and rejects results for a superseded card.
protocol DictionaryProvider: Sendable {
    var source: DictionarySource { get }
    func lookup(_ request: DictionaryRequest) async throws -> DictionaryLookup
}

struct SystemDictionaryProvider: DictionaryProvider {
    let source = DictionarySource.system
    func lookup(_ request: DictionaryRequest) async throws -> DictionaryLookup {
        await Task.detached(priority: .userInitiated) { SystemDictionary.lookup(request.text) }.value
    }
}

struct MDXDictionaryProvider: DictionaryProvider {
    let source: DictionarySource
    let reader: MDXReader
    func lookup(_ request: DictionaryRequest) async throws -> DictionaryLookup {
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 100 else { return .invalidQuery }
        return try await Task.detached(priority: .userInitiated) {
            let normalized = text.replacingOccurrences(of: "’", with: "'")
            var seen = Set<String>()
            for candidate in [text, normalized] where seen.insert(candidate).inserted {
                if let body = try reader.lookup(candidate) {
                    return .found(DictionaryEntry(query: candidate, text: body, format: .plainText))
                }
            }
            return .notFound(text)
        }.value
    }
}

struct DictionaryResponse: Sendable {
    let source: DictionarySource
    let result: DictionaryLookup?
    let error: String?
    var entry: DictionaryEntry? { result?.entry }
    var message: String {
        if let error { return L("Could not query “\(source.displayName)”: \(error)\nChoose another dictionary or reimport the file in Dictionaries settings.") }
        if source.kind == .system { return result?.displayText ?? "" }
        if case .notFound(let word) = result {
            return L("No entry for “\(word)” in “\(source.displayName)”. You can choose another dictionary or save the word and its original context.")
        }
        return result?.displayText ?? ""
    }
}

/// UI-owned configuration; parsing and lookup execute in background tasks.
/// Imports become immutable managed copies only after validation. Never modify the user's source file.
@MainActor final class DictionaryLibrary {
    static let preferenceKey = "dictionary.configuration.v1"
    struct Record: Codable, Equatable, Sendable {
        let id: UUID
        let name: String
        let entries: Int
        var source: DictionarySource { DictionarySource(id: id.uuidString, name: name, kind: .mdx) }
    }
    private struct Configuration: Codable { var selected: String; var records: [Record] }
    private(set) var records: [Record] = []
    private(set) var selectedID = DictionarySource.system.id
    private(set) var isImporting = false
    private let root: URL
    private let defaults: UserDefaults
    private var readers: [UUID: MDXReader] = [:]

    init(root: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "io.github.albort12138.wordnest", isDirectory: true)
            .appendingPathComponent("Dictionaries", isDirectory: true)
        if let data = defaults.data(forKey: Self.preferenceKey), let saved = try? JSONDecoder().decode(Configuration.self, from: data) {
            var seen = Set<UUID>()
            records = saved.records.filter { seen.insert($0.id).inserted && !$0.name.isEmpty && $0.name.count <= 120 && $0.entries > 0 }
            selectedID = saved.selected == DictionarySource.system.id || records.contains(where: { $0.source.id == saved.selected }) ? saved.selected : DictionarySource.system.id
        }
    }

    var sources: [DictionarySource] { [.system] + records.map(\.source) }
    var selectedSource: DictionarySource { sources.first { $0.id == selectedID } ?? .system }
    func isAvailable(_ source: DictionarySource) -> Bool {
        source.kind == .system || records.contains { $0.source.id == source.id && FileManager.default.fileExists(atPath: fileURL($0.id).path) }
    }

    func select(_ id: String) throws {
        guard !isImporting, sources.contains(where: { $0.id == id }) else { throw MDXError.invalid }
        selectedID = id
        try persist()
    }

    @discardableResult func importMDX(from sourceURL: URL) async throws -> Record {
        guard !isImporting, sourceURL.pathExtension.lowercased() == "mdx" else { throw MDXError.invalid }
        isImporting = true
        defer { isImporting = false }
        let id = UUID()
        let target = fileURL(id)
        let directory = root
        let (record, reader) = try await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            let access = sourceURL.startAccessingSecurityScopedResource()
            defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }
            let attributes = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard attributes.isRegularFile == true, let size = attributes.fileSize, size > 0, size <= MDXReader.maxFileSize else { throw MDXError.limit }
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let staging = directory.appendingPathComponent("import-" + id.uuidString + ".tmp")
            defer { try? manager.removeItem(at: staging) }
            try manager.copyItem(at: sourceURL, to: staging)
            let parsed = try MDXReader(url: staging)
            let title = parsed.title.isEmpty ? String(sourceURL.deletingPathExtension().lastPathComponent.prefix(120)) : parsed.title
            let record = Record(id: id, name: title, entries: parsed.entryCount)
            try manager.moveItem(at: staging, to: target)
            return (record, parsed)
        }.value
        let previous = selectedID
        records.append(record)
        readers[id] = reader
        selectedID = record.source.id
        do { try persist() }
        catch {
            records.removeAll { $0.id == id }; readers.removeValue(forKey: id); selectedID = previous
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return record
    }

    func remove(_ id: UUID) throws {
        guard !isImporting, records.contains(where: { $0.id == id }) else { throw MDXError.invalid }
        // Preserve the file if saving the new configuration fails. Orphans are harmless and never queried.
        let oldRecords = records, previous = selectedID
        records.removeAll { $0.id == id }
        if selectedID == id.uuidString { selectedID = DictionarySource.system.id }
        do { try persist() } catch { records = oldRecords; selectedID = previous; throw error }
        readers.removeValue(forKey: id)
        try? FileManager.default.removeItem(at: fileURL(id))
    }

    func lookup(_ request: DictionaryRequest, source: DictionarySource? = nil) async -> DictionaryResponse {
        let source = source ?? selectedSource
        do {
            let provider: any DictionaryProvider
            if source.kind == .system { provider = SystemDictionaryProvider() }
            else {
                guard let record = records.first(where: { $0.source.id == source.id }) else { throw MDXError.invalid }
                let reader: MDXReader
                if let cached = readers[record.id] { reader = cached }
                else {
                    let file = fileURL(record.id)
                    reader = try await Task.detached(priority: .userInitiated) { try MDXReader(url: file) }.value
                    if records.contains(where: { $0.id == record.id }) { readers[record.id] = reader }
                }
                provider = MDXDictionaryProvider(source: source, reader: reader)
            }
            return DictionaryResponse(source: source, result: try await provider.lookup(request), error: nil)
        } catch { return DictionaryResponse(source: source, result: nil, error: error.localizedDescription) }
    }

    private func fileURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".mdx") }
    private func persist() throws {
        defaults.set(try JSONEncoder().encode(Configuration(selected: selectedID, records: records)), forKey: Self.preferenceKey)
    }
}
