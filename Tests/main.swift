import AppKit
import CoreText
import AVFoundation

// Existing dictionary/data fixtures pin presentation; locale resolution is tested independently.
UILocalization.languageOverride = .simplifiedChinese

var failures = 0
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if !condition() {
        failures += 1
        print("FAIL: \(name)")
    }
}

func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.0001 }

let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
let center = CaptureRegion.make(screen: primary, mouse: CGPoint(x: 720, y: 450), imageWidth: 2880, imageHeight: 1800)!
check(center.pixels == CGRect(x: 480, y: 660, width: 1920, height: 480), "Retina crop uses physical pixels")
check(near(center.pointer.x, 0.5) && near(center.pointer.y, 0.5), "center pointer is normalized")
let lower = CaptureRegion.make(screen: primary, mouse: CGPoint(x: 400, y: 20), imageWidth: 2880, imageHeight: 1800)!
check(lower.pixels.maxY == 1800, "crop clamps at bottom edge")
check(near(lower.pointer.y, 40.0 / 480), "bottom pointer uses Vision coordinates")
let external = CGRect(x: -1920, y: 900, width: 1920, height: 1080)
let upper = CaptureRegion.make(screen: external, mouse: CGPoint(x: -1910, y: 1970), imageWidth: 1920, imageHeight: 1080)!
check(upper.pixels.origin == .zero, "negative-origin / upper display crop")
check(near(upper.pointer.x, 10.0 / 960) && near(upper.pointer.y, 230.0 / 240), "upper display pointer conversion")
check(CaptureRegion.make(screen: primary, mouse: CGPoint(x: -1, y: 100), imageWidth: 2880, imageHeight: 1800) == nil, "outside display is rejected")
check(CaptureRegion.make(screen: .zero, mouse: .zero, imageWidth: 0, imageHeight: 0) == nil, "invalid geometry is rejected")

let sample = "I'm reluctant; don't re-enter someone’s state-of-the-art plan."
let tokens = WordSelection.ranges(in: sample).map { String(sample[$0]) }
check(tokens == ["I'm", "reluctant", "don't", "re-enter", "someone’s", "state-of-the-art", "plan"], "apostrophes and compounds stay intact")
check(!WordSelection.ranges(in: SampleText.value("Chinese tokenization with punctuation")).isEmpty, "Chinese words are available in multilingual lookup")
let fragments = [
    TextFragment(text: "accept the offer.", bounds: CGRect(x: 0.45, y: 0.5, width: 0.3, height: 0.1)),
    TextFragment(text: "I was reluctant to", bounds: CGRect(x: 0.1, y: 0.51, width: 0.32, height: 0.1)),
    TextFragment(text: SampleText.value("Chinese subtitle fragment"), bounds: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08))
]
check(SubtitleRows.groups(fragments) == [[1, 0], [2]], "split subtitle observations join left-to-right without joining Chinese row")
let columns = [
    TextFragment(text: "left", bounds: CGRect(x: 0.05, y: 0.5, width: 0.1, height: 0.05)),
    TextFragment(text: "right", bounds: CGRect(x: 0.8, y: 0.5, width: 0.1, height: 0.05))
]
check(SubtitleRows.groups(columns).count == 2, "distant same-height columns stay separate")
let word = LookupWord(text: "reluctant", sentence: "I was reluctant.", bounds: CGRect(x: 0.2, y: 0.4, width: 0.2, height: 0.1), confidence: 0.9)
check(WordSelection.hit(words: [word], pointer: CGPoint(x: 0.3, y: 0.45))?.text == "reluctant", "pointer hits target")
check(WordSelection.hit(words: [word], pointer: CGPoint(x: 0.8, y: 0.45)) == nil, "empty space never chooses a distant word")
let uncertain = LookupWord(text: "wrong", sentence: "wrong", bounds: word.bounds, confidence: 0.1)
check(WordSelection.hit(words: [uncertain], pointer: CGPoint(x: 0.3, y: 0.45)) == nil, "low-confidence result does not become a hit")

