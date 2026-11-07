import Foundation
import CoreFoundation

// zlib is part of macOS. Keep the small C boundary explicit; no external runtime is needed.
@_silgen_name("uncompress") private func mdxUncompress(_ destination: UnsafeMutablePointer<UInt8>, _ size: UnsafeMutablePointer<UInt>, _ source: UnsafePointer<UInt8>, _ sourceSize: UInt) -> Int32

enum MDXError: LocalizedError {
    case invalid, unsupportedVersion, unsupportedCompression, protectedDictionary, unsupportedEncoding, limit, checksum
    var errorDescription: String? {
        switch self {
        case .invalid: return L("The MDX file is incomplete or has an invalid structure.")
        case .unsupportedVersion: return L("This version supports MDX 2.x. MDX 1.x and 3.x are not supported yet.")
        case .unsupportedCompression: return L("This MDX uses unsupported compression. Use a version with zlib or uncompressed blocks; LZO is not supported yet.")
        case .protectedDictionary: return L("Password-protected MDX dictionaries are not supported. Import an unprotected file you are authorized to use.")
        case .unsupportedEncoding: return L("This MDX text encoding is not supported.")
        case .limit: return L("This dictionary exceeds the supported file, index, block or entry size limits.")
        case .checksum: return L("The MDX checksum does not match. The file may be damaged.")
        }
    }
}

/// Independent MDX 2.x reader based on the published container description by zhansliu.
/// Immutable, file-backed data and bounded block decoding keep lookup off the UI thread.
/// Scope: UTF-8/UTF-16LE/GBK/Big5, raw/zlib blocks, and standard encrypted key indexes.
/// Password-protected headers, LZO, MDD resources and executable dictionary HTML are excluded.
struct MDXReader: Sendable {
    static let maxFileSize = 1_073_741_824
    private static let maxBlockSize = 32 * 1_024 * 1_024
    private static let maxEntrySize = 4 * 1_024 * 1_024
    let title: String
    let entryCount: Int
    private let data: Data
    private let encoding: String.Encoding
    private let caseSensitive: Bool
    private let entries: [Key]
    private let exact: [String: [Int]]
    private let folded: [String: [Int]]
    private let blocks: [Block]
    private let recordSize: Int

    private struct Key: Sendable { let word: String; let offset: Int }
    private struct Block: Sendable { let fileOffset: Int; let compressed: Int; let offset: Int; let decoded: Int }

