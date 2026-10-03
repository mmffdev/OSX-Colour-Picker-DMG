import AppKit

// ---------- Project details and templates ----------
//
// A project is a folder of palettes with a form of details behind it: who it is for, who owns it,
// what may be done with it. Details that repeat from project to project — a client's address, the
// studio's own contact lines, standard usage terms — can be saved as a template and filled into
// the next project's form. Templates are kept per Mac, in preferences.

/// One box on the project form. The raw value is the key the answer is stored under.
enum ProjectField: String, CaseIterable {
    case description, reference, purchaseOrder, status, startDate, dueDate
    case clientCompany, clientContact, clientRole, clientEmail, clientPhone, clientWebsite, clientAddress, clientCompanyNumber, clientTaxNumber
    case ownerCompany, ownerDepartment, ownerName, ownerContact, ownerRole, ownerEmail, ownerPhone, ownerExtension, ownerMobile,
         ownerWebsite, ownerAddress, ownerCompanyNumber, ownerTaxNumber
    case copyright, usageTerms, confidentiality
    case colourSpace, brandGuidelines
    case notes

    enum Section: String, CaseIterable {
        case project = "Project", client = "Client", studio = "Studio", rights = "Rights", colour = "Colour", notes = "Notes"
    }

    enum Kind: Equatable {
        case line, lines
        case choice([String])
    }

    var section: Section {
        switch self {
        case .description, .reference, .purchaseOrder, .status, .startDate, .dueDate: return .project
        case .clientCompany, .clientContact, .clientRole, .clientEmail, .clientPhone, .clientWebsite, .clientAddress,
             .clientCompanyNumber, .clientTaxNumber: return .client
        case .ownerCompany, .ownerDepartment, .ownerName, .ownerContact, .ownerRole, .ownerEmail, .ownerPhone, .ownerExtension, .ownerMobile,
             .ownerWebsite, .ownerAddress, .ownerCompanyNumber, .ownerTaxNumber: return .studio
        case .copyright, .usageTerms, .confidentiality: return .rights
        case .colourSpace, .brandGuidelines: return .colour
        case .notes: return .notes
        }
    }

    var title: String {
        switch self {
        case .description: return "Description"
        case .reference: return "Job reference"
        case .purchaseOrder: return "Purchase order"
        case .status: return "Status"
        case .startDate: return "Start date"
        case .dueDate: return "Due date"
        case .clientCompany: return "Company"
        case .clientContact: return "Contact name"
        case .clientRole: return "Job title"
        case .clientEmail: return "Email"
        case .clientPhone: return "Phone"
        case .clientWebsite: return "Website"
        case .clientAddress: return "Address"
        case .clientCompanyNumber: return "Company number"
        case .clientTaxNumber: return "VAT / tax number"
        case .ownerName: return "Project owner"
        case .ownerCompany: return "Studio"
        case .ownerEmail: return "Email"
        case .ownerPhone: return "Phone"
        case .ownerWebsite: return "Website"
        case .ownerAddress: return "Address"
        case .ownerDepartment: return "Department"
        case .ownerContact: return "Contact name"
        case .ownerRole: return "Job title"
        case .ownerExtension: return "Extension"
        case .ownerMobile: return "Mobile number"
        case .ownerCompanyNumber: return "Company number"
        case .ownerTaxNumber: return "VAT / tax number"
        case .copyright: return "Copyright notice"
        case .usageTerms: return "Usage terms"
        case .confidentiality: return "Confidentiality"
        case .colourSpace: return "Colour space / profile"
        case .brandGuidelines: return "Brand guidelines link"
        case .notes: return "Notes"
        }
    }

    var kind: Kind {
        switch self {
        case .description, .clientAddress, .ownerAddress, .usageTerms, .notes: return .lines
        case .status: return .choice(["Proposal", "Active", "On hold", "Complete", "Archived"])
        case .confidentiality: return .choice(["Public", "Internal", "Confidential", "Under NDA"])
        default: return .line
        }
    }