// Inject results at the dictionary API boundary to cover UI states that depend on installed dictionaries.
// Use --system-dictionary for a real local lookup; ordinary regressions require no specific dictionary.
let chineseEntry = SystemDictionary.lookup(" reluctant ") { query in
    query == "reluctant" ? SampleText.value("Reluctant entry padded") : nil
}
check(chineseEntry.entry?.query == "reluctant", "dictionary trims query before system call")
check(chineseEntry.entry?.text == SampleText.value("Reluctant entry normalized"), "dictionary retains Chinese definition")
check(chineseEntry.entry?.containsChinese == true, "Chinese entry is labeled correctly")
let englishEntry = SystemDictionary.lookup("don't") { _ in "informal = do not → do" }
let phoneticEntry = DictionaryEntry(query: "reluctant", text: SampleText.value("Reluctant entry with pronunciation"))
check(phoneticEntry.pronunciation == "BrE rɪˈlʌktənt, AmE rəˈləktənt", "dictionary phonetics retain original English accent labels")
check(DictionaryEntry(query: "word", text: "word | an example sentence | meaning").pronunciation == nil, "ordinary pipe-delimited text is not presented as phonetics")
check(DictionaryEntry(query: "word", text: "word | BrE first\nsecond | meaning").pronunciation == nil, "multiline dictionary body is not extracted as phonetics")
check(englishEntry.entry?.pronunciation == nil, "entry without pronunciation keeps its original definition without inventing IPA")
let happiness = DictionaryEntry(query: "happiness", text: SampleText.value("Happiness complete entry"))
let happinessCard = DictionaryPresentation(entry: happiness)
check(happinessCard.grammar == SampleText.value("Noun · uncountable"), "happiness grammar is separated from meaning")
check(happinessCard.meaning == SampleText.value("Happiness meaning with pinyin"), "happiness Chinese meaning retains attached pinyin")
check(happinessCard.examples == [SampleText.value("Happiness first example"), SampleText.value("Happiness second example")], "dictionary examples stay separate from subtitle source")
let unknownFormat = DictionaryPresentation(entry: DictionaryEntry(query: "word", text: "unrecognized text | example | other"))
check(unknownFormat.meaning == "unrecognized text | example | other", "unknown dictionary format is kept intact")
check(DictionaryPresentation(entry: DictionaryEntry(query: "word", text: SampleText.value("Unrecognized dictionary prefix"))).meaning == SampleText.value("Unrecognized dictionary prefix"), "unknown grammar prefix is preserved rather than discarded")
check(englishEntry.entry?.containsChinese == false, "English cross-reference is not labeled Chinese")
check(englishEntry.displayText.contains(SampleText.value("Missing Chinese dictionary guidance fragment")), "English-only result includes setup guidance")
let absent = SystemDictionary.lookup("qzxnonexistentword") { _ in nil }
if case .notFound("qzxnonexistentword") = absent { check(true, "missing entry retains queried word") }
else { check(false, "missing entry retains queried word") }
check(absent.displayText.contains(SampleText.value("Word correction guidance fragment")), "missing entry suggests correction")
var invalidCalledProvider = false
let invalid = SystemDictionary.lookup("  \n") { _ in invalidCalledProvider = true; return "unexpected" }
check(!invalidCalledProvider && invalid.entry == nil, "empty query never calls dictionary")
check(invalid.displayText.contains(SampleText.value("Input guidance fragment")), "invalid input gets actionable message")
let tooLong = SystemDictionary.lookup(String(repeating: "x", count: 101)) { _ in
    invalidCalledProvider = true
    return "unexpected"
}
check(!invalidCalledProvider && tooLong.entry == nil, "oversized query never calls dictionary")
let fallback = SystemDictionary.lookup("Reluctant") { $0 == "reluctant" ? SampleText.value("Reluctant meaning") : nil }
check(fallback.entry?.query == "reluctant", "case fallback preserves actual query")
let apostrophe = SystemDictionary.lookup("don’t") { $0 == "don't" ? "do not" : nil }
check(apostrophe.entry?.query == "don't", "curly apostrophe fallback")
var attempts: [String] = []
_ = SystemDictionary.lookup("word") { attempts.append($0); return nil }
check(attempts == ["word"], "identical fallback queries are deduplicated")
let longText = String(repeating: SampleText.value("Long definition repeat fragment"), count: 2000)
let longEntry = SystemDictionary.lookup("long") { _ in longText }
check(longEntry.entry?.text == longText && longEntry.displayText.contains(longText), "long dictionary entries are not truncated")

