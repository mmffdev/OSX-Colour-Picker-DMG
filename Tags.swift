import AppKit

// ---------- Tags: one bar for tagging, one page for managing ----------
//
// Every place that tags something uses the same TagBar: pressing a tag icon swaps the page's
// action bar for it. The tag editor is a full page listing every tag with its name, colour,
// scope and what wears it.

/// The colour a tag is drawn in: its own if it has one, the accent colour otherwise.
func tagColour(_ info: TagInfo?) -> NSColor {
    info?.colour.flatMap(colorFromHex) ?? .controlAccentColor
}

/// A row that takes the place of a page's action bar while tags are being edited: what is being
/// tagged, a field of tags, and Done. Return or Done saves; Esc leaves things as they were.
/// A second row opens underneath when there is something to say: the existing tags that match
/// what is being typed, and a scope for each tag that is new.
final class TagBar: NSView, NSTokenFieldDelegate {
    /// Called when the bar is finished with, saved or not, so the page can put its own bar back.
    var onClose: (() -> Void)?
    private let title = caption("")
    private let field = NSTokenField(frame: .zero)
    private let extras = NSStackView()
    private var library = Library()
    private var offered: [String] = []
    /// The projects a new tag may be given to; empty leaves every new tag global.
    private var scopes: [Project] = []
    /// The scope chosen for each new tag, by lowercased name. Absent means global.
    private var chosen: [String: UUID] = [:]
    private var commit: (([String], [String: UUID]) -> Void)?
    private var open = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        let icon = NSImageView(image: symbol("tag", "Tags", size: 12))
        icon.contentTintColor = .secondaryLabelColor
        title.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        title.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        field.tokenStyle = .rounded
        field.placeholderString = "Add tags, separated by commas"
        field.font = NSFont.systemFont(ofSize: 12)
        field.delegate = self
        field.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let done = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded
        done.controlSize = .small
        let row = NSStackView(views: [icon, title, field, done])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        extras.orientation = .horizontal
        extras.spacing = 6
        extras.alignment = .centerY
        extras.isHidden = true
        let column = NSStackView(views: [row, extras])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Starts an edit. `what` names the thing being tagged. `projects` are the projects it sits in:
    /// their tags are offered alongside the global ones, and a new tag may be given to one of
    /// them. A project tag from anywhere else is not offered, and would not be accepted.
    func begin(_ what: String, tags: [String], in library: Library, projects: Set<UUID>,
               commit: @escaping ([String], [String: UUID]) -> Void) {
        title.stringValue = what
        field.objectValue = tags
        self.library = library
        offered = library.allTags.filter { library.mayWear($0, in: projects) }
        scopes = library.orderedProjects.filter { projects.contains($0.id) }
        chosen = [:]
        self.commit = commit
        open = true
        refreshExtras()
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.open else { return }
            self.window?.makeFirstResponder(self.field)
            self.field.currentEditor()?.moveToEndOfDocument(nil)
        }
    }

    /// Closes the bar, keeping the tags or dropping the changes.
    func end(saving: Bool) {
        guard open else { return }
        open = false
        if saving {
            window?.makeFirstResponder(nil)   // turns whatever is half-typed into a tag
            let tags = Library.cleanTags(tokens(includingTyped: true))
            let fresh = Set(tags.map { $0.lowercased() })
            commit?(tags, chosen.filter { fresh.contains($0.key) && !known($0.key) })
        } else {
            field.abortEditing()
        }
        commit = nil
        extras.isHidden = true
        onClose?()
    }

    @objc private func doneTapped() { end(saving: true) }

    /// For a trial run: types into the field as the keyboard would.
    func rehearse(typing text: String) {
        (field.currentEditor() as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: What is in the field

    private func known(_ name: String) -> Bool { library.allTags.contains { $0.lowercased() == name.lowercased() } }

    /// What is being typed after the last finished tag.
    private var typed: String {
        guard let text = field.currentEditor()?.string else { return "" }
        // Finished tags show as attachments; pasted text may still hold its commas.
        let tail = text.split(omittingEmptySubsequences: false) { $0 == "\u{FFFC}" || $0 == "," }.last.map(String.init) ?? ""
        return tail.trimmingCharacters(in: .whitespaces)
    }

    private func tokens(includingTyped: Bool) -> [String] {
        var all = (field.objectValue as? [Any])?.compactMap { $0 as? String } ?? []
        if !includingTyped, !typed.isEmpty, all.last?.trimmingCharacters(in: .whitespaces) == typed { all.removeLast() }
        return all
    }

    func controlTextDidChange(_ obj: Notification) { refreshExtras() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { end(saving: true); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { end(saving: false); return true }
        // Tab takes the first match, when there is one.
        if selector == #selector(NSResponder.insertTab(_:)), let first = matches().first { take(first); return true }
        return false
    }

    // The matches are shown in the bar's second row instead of the field's own small menu.
    func tokenField(_ tokenField: NSTokenField, completionsForSubstring substring: String, indexOfToken tokenIndex: Int,
                    indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?) -> [Any]? { [] }

    private func matches() -> [String] {
        let text = typed.lowercased()
        guard !text.isEmpty else { return [] }
        let have = Set(tokens(includingTyped: false).map { $0.lowercased() })
        let fits = offered.filter { !have.contains($0.lowercased()) && $0.lowercased().contains(text) }
        return fits.sorted { ($0.lowercased().hasPrefix(text) ? 0 : 1, $0.lowercased()) < ($1.lowercased().hasPrefix(text) ? 0 : 1, $1.lowercased()) }
    }

    /// Puts an existing tag in place of what was being typed.
    private func take(_ tag: String) {
        field.objectValue = tokens(includingTyped: false) + [tag]
        window?.makeFirstResponder(field)
        field.currentEditor()?.moveToEndOfDocument(nil)
        refreshExtras()
    }

    // MARK: The second row

    /// While typing: the tags that match, each a button in its own colour. Otherwise: a scope
    /// menu for every tag in the field that does not exist yet.
    private func refreshExtras() {
        extras.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let found = matches()
        if !found.isEmpty {
            extras.addArrangedSubview(caption("Matches", size: 11))
            for (at, tag) in found.prefix(6).enumerated() {
                let home = library.project(ofTag: tag).flatMap { library.project($0)?.name }
                let chip = NSButton(title: home.map { "\(tag)  \u{00B7}  \($0)" } ?? tag, target: self, action: #selector(matchTapped(_:)))
                chip.bezelStyle = .recessed
                chip.controlSize = .small
                // A dot in the tag's own colour; a button's tint would be overridden by its style.
                let colour = tagColour(library.info(forTag: tag))
                chip.image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
                    colour.setFill()
                    NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                    return true
                }
                chip.imagePosition = .imageLeading
                chip.identifier = NSUserInterfaceItemIdentifier(tag)
                chip.toolTip = at == 0 ? "Press Tab to use this tag" : "Use this tag"
                extras.addArrangedSubview(chip)
            }
            if found.count > 6 { extras.addArrangedSubview(caption("+\(found.count - 6) more", size: 11)) }
        } else if !scopes.isEmpty {
            let fresh = tokens(includingTyped: false).filter { !known($0) }
            if !fresh.isEmpty { extras.addArrangedSubview(caption("New", size: 11)) }
            for tag in fresh {
                let menu = NSPopUpButton(frame: .zero, pullsDown: false)
                menu.controlSize = .small
                menu.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                menu.addItem(withTitle: "\(tag): Global")
                for p in scopes {
                    menu.addItem(withTitle: "\(tag): \(p.name) only")
                    menu.lastItem?.representedObject = p.id
                }
                if let id = chosen[tag.lowercased()], let at = scopes.firstIndex(where: { $0.id == id }) { menu.selectItem(at: at + 1) }
                menu.identifier = NSUserInterfaceItemIdentifier(tag)
                menu.target = self
                menu.action = #selector(scopeChosen(_:))
                menu.toolTip = "A global tag is offered everywhere; a project tag only inside that project"
                extras.addArrangedSubview(menu)
            }
        }
        extras.isHidden = extras.arrangedSubviews.isEmpty
    }

    @objc private func matchTapped(_ sender: NSButton) {
        if let tag = sender.identifier?.rawValue { take(tag) }
    }

    @objc private func scopeChosen(_ sender: NSPopUpButton) {
        guard let tag = sender.identifier?.rawValue else { return }
        chosen[tag.lowercased()] = sender.selectedItem?.representedObject as? UUID
    }
}

private final class TagListView: NSView {
    override var isFlipped: Bool { true }
}

/// The tag editor: every tag with its colour, name, scope, and a strip of the swatches that wear it.
final class TagEditorController: NSViewController, NSTextFieldDelegate {
    private let library: LibraryController
    var onClose: (() -> Void)?
    private var focus: String?
    private let count = caption("")
    private let rows = NSStackView()
    /// What each row's controls belong to, by the control's tag.
    private var names: [String] = []
    private var ownChange = false
    /// The tags ticked for acting on together.
    private var ticked = Set<String>()
    private let heading = NSTextField(labelWithString: "Tags")
    private var browsing: [NSView] = []
    private var selecting: [NSView] = []

    init(library: LibraryController, focus: String?) {
        self.library = library
        self.focus = focus
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView()
        heading.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        let add = NSButton(title: "New Tag", target: self, action: #selector(newTapped))
        add.bezelStyle = .rounded
        add.controlSize = .small
        add.image = symbol("plus", "New tag", size: 10)
        add.imagePosition = .imageLeading
        let done = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded
        done.controlSize = .small
        done.keyEquivalent = "\u{1b}"
        // With two or more tags ticked, these take the place of New Tag and Done.
        let remove = NSButton(title: "Remove All", target: self, action: #selector(removeTicked))
        remove.bezelStyle = .rounded
        remove.controlSize = .small
        remove.image = symbol("trash", "Remove", size: 10)
        remove.imagePosition = .imageLeading
        remove.toolTip = "Delete every ticked tag"
        let clear = NSButton(title: "Deselect", target: self, action: #selector(clearTicked))
        clear.bezelStyle = .rounded
        clear.controlSize = .small
        browsing = [add, done]
        selecting = [remove, clear]

        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        rows.translatesAutoresizingMaskIntoConstraints = false
        let document = TagListView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rows)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document

        for v in [heading, count, add, done, remove, clear, scroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 6),
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            count.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 3),
            count.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            done.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            done.centerYAnchor.constraint(equalTo: count.centerYAnchor),
            add.trailingAnchor.constraint(equalTo: done.leadingAnchor, constant: -8),
            add.centerYAnchor.constraint(equalTo: done.centerYAnchor),
            clear.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            clear.centerYAnchor.constraint(equalTo: count.centerYAnchor),
            remove.trailingAnchor.constraint(equalTo: clear.leadingAnchor, constant: -8),
            remove.centerYAnchor.constraint(equalTo: clear.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: count.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            rows.topAnchor.constraint(equalTo: document.topAnchor, constant: 4),
            rows.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            rows.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            rows.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20),
        ])
        view = root
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: .libraryDidChange, object: library)
        reload()
    }

    @objc private func libraryChanged() { if !ownChange { reload() } }

    /// Global tags first, then each project's, every list in name order.
    private func reload() {
        let lib = library.library
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        names = lib.allTags
        ticked = ticked.filter(names.contains)
        showHeader()
        var sections: [(title: String, tags: [String])] = [("Global Tags", names.filter { lib.project(ofTag: $0) == nil })]
        for p in lib.orderedProjects {
            sections.append(("Project Tags  \u{00B7}  \(p.name)", names.filter { lib.project(ofTag: $0) == p.id }))
        }
        for section in sections where !section.tags.isEmpty || section.title == "Global Tags" {
            let title = NSTextField(labelWithString: section.title)
            title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            rows.addArrangedSubview(title)
            rows.setCustomSpacing(8, after: title)
            if section.tags.isEmpty {
                rows.addArrangedSubview(caption("Press New Tag, or tag a swatch or palette, and it will be listed here."))
            }
            for name in section.tags {
                let row = makeRow(name, lib)
                rows.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            }
            if let last = rows.arrangedSubviews.last { rows.setCustomSpacing(18, after: last) }
        }
        if let name = focus, let at = names.firstIndex(of: name) {
            focus = nil
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let field = self.rows.viewWithTag(1000 + at) as? NSTextField else { return }
                self.view.window?.makeFirstResponder(field)
            }
        }
    }

    private func makeRow(_ name: String, _ lib: Library) -> NSView {
        let at = names.firstIndex(of: name) ?? 0
        let info = lib.info(forTag: name)

        let tick = NSButton(checkboxWithTitle: "", target: self, action: #selector(tickChanged(_:)))
        tick.tag = at
        tick.state = ticked.contains(name) ? .on : .off
        tick.toolTip = "Tick two or more tags to remove them together"

        let well = NSColorWell()
        well.color = tagColour(info)
        well.tag = at
        well.target = self
        well.action = #selector(colourChanged(_:))
        well.toolTip = "The colour of this tag in the sidebar"

        let field = NSTextField(string: name)
        field.tag = 1000 + at
        field.delegate = self
        field.toolTip = "Rename the tag everywhere it is used"

        let scope = NSPopUpButton(frame: .zero, pullsDown: false)
        scope.controlSize = .small
        scope.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        scope.addItem(withTitle: "Global")
        for p in lib.orderedProjects {
            scope.addItem(withTitle: "Project: \(p.name)")
            scope.lastItem?.representedObject = p.id
        }
        scope.selectItem(at: lib.project(ofTag: name).flatMap { id in lib.orderedProjects.firstIndex { $0.id == id } }.map { $0 + 1 } ?? 0)
        scope.tag = at
        scope.target = self
        scope.action = #selector(scopeChanged(_:))
        scope.toolTip = "A global tag is offered everywhere; a project tag only inside that project"

        let uses = lib.uses(ofTag: name)
        let hexes = lib.hexes(tagged: name)
        var parts: [String] = []
        if !uses.swatches.isEmpty { parts.append(plural(uses.swatches.count, "Swatch", "Swatches")) }
        if !uses.palettes.isEmpty { parts.append(plural(uses.palettes.count, "Palette")) }
        let used = caption(parts.isEmpty ? "Not used yet" : parts.joined(separator: "  \u{00B7}  "))
        used.toolTip = uses.palettes.isEmpty ? nil : "On " + uses.palettes.map { $0.name }.joined(separator: ", ")

        let strip = SpectrumView()
        strip.radius = 5
        strip.outlinesWhenEmpty = true
        strip.hexes = Array(lib.colours.map { $0.hex }.filter(hexes.contains).prefix(80))
        strip.toolTip = hexes.isEmpty ? "Nothing wears this tag yet" : "Every swatch that wears this tag, itself or through its palette"
        strip.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let delete = symbolButton("trash", tooltip: "Delete this tag", target: self, action: #selector(deleteTapped(_:)))
        delete.tag = at

        let row = NSStackView(views: [tick, well, field, scope, used, strip, delete])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 34),
            well.heightAnchor.constraint(equalToConstant: 22),
            field.widthAnchor.constraint(equalToConstant: 160),
            scope.widthAnchor.constraint(equalToConstant: 150),
            used.widthAnchor.constraint(equalToConstant: 120),
            strip.heightAnchor.constraint(equalToConstant: 22),
            strip.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        row.distribution = .fill
        for v in [tick, well, field, scope, used, delete] as [NSView] { v.setContentHuggingPriority(.required, for: .horizontal) }
        return row
    }

    /// The title, the count line, and which pair of buttons is showing.
    private func showHeader() {
        let many = ticked.count > 1
        heading.stringValue = many ? "\(ticked.count) Tags Selected" : "Tags"
        count.stringValue = many ? "Remove them together, or untick to go back"
            : names.isEmpty ? "No tags yet" : plural(names.count, "Tag")
        browsing.forEach { $0.isHidden = many }
        selecting.forEach { $0.isHidden = !many }
    }

    @objc private func tickChanged(_ sender: NSButton) {
        guard let name = name(sender) else { return }
        if sender.state == .on { ticked.insert(name) } else { ticked.remove(name) }
        showHeader()
    }

    @objc private func clearTicked() {
        ticked = []
        reload()
    }

    @objc private func removeTicked() {
        guard let window = view.window, ticked.count > 1 else { return }
        let going = names.filter(ticked.contains)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete \(going.count) tags?"
        alert.informativeText = going.joined(separator: ", ") + "\n\nThey will be taken off everything that wears them. The swatches and palettes themselves are not touched."
        alert.addButton(withTitle: "Delete Tags")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.ticked = []
            self?.library.deleteTags(going)
        }
    }

    private func name(_ control: NSView) -> String? {
        let at = control.tag >= 1000 ? control.tag - 1000 : control.tag
        return names.indices.contains(at) ? names[at] : nil
    }

    // The colour panel sends a stream of changes; the list is not rebuilt for each, or the
    // well would lose its hold on the panel.
    @objc private func colourChanged(_ sender: NSColorWell) {
        guard let name = name(sender) else { return }
        ownChange = true
        library.setTag(name, colour: hexOf(sender.color), project: library.library.project(ofTag: name))
        ownChange = false
    }

    @objc private func scopeChanged(_ sender: NSPopUpButton) {
        guard let name = name(sender) else { return }
        library.setTag(name, colour: library.library.info(forTag: name)?.colour, project: sender.selectedItem?.representedObject as? UUID)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let old = name(field) else { return }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty || typed == old { field.stringValue = old; return }
        library.renameTag(old, to: typed)
    }

    @objc private func deleteTapped(_ sender: NSButton) {
        guard let name = name(sender) else { return }
        let uses = library.library.uses(ofTag: name)
        guard !uses.swatches.isEmpty || !uses.palettes.isEmpty, let window = view.window else { library.deleteTag(name); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete the tag \u{201C}\(name)\u{201D}?"
        alert.informativeText = "It will be taken off everything that wears it. The swatches and palettes themselves are not touched."
        alert.addButton(withTitle: "Delete Tag")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.library.deleteTag(name) }
        }
    }

    @objc private func newTapped() {
        view.window?.makeFirstResponder(nil)
        focus = library.newTag()
        reload()
    }

    @objc private func doneTapped() {
        view.window?.makeFirstResponder(nil)
        NSColorPanel.shared.orderOut(nil)
        onClose?()
    }
}
