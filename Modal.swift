import AppKit

// ---------- A question, asked in the middle of the page ----------
//
// A small panel in the dead centre of the page, above everything in the window, with the rest
// dimmed: a heading, a sentence or two, and the answers as buttons. Escape, or a click outside,
// is the last answer (the one that changes nothing).

struct ModalChoice {
    let title: String
    let symbol: String
    let run: () -> Void
}

/// Where the thing being named will be kept: the usual folder for a name, until the user chooses another.
final class ModalPlace {
    /// The folder a thing of this name would go in, named for it.
    let usual: (String) -> URL
    /// The folder the user chose instead, if any: the thing goes straight in it, by its name.
    var chosen: URL?
    init(usual: @escaping (String) -> URL) { self.usual = usual }
    func folder(for name: String) -> URL { chosen.map { $0.appendingPathComponent(filesystemName(name)) } ?? usual(name) }
}

/// One line of text to ask for: what it is for, what to check, and what to do with it.
struct ModalPrompt {
    let title: String
    let message: String
    let placeholder: String
    let confirm: String
    let symbol: String
    /// What is wrong with the text, in words for the user; nil when it will do.
    let check: (String) -> String?
    /// Set when the thing named gets a folder: the sheet shows where, and lets it be changed.
    var place: ModalPlace? = nil
    let done: (String) -> Void
}

/// The same panel as a question, with a line to type on: Return confirms, Escape or a click outside cancels.
final class PromptSheet: NSView, NSTextFieldDelegate {
    private let panel = NSView()
    private let prompt: ModalPrompt
    private let field = NSTextField()
    private let problem = caption("")
    private let where_ = NSTextField(labelWithString: "")

