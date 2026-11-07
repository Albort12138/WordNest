import Foundation

/// Read signed app resources, or checked-in assets for standalone test executables.
enum TextResources {
    static var root: URL {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.resourceURL ?? Bundle.main.bundleURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets")
    }

    static func catalog(in folder: String, prefix: String) -> [String: String] {
        let directory = root.appendingPathComponent(folder)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            preconditionFailure("Missing bundled text resource directory: \(folder)")
        }
        let selected = files.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
        precondition(!selected.isEmpty, "Missing bundled text catalog: \(folder)/\(prefix)")
        var result: [String: String] = [:]
        for file in selected.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let data = try? Data(contentsOf: file),
                  let entries = try? JSONDecoder().decode([String: String].self, from: data) else {
                preconditionFailure("Invalid bundled text catalog: \(file.lastPathComponent)")
            }
            for (key, value) in entries {
                precondition(result[key] == nil || result[key] == value, "Conflicting bundled text key: \(key)")
                result[key] = value
            }
        }
        return result
    }

    /// Replace slots once, from the end, so inserted user content is never interpreted as a template.
    static func interpolate(_ template: String, arguments: [String]) -> String {
        let result = NSMutableString(string: template)
        let expression = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
        let matches = expression.matches(in: template, range: NSRange(location: 0, length: result.length))
        for match in matches.reversed() {
            let number = (template as NSString).substring(with: match.range(at: 1))
            if let index = Int(number), arguments.indices.contains(index) {
                result.replaceCharacters(in: match.range, with: arguments[index])
            }
        }
        return result as String
    }
}

/// Storage markers belong to the existing Notes format, independent of interface language.
/// Missing schema resources are packaging errors; never silently replace persisted identifiers.
enum LegacyNotesText {
    static let catalog = TextResources.catalog(in: "Compatibility", prefix: "legacy-notes")

    static func value(_ key: String) -> String {
        guard let value = catalog[key] else { preconditionFailure("Missing legacy Notes text: \(key)") }
        return value
    }

    static func format(_ key: String, _ arguments: [String]) -> String {
        TextResources.interpolate(value(key), arguments: arguments)
    }

    static func englishKey(for storedValue: String) -> String? {
        catalog.first(where: { $0.value == storedValue })?.key
    }

    /// Inject a fixed storage identifier into a script without changing its quoted-string syntax.
    static func appleScriptLiteral(_ key: String) -> String {
        let escaped = value(key).replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"" + escaped + "\""
    }
}

/// Multilingual examples and expected fixture text are data, not source-language literals.
enum SampleText {
    static let catalog = TextResources.catalog(in: "Fixtures", prefix: "sample-text")

    static func value(_ key: String) -> String {
        guard let value = catalog[key] else { preconditionFailure("Missing sample text: \(key)") }
        return value
    }

    static func format(_ key: String, _ arguments: [String]) -> String {
        TextResources.interpolate(value(key), arguments: arguments)
    }
}
