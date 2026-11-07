import Foundation

func runInterfaceLanguageTests() {
    let name = "WordNest.InterfaceLanguageTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    check(UILanguage.load(in: defaults) == .system, "fresh installation follows the system language")
    check(UILanguage.system.resolved(preferredLanguages: ["zh-Hans-CN", "en-US"]) == .simplifiedChinese,
          "system Chinese preferences resolve to supported Chinese interface")
    check(UILanguage.system.resolved(preferredLanguages: ["en-GB", "zh-Hans"]) == .english,
          "system language resolution honors preferred order")
    check(UILanguage.system.resolved(preferredLanguages: ["fr-FR", "zh-TW"]) == .simplifiedChinese,
          "system default uses the next supported preferred language")
    check(UILanguage.system.resolved(preferredLanguages: ["fr-FR"]) == .english,
          "unsupported system languages fall back to English")
    check(UILanguage.system.resolved(preferredLanguages: []) == .english,
          "empty system language preferences fall back to English")
    check(UILanguage.english.resolved(preferredLanguages: ["zh-Hans"]) == .english,
          "explicit English overrides Chinese system preferences")
    check(UILanguage.simplifiedChinese.resolved(preferredLanguages: ["en-US"]) == .simplifiedChinese,
          "explicit Chinese overrides English system preferences")
    defaults.set("fr-FR", forKey: "lookup.sourceLanguage.v1")
    let notebookData = Data("unchanged notebook selection".utf8)
    defaults.set(notebookData, forKey: "vocabulary.appleNotes.configuration.v2")
    UILanguage.english.save(in: defaults)
    check(UILanguage.load(in: UserDefaults(suiteName: name)!) == .english, "interface language selection persists across settings instances")
    check(defaults.string(forKey: "lookup.sourceLanguage.v1") == "fr-FR", "interface selection never changes the recognition language")
    check(defaults.data(forKey: "vocabulary.appleNotes.configuration.v2") == notebookData, "interface selection never rewrites notebook configuration")
    UILanguage.system.save(in: defaults)
    check(defaults.string(forKey: UILanguage.preferenceKey) == "system", "follow-system choice persists the policy rather than a resolved language")
    defaults.set("invalid", forKey: UILanguage.preferenceKey)
    check(UILanguage.load(in: defaults) == .system, "invalid stored language safely follows the system")
    check(L("Settings…", language: .english) == "Settings…", "English catalog resources are loaded")
    check(L("Settings…", language: .simplifiedChinese) == SampleText.value("Settings…"), "English source keys load the Chinese interface catalog")
    check(Set(UILocalization.englishCatalog.keys) == Set(UILocalization.chineseCatalog.keys), "both interface languages cover the same English keys")
    check(L("Welcome step", language: .english) == "Welcome to WordNest", "context keys retain their intended English display text")
    check(L("language.nativeChinese", language: .english) == SampleText.value("Simplified Chinese"), "the language picker keeps its native-language label in English UI")
    check(L("Saved to \(SampleText.value("Test account name"))", language: .simplifiedChinese)
          == SampleText.value("Saved to {0}").replacingOccurrences(of: "{0}", with: SampleText.value("Test account name")),
          "Chinese catalog interpolation retains the original localized template")
    let account = SampleText.value("Untrusted interpolation content")
    check(L("Saved to \(account)", language: .english) == "Saved to " + account,
          "translation keeps user data verbatim without recursively interpreting placeholders")
    check(L(" · Collected \(12) times", language: .english) == " · Collected 12 times", "interpolated counters use stable numbered catalog keys")
    check(L("not cataloged \(account)", language: .english) == "not cataloged " + account, "missing entries preserve content and interpolate safely")
    check(UILocalization.key(SampleText.value("Han characters"), language: .english) == "Han characters", "script categories translate only for display")
    check(BookRow.pageNames.contains(SampleText.value("Han characters")), "stored Notes categories retain their original identifiers")
    let previousLanguage = UILocalization.languageOverride
    defer { UILocalization.languageOverride = previousLanguage }
    let entry = VocabularyEntry(word: "happiness", definition: SampleText.value("Happiness short entry"), sentence: "Happiness matters.")
    let missing = VocabularyEntry(word: "unlisted", definition: nil, sentence: "An unlisted word.")
    var page = AlphabetPage(letter: "H", isTest: true, rows: [])
    do {
        UILocalization.languageOverride = .simplifiedChinese
        _ = try page.collect(entry)
        let table = page.html
        let single = entry.notesHTML
        let missingDefinition = missing.notesHTML
        UILocalization.languageOverride = .english
        check(page.html == table, "switching interface language preserves the exact managed Notes table HTML")
        check(entry.notesHTML == single && missing.notesHTML == missingDefinition, "localized presentation never changes stored definitions, grammar or missing-entry fallback")
        let readback = try AlphabetPage.parse(html: table, letter: "H", isTest: true, attachmentCount: 1)
        check(readback.rows == page.rows && readback.rows.first?.count == 1, "English UI reads existing Chinese-schema tables without changing collection counts")
    } catch { check(false, "interface-language storage compatibility fixture: \(error)") }
}