    init(_ prompt: ModalPrompt) {
        self.prompt = prompt
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 14
        panel.layer?.cornerCurve = .continuous
        panel.layer?.borderWidth = 1
        panel.shadow = { let s = NSShadow(); s.shadowBlurRadius = 30; s.shadowOffset = NSSize(width: 0, height: -8); s.shadowColor = NSColor.black.withAlphaComponent(0.45); return s }()

        let heading = NSTextField(wrappingLabelWithString: prompt.title)
        heading.font = PageStyle.titleFont
        let body = NSTextField(wrappingLabelWithString: prompt.message)
        body.font = NSFont.systemFont(ofSize: TextSize.body)
        body.textColor = .secondaryLabelColor
        field.placeholderString = prompt.placeholder
        field.font = NSFont.systemFont(ofSize: TextSize.body)
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none   // the system's ring is the accent colour; the caret says where typing goes
        field.delegate = self
        problem.textColor = .systemRed
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        problem.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [problem, spacer,
                                      toolButton("Cancel", "xmark", "Cancel (Escape)", target: self, action: #selector(cancelTapped)),
                                      toolButton(prompt.confirm, prompt.symbol, prompt.confirm + " (Return)", target: self, action: #selector(confirmTapped))])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = PageStyle.barSpacing

        // Where it will be kept, when it gets a folder: the path follows the name as it is typed.
        let kept = NSStackView()
        if prompt.place != nil {
            where_.font = NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular)
            where_.textColor = .secondaryLabelColor
            where_.lineBreakMode = .byTruncatingMiddle
            where_.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let text = NSStackView(views: [caption("Kept in"), where_])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 2
            let gap = NSView()
            gap.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
            kept.setViews([text, gap, toolButton("Change\u{2026}", "folder", "Choose another folder for it", target: self, action: #selector(changeTapped))], in: .leading)
            kept.orientation = .horizontal
            kept.alignment = .centerY
            kept.spacing = PageStyle.barSpacing
            showPlace()
        }

        addSubview(panel)
        for v in [panel, heading, body, field, kept, bar] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        for v in [heading, body, field, kept, bar] as [NSView] { panel.addSubview(v) }
        let pad = SwatchListStyle.sheetPad
        NSLayoutConstraint.activate([
            kept.topAnchor.constraint(equalTo: field.bottomAnchor, constant: prompt.place == nil ? 0 : 12),
            kept.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            kept.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            bar.topAnchor.constraint(equalTo: kept.bottomAnchor, constant: 18),
            panel.widthAnchor.constraint(equalToConstant: 520),
            heading.topAnchor.constraint(equalTo: panel.topAnchor, constant: pad),
            heading.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: pad),
            heading.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -pad),
            body.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            body.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            field.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 14),
            field.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            bar.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -pad),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func present(over page: NSView) {
        guard let root = page.window?.contentView else { return }
        root.addSubview(self, positioned: .above, relativeTo: nil)
        let across = panel.centerXAnchor.constraint(equalTo: page.centerXAnchor)
        across.priority = .defaultHigh
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: root.topAnchor),
            bottomAnchor.constraint(equalTo: root.bottomAnchor),
            leadingAnchor.constraint(equalTo: root.leadingAnchor),
            trailingAnchor.constraint(equalTo: root.trailingAnchor),
            across,
            panel.centerYAnchor.constraint(equalTo: page.centerYAnchor),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 8),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -8),
        ])
        window?.makeFirstResponder(field)
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        super.updateLayer()
        panel.layer?.backgroundColor = Theme.grey(0.05).cgColor
        panel.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
    }

    @objc private func confirmTapped() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let wrong = prompt.check(text) { problem.stringValue = wrong; return }
        removeFromSuperview()
        prompt.done(text)
    }
    @objc private func cancelTapped() { removeFromSuperview() }

    private func showPlace() {
        guard let place = prompt.place else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        where_.stringValue = (place.folder(for: name.isEmpty ? "Name" : name).path as NSString).abbreviatingWithTildeInPath
    }
    func controlTextDidChange(_ obj: Notification) { showPlace() }

    @objc private func changeTapped() {
        guard let place = prompt.place, let win = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder its own folder goes in"
        panel.directoryURL = place.chosen ?? place.usual("Name").deletingLastPathComponent()
        panel.beginSheetModal(for: win) { [weak self] r in
            if r == .OK, let u = panel.url { place.chosen = u; self?.showPlace() }
        }
    }
    override func cancelOperation(_ sender: Any?) { cancelTapped() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { confirmTapped(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { cancelTapped(); return true }
        return false
    }
    override func mouseDown(with event: NSEvent) {
        if !panel.frame.contains(convert(event.locationInWindow, from: nil)) { cancelTapped() }
    }
    override func scrollWheel(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}

final class ChoiceSheet: NSView {
    private let panel = NSView()
    private let choices: [ModalChoice]

    /// `choices` are laid out left to right; the last is the way out and is what Escape picks.
    init(title: String, message: String, choices: [ModalChoice]) {
        self.choices = choices
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 14
        panel.layer?.cornerCurve = .continuous
        panel.layer?.borderWidth = 1
        panel.shadow = { let s = NSShadow(); s.shadowBlurRadius = 30; s.shadowOffset = NSSize(width: 0, height: -8); s.shadowColor = NSColor.black.withAlphaComponent(0.45); return s }()

        let heading = NSTextField(wrappingLabelWithString: title)
        heading.font = PageStyle.titleFont
        let body = NSTextField(wrappingLabelWithString: message)
        body.font = NSFont.systemFont(ofSize: TextSize.body)
        body.textColor = .secondaryLabelColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        var buttons: [NSView] = [spacer]
        for (i, choice) in choices.enumerated() {
            let b = toolButton(choice.title, choice.symbol, choice.title, target: self, action: #selector(chosen(_:)))
            b.tag = i
            buttons.append(b)
        }
        let bar = NSStackView(views: buttons)
        bar.orientation = .horizontal
        bar.spacing = PageStyle.barSpacing

        addSubview(panel)
        for v in [panel, heading, body, bar] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        for v in [heading, body, bar] as [NSView] { panel.addSubview(v) }
        let pad = SwatchListStyle.sheetPad
        NSLayoutConstraint.activate([
            panel.widthAnchor.constraint(equalToConstant: 520),
            heading.topAnchor.constraint(equalTo: panel.topAnchor, constant: pad),
            heading.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: pad),
            heading.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -pad),
            body.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            body.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            bar.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 20),
            bar.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -pad),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Lays the sheet over the whole window with its panel in the centre of `page`.
    func present(over page: NSView) {
        guard let root = page.window?.contentView else { return }
        root.addSubview(self, positioned: .above, relativeTo: nil)
        let across = panel.centerXAnchor.constraint(equalTo: page.centerXAnchor)
        across.priority = .defaultHigh   // the page's centre, unless that would leave the window
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: root.topAnchor),
            bottomAnchor.constraint(equalTo: root.bottomAnchor),
            leadingAnchor.constraint(equalTo: root.leadingAnchor),
            trailingAnchor.constraint(equalTo: root.trailingAnchor),
            across,
            panel.centerYAnchor.constraint(equalTo: page.centerYAnchor),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 8),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -8),
        ])
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        super.updateLayer()
        panel.layer?.backgroundColor = Theme.grey(0.05).cgColor
        panel.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
    }

    private func pick(_ index: Int) {
        removeFromSuperview()
        if choices.indices.contains(index) { choices[index].run() }
    }

    @objc private func chosen(_ sender: NSButton) { pick(sender.tag) }
    override func cancelOperation(_ sender: Any?) { pick(choices.count - 1) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { pick(choices.count - 1) } else { super.keyDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        if !panel.frame.contains(convert(event.locationInWindow, from: nil)) { pick(choices.count - 1) }
    }
    override func scrollWheel(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}