    init(url: URL) throws {
        let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard attributes.isRegularFile == true, let size = attributes.fileSize, size > 0 else { throw MDXError.invalid }
        guard size <= Self.maxFileSize else { throw MDXError.limit }
        let file = try Data(contentsOf: url, options: .mappedIfSafe)
        var cursor = MDXCursor(file)
        let headerSize = try cursor.integer(bytes: 4)
        guard headerSize <= 1_048_576 else { throw MDXError.limit }
        let headerData = try cursor.take(headerSize)
        guard try cursor.integer(bytes: 4, littleEndian: true) == Int(Self.adler32(headerData)),
              let header = String(data: headerData, encoding: .utf16LittleEndian) else { throw MDXError.checksum }
        let attributesMap = Self.headerAttributes(header)
        guard let version = Double(attributesMap["GeneratedByEngineVersion"] ?? ""), version >= 2, version < 3 else { throw MDXError.unsupportedVersion }
        let rawEncryption = attributesMap["Encrypted"] ?? "0"
        let encryption = rawEncryption.lowercased() == "no" ? "0" : rawEncryption
        guard let flags = Int(encryption), flags == 0 || flags == 2 else { throw MDXError.protectedDictionary }
        let textEncoding = try Self.textEncoding(attributesMap["Encoding"] ?? "UTF-8")
        let unit = textEncoding == .utf16LittleEndian ? 2 : 1
        let keyHeader = try cursor.take(40)
        guard try cursor.integer(bytes: 4) == Int(Self.adler32(keyHeader)) else { throw MDXError.checksum }
        var keySizes = MDXCursor(keyHeader)
        let keyBlockCount = try keySizes.integer()
        let count = try keySizes.integer()
        let indexDecodedSize = try keySizes.integer()
        let indexSize = try keySizes.integer()
        let keyBytes = try keySizes.integer()
        guard count > 0, count <= 1_000_000, keyBlockCount > 0, keyBlockCount <= count else { throw MDXError.limit }
        guard indexSize <= Self.maxBlockSize + 1_048_576 else { throw MDXError.limit }
        var indexData = try cursor.take(indexSize)
        if flags == 2 { indexData = try Self.decryptKeyIndex(indexData) }
        var index = MDXCursor(try Self.decodeBlock(indexData, expected: indexDecodedSize))
        let keyStart = cursor.position
        var keyOffset = 0
        var keys: [Key] = []
        keys.reserveCapacity(count)
        var totalKeyBytes = 0
        for _ in 0..<keyBlockCount {
            let blockCount = try index.integer()
            guard blockCount > 0, blockCount <= count - keys.count else { throw MDXError.invalid }
            for _ in 0..<2 {
                let length = try index.integer(bytes: 2)
                guard length <= 4_096 else { throw MDXError.limit }
                let boundary = try index.take((length + 1) * unit)
                guard boundary.suffix(unit).allSatisfy({ $0 == 0 }) else { throw MDXError.invalid }
            }
            let compressed = try index.integer()
            let decoded = try index.integer()
            guard compressed <= Self.maxBlockSize + 1_048_576 else { throw MDXError.limit }
            guard decoded <= Self.maxBlockSize, totalKeyBytes <= 64 * 1_024 * 1_024 - decoded else { throw MDXError.limit }
            totalKeyBytes += decoded
            guard compressed <= keyBytes - keyOffset else { throw MDXError.invalid }
            var blockCursor = MDXCursor(try Self.decodeBlock(try Self.range(file, start: keyStart + keyOffset, count: compressed), expected: decoded))
            for _ in 0..<blockCount {
                let offset = try blockCursor.integer()
                let keyData = try blockCursor.terminated(unit: unit)
                guard let key = String(data: keyData, encoding: textEncoding), !key.isEmpty else { throw MDXError.invalid }
                if let previous = keys.last, previous.offset > offset { throw MDXError.invalid }
                keys.append(Key(word: key, offset: offset))
            }
            guard blockCursor.isAtEnd else { throw MDXError.invalid }
            keyOffset += compressed
        }
        guard index.isAtEnd, keyOffset == keyBytes, keys.count == count else { throw MDXError.invalid }
        try cursor.skip(keyBytes)
        let recordBlockCount = try cursor.integer()
        let recordCount = try cursor.integer()
        let recordIndexSize = try cursor.integer()
        let recordBytes = try cursor.integer()
        guard recordBlockCount > 0, recordBlockCount <= 1_000_000, recordCount == count,
              recordIndexSize == recordBlockCount * 16 else { throw MDXError.invalid }
        var recordIndex = MDXCursor(try cursor.take(recordIndexSize))
        var records: [Block] = []
        let recordStart = cursor.position
        var compressedOffset = 0
        var decodedOffset = 0
        for _ in 0..<recordBlockCount {
            let compressed = try recordIndex.integer()
            let decoded = try recordIndex.integer()
            guard decoded > 0, decoded <= Self.maxBlockSize, compressed >= 8,
                  compressed <= Self.maxBlockSize + 1_048_576,
                  compressed <= recordBytes - compressedOffset,
                  decoded <= Int.max - decodedOffset else { throw MDXError.limit }
            // Inspect compression now so an unusable dictionary cannot become the selected source.
            let prefix = try Self.range(file, start: recordStart + compressedOffset, count: 4)
            guard prefix == Data([0, 0, 0, 0]) || prefix == Data([2, 0, 0, 0]) else { throw MDXError.unsupportedCompression }
            records.append(Block(fileOffset: recordStart + compressedOffset, compressed: compressed, offset: decodedOffset, decoded: decoded))
            compressedOffset += compressed
            decodedOffset += decoded
        }
        guard compressedOffset == recordBytes, recordBytes == cursor.remaining,
              keys.first?.offset == 0, keys.last!.offset < decodedOffset else { throw MDXError.invalid }
        var raw: [String: [Int]] = [:]
        var normalized: [String: [Int]] = [:]
        for (index, key) in keys.enumerated() {
            raw[key.word, default: []].append(index)
            normalized[key.word.lowercased(), default: []].append(index)
        }
        data = file
        encoding = textEncoding
        caseSensitive = attributesMap["KeyCaseSensitive"]?.lowercased() == "yes"
        entries = keys
        exact = raw
        folded = normalized
        blocks = records
        recordSize = decodedOffset
        entryCount = count
        title = String(DictionaryText.plainText(attributesMap["Title"] ?? url.deletingPathExtension().lastPathComponent).prefix(120))
    }

