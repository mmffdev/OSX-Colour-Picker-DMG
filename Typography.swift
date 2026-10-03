import AppKit

// ---------- Typography palettes ----------
//
// A Typography palette holds pairings rather than loose colours: a text colour on a background,
// with the words and fonts it was tried in. Its page shows each one as a real example. Pairings are
// made in cTools ▸ Contrast. In every other way it is a palette: it can be starred, put in a
// project, renamed, synced and exported.

/// The font for a family name, or the system font when the name is nil or not on this Mac.
func typeFont(family: String?, size: CGFloat, bold: Bool) -> NSFont {
    let system = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    guard let family = family else { return system }
    return NSFontManager.shared.font(withFamily: family, traits: bold ? .boldFontMask : [], weight: bold ? 9 : 5, size: size) ?? system
}

/// Whether a font family a pairing names is installed on this Mac.
func fontInstalled(_ family: String) -> Bool { NSFontManager.shared.availableFontFamilies.contains(family) }

/// Font Book, where fonts are installed. It cannot be told which font to look for, so the name is
/// put on the clipboard for pasting into its search, or into a font shop.
func openFontBook(copying family: String) {
    copyToClipboard(family)
    let paths = ["/System/Applications/Font Book.app", "/Applications/Font Book.app"]
    if let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

func searchWeb(forFont family: String) {
    var parts = URLComponents(string: "https://www.google.com/search")
    parts?.queryItems = [URLQueryItem(name: "q", value: "\(family) font")]
    if let url = parts?.url { NSWorkspace.shared.open(url) }
}

extension LibraryController {
    /// Typography palettes, in the order of the Typography list.
    var typographyOrder: [Swatch] { library.listedPalettes.filter { $0.isTypography } }

    @objc func newTypography() { addTypography(to: nil) }

    func addTypography(to project: UUID?) {
        var id: UUID?
        apply { id = $0.createTypography(in: project) }
        if let id = id { onShow?(.palette(id), false) }
    }

    /// Saves a pairing into a Typography palette, making the palette first when `id` is nil. Returns where it went.
    @discardableResult
    func keep(_ style: TypeStyle, in id: UUID?) -> UUID? {
        var palette = id, existed = false, name = style.name
        apply { lib in
            if palette == nil || lib.swatch(palette!)?.isTypography != true { palette = lib.createTypography() }
            guard let p = palette else { return }
            existed = lib.swatch(p)?.styles?.contains { $0.id == style.id } ?? false
            var s = style
            if !existed && s.name.isEmpty { s.name = lib.nextStyleName(in: p) }
            lib.setStyle(s, in: p)
            name = lib.swatch(p)?.styles?.first { $0.id == style.id }?.name ?? s.name
        }
        let home = palette.flatMap { library.swatch($0)?.name } ?? "Typography"
        flash(existed ? "Updated \(name) In \(home)" : "Added \(name) To \(home)")
        return palette
    }

    func removeStyle(_ style: UUID, from id: UUID) { apply { $0.removeStyle(style, from: id) } }
    func replaceFont(_ old: String, with new: String?, in id: UUID) {
        apply { $0.replaceFont(old, with: new, in: id) }
        flash("Replaced \(old) With \(new ?? "The System Font")")
    }
}

/// One pairing, shown as it would be used, with its name, numbers and actions beside it.
private final class TypeCard: NSView, NSTextFieldDelegate {
    static let height: CGFloat = 176

    var onRename: ((String) -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onCopy: ((String) -> Void)?
    /// A missing font is to be swapped for another family (nil = the system font).
    var onReplace: ((_ missing: String, _ with: String?) -> Void)?

    private var style: TypeStyle
    private let name = NSTextField()
    private let numbers = NSTextField(labelWithString: "")
    private let fonts = NSTextField(wrappingLabelWithString: "")
    private var edit: NSButton!, bin: NSButton!, copyInk: NSButton!, copyPaper: NSButton!
    private var missing: [(note: NSTextField, replace: NSPopUpButton, get: NSPopUpButton, family: String)] = []
    override var isFlipped: Bool { true }

    init(style: TypeStyle) {
        self.style = style
        super.init(frame: .zero)
        name.stringValue = style.name
        name.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        name.isBordered = false
        name.drawsBackground = false
        name.focusRingType = .none
        name.lineBreakMode = .byTruncatingTail
        name.cell?.usesSingleLineMode = true
        name.delegate = self
        name.toolTip = "Click To Rename"
        name.setAccessibilityLabel("Name of this pairing")

        let ratio = contrastRatio(style.ink, style.paper)
        let grade = ["AAA": "AAA", "AA": "AA", "AA large": "AA Large", "fail": "Fail"][contrastGrade(ratio)] ?? ""
        let line = NSMutableAttributedString(string: ContrastPair.text(ratio), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: TextSize.body, weight: .semibold), .foregroundColor: NSColor.labelColor])
        line.append(NSAttributedString(string: "  " + grade, attributes: [
            .font: NSFont.systemFont(ofSize: TextSize.body, weight: .semibold),
            .foregroundColor: ratio >= 4.5 ? NSColor.systemGreen : ratio >= 3 ? NSColor.systemOrange : NSColor.systemRed]))
        numbers.attributedStringValue = line

        fonts.font = NSFont.systemFont(ofSize: 11)
        fonts.textColor = .secondaryLabelColor
        fonts.maximumNumberOfLines = 2
        fonts.stringValue = "Heading: \(style.headingFont ?? "System Font")\nText: \(style.bodyFont ?? "System Font")"

        func small(_ title: String, _ tip: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            b.toolTip = tip
            return b
        }
        // Read together: "Text #FFFFFF On #2456F5".
        copyInk = small("Text \(style.ink)", "Copy The Text Colour", #selector(copyInkTapped))
        copyPaper = small("On \(style.paper)", "Copy The Background", #selector(copyPaperTapped))
        edit = small("Edit In Contrast", "Open This Pairing In The Contrast Tool", #selector(editTapped))
        bin = symbolButton("trash", tooltip: "Delete This Pairing", target: self, action: #selector(binTapped))
        for v in [name, numbers, fonts, copyInk, copyPaper, edit, bin] as [NSView] { addSubview(v) }

        // A font this Mac does not have is named, so it can be found, and can be swapped for one it does have.
        var seen = Set<String>()
        for family in style.fonts where !fontInstalled(family) && seen.insert(family).inserted {
            let note = NSTextField(labelWithString: "Font Missing: \(family)")
            note.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            note.textColor = .systemOrange
            note.lineBreakMode = .byTruncatingTail
            note.toolTip = "\(family) Is Not Installed On This Mac, So The System Font Is Shown In Its Place"
            let replace = NSPopUpButton(frame: .zero, pullsDown: true)
            replace.addItem(withTitle: "Replace")
            replace.addItem(withTitle: "System Font")
            replace.menu?.addItem(.separator())
            replace.addItems(withTitles: NSFontManager.shared.availableFontFamilies)
            replace.target = self
            replace.action = #selector(replaceChosen(_:))
            replace.toolTip = "Use Another Font In Place Of \(family), Throughout This Typography Palette"
            let get = NSPopUpButton(frame: .zero, pullsDown: true)
            get.addItem(withTitle: "Get Font")
            for (title, action) in [("Copy The Name \u{201C}\(family)\u{201D}", #selector(copyFontName(_:))),
                                    ("Open Font Book", #selector(fontBookChosen(_:))),
                                    ("Search The Web For \u{201C}\(family)\u{201D}", #selector(searchChosen(_:)))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                item.representedObject = family
                get.menu?.addItem(item)
            }
            get.toolTip = "Ways To Find And Install \(family)"
            for p in [replace, get] {
                p.controlSize = .small
                p.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                p.tag = missing.count
            }
            for v in [note, replace, get] as [NSView] { addSubview(v) }
            missing.append((note, replace, get, family))
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private var sample: NSRect { NSRect(x: 0, y: 0, width: max(120, bounds.width - 260), height: bounds.height) }

    override func layout() {
        super.layout()
        let x = sample.maxX + 16, w = bounds.width - x
        var y: CGFloat = 4
        name.frame = NSRect(x: x - 2, y: y, width: w - 24, height: 18)
        bin.frame = NSRect(x: bounds.width - 20, y: y, width: 20, height: 18)
        y += 22
        numbers.frame = NSRect(x: x, y: y, width: w, height: 16)
        y += 20
        fonts.frame = NSRect(x: x, y: y, width: w, height: 30)
        y += 34
        for m in missing {
            m.note.frame = NSRect(x: x, y: y, width: w, height: 15)
            y += 17
            m.replace.frame = NSRect(x: x, y: y, width: (w - 6) / 2, height: 20)
            m.get.frame = NSRect(x: x + (w + 6) / 2, y: y, width: (w - 6) / 2, height: 20)
            y += 24
        }
        // The copy and edit buttons sit at the foot, unless missing-font rows have used the room.
        let foot = max(y, bounds.height - 22 - 26)
        copyInk.frame = NSRect(x: x, y: foot, width: (w - 6) / 2, height: 20)
        copyPaper.frame = NSRect(x: x + (w + 6) / 2, y: foot, width: (w - 6) / 2, height: 20)
        edit.frame = NSRect(x: x, y: foot + 24, width: w, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = sample
        let ink = colorFromHex(style.ink) ?? .black, paper = colorFromHex(style.paper) ?? .white
        paper.setFill()
        NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12).stroke()

        let pad: CGFloat = 20, width = box.width - pad * 2
        let line = NSMutableParagraphStyle()
        line.lineBreakMode = .byTruncatingTail
        let heading = NSAttributedString(string: style.heading, attributes: [
            .font: typeFont(family: style.headingFont, size: 30, bold: true), .foregroundColor: ink, .paragraphStyle: line])
        let headingHeight = ceil(heading.size().height)
        heading.draw(in: NSRect(x: box.minX + pad, y: pad - 2, width: width, height: headingHeight))
        let body = NSAttributedString(string: style.body, attributes: [
            .font: typeFont(family: style.bodyFont, size: 13, bold: false), .foregroundColor: ink])
        let top = pad + headingHeight + 4
        body.draw(with: NSRect(x: box.minX + pad, y: top, width: width, height: box.height - top - pad),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    override func isAccessibilityElement() -> Bool { false }

    @objc private func editTapped() { onEdit?() }
    @objc private func binTapped() { onDelete?() }
    @objc private func copyInkTapped() { onCopy?(style.ink) }
    @objc private func copyPaperTapped() { onCopy?(style.paper) }
    @objc private func replaceChosen(_ sender: NSPopUpButton) {
        guard missing.indices.contains(sender.tag), sender.indexOfSelectedItem > 0, let title = sender.titleOfSelectedItem else { return }
        onReplace?(missing[sender.tag].family, sender.indexOfSelectedItem == 1 ? nil : title)
    }
    @objc private func copyFontName(_ sender: NSMenuItem) { if let f = sender.representedObject as? String { onCopy?(f) } }
    @objc private func fontBookChosen(_ sender: NSMenuItem) { if let f = sender.representedObject as? String { openFontBook(copying: f) } }
    @objc private func searchChosen(_ sender: NSMenuItem) { if let f = sender.representedObject as? String { searchWeb(forFont: f) } }

    func controlTextDidEndEditing(_ obj: Notification) {
        let typed = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty || typed == style.name { name.stringValue = style.name; return }
        onRename?(typed)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            name.abortEditing()
            name.stringValue = style.name
            window?.makeFirstResponder(superview)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            window?.makeFirstResponder(superview)
            return true
        }
        return false
    }
}

private final class CardColumn: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

final class TypographyViewController: NSViewController, NSTextFieldDelegate {
    private let library: LibraryController
    private var id: UUID?
    /// What the cards were last built from, so an unrelated library change does not rebuild them mid-edit.
    private var built: [TypeStyle]?

    private let name = NSTextField()
    private lazy var header = PageHeader(title: name, actions: [add])
    private var add: NSButton!
    private let scroll = NSScrollView()
    private let column = CardColumn()
    private let empty = NSTextField(wrappingLabelWithString: "")
    private var cards: [TypeCard] = []

    init(library: LibraryController) {
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let page = ToolPageView(frame: NSRect(x: 0, y: 0, width: 700, height: 520))
        page.onLayout = { [weak self] in self?.arrange(in: $0) }
        view = page

        name.isBordered = false
        name.drawsBackground = false
        name.focusRingType = .none
        name.lineBreakMode = .byTruncatingTail
        name.cell?.usesSingleLineMode = true
        name.delegate = self
        name.toolTip = "Click To Rename"
        name.setAccessibilityLabel("Typography palette name")
        add = toolButton("New Pairing", "plus", "Open Contrast To Make A Pairing For This Palette", target: self, action: #selector(addTapped))
        empty.stringValue = "No pairings yet. Press New Pairing: in Contrast, choose a text colour and a background, type your own words, pick the fonts, then press Add To Typography."
        empty.textColor = .secondaryLabelColor
        empty.font = NSFont.systemFont(ofSize: 13)
        empty.alignment = .center

        scroll.documentView = column
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        for v in [header, scroll, empty] as [NSView] { page.addSubview(v) }
    }

    /// Shows a Typography palette, or refreshes the one showing after the library has changed.
    func show(_ new: UUID) {
        _ = view
        if id != new { built = nil; scroll.contentView.scroll(to: .zero) }
        id = new
        guard let s = library.library.swatch(new), let styles = s.styles else { return }
        if name.currentEditor() == nil { name.stringValue = s.name }
        var parts = [plural(styles.count, "Pairing")]
        if let project = s.projectID.flatMap({ library.library.project($0)?.name }) { parts.append("In \(project)") }
        let lost = Set(styles.flatMap { $0.fonts }.filter { !fontInstalled($0) })
        if !lost.isEmpty { parts.append(plural(lost.count, "Font") + " Missing") }
        header.subtitle.stringValue = parts.joined(separator: "  \u{00B7}  ")
        empty.isHidden = !styles.isEmpty

        guard built != styles else { return }
        built = styles
        cards.forEach { $0.removeFromSuperview() }
        cards = styles.map { style in
            let card = TypeCard(style: style)
            card.onRename = { [weak self] typed in
                var renamed = style
                renamed.name = typed
                self?.library.apply { $0.setStyle(renamed, in: new) }
            }
            card.onEdit = { [weak self] in self?.library.onOpenContrast?(new, style.id) }
            card.onDelete = { [weak self] in self?.library.removeStyle(style.id, from: new) }
            card.onCopy = { [weak self] in self?.library.copy($0) }
            card.onReplace = { [weak self] missing, with in self?.library.replaceFont(missing, with: with, in: new) }
            column.addSubview(card)
            return card
        }
        view.needsLayout = true
    }

    private func arrange(in b: NSRect) {
        let pad = PageStyle.side
        header.frame = NSRect(x: 0, y: view.safeAreaInsets.top, width: b.width, height: PageStyle.height)
        let top = header.frame.maxY
        scroll.frame = NSRect(x: pad, y: top, width: b.width - pad * 2, height: max(40, b.height - top - 8))
        // Clear of the scroller, when the Mac is set to show one all the time.
        let width = scroll.contentSize.width - 2, gap: CGFloat = 16
        var y: CGFloat = 0
        for card in cards {
            card.frame = NSRect(x: 0, y: y, width: min(width, 900), height: TypeCard.height)
            y += TypeCard.height + gap
        }
        column.frame = NSRect(x: 0, y: 0, width: width, height: max(scroll.frame.height, y + 4))
        empty.frame = NSRect(x: pad + 40, y: top + 60, width: max(100, b.width - pad * 2 - 80), height: 60)
    }

    @objc private func addTapped() { if let id = id { library.onOpenContrast?(id, nil) } }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let id = id, let s = library.library.swatch(id) else { return }
        let typed = name.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty || typed == s.name { name.stringValue = s.name; return }
        library.rename(id, to: typed)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            name.abortEditing()
            if let id = id { name.stringValue = library.library.swatch(id)?.name ?? "" }
            view.window?.makeFirstResponder(view)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            view.window?.makeFirstResponder(view)
            return true
        }
        return false
    }
}
