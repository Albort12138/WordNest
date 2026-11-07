import Foundation

enum ResolvedUILanguage: String {
    case simplifiedChinese = "zh-Hans", english = "en"
    var localeIdentifier: String { self == .simplifiedChinese ? "zh_CN" : "en_US" }
}

/// Interface language is independent of OCR language and never changes stored vocabulary.
enum UILanguage: String, CaseIterable {
    case system, simplifiedChinese = "zh-Hans", english = "en"
    static let preferenceKey = "interface.language.v1"

    static func load(in defaults: UserDefaults = .standard) -> UILanguage {
        UILanguage(rawValue: defaults.string(forKey: preferenceKey) ?? "system") ?? .system
    }

    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> ResolvedUILanguage {
        switch self {
        case .simplifiedChinese: return .simplifiedChinese
        case .english: return .english
        case .system:
            for language in preferredLanguages {
                let code = language.lowercased().replacingOccurrences(of: "_", with: "-")
                if code == "zh" || code.hasPrefix("zh-") { return .simplifiedChinese }
                if code == "en" || code.hasPrefix("en-") { return .english }
            }
            return .english
        }
    }

    func save(in defaults: UserDefaults = .standard) {
        let previous = Self.load(in: defaults)
        defaults.set(rawValue, forKey: Self.preferenceKey)
        // macOS can terminate the app immediately after the next permission request.
        defaults.synchronize()
        if previous != self, defaults === UserDefaults.standard {
            NotificationCenter.default.post(name: .wordNestInterfaceLanguageDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let wordNestInterfaceLanguageDidChange = Notification.Name("WordNest.InterfaceLanguageDidChange")
}

/// Keep interpolated user data separate from translation keys and replace it only once.
struct UIString: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]

    init(stringLiteral value: String) { key = value; arguments = [] }
    init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"
            arguments.append(String(describing: value))
        }
    }
}

enum UILocalization {
    // Fixed-data checks can pin presentation without changing a user's language preference.
    static var languageOverride: ResolvedUILanguage?
    static var currentLanguage: ResolvedUILanguage { languageOverride ?? UILanguage.load().resolved() }
    static let englishCatalog = TextResources.catalog(in: "Localization", prefix: "en-")
    static let chineseCatalog = TextResources.catalog(in: "Localization", prefix: "zh-Hans-")

    static func key(_ key: String, language: ResolvedUILanguage? = nil) -> String {
        let resolved = language ?? currentLanguage
        // Explicit display-only callers may pass a stable legacy category or grammar label.
        let sourceKey = LegacyNotesText.englishKey(for: key) ?? key
        let catalog = resolved == .english ? englishCatalog : chineseCatalog
        return catalog[sourceKey] ?? sourceKey
    }

    static func text(_ value: UIString, language: ResolvedUILanguage? = nil) -> String {
        TextResources.interpolate(key(value.key, language: language), arguments: value.arguments)
    }
}

func L(_ value: UIString, language: ResolvedUILanguage? = nil) -> String {
    UILocalization.text(value, language: language)
}