    func lookup(_ query: String) throws -> String? {
        try lookup(query, visited: [])
    }

    private func lookup(_ query: String, visited: Set<String>) throws -> String? {
        guard visited.count < 8, !visited.contains(query) else { throw MDXError.invalid }
        let matches = exact[query] ?? (caseSensitive ? nil : folded[query.lowercased()])
        guard let matches else { return nil }
        var results: [String] = []
        var seen = Set<String>()
        for index in matches.prefix(16) {
            let start = entries[index].offset
            var next = index + 1
            while next < entries.count && entries[next].offset == start { next += 1 }
            let end = next < entries.count ? entries[next].offset : recordSize
            guard end > start, end - start <= Self.maxEntrySize else { throw MDXError.limit }
            var record = Data()
            for block in blocks where block.offset < end && block.offset + block.decoded > start {
                let decoded = try Self.decodeBlock(try Self.range(data, start: block.fileOffset, count: block.compressed), expected: block.decoded)
                record.append(decoded.subdata(in: max(0, start - block.offset)..<min(block.decoded, end - block.offset)))
            }
            guard let text = String(data: record, encoding: encoding) else { throw MDXError.unsupportedEncoding }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
            let body: String
            if trimmed.hasPrefix("@@@LINK=") {
                let target = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
                body = try lookup(target, visited: visited.union([query])) ?? ""
            } else { body = DictionaryText.plainText(trimmed) }
            if !body.isEmpty, seen.insert(body).inserted { results.append(body) }
        }
        return results.isEmpty ? nil : results.joined(separator: "\n\n")
    }

    private static func range(_ data: Data, start: Int, count: Int) throws -> Data {
        guard start >= 0, count >= 0, start <= data.count, count <= data.count - start else { throw MDXError.invalid }
        return data.subdata(in: start..<(start + count))
    }

    private static func decodeBlock(_ block: Data, expected: Int) throws -> Data {
        guard expected >= 0, expected <= maxBlockSize, block.count >= 8, block.count <= maxBlockSize + 1_048_576 else { throw MDXError.limit }
        let type = Array(block.prefix(4))
        let result: Data
        if type == [0, 0, 0, 0] { result = Data(block.dropFirst(8)) }
        else if type == [2, 0, 0, 0] {
            var output = [UInt8](repeating: 0, count: max(expected, 1))
            var length = UInt(expected)
            let input = [UInt8](block.dropFirst(8))
            guard !input.isEmpty else { throw MDXError.invalid }
            let status = output.withUnsafeMutableBufferPointer { destination in
                input.withUnsafeBufferPointer { source in
                    mdxUncompress(destination.baseAddress!, &length, source.baseAddress!, UInt(input.count))
                }
            }
            guard status == 0, length == UInt(expected) else { throw MDXError.invalid }
            result = Data(output.prefix(expected))
        } else { throw MDXError.unsupportedCompression }
        guard result.count == expected else { throw MDXError.invalid }
        var checksum = MDXCursor(Data(block[4..<8]))
        guard try checksum.integer(bytes: 4) == Int(adler32(result)) else { throw MDXError.checksum }
        return result
    }

