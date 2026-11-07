import Foundation
import CoreGraphics
import NaturalLanguage

// Data and geometry rules only: no screen access or AppKit windows.
// Separate hit testing from UI so fixed coordinates cover Retina, external displays, and OCR fragments.

/// A pointer-selectable word candidate; all bounds are relative to the cropped OCR image.
struct LookupWord {
    let text: String
    /// A visual line assembled from OCR fragments; it may still be an incomplete grammatical sentence.
    let sentence: String
    /// Vision coordinates: bottom-left origin, normalized to 0...1 independently of image pixel dimensions.
    let bounds: CGRect
    /// Vision confidence for the text candidate, not a calibrated probability that this word is correct.
    let confidence: Float
    /// The OCR source-language hint; automatic inference from word/context does not resolve dictionary senses.
    var language: String? = nil
}

/// Word candidates, visual lines, and OCR duration; excludes capture, cropping, and UI time.
struct LookupResult {
    let words: [LookupWord]
    let lines: [String]
    let elapsed: TimeInterval
}

/// A Vision text fragment; multiple fragments may form one visual line, so it is not a complete sentence.
struct TextFragment {
    let text: String
    let bounds: CGRect
}

enum SubtitleRows {
    /// Group nearby, vertically aligned fragments into visual lines and return their original indices.
    /// Keep indices so TextRecognizer can query precise word bounds from the original VNRecognizedText.
    /// These heuristics need real-subtitle calibration; they do not guarantee complete subtitles or multi-column articles.
    static func groups(_ fragments: [TextFragment]) -> [[Int]] {
        // Vision y increases upward: traverse top to bottom, then left to right at equal height.
        let order = fragments.indices.sorted {
            let a = fragments[$0].bounds
            let b = fragments[$1].bounds
            return abs(a.midY - b.midY) < 0.001 ? a.minX < b.minX : a.midY > b.midY
        }
        var rows: [[Int]] = []
        for index in order {
            let rect = fragments[index].bounds
            let match = rows.firstIndex { row in
                row.contains { other in
                    let box = fragments[other].bounds
                    let height = min(box.height, rect.height)
                    guard height > 0 else { return false }
                    // Scale thresholds by text height rather than fixed pixels to accommodate fonts and Retina scaling.
                    // Constrain overlap, center offset, and horizontal gap to avoid joining bilingual rows or distant columns.
                    let overlap = min(box.maxY, rect.maxY) - max(box.minY, rect.minY)
                    let gap = max(0, max(rect.minX - box.maxX, box.minX - rect.maxX))
                    return overlap >= height * 0.6
                        && abs(box.midY - rect.midY) <= height * 0.6
                        && gap <= max(box.height, rect.height) * 3
                }
            }
            if let match { rows[match].append(index) }
            else { rows.append([index]) }
        }
        // Sort each line by x again; OCR output order and initial traversal order are not reading order.
        return rows.map { $0.sorted { fragments[$0].bounds.minX < fragments[$1].bounds.minX } }
    }
}

/// Carry the CGImage crop and the pointer inside it together so both share one coordinate conversion.
struct CaptureRegion {
    /// CGImage pixel coordinates with a top-left origin, suitable for cropping(to:).
    let pixels: CGRect
    /// Normalized Vision coordinates inside the crop, with a bottom-left origin, for word hit testing.
    let pointer: CGPoint

    /// Convert AppKit global logical points to screenshot pixels, then to Vision coordinates inside the crop.
    /// - Parameters:
    ///   - screen: Global logical-point bounds of the pointer display; external display origins may be negative.
    ///   - mouse: Global pointer position at the hotkey event; never reread it after OCR.
    ///   - imageWidth: Actual captured image width in pixels; do not assume every display uses 2x scaling.
    ///   - imageHeight: Actual captured image height in pixels.
    /// - Returns: nil for invalid bounds or a pointer outside the display.
    static func make(screen: CGRect, mouse: CGPoint, imageWidth: Int, imageHeight: Int) -> CaptureRegion? {
        guard screen.width > 0, screen.height > 0,
              imageWidth > 0, imageHeight > 0, screen.contains(mouse) else { return nil }
        let sx = CGFloat(imageWidth) / screen.width
        let sy = CGFloat(imageHeight) / screen.height
        // Remove the display desktop offset, then convert the AppKit bottom-left origin to the image top-left origin.
        let px = (mouse.x - screen.minX) * sx
        let py = (screen.maxY - mouse.y) * sy
        // The 960 x 240 size is in logical points, balancing context and OCR cost rather than fixing physical pixels.
        let width = min(CGFloat(imageWidth), (960 * sx).rounded())
        let height = min(CGFloat(imageHeight), (240 * sy).rounded())
        // Shift the crop near edges to keep it inside the image; the pointer need not remain at its center.
        let left = max(0, min(CGFloat(imageWidth) - width, (px - width / 2).rounded()))
        let top = max(0, min(CGFloat(imageHeight) - height, (py - height / 2).rounded()))
        return CaptureRegion(
            pixels: CGRect(x: left, y: top, width: width, height: height),
            // Normalize relative to the crop and invert y to match Vision word bounds.
            pointer: CGPoint(x: (px - left) / width, y: 1 - (py - top) / height)
        )
    }
}

enum WordSelection {
    // Keep Unicode letters and combining marks intact, including internal apostrophes and hyphens in Latin text.
    // Use system tokenization for Chinese, Japanese, Korean, and Thai, where spaces do not reliably delimit words.
    static let tokenPattern = "[\\p{L}\\p{M}]+(?:['’\\-‑][\\p{L}\\p{M}]+)*"

    /// NSRegularExpression uses UTF-16 indices; convert them to a Range in the original Swift string.
    /// Vision reuses this range, so do not lowercase or rewrite the string before querying its bounds.
    static func ranges(in text: String, language: NLLanguage? = nil) -> [Range<String.Index>] {
        let expression = try! NSRegularExpression(pattern: tokenPattern)
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text) }.flatMap { range -> [Range<String.Index>] in
            let part = String(text[range])
            guard LanguageSupport.hasLetters(part) else { return [] }
            guard part.range(of: "[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}\\p{Thai}]", options: .regularExpression) != nil else { return [range] }
            let tokenizer = NLTokenizer(unit: .word)
            tokenizer.string = text
            if let language { tokenizer.setLanguage(language) }
            var tokens: [Range<String.Index>] = []
            tokenizer.enumerateTokens(in: range) { token, _ in
                if LanguageSupport.hasLetters(String(text[token])) { tokens.append(token) }
                return true
            }
            return tokens
        }
    }

    /// Return a word only when the pointer hits its bounds and confidence meets the heuristic threshold; otherwise nil.
    /// Never select a distant nearest word, which could return plausible but wrong definitions over blanks or other text.
    static func hit(words: [LookupWord], pointer: CGPoint) -> LookupWord? {
        words.filter { $0.confidence >= 0.35 && $0.bounds.contains(pointer) }
            .min { a, b in
                // OCR bounds may overlap; distance disambiguates actual hits without expanding the hit area.
                distance(a.bounds, pointer) < distance(b.bounds, pointer)
            }
    }

    private static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        pow(rect.midX - point.x, 2) + pow(rect.midY - point.y, 2)
    }
}
