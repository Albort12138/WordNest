import Foundation
import CoreGraphics
import Vision

/// Convert a cropped image to positioned word candidates; no capture, selection, UI, or networking.
/// Vision perform is synchronous; UI callers must execute it in a background task.
enum TextRecognizer {
    /// Interpret the image as .up; every returned bound is relative to this input image.
    /// Propagate failures for UI reporting instead of disguising engine errors as an empty word list.
    static func recognize(_ image: CGImage, language: SourceLanguage = .automatic) throws -> LookupResult {
        // Use a monotonic clock for OCR duration; App.swift measures the entire lookup flow separately.
        let started = ProcessInfo.processInfo.systemUptime
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try configure(request, language: language)
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])
        var words: [LookupWord] = []
        var lines: [String] = []
        // Keep the best text candidate per observation and retain its Vision object for word-level bounds.
        let recognized = (request.results ?? []).compactMap { observation -> (VNRecognizedText, CGRect)? in
            guard let text = observation.topCandidates(1).first else { return nil }
            return (text, observation.boundingBox)
        }
        let fragments = recognized.map { TextFragment(text: $0.0.string, bounds: $0.1) }
        // A visual subtitle line may contain multiple fragments. Merge context, but query word bounds from each original fragment,
        // rather than estimating positions in a joined string and producing correct text with incorrect pointer hits.
        for row in SubtitleRows.groups(fragments) {
            let sentence = row.map { fragments[$0].text }.joined(separator: " ")
            lines.append(sentence)
            for index in row {
                let text = recognized[index].0
                for range in WordSelection.ranges(in: text.string, language: language.naturalLanguage) {
                    // Skip candidates without reliable word bounds; they cannot support pointer lookup.
                    guard let box = try text.boundingBox(for: range) else { continue }
                    words.append(LookupWord(
                        text: String(text.string[range]), sentence: sentence,
                        bounds: box.boundingBox, confidence: text.confidence,
                        language: LanguageSupport.language(for: String(text.string[range]), context: sentence, preferred: language.hint)
                    ))
                }
            }
        }
        return LookupResult(words: words, lines: lines,
                            elapsed: ProcessInfo.processInfo.systemUptime - started)
    }

    /// Use actually supported language identifiers; report unavailable explicit selections rather than silently using English.
    static func configure(_ request: VNRecognizeTextRequest, language: SourceLanguage) throws {
        let supported = try request.supportedRecognitionLanguages()
        if language == .automatic {
            request.automaticallyDetectsLanguage = true
            let preferred = SourceLanguage.allCases.compactMap { $0.hint.flatMap { recognitionCode($0, supported: supported) } }
            request.recognitionLanguages = (preferred + supported).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        } else {
            guard let code = recognitionCode(language.rawValue, supported: supported) else {
                throw NSError(domain: "WordNest.Language", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Text recognition on this macOS does not support \(language.title). Choose another source language in the menu.")])
            }
            request.automaticallyDetectsLanguage = false
            request.recognitionLanguages = [code]
        }
    }

    static func availableSourceLanguages() throws -> Set<SourceLanguage> {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        return Set(SourceLanguage.allCases.filter { $0 == .automatic || recognitionCode($0.rawValue, supported: supported) != nil })
    }

    private static func recognitionCode(_ value: String, supported: [String]) -> String? {
        if let exact = supported.first(where: { $0 == value || $0.hasPrefix(value + "-") }) { return exact }
        // Simplified and Traditional Chinese use different models; a shared zh prefix does not permit substitution. Allow regional aliases elsewhere.
        if value.hasPrefix("zh-") { return nil }
        return supported.first { $0.hasPrefix(String(value.prefix(2)) + "-") }
    }
}