if CommandLine.arguments.contains("--system-dictionary") {
    // Query fixed sample words only; do not read the screen or change dictionary preferences.
    for query in ["reluctant", "accept", "running"] {
        let actual = SystemDictionary.lookup(query)
        check(actual.entry?.containsChinese == true, "real system dictionary returns Chinese: \(query)")
        print("SYSTEM_DICTIONARY \(query): Chinese=\(actual.entry?.containsChinese == true)")
    }
    check(SystemDictionary.lookup("qzxnonexistentword").entry == nil, "real system dictionary handles missing word")
}

func makeFixture(dark: Bool) -> (CGImage, CGPoint) {
    let width = 1800
    let height = 480
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor((dark ? NSColor.black : NSColor.white).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = NSFont.monospacedSystemFont(ofSize: 50, weight: .medium)
    let sentence = "I was reluctant to accept the offer."
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: dark ? NSColor.white : NSColor.black
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: sentence, attributes: attrs))
    context.textPosition = CGPoint(x: 100, y: 170)
    CTLineDraw(line, context)
    let chinese = NSAttributedString(string: SampleText.value("Chinese subtitle OCR line"), attributes: [
        .font: NSFont.systemFont(ofSize: 38), .foregroundColor: dark ? NSColor.white : NSColor.black
    ])
    context.textPosition = CGPoint(x: 100, y: 90)
    CTLineDraw(CTLineCreateWithAttributedString(chinese), context)
    let prefix = CTLineCreateWithAttributedString(NSAttributedString(string: "I was ", attributes: attrs))
    let target = CTLineCreateWithAttributedString(NSAttributedString(string: "reluctant", attributes: attrs))
    let before = CTLineGetTypographicBounds(prefix, nil, nil, nil)
    let extent = CTLineGetTypographicBounds(target, nil, nil, nil)
    return (context.makeImage()!, CGPoint(x: (100 + before + extent / 2) / Double(width), y: 190.0 / Double(height)))
}

