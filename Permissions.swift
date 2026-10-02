import AppKit

// ---------- Permissions: what macOS has to allow, shown once at first open and always in Settings ----------
//
// Each permission is one row: a light, a title, a line saying where things stand, and a button that
// does the next step. Rows are added here as the app gains features that need them.

enum PermissionState { case on, waiting, off, unavailable }

struct Permission {
    let title: String
    let state: () -> PermissionState
    /// One line for the current state.
    let detail: () -> String
    /// The button's title for the current state; nil when there is nothing to press.
    let button: () -> String?
    /// What the button does. Throws to show an error.
    let act: () throws -> Void

    static var all: [Permission] { [adobe] }

    static let adobe = Permission(
        title: "Adobe apps",
        state: {
            switch AdobeAccess.state {
            case .on: return .on
            case .waiting: return .waiting
            case .off: return .off
            case .nothingToDo: return .unavailable
            }
        },
        detail: {
            switch AdobeAccess.state {
            case .on: return "On. Palettes go into Photoshop, Illustrator and InDesign's library folders without a password."
            case .waiting: return "Waiting for you to allow MMFFDev Colour 3 in System Settings \u{25B8} General \u{25B8} Login Items."
            case .off where AdobeAccess.way == .helper:
                return "Adding a palette to an Adobe app asks for your password each time. Allow it once and it never asks again: a small helper that can only write swatch files into Adobe's library folders."
            case .off:
                return "Adding a palette to an Adobe app asks for your password each time. Allow it once and it never asks again: your account is given leave to add files to Adobe's library folders. Needs doing again after an Adobe upgrade."
            case .nothingToDo: return "No Adobe apps were found on this Mac. Nothing to set up."
            }
        },
        button: {
            switch AdobeAccess.state {
            case .on: return "Turn Off"
            case .waiting: return "Open Login Items"
            case .off: return "Allow\u{2026}"
            case .nothingToDo: return nil
            }
        },
        act: {
            switch AdobeAccess.state {
            case .on: _ = try AdobeAccess.turnOff()
            case .waiting: _ = try AdobeAccess.turnOn()
            case .off: _ = try AdobeAccess.turnOn()
            case .nothingToDo: break
            }
        })
}

/// One permission as a row. `refresh()` reads the state again.
final class PermissionRow: NSView {
    private let permission: Permission
    private let light = NSTextField(labelWithString: "\u{25CF}")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)
    var onError: ((Error) -> Void)?

    init(_ p: Permission) {
        permission = p
        super.init(frame: .zero)
        let title = NSTextField(labelWithString: p.title)
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        detail.font = NSFont.systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.preferredMaxLayoutWidth = 330
        light.font = NSFont.systemFont(ofSize: 14)
        light.setContentHuggingPriority(.required, for: .horizontal)
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(pressed)
        button.setContentHuggingPriority(.required, for: .horizontal)
        let words = NSStackView(views: [title, detail])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 3
        let row = NSStackView(views: [light, words, button])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            words.widthAnchor.constraint(equalToConstant: 330),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        switch permission.state() {
        case .on: light.textColor = .systemGreen
        case .waiting: light.textColor = .systemOrange
        case .off: light.textColor = .systemRed
        case .unavailable: light.textColor = .tertiaryLabelColor
        }
        detail.stringValue = permission.detail()
        if let t = permission.button() { button.title = t; button.isHidden = false } else { button.isHidden = true }
    }

    @objc private func pressed() {
        do { try permission.act() } catch { onError?(error) }
        refresh()
    }
}

/// A column of rows that looks again whenever the app comes to the front, since allowing things
/// happens in System Settings.
final class PermissionsView: NSStackView {
    private var rows: [PermissionRow] = []

    init(onError: @escaping (Error) -> Void) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 18
        for p in Permission.all {
            let r = PermissionRow(p)
            r.onError = onError
            rows.append(r)
            addArrangedSubview(r)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didBecomeActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc func refresh() { rows.forEach { $0.refresh() } }
}

// MARK: Settings pane

final class PermissionsPanel: SettingsPanel {
    private lazy var list = PermissionsView { [weak self] in self?.library.show($0) }

    override var labelWidth: CGFloat { 0 }

    override func rows() -> [[NSView]] {[
        [list],
    ]}

    override func refresh() { list.refresh() }
}

// MARK: First open

/// Shown once, over the main window, the first time the app opens. Settings ▸ Permissions shows the same rows after.
final class SetupWindowController: NSWindowController {
    static func show(over parent: NSWindow) {
        let c = SetupWindowController()
        parent.beginSheet(c.window!) { _ in Prefs.setupDone = true; keep = nil }
        keep = c
    }
    private static var keep: SetupWindowController?

    convenience init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        self.init(window: win)
        let title = NSTextField(labelWithString: "Welcome to MMFFDev Colour 3")
        title.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        let intro = NSTextField(wrappingLabelWithString: "A few things macOS needs you to allow, so that from now on everything just works. You can change any of them later in Settings \u{25B8} Permissions.")
        intro.font = NSFont.systemFont(ofSize: 13)
        intro.preferredMaxLayoutWidth = 460
        let list = PermissionsView { [weak self] error in
            guard let w = self?.window else { return }
            NSAlert(error: error).beginSheetModal(for: w)
        }
        let done = NSButton(title: "Done", target: self, action: #selector(finish))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [done])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        let column = NSStackView(views: [title, intro, list, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 16
        column.setCustomSpacing(8, after: title)
        column.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 20, right: 28)
        column.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: content.topAnchor), column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor), column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            buttons.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -28),
        ])
        win.contentView = content
        win.setContentSize(content.fittingSize)
    }

    @objc private func finish() {
        guard let w = window else { return }
        w.sheetParent?.endSheet(w)
    }
}
