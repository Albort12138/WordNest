import AVFoundation
import Foundation

/// Speak only the current query word, including when no dictionary definition is available.
/// Retain one synthesizer so temporary-object deallocation cannot interrupt speech; call from the main thread.
@MainActor final class WordSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    var onSpeakingChanged: ((Bool) -> Void)?
    private(set) var isSpeaking = false

    // Use a matching local voice only; never substitute English for a missing language or download voice packs.
    private(set) var voice = AVSpeechSynthesisVoice(language: "en-US")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Share input and voice configuration with playback so integration tests can render the same utterance to buffers.
    func voiceForWord(_ word: String, language: String? = nil, context: String = "") -> AVSpeechSynthesisVoice? {
        let code = LanguageSupport.language(for: word, context: context, preferred: language)
        let base = String(code.prefix(2))
        if let selected = AVSpeechSynthesisVoice(language: code), selected.language.hasPrefix(base) { return selected }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(base) }
    }

    func utterance(for rawWord: String, language: String? = nil, context: String = "") -> AVSpeechUtterance? {
        let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word.count <= 100,
              LanguageSupport.hasLetters(word),
              let selected = voiceForWord(word, language: language, context: context) else { return nil }
        voice = selected
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = selected
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        return utterance
    }

    /// A new request replaces the old one; rapid clicks must not queue a series of utterances.
    /// Return inline error text for the card instead of interrupting video with a modal dialog.
    @discardableResult
    func speak(_ word: String, language: String? = nil, context: String = "") -> String? {
        guard let utterance = utterance(for: word, language: language, context: context) else {
            let name = LanguageSupport.displayName(LanguageSupport.language(for: word, context: context, preferred: language))
            return LanguageSupport.hasLetters(word)
                ? L("No \(name) voice is available. Add a voice for this language in System Settings > Accessibility.")
                : L("Look up a word or phrase containing letters (up to 100 characters) before playing pronunciation.")
        }
        stop()
        currentUtterance = utterance
        isSpeaking = true
        onSpeakingChanged?(true)
        synthesizer.speak(utterance)
        return nil
    }

    func stop() {
        // Clear identity before stopping so a late cancellation callback cannot end the next playback.
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        onSpeakingChanged?(false)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        complete(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        complete(utterance)
    }

    nonisolated private func complete(_ utterance: AVSpeechUtterance) {
        // Do not assume the callback thread; marshal state and associated AppKit updates to the main thread.
        let identity = ObjectIdentifier(utterance)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.currentUtterance.map(ObjectIdentifier.init) == identity else { return }
            self.currentUtterance = nil
            self.isSpeaking = false
            self.onSpeakingChanged?(false)
        }
    }
}