do {
    for dark in [false, true] {
        let (image, pointer) = makeFixture(dark: dark)
        let result = try TextRecognizer.recognize(image)
        let hit = WordSelection.hit(words: result.words, pointer: pointer)
        check(result.words.contains(where: { $0.text.lowercased() == "reluctant" }), "Vision recognizes target on \(dark ? "dark" : "light") bilingual fixture")
        check(hit?.text.lowercased() == "reluctant", "Vision word bounds match independently calculated pointer on \(dark ? "dark" : "light") fixture")
        check(hit?.sentence.contains("accept") == true, "original subtitle line is retained")
        print(String(format: "FIXTURE %@: OCR %.3fs; hit=%@", dark ? "dark" : "light", result.elapsed, hit?.text ?? "NONE"))
        if let destination = ProcessInfo.processInfo.environment["FIXTURE_OUTPUT"], dark {
            let representation = NSBitmapImageRep(cgImage: image)
            try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
        }
        // Exercise the exact top-left image-cropping / bottom-left Vision mapping used by capture.
        let mouse = CGPoint(x: pointer.x * 1800, y: pointer.y * 480)
        let crop = CaptureRegion.make(screen: CGRect(x: 0, y: 0, width: 1800, height: 480), mouse: mouse,
                                      imageWidth: 1800, imageHeight: 480)!
        let cropped = image.cropping(to: crop.pixels)!
        let croppedResult = try TextRecognizer.recognize(cropped)
        check(WordSelection.hit(words: croppedResult.words, pointer: crop.pointer)?.text.lowercased() == "reluctant", "real CGImage crop preserves mouse-to-word mapping")
    }
} catch {
    failures += 1
    print("FAIL: OCR execution: \(error)")
}
// The local speech integration check generates buffers without playback, recording, or screen access.
// Require actual non-silent PCM output; a successful API call alone does not demonstrate usable speech.
if CommandLine.arguments.contains("--speech") {
    MainActor.assumeIsolated {
        let speaker = WordSpeaker()
        check(speaker.voice?.language.hasPrefix("en-") == true, "installed voice is explicitly English")
        check(speaker.utterance(for: "   ") == nil, "empty speech input is rejected")
        check(speaker.utterance(for: String(repeating: "x", count: 101)) == nil, "oversized speech input is rejected")
        check(speaker.utterance(for: "1234") == nil, "non-letter input does not trigger speech")
        let writer = AVSpeechSynthesizer()
        // Generate twice with one synthesizer to catch failures after the first successful utterance.
        for (word, language) in [("reluctant", "en-US"), ("don't", "en-US"), ("bonjour", "fr-FR"), (SampleText.value("Japanese study word"), "ja-JP"), ("안녕하세요", "ko-KR"), ("mañana", "es-ES"), ("Straße", "de-DE")] {
            guard let utterance = speaker.utterance(for: " \(word) ", language: language) else {
                check(speaker.speak(word, language: language) != nil && !speaker.isSpeaking, "missing language voice gives a clear error without unrelated speech")
                print("VOICE_UNAVAILABLE: \(language)")
                continue
            }
            check(utterance.voice?.language.hasPrefix(String(language.prefix(2))) == true, "speech voice matches source language: \(language)")
            check(utterance.speechString == word, "speech uses trimmed queried word: \(word)")
            let lock = NSLock()
            var frames: AVAudioFramePosition = 0
            var hasSound = false
            var finished = false
            writer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                lock.lock()
                frames += AVAudioFramePosition(pcm.frameLength)
                if let samples = pcm.floatChannelData, pcm.frameLength > 0 {
                    hasSound = hasSound || UnsafeBufferPointer(start: samples[0], count: Int(pcm.frameLength)).contains { abs($0) > 0.0001 }
                }
                if pcm.frameLength == 0 { finished = true }
                lock.unlock()
            }
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                lock.lock()
                let done = finished
                lock.unlock()
                if done { break }
                _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            lock.lock()
            let validAudio = finished && frames > 0 && hasSound
            let frameCount = frames
            lock.unlock()
            check(validAudio, "local speech completes with non-silent PCM: \(word) (\(frameCount) frames)")
            if !validAudio { writer.stopSpeaking(at: .immediate) }
        }
    }
}

// The synchronous top-level harness pumps the main event loop for asynchronous collection checks.
// The fake client never connects to Notes; actual write acceptance uses the candidate app.
var notesTestsFinished = false
runLanguageTests()
runInterfaceLanguageTests()
runAlphabetTests()
Task { @MainActor in
    await runDictionaryTests()
    await runNotesTests()
    await runSourceTests()
    await runSetupTests()
    await runProductTests()
    notesTestsFinished = true
}
let notesTestDeadline = Date().addingTimeInterval(30)
while !notesTestsFinished && Date() < notesTestDeadline {
    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
}
check(notesTestsFinished, "asynchronous collection checks complete within deadline")
print("\(checks) checks; \(failures) failures. Synthetic fixtures only; no user screen captured.")
exit(failures == 0 ? 0 : 1)
