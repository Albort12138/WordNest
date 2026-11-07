import AppKit
import CoreText
import Vision
import NaturalLanguage

func runLanguageTests() {
    func tokens(_ text: String, _ language: NLLanguage? = nil) -> [String] {
        WordSelection.ranges(in: text, language: language).map { String(text[$0]) }
    }
    check(tokens("école Straße mañana déjà-vu l’école") == ["école", "Straße", "mañana", "déjà-vu", "l’école"], "accented Latin words and internal punctuation remain intact")
    check(tokens("e\u{301}cole").first == "e\u{301}cole", "combining accents retain original string ranges")
    check(tokens("привет мир") == ["привет", "мир"], "Cyrillic word boundaries survive")
    check(tokens("مرحبا بالعالم") == ["مرحبا", "بالعالم"], "Arabic words retain complete letter sequences")
    check(tokens("안녕하세요 공부", .korean).contains("공부"), "Korean is not discarded as non-English")
    let japanese = tokens(SampleText.value("Japanese tokenizer context"), .japanese)
    check(japanese.contains(SampleText.value("Japanese study word")) && japanese.count > 1, "Japanese is segmented into words rather than a whole subtitle")
    let chinese = tokens(SampleText.value("Chinese tokenizer context"), .simplifiedChinese)
    check(chinese.count > 1 && chinese.joined() == SampleText.value("Chinese tokenizer context"), "Chinese segmentation preserves text without treating a whole line as one word")
    check(tokens("123 -- 😀").isEmpty, "numbers, punctuation and emoji do not create words")
    check(tokens("\u{301}").isEmpty, "isolated combining marks do not create words")
    check(LanguageSupport.language(for: SampleText.value("Japanese study word"), context: SampleText.value("Japanese language inference context")) == "ja-JP", "Japanese sentence resolves Han-word pronunciation")
    check(LanguageSupport.language(for: SampleText.value("Learning sample word")) == "zh-CN", "Han-only automatic fallback is explicit Chinese")
    check(LanguageSupport.language(for: "안녕하세요") == "ko-KR", "Hangul resolves Korean pronunciation")
    check(LanguageSupport.language(for: "gift", preferred: "de-DE") == "de-DE", "manual language resolves ambiguous short words")
    check(!DictionaryEntry(query: SampleText.value("Japanese study word"), text: SampleText.value("Japanese dictionary explanation")).containsChinese, "Japanese kanji is not reported as Chinese translation")
    check((try? BookRow.letter("école")) == "E" && (try? BookRow.letter("Äpfel")) == "A", "accented initials reuse A-Z pages")
    check(BookRow.key("école") == BookRow.key("e\u{301}cole"), "canonically equivalent spelling merges")
    check(BookRow.key("résumé") != BookRow.key("resume"), "distinct accents are not erased from merge identity")
    for (word, page) in [(SampleText.value("Learning sample word"), SampleText.value("Han characters")), ("ありがとう", SampleText.value("Kana")), ("안녕", SampleText.value("Hangul")), ("привет", SampleText.value("Cyrillic")), ("γεια", SampleText.value("Greek")), ("مرحبا", SampleText.value("Arabic script category")), ("สวัสดี", SampleText.value("Thai script category"))] {
        do {
            let actual = try BookRow.letter(word)
            check(actual == page, "script page is stable: \(word)")
            var book = AlphabetPage(letter: page, isTest: true, rows: [])
            let entry = VocabularyEntry(word: word, definition: nil, sentence: word, isTestEntry: true)
            _ = try book.collect(entry)
            _ = try book.collect(VocabularyEntry(word: word, definition: nil, sentence: word, isTestEntry: true))
            let parsed = try AlphabetPage.parse(html: book.html, letter: page, isTest: true, attachmentCount: 1)
            check(parsed.rows.first?.count == 2 && parsed.rows.first?.word == word && parsed.editable, "Unicode table and count round trip: \(word)")
        } catch { check(false, "script table: \(error)") }
    }
    do {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        print("OCR_LANGUAGES: " + (try request.supportedRecognitionLanguages()).joined(separator: ", "))
        try TextRecognizer.configure(request, language: .automatic)
        check(request.automaticallyDetectsLanguage && !request.recognitionLanguages.isEmpty, "automatic OCR only configures supported languages")
        for (word, language) in [("école", SourceLanguage.french), ("Straße", .german), ("mañana", .spanish), (SampleText.value("Japanese study word"), .japanese), ("공부", .korean), ("привет", .russian)] {
            let context = CGContext(data: nil, width: 1200, height: 400, bitsPerComponent: 8, bytesPerRow: 4800,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 400))
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: word, attributes: [.font: NSFont.systemFont(ofSize: 64), .foregroundColor: NSColor.black]))
            context.textPosition = CGPoint(x: 120, y: 150)
            CTLineDraw(line, context)
            let extent = CTLineGetTypographicBounds(line, nil, nil, nil)
            let pointer = CGPoint(x: (120 + extent / 2) / 1200, y: 178.0 / 400)
            let result = try TextRecognizer.recognize(context.makeImage()!, language: language)
            let hit = WordSelection.hit(words: result.words, pointer: pointer)
            print("MULTILINGUAL_OCR \(language.rawValue): expected=\(word), hit=\(hit?.text ?? "NONE"), words=\(result.words.map(\.text))")
            check(hit?.text.precomposedStringWithCanonicalMapping.lowercased() == word.lowercased(), "real Vision word and pointer match: \(language.title)")
            check(hit?.language == language.rawValue, "explicit OCR language travels with word: \(language.title)")
            let automatic = try TextRecognizer.recognize(context.makeImage()!, language: .automatic)
            let automaticHit = WordSelection.hit(words: automatic.words, pointer: pointer)
            print("AUTO_OCR \(language.rawValue): hit=\(automaticHit?.text ?? "NONE")")
            check(automaticHit?.text.precomposedStringWithCanonicalMapping.lowercased() == word.lowercased(), "automatic Vision word and pointer match: \(language.title)")
        }
    } catch { check(false, "multilingual Vision: \(error)") }
}
