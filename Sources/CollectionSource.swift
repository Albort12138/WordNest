import Foundation

/// A page snapshot belongs to lookup time. Accept web URLs only; never fetch pages, resolve links online, or infer playback time.
struct CollectionSource: Codable, Equatable {
    let url: String
    let title: String

    init?(url raw: String, title: String = "") {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count <= 8192, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let parts = URLComponents(string: value), let scheme = parts.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, let parsed = parts.url else { return nil }
        self.url = parsed.absoluteString
        self.title = title.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            .precomposedStringWithCanonicalMapping.prefix(1000).description
    }

    /// Group share, tracking, and time variants of one Bilibili/YouTube video; retain the full raw URL in each event.
    /// Keep Bilibili parts separate and preserve semantic parameters/fragments on unknown sites to avoid merging distinct pages.
    var identityURL: String {
        guard var parts = URLComponents(string: url) else { return url }
        let host = parts.host?.lowercased() ?? ""
        let path = parts.path.split(separator: "/").map(String.init)
        if ["bilibili.com", "www.bilibili.com", "m.bilibili.com"].contains(host), path.count == 2, path[0] == "video" {
            var result = "https://www.bilibili.com/video/\(path[1])/"
            if let p = parts.queryItems?.first(where: { $0.name == "p" })?.value.flatMap(Int.init), p > 1 { result += "?p=\(p)" }
            return result
        }
        var videoID: String?
        if host == "youtu.be", path.count == 1 { videoID = path[0] }
        if ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(host) {
            if parts.path == "/watch" { videoID = parts.queryItems?.first(where: { $0.name == "v" })?.value }
            if path.count == 2 && ["shorts", "live"].contains(path[0]) { videoID = path[1] }
        }
        if let videoID, !videoID.isEmpty, videoID.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil {
            return "https://www.youtube.com/watch?v=\(videoID)"
        }
        parts.host = host
        let query = parts.queryItems?.filter { !$0.name.lowercased().hasPrefix("utm_") && !["fbclid", "gclid"].contains($0.name.lowercased()) }
        parts.queryItems = query?.isEmpty == true ? nil : query
        return parts.url?.absoluteString ?? url
    }

    var kind: String {
        identityURL.hasPrefix("https://www.bilibili.com/video/") || identityURL.hasPrefix("https://www.youtube.com/watch?v=") ? LegacyNotesText.value("Video") : LegacyNotesText.value("Webpage")
    }
    var displayName: String { title.isEmpty ? url : title }
}

/// One record per deliberate collection; reuse the query UUID so retries cannot add events or increment twice.
struct CollectionOccurrence: Codable, Equatable {
    let id: UUID
    let recordedAt: String
    let sentence: String
    let source: CollectionSource?

    init(entry: VocabularyEntry) {
        id = entry.id
        recordedAt = ISO8601DateFormatter().string(from: entry.createdAt)
        sentence = BookRow.clean(entry.sentence)
        source = entry.source
    }

    init(id: UUID, recordedAt: String, sentence: String, source: CollectionSource?) {
        self.id = id; self.recordedAt = recordedAt; self.sentence = sentence; self.source = source
    }
}
