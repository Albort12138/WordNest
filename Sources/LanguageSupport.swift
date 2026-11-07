import Foundation
import NaturalLanguage

/// Centralize source-language selection and speech inference; query Vision for actual OCR support on this macOS.
/// Short words make automatic detection ambiguous; retain explicit language selection and treat inference as uncertain.
enum SourceLanguage: String, CaseIterable {
    case automatic = "auto", english = "en-US", simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant"
    case japanese = "ja-JP", korean = "ko-KR", french = "fr-FR", german = "de-DE", spanish = "es-ES"
    case italian = "it-IT", portuguese = "pt-BR", russian = "ru-RU", arabic = "ar-SA"
    case thai = "th-TH", vietnamese = "vi-VN", ukrainian = "uk-UA", turkish = "tr-TR"

    var title: String {
        switch self {
        case .automatic: return L("Automatic detection")
        case .english: return L("English")
        case .simplifiedChinese: return L("Simplified Chinese")
        case .traditionalChinese: return L("Traditional Chinese")
        case .japanese: return L("Japanese")
        case .korean: return L("Korean")
        case .french: return L("French")
        case .german: return L("German")
        case .spanish: return L("Spanish")
        case .italian: return L("Italian")
        case .portuguese: return L("Portuguese")
        case .russian: return L("Russian")
        case .arabic: return L("Arabic")
        case .thai: return L("Thai")
        case .vietnamese: return L("Vietnamese")
        case .ukrainian: return L("Ukrainian")
        case .turkish: return L("Turkish")
        }
    }
    var hint: String? { self == .automatic ? nil : rawValue }
    var naturalLanguage: NLLanguage? {
        guard self != .automatic else { return nil }
        if self == .simplifiedChinese { return .simplifiedChinese }
        if self == .traditionalChinese { return .traditionalChinese }
        return NLLanguage(rawValue: String(rawValue.prefix(2)))
    }
    static func load() -> SourceLanguage {
        SourceLanguage(rawValue: UserDefaults.standard.string(forKey: "lookup.sourceLanguage.v1") ?? "auto") ?? .automatic
    }
    func save() { UserDefaults.standard.set(rawValue, forKey: "lookup.sourceLanguage.v1") }
}

enum LanguageSupport {
    static func hasLetters(_ text: String) -> Bool {
        // Foundation letters may include combining marks; an isolated accent must not become a word.
        text.unicodeScalars.contains {
            switch $0.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
            default: return false
            }
        }
    }

    /// Prefer explicit selection; otherwise detect distinctive scripts first, then use context for short Latin words.
    /// The same Han word may be Chinese or Japanese; glyphs alone cannot guarantee its spoken language.
    static func language(for word: String, context: String = "", preferred: String? = nil) -> String {
        if let preferred, preferred != "auto" { return preferred }
        if word.range(of: "[\\p{Hiragana}\\p{Katakana}]", options: .regularExpression) != nil { return "ja-JP" }
        if word.range(of: "\\p{Hangul}", options: .regularExpression) != nil { return "ko-KR" }
        if word.range(of: "\\p{Han}", options: .regularExpression) != nil {
            if context.range(of: "[\\p{Hiragana}\\p{Katakana}]", options: .regularExpression) != nil { return "ja-JP" }
            return "zh-CN"
        }
        let sample = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let detected = NLLanguageRecognizer.dominantLanguage(for: sample.count >= 12 ? sample : word)
        switch detected {
        case .english: return "en-US"
        case .simplifiedChinese: return "zh-CN"
        case .traditionalChinese: return "zh-TW"
        case .japanese: return "ja-JP"
        case .korean: return "ko-KR"
        default: return detected?.rawValue ?? "en-US"
        }
    }

    static func displayName(_ code: String) -> String {
        Locale(identifier: UILocalization.currentLanguage.localeIdentifier).localizedString(forLanguageCode: code) ?? code
    }
}
