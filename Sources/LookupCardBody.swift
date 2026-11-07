import AppKit

/// Scrollable card body with separate definitions, dictionary examples, and video context instead of one debug-text block.
/// The card supplies width and text determines height; retain complete long entries inside the scroll view.
@MainActor final class LookupCardBody: NSView {
    override var isFlipped: Bool { true }
    private let stack = NSStackView()

    init(width: CGFloat, definition: String?, message: String, word: LookupWord?, format: DictionaryEntryFormat = .system,
         source: DictionarySource = .system) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor)
        ])
        if let definition {
            let entry = DictionaryEntry(query: word?.text ?? "", text: definition, format: format)
            let presentation = DictionaryPresentation(entry: entry)
            let meaning = section(title: source.kind == .system ? L("Definition · Local dictionary") : L("Definition · \(source.displayName)"), tinted: false)
            if let grammar = presentation.displayGrammar {
                addLabel(grammar, font: .systemFont(ofSize: 12, weight: .medium), color: .secondaryLabelColor, to: meaning)
            }
            let definitionField = addLabel(presentation.meaning, font: .systemFont(ofSize: entry.containsChinese ? 21 : 15, weight: .medium), to: meaning)
            if entry.containsChinese, format == .system {
                // Keep dictionary pinyin visible but deemphasize Latin text so the Chinese meaning is easier to scan.
                let value = NSMutableAttributedString(string: presentation.meaning, attributes: [
                    .font: NSFont.systemFont(ofSize: 21, weight: .medium), .foregroundColor: NSColor.labelColor
                ])
                if let latin = try? NSRegularExpression(pattern: "[\\p{Latin}\\p{M}]+") {
                    let full = NSRange(presentation.meaning.startIndex..., in: presentation.meaning)
                    for match in latin.matches(in: presentation.meaning, range: full) {
                        value.addAttributes([.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor], range: match.range)
                    }
                }
                definitionField.attributedStringValue = value
            }
            if !presentation.examples.isEmpty {
                let examples = section(title: L("Dictionary examples"), tinted: false)
                for (index, example) in presentation.examples.enumerated() {
                    let field = addLabel(example, font: .systemFont(ofSize: 14), to: examples)
                    // System examples may concatenate English and Chinese; break before the first Han character for comparison.
                    if entry.containsChinese, let han = example.range(of: "\\p{Han}", options: .regularExpression), han.lowerBound > example.startIndex {
                        let english = String(example[..<han.lowerBound]).trimmingCharacters(in: .whitespaces)
                        let chinese = String(example[han.lowerBound...])
                        let text = NSMutableAttributedString(string: english + "\n", attributes: [
                            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor
                        ])
                        text.append(NSAttributedString(string: chinese, attributes: [
                            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.secondaryLabelColor
                        ]))
                        field.attributedStringValue = text
                    }
                    if index < presentation.examples.count - 1 { examples.setCustomSpacing(12, after: field) }
                }
            }
            if !entry.containsChinese, source.kind == .system {
                let note = section(title: L("Dictionary notice"), tinted: false)
                addLabel(L("The current dictionary has not returned a confirmed Chinese definition. Check the corresponding language resources in Dictionary settings. Multilingual recognition does not mean a Chinese dictionary is installed for each language."), font: .systemFont(ofSize: 12), color: .secondaryLabelColor, to: note)
            }
        } else {
            let state = section(title: L("Definition"), tinted: false)
            addLabel(message, font: .systemFont(ofSize: 14), color: .secondaryLabelColor, to: state)
        }
        if let word, !word.sentence.isEmpty {
            let context = section(title: L("Original text"), tinted: true)
            let field = addLabel(word.sentence, font: .systemFont(ofSize: 15), to: context)
            let value = NSMutableAttributedString(string: word.sentence, attributes: [
                .font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.labelColor
            ])
            // Use the same whole-word tokenization rules; do not highlight partial matches such as happy inside happiness.
            for range in WordSelection.ranges(in: word.sentence)
                where String(word.sentence[range]).caseInsensitiveCompare(word.text) == .orderedSame {
                value.addAttributes([
                    .foregroundColor: NSColor.controlAccentColor,
                    .font: NSFont.systemFont(ofSize: 15, weight: .semibold)
                ], range: NSRange(range, in: word.sentence))
            }
            field.attributedStringValue = value
        }
        resizeToFit(width: width)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func resizeToFit(width: CGFloat) {
        setFrameSize(NSSize(width: width, height: frame.height))
        layoutSubtreeIfNeeded()
        setFrameSize(NSSize(width: width, height: ceil(stack.fittingSize.height) + 2))
        layoutSubtreeIfNeeded()
    }

    private func section(title: String, tinted: Bool) -> NSStackView {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 0
        box.fillColor = tinted ? NSColor.controlAccentColor.withAlphaComponent(0.055) : .textBackgroundColor
        box.cornerRadius = 10
        box.contentViewMargins = .zero
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 7
        content.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        box.contentView = container
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])
        stack.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        addLabel(title, font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor, to: content)
        return content
    }

    @discardableResult
    private func addLabel(_ text: String, font: NSFont, color: NSColor = .labelColor, to section: NSStackView) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.textColor = color
        field.isSelectable = true
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        section.addArrangedSubview(field)
        field.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return field
    }
}