    var placeholder: String {
        switch self {
        case .description: return "What the work is, in a line or two"
        case .reference: return "e.g. JOB-0042"
        case .startDate, .dueDate: return "e.g. 2 October 2026"
        case .clientEmail, .ownerEmail: return "name@company.com"
        case .clientWebsite, .ownerWebsite, .brandGuidelines: return "https://"
        case .copyright: return "e.g. \u{00A9} 2026 Company Ltd. All rights reserved."
        case .usageTerms: return "Who may use these colours, where, and for how long"
        case .colourSpace: return "e.g. sRGB, Display P3, FOGRA39"
        default: return ""
        }
    }

    var isEmail: Bool { self == .clientEmail || self == .ownerEmail }

    /// Whether a template carries the field. What belongs to one job only — its description,
    /// numbers, dates, status and notes — is left out.
    var inTemplate: Bool {
        switch self {
        case .description, .reference, .purchaseOrder, .status, .startDate, .dueDate, .notes: return false
        default: return true
        }
    }

    static func fields(in section: Section, templateOnly: Bool = false) -> [ProjectField] {
        allCases.filter { $0.section == section && (!templateOnly || $0.inTemplate) }
    }

    /// Answers with the blanks and unknown keys dropped, and the rest trimmed.
    static func tidy(_ values: [String: String], templateOnly: Bool = false) -> [String: String] {
        var out: [String: String] = [:]
        for field in allCases where !templateOnly || field.inTemplate {
            let text = (values[field.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { out[field.rawValue] = text }
        }
        return out
    }

    /// What stops the form being saved, in words for the user; nil when it is fine.
    static func problem(name: String, values: [String: String], naming what: String = "project") -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the \(what) a name." }
        for field in allCases where field.isEmail {
            let text = (values[field.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let parts = text.split(separator: "@", omittingEmptySubsequences: false)
            if parts.count != 2 || parts[0].isEmpty || !parts[1].contains(".") || parts[1].hasPrefix(".") || parts[1].hasSuffix(".") || text.contains(" ") {
                return "The \(field.section.rawValue.lowercased()) email does not look like an email address."
            }
        }
        return nil
    }
}

/// Details saved to fill into other projects.
struct ProjectTemplate: Codable, Equatable {
    let id: UUID
    var name: String
    var values: [String: String]

    /// `templates` with one more saved. A template of the same name is replaced, so saving again
    /// under a name is how a template is brought up to date.
    static func saving(_ values: [String: String], named raw: String, into templates: [ProjectTemplate], id: UUID = UUID()) -> [ProjectTemplate] {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return templates }
        var out = templates
        let kept = ProjectField.tidy(values, templateOnly: true)
        if let i = out.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            out[i].name = name
            out[i].values = kept
        } else {
            out.append(ProjectTemplate(id: id, name: name, values: kept))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The form's answers after this template is filled in: what the template holds replaces
    /// what was there, and everything else is left alone.
    func filling(_ current: [String: String]) -> [String: String] {
        current.merging(ProjectField.tidy(values, templateOnly: true)) { _, mine in mine }
    }
}

enum ProjectTemplates {
    static var all: [ProjectTemplate] {
        get { Prefs.projectTemplates.flatMap { try? JSONDecoder().decode([ProjectTemplate].self, from: $0) } ?? [] }
        set { Prefs.projectTemplates = try? JSONEncoder().encode(newValue) }
    }

    static func save(_ values: [String: String], named name: String) { all = ProjectTemplate.saving(values, named: name, into: all) }

    /// Changes one template in place, renaming it if need be.
    static func update(_ id: UUID, name: String, values: [String: String]) {
        var list = all
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].name = uniqueName(name.trimmingCharacters(in: .whitespacesAndNewlines), among: list.filter { $0.id != id }.map { $0.name })
        list[i].values = ProjectField.tidy(values, templateOnly: true)
        all = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func delete(_ id: UUID) { all = all.filter { $0.id != id } }
}

private final class FormDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// The project form, shown as a sheet over the window. The same form edits a template, with
/// only the fields a template carries.
final class ProjectFormController: NSViewController, NSTextFieldDelegate, NSMenuDelegate {
    enum Mode: Equatable {
        case newProject, project, template
        /// Laid into a project's Overview page: no header of its own, and Save keeps it open.
        case overview
    }

    /// The project is locked: the form can be read and nothing in it changed.
    var locked = false
    private var embedded: Bool { mode == .overview }

    private let mode: Mode
    private var startName: String
    private var startValues: [String: String]
    private let onSave: (String, [String: String]) -> Void
    /// Set when the form covers the page instead of sitting in a sheet; called to take it away.
    var onClose: (() -> Void)?

    private let nameField = NSTextField()
    /// "Fill from Template": in the form's own header, or handed to the Overview page for its action bar.
    let templates = NSPopUpButton(frame: .zero, pullsDown: true)
    private let message = NSTextField(labelWithString: "")
    private var controls: [(field: ProjectField, control: NSControl)] = []
    /// The saved-values buttons, one per field and one per section; each carries its key as its identifier.
    private var savedButtons: [NSButton] = []

    init(mode: Mode, name: String, values: [String: String], onSave: @escaping (String, [String: String]) -> Void) {
        self.mode = mode
        startName = name
        startValues = values
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Shows the form as a sheet over `window`.
    static func present(over window: NSWindow, mode: Mode, name: String = "", values: [String: String] = [:],
                        onSave: @escaping (String, [String: String]) -> Void) {
        let sheet = NSWindow(contentViewController: ProjectFormController(mode: mode, name: name, values: values, onSave: onSave))
        sheet.styleMask = [.titled]
        sheet.setContentSize(NSSize(width: 640, height: min(680, window.frame.height - 80)))
        window.beginSheet(sheet)
    }

    private var isTemplate: Bool { mode == .template }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 680))

        let header = PageHeader(actions: [templates])
        header.title.stringValue = mode == .newProject ? "New Project" : mode == .project ? "Project Details" : "Project Template"
        let nameLabel = fieldLabel(isTemplate ? "Template name" : "Project name")
        nameField.stringValue = startName
        nameField.placeholderString = isTemplate ? "Client or studio the details belong to" : "Client, product or piece of work"
        nameField.font = NSFont.systemFont(ofSize: 13)

        (templates.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        templates.menu?.delegate = self
        templates.addItem(withTitle: "Fill from Template")
        templates.isHidden = isTemplate
        templates.toolTip = "Fill the form from saved details, or save these as a template"

        // The fields, section by section, in a grid that scrolls.
        var rows: [[NSView]] = []
        var headingRows: [Int] = []
        for section in ProjectField.Section.allCases {
            let fields = ProjectField.fields(in: section, templateOnly: isTemplate)
            guard !fields.isEmpty else { continue }
            let title = NSTextField(labelWithString: section.rawValue)
            title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            headingRows.append(rows.count)
            // The section's own saved sets, on the same column as each field's saved values.
            let sectionSaved: NSView = FormMemory.lead(of: section).isEmpty ? NSGridCell.emptyContentView
                : savedButton("Fill This Whole Section From A Saved \(section.rawValue)", #selector(sectionSavedTapped(_:)), key: section.rawValue)
            rows.append([title, NSGridCell.emptyContentView, sectionSaved])
            for field in fields {
                let control = makeControl(for: field)
                controls.append((field, control))
                let saved: NSView = FormMemory.remembers(field) ? savedButton("Use A Saved \(field.title)", #selector(fieldSavedTapped(_:)), key: field.rawValue)
                    : NSGridCell.emptyContentView
                rows.append([fieldLabel(field.title), control, saved])
            }
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 160
        grid.column(at: 1).width = 400
        grid.column(at: 2).width = 20
        grid.column(at: 2).xPlacement = .center
        grid.rowAlignment = .firstBaseline
        for r in headingRows {
            grid.row(at: r).topPadding = r == 0 ? 0 : 14
            grid.cell(atColumnIndex: 0, rowIndex: r).xPlacement = .leading
            grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: r, length: 1))
        }
        for (r, row) in rows.enumerated() where (row[1] as? NSTextField)?.tag == 1 { grid.row(at: r).rowAlignment = .none; grid.cell(atColumnIndex: 0, rowIndex: r).yPlacement = .top }

        let document = FormDocumentView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(grid)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document

        message.textColor = .systemRed
        message.font = NSFont.systemFont(ofSize: 11)
        message.lineBreakMode = .byTruncatingTail
        let cancel: NSButton, save: NSButton
        if embedded {
            // On the page the buttons are the page's own kind, and the form stays up after a save.
            cancel = toolButton("Revert", "arrow.uturn.backward", "Put Back What Was Last Saved", target: self, action: #selector(cancelTapped))
            save = toolButton("Save", "checkmark", "Save The Project's Details (\u{2318}S)", target: self, action: #selector(saveTapped))
            save.keyEquivalent = "s"
            save.keyEquivalentModifierMask = .command
            for c in [nameField, cancel, save] + controls.map({ $0.control }) + savedButtons as [NSControl] { c.isEnabled = !locked }
            templates.isEnabled = !locked
            if locked { say("The project is locked. Unlock it to change these details.", good: true) }
        } else {
            cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
            cancel.keyEquivalent = "\u{1b}"
            save = NSButton(title: mode == .newProject ? "Create Project" : "Save", target: self, action: #selector(saveTapped))
            save.keyEquivalent = "\r"
        }
        let top = hairline(), bottom = hairline()
        let inset: CGFloat = embedded ? PageStyle.side : 24

        for v in (embedded ? [] : [header]) + [nameLabel, nameField, top, scroll, bottom, message, cancel, save] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate(embedded ? [
            nameField.topAnchor.constraint(equalTo: root.topAnchor, constant: 4),
        ] : [
            root.widthAnchor.constraint(equalToConstant: 640),
            header.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: PageStyle.height),
            nameField.topAnchor.constraint(equalTo: header.bottomAnchor),
        ])
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: inset),
            nameLabel.widthAnchor.constraint(equalToConstant: 160),
            nameLabel.firstBaselineAnchor.constraint(equalTo: nameField.firstBaselineAnchor),
            nameField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 10),
            nameField.widthAnchor.constraint(equalToConstant: 400),
            top.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 14),
            top.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            bottom.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: save.topAnchor, constant: -14),
            save.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),
            save.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            message.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: inset),
            message.trailingAnchor.constraint(lessThanOrEqualTo: cancel.leadingAnchor, constant: -12),
            message.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            grid.topAnchor.constraint(equalTo: document.topAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: inset),
            grid.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18),
        ])
        view = root
        show(startValues)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !embedded { view.window?.makeFirstResponder(nameField) }
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text + ":")
        l.alignment = .right
        l.textColor = .secondaryLabelColor
        return l
    }

    private func makeControl(for field: ProjectField) -> NSControl {
        switch field.kind {
        case .choice(let options):
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: ["Not set"] + options)
            return popup
        case .line, .lines:
            let text = NSTextField()
            text.placeholderString = field.placeholder
            text.delegate = self
            if field.kind == .lines {
                text.tag = 1   // Return starts a new line in these
                text.usesSingleLineMode = false
                text.cell?.wraps = true
                text.cell?.isScrollable = false
                text.heightAnchor.constraint(equalToConstant: 58).isActive = true
            }
            return text
        }
    }

    // MARK: Saved values

    private func savedButton(_ tip: String, _ action: Selector, key: String) -> NSButton {
        let b = symbolButton("square.stack", tooltip: tip, target: self, action: action)
        b.image = symbol("square.stack", tip, size: 12)
        b.identifier = NSUserInterfaceItemIdentifier(key)
        savedButtons.append(b)
        return b
    }

    /// One line for a menu: the first line of the value, cut short if it runs on.
    private func menuTitle(_ value: String) -> String {
        let first = value.split(whereSeparator: { $0.isNewline }).first.map(String.init) ?? value
        let more = first.count < value.trimmingCharacters(in: .whitespacesAndNewlines).count
        return (first.count > 60 ? String(first.prefix(60)) + "\u{2026}" : first) + (more && first.count <= 60 ? " \u{2026}" : "")
    }

    @objc private func fieldSavedTapped(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue, let field = ProjectField(rawValue: key) else { return }
        let saved = FormMemoryStore.load().remembered(for: field)
        let menu = NSMenu()
        if saved.isEmpty {
            menu.addItem(withTitle: "Nothing Saved For \(field.title) Yet", action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(withTitle: "What You Type Here Is Remembered When The Form Is Saved", action: nil, keyEquivalent: "").isEnabled = false
        }
        let forget = NSMenu()
        for value in saved {
            let item = menu.addItem(withTitle: menuTitle(value), action: #selector(useSavedValue(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [key, value]
            let drop = forget.addItem(withTitle: menuTitle(value), action: #selector(forgetSavedValue(_:)), keyEquivalent: "")
            drop.target = self
            drop.representedObject = [key, value]
        }
        if !saved.isEmpty {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Forget", action: nil, keyEquivalent: "").submenu = forget
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func useSavedValue(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let control = controls.first(where: { $0.field.rawValue == pair[0] })?.control else { return }
        control.stringValue = pair[1]
    }

    @objc private func forgetSavedValue(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2, let field = ProjectField(rawValue: pair[0]) else { return }
        FormMemoryStore.update { $0.forget(pair[1], for: field) }
    }

    @objc private func sectionSavedTapped(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue, let section = ProjectField.Section(rawValue: key) else { return }
        let saved = FormMemoryStore.load().records(for: section)
        let menu = NSMenu()
        if section == .studio {
            // The organisation set in Settings is always on offer here, ahead of what the form has remembered.
            let organisation = ProjectField.tidy(Prefs.organisation)
            let name = [ProjectField.ownerCompany, .ownerName].compactMap { organisation[$0.rawValue] }.first
            let item = menu.addItem(withTitle: organisation.isEmpty ? "My Organisation (Not Set Yet: Settings, Organisation)" : "My Organisation" + (name.map { ": " + menuTitle($0) } ?? ""),
                                    action: organisation.isEmpty ? nil : #selector(useOrganisation), keyEquivalent: "")
            item.target = self
            item.isEnabled = !organisation.isEmpty
            menu.addItem(.separator())
        }
        if saved.isEmpty {
            let lead = FormMemory.lead(of: section).first?.title ?? "Name"
            menu.addItem(withTitle: "No Saved \(section.rawValue) Yet", action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(withTitle: "A Section Is Remembered Under Its \(lead) When The Form Is Saved", action: nil, keyEquivalent: "").isEnabled = false
        }
        let forget = NSMenu()
        for record in saved {
            let item = menu.addItem(withTitle: menuTitle(record.name), action: #selector(useSavedSection(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [key, record.id.uuidString]
            let drop = forget.addItem(withTitle: menuTitle(record.name), action: #selector(forgetSavedSection(_:)), keyEquivalent: "")
            drop.target = self
            drop.representedObject = [key, record.id.uuidString]
        }
        if !saved.isEmpty {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Forget", action: nil, keyEquivalent: "").submenu = forget
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    private func record(_ sender: NSMenuItem) -> (ProjectField.Section, FormMemory.SectionRecord)? {
        guard let pair = sender.representedObject as? [String], pair.count == 2, let section = ProjectField.Section(rawValue: pair[0]),
              let record = FormMemoryStore.load().records(for: section).first(where: { $0.id.uuidString == pair[1] }) else { return nil }
        return (section, record)
    }

    @objc private func useSavedSection(_ sender: NSMenuItem) {
        guard let (section, record) = record(sender) else { return }
        show(FormMemoryStore.load().filling(values, with: record, in: section))
        say("Filled \(section.rawValue) from \(record.name).", good: true)
    }

    @objc private func useOrganisation() {
        let organisation = ProjectField.tidy(Prefs.organisation)
        guard !organisation.isEmpty else { return }
        let record = FormMemory.SectionRecord(id: UUID(), name: "My Organisation", values: organisation, savedAt: Date())
        show(FormMemory().filling(values, with: record, in: .studio))
        say("Filled Studio from your organisation.", good: true)
    }

    @objc private func forgetSavedSection(_ sender: NSMenuItem) {
        guard let (section, record) = record(sender) else { return }
        FormMemoryStore.update { $0.forget(record: record.id, in: section) }
    }

    // MARK: Values

    private var values: [String: String] {
        var out: [String: String] = [:]
        for (field, control) in controls {
            if let popup = control as? NSPopUpButton { out[field.rawValue] = popup.indexOfSelectedItem > 0 ? popup.titleOfSelectedItem ?? "" : "" }
            else { out[field.rawValue] = control.stringValue }
        }
        // What this form has no box for is kept as it came.
        return startValues.merging(out) { _, shown in shown }
    }

    private func show(_ values: [String: String]) {
        for (field, control) in controls {
            let text = values[field.rawValue] ?? ""
            if let popup = control as? NSPopUpButton {
                if popup.itemTitles.contains(text) { popup.selectItem(withTitle: text) } else { popup.selectItem(at: 0) }
            } else {
                control.stringValue = text
            }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control.tag == 1, selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        textView.insertNewlineIgnoringFieldEditor(nil)
        return true
    }

    // MARK: Templates

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: "Fill from Template", action: nil, keyEquivalent: "")
        let saved = ProjectTemplates.all
        for t in saved {
            let item = menu.addItem(withTitle: t.name, action: #selector(fill(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = t.id
        }
        if saved.isEmpty { menu.addItem(withTitle: "No templates yet", action: nil, keyEquivalent: "").isEnabled = false }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Save as Template\u{2026}", action: #selector(saveAsTemplate), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Manage Templates\u{2026}", action: #selector(manageTemplates), keyEquivalent: "").target = self
    }

    @objc private func fill(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let template = ProjectTemplates.all.first(where: { $0.id == id }) else { return }
        show(template.filling(values))
        say("Filled from \(template.name).", good: true)
    }

    @objc private func saveAsTemplate() {
        guard let window = view.window else { return }
        let kept = ProjectField.tidy(values, templateOnly: true)
        guard !kept.isEmpty else { say("Fill in some client, studio or rights details first; those are what a template keeps."); return }
        let alert = NSAlert()
        alert.messageText = "Save as Template"
        alert.informativeText = "Keeps the client, studio, rights and colour details to fill into other projects. Saving under an existing name replaces that template."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = kept[ProjectField.clientCompany.rawValue] ?? kept[ProjectField.ownerCompany.rawValue] ?? nameField.stringValue
        field.placeholderString = "Template name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save Template")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard response == .alertFirstButtonReturn, !name.isEmpty else { return }
            ProjectTemplates.save(kept, named: name)
            self?.say("Saved the template \u{201C}\(name)\u{201D}.", good: true)
        }
    }

    @objc private func manageTemplates() {
        if let window = view.window { ProjectTemplatesController.present(over: window) }
    }

    private func say(_ text: String, good: Bool = false) {
        message.stringValue = text
        message.textColor = good ? .secondaryLabelColor : .systemRed
    }

    // MARK: Buttons

    @objc private func saveTapped() {
        view.window?.makeFirstResponder(nil)   // take in whatever is still being typed
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let answers = ProjectField.tidy(values, templateOnly: isTemplate)
        if let problem = ProjectField.problem(name: name, values: answers, naming: isTemplate ? "template" : "project") { say(problem); return }
        // What a project's form holds is remembered for next time: each field, and each section under its name.
        if !isTemplate { FormMemoryStore.update { $0.remember(answers) } }
        if embedded {
            // The page stays; what was saved becomes what Revert goes back to.
            startName = name
            startValues = answers
            onSave(name, answers)
            say("Saved.", good: true)
            return
        }
        close()
        onSave(name, answers)
    }

    @objc private func cancelTapped() {
        if embedded {
            view.window?.makeFirstResponder(nil)
            nameField.stringValue = startName
            show(startValues)
            say("Put back to what was last saved.", good: true)
            return
        }
        close()
    }

    private func close() {
        if let onClose = onClose { onClose(); return }
        guard let sheet = view.window else { return }
        if let parent = sheet.sheetParent { parent.endSheet(sheet) } else { sheet.close() }
    }
}

/// The list of saved templates: look one over, edit it, copy it, delete it, start a new one.
final class ProjectTemplatesController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let preview = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 300))
    private var list: [ProjectTemplate] = []
    private var buttons: [NSButton] = []

    static func present(over window: NSWindow) {
        let sheet = NSWindow(contentViewController: ProjectTemplatesController())
        sheet.styleMask = [.titled]
        window.beginSheet(sheet)
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 460))
        let heading = NSTextField(labelWithString: "Project Templates")
        heading.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let about = NSTextField(wrappingLabelWithString: "Saved client, studio and rights details. Fill one into a project from the form\u{2019}s \u{201C}Fill from Template\u{201D} menu.")
        about.font = NSFont.systemFont(ofSize: 11)
        about.textColor = .secondaryLabelColor

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        table.addTableColumn(column)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(editTapped)
        table.rowHeight = 24
        let names = NSScrollView()
        names.documentView = table
        names.hasVerticalScroller = true
        names.borderType = .bezelBorder

        preview.isEditable = false
        preview.font = NSFont.systemFont(ofSize: TextSize.body)
        preview.isVerticallyResizable = true
        preview.textContainer?.widthTracksTextView = true
        preview.drawsBackground = false
        preview.textContainerInset = NSSize(width: 10, height: 10)
        preview.autoresizingMask = [.width]
        let details = NSScrollView()
        details.documentView = preview
        details.hasVerticalScroller = true
        details.borderType = .bezelBorder

        let new = NSButton(title: "New\u{2026}", target: self, action: #selector(newTapped))
        let edit = NSButton(title: "Edit\u{2026}", target: self, action: #selector(editTapped))
        let duplicate = NSButton(title: "Duplicate", target: self, action: #selector(duplicateTapped))
        let delete = NSButton(title: "Delete", target: self, action: #selector(deleteTapped))
        buttons = [edit, duplicate, delete]
        let done = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        done.keyEquivalent = "\r"
        let actions = NSStackView(views: [new, edit, duplicate, delete])
        actions.spacing = 8

        for v in [heading, about, names, details, actions, done] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 640),
            root.heightAnchor.constraint(equalToConstant: 460),
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            about.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4),
            about.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            about.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            names.topAnchor.constraint(equalTo: about.bottomAnchor, constant: 14),
            names.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            names.widthAnchor.constraint(equalToConstant: 200),
            names.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -14),
            details.topAnchor.constraint(equalTo: names.topAnchor),
            details.leadingAnchor.constraint(equalTo: names.trailingAnchor, constant: 12),
            details.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            details.bottomAnchor.constraint(equalTo: names.bottomAnchor),
            actions.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            actions.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            done.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            done.centerYAnchor.constraint(equalTo: actions.centerYAnchor),
        ])
        view = root
        reload(selecting: nil)
    }

    private var chosen: ProjectTemplate? { list.indices.contains(table.selectedRow) ? list[table.selectedRow] : nil }

    private func reload(selecting id: UUID?) {
        list = ProjectTemplates.all
        table.reloadData()
        let row = id.flatMap { id in list.firstIndex { $0.id == id } } ?? (list.isEmpty ? -1 : 0)
        if row >= 0 { table.selectRowIndexes([row], byExtendingSelection: false) }
        showChosen()
    }

    /// Writes the chosen template out, section by section, for reading.
    private func showChosen() {
        buttons.forEach { $0.isEnabled = chosen != nil }
        let text = NSMutableAttributedString()
        let plain: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: TextSize.body), .foregroundColor: NSColor.labelColor]
        let quiet: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: TextSize.body), .foregroundColor: NSColor.secondaryLabelColor]
        let bold: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: TextSize.body, weight: .semibold), .foregroundColor: NSColor.labelColor]
        guard let template = chosen else {
            text.append(NSAttributedString(string: list.isEmpty ? "No templates yet.\n\nPress New\u{2026} to write one, or choose Save as Template in a project\u{2019}s form." : "", attributes: quiet))
            preview.textStorage?.setAttributedString(text)
            return
        }
        for section in ProjectField.Section.allCases {
            let filled = ProjectField.fields(in: section, templateOnly: true).filter { template.values[$0.rawValue] != nil }
            guard !filled.isEmpty else { continue }
            text.append(NSAttributedString(string: (text.length == 0 ? "" : "\n") + section.rawValue + "\n", attributes: bold))
            for field in filled {
                text.append(NSAttributedString(string: field.title + ":  ", attributes: quiet))
                text.append(NSAttributedString(string: (template.values[field.rawValue] ?? "").replacingOccurrences(of: "\n", with: ", ") + "\n", attributes: plain))
            }
        }
        if text.length == 0 { text.append(NSAttributedString(string: "This template is empty.", attributes: quiet)) }
        preview.textStorage?.setAttributedString(text)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { list.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: list[row].name)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { showChosen() }

    @objc private func newTapped() {
        guard let window = view.window else { return }
        ProjectFormController.present(over: window, mode: .template) { [weak self] name, values in
            let id = UUID()
            ProjectTemplates.all = ProjectTemplate.saving(values, named: uniqueName(name, among: ProjectTemplates.all.map { $0.name }), into: ProjectTemplates.all, id: id)
            self?.reload(selecting: id)
        }
    }

    @objc private func editTapped() {
        guard let window = view.window, let template = chosen else { return }
        ProjectFormController.present(over: window, mode: .template, name: template.name, values: template.values) { [weak self] name, values in
            ProjectTemplates.update(template.id, name: name, values: values)
            self?.reload(selecting: template.id)
        }
    }

    @objc private func duplicateTapped() {
        guard let template = chosen else { return }
        let id = UUID()
        ProjectTemplates.all = ProjectTemplate.saving(template.values, named: uniqueName(template.name + " copy", among: list.map { $0.name }), into: ProjectTemplates.all, id: id)
        reload(selecting: id)
    }

    @objc private func deleteTapped() {
        guard let window = view.window, let template = chosen else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete the template \u{201C}\(template.name)\u{201D}?"
        alert.informativeText = "Projects already filled from it keep their details."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            ProjectTemplates.delete(template.id)
            self?.reload(selecting: nil)
        }
    }

    @objc private func doneTapped() {
        guard let sheet = view.window else { return }
        if let parent = sheet.sheetParent { parent.endSheet(sheet) } else { sheet.close() }
    }
}