    static func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data { a = (a + UInt32(byte)) % 65_521; b = (b + a) % 65_521 }
        return (b << 16) | a
    }

    private static func decryptKeyIndex(_ data: Data) throws -> Data {
        guard data.count >= 8 else { throw MDXError.invalid }
        let key = RIPEMD128.hash(Data(data[4..<8]) + Data([0x95, 0x36, 0, 0]))
        let input = [UInt8](data.dropFirst(8))
        var output = Data(data.prefix(8))
        var previous: UInt8 = 0x36
        for (i, byte) in input.enumerated() {
            output.append(((byte >> 4) | (byte << 4)) ^ previous ^ UInt8(truncatingIfNeeded: i) ^ key[i % key.count])
            previous = byte
        }
        return output
    }

    private static func headerAttributes(_ header: String) -> [String: String] {
        guard let expression = try? NSRegularExpression(pattern: "([A-Za-z][A-Za-z0-9]*)\\s*=\\s*\"([^\"]*)\"") else { return [:] }
        let string = header as NSString
        return expression.matches(in: header, range: NSRange(location: 0, length: string.length)).reduce(into: [:]) {
            $0[string.substring(with: $1.range(at: 1))] = string.substring(with: $1.range(at: 2))
        }
    }

    private static func textEncoding(_ value: String) throws -> String.Encoding {
        switch value.uppercased().replacingOccurrences(of: "-", with: "") {
        case "UTF8": return .utf8
        case "UTF16", "UTF16LE": return .utf16LittleEndian
        case "GBK", "GB2312", "GB18030": return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        case "BIG5": return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        default: throw MDXError.unsupportedEncoding
        }
    }
}

private struct MDXCursor {
    let data: Data
    var position = 0
    init(_ data: Data) { self.data = data }
    var remaining: Int { data.count - position }
    var isAtEnd: Bool { remaining == 0 }
    mutating func skip(_ count: Int) throws {
        guard count >= 0, count <= remaining else { throw MDXError.invalid }
        position += count
    }
    mutating func take(_ count: Int) throws -> Data {
        guard count >= 0, count <= remaining else { throw MDXError.invalid }
        defer { position += count }
        return data.subdata(in: position..<(position + count))
    }
    mutating func integer(bytes: Int = 8, littleEndian: Bool = false) throws -> Int {
        let bytes = [UInt8](try take(bytes))
        var value: UInt64 = 0
        for byte in littleEndian ? Array(bytes.reversed()) : bytes { value = (value << 8) | UInt64(byte) }
        guard value <= UInt64(Int.max) else { throw MDXError.limit }
        return Int(value)
    }
    mutating func terminated(unit: Int) throws -> Data {
        let start = position
        while remaining >= unit {
            guard position - start <= 4_096 else { throw MDXError.limit }
            let zeros = data[position] == 0 && (unit == 1 || data[position + 1] == 0)
            if zeros { let result = data.subdata(in: start..<position); position += unit; return result }
            position += unit
        }
        throw MDXError.invalid
    }
}

/// Render local dictionary text without a WebView, scripts, external entities or remote resources.
enum DictionaryText {
    static func plainText(_ html: String) -> String {
        let safe = html.replacingOccurrences(of: "(?is)<(script|style|iframe|object|template)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?is)<!DOCTYPE[^>]*>|<!ENTITY[^>]*>", with: "", options: .regularExpression)
        func text(_ node: XMLNode, depth: Int = 0) -> String {
            guard depth < 128 else { return "" }
            if node.kind == .text { return node.stringValue ?? "" }
            let name = node.name?.lowercased() ?? ""
            if ["head", "script", "style", "iframe", "object", "template", "audio", "video"].contains(name) { return "" }
            if name == "br" { return "\n" }
            let body = (node.children ?? []).map { text($0, depth: depth + 1) }.joined()
            return body + (["p", "div", "li", "tr", "h1", "h2", "h3"].contains(name) ? "\n" : (name == "td" ? "\t" : ""))
        }
        let output: String
        if let document = try? XMLDocument(xmlString: "<html><body>" + safe + "</body></html>", options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]) {
            output = text(document)
        } else { output = safe.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression) }
        return output.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\n[ \\t]+", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }
}
