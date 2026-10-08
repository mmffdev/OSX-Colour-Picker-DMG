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

    /// What the setup asks up front: Screen Recording alone, since it needs a restart. Documents is
    /// asked where it belongs, on the catalogue step; the Adobe helper is leaving both editions
    /// (Rick, 2026-10-07) and its row went with it.
    static var all: [Permission] { [screenRecording] }

    /// Sample reads the screen through ScreenCaptureKit. macOS asks once, and only applies the
    /// answer to a fresh copy of the app, so a grant made now needs a restart.
    static let screenRecording = Permission(
        title: "Screen Recording",
        state: {
            if ScreenAccess.granted { return ScreenAccess.restartNeeded ? .waiting : .on }
            return ScreenAccess.asked ? .waiting : .off
        },
        detail: {
            if ScreenAccess.granted {
                return ScreenAccess.restartNeeded ? "Allowed. It applies when \(Brand.name) restarts. Turn it off again under Screen Recording in System Settings."
                    : "On. Sample turns any part of the screen into a palette. Turn it off again under Screen Recording in System Settings."
            }
            return ScreenAccess.asked
                ? "Switch \(Brand.name) on under Screen Recording in System Settings, then restart it once."
                : "Lets Sample turn any part of the screen into a palette. macOS asks once, then needs one restart."
        },
        button: {
            if ScreenAccess.granted { return ScreenAccess.restartNeeded ? "Restart Now" : "Turn Off\u{2026}" }
            return ScreenAccess.asked ? "Open System Settings" : "Allow\u{2026}"
        },
        act: {
            if ScreenAccess.granted { if ScreenAccess.restartNeeded { Relaunch.now() } else { ScreenAccess.openSettings() }; return }
            if ScreenAccess.asked { ScreenAccess.openSettings() } else { ScreenAccess.ask() }
        })

    /// A catalogue kept in Documents makes macOS ask once whether the app may use the folder. Asked
    /// here, the question comes while the user is reading why, instead of out of nowhere later.
    static let documents = Permission(
        title: "Documents Folder",
        state: { DocumentsAccess.current },
        detail: {
            switch DocumentsAccess.current {
            case .on: return "On. Your catalogue can live in Documents. Turn it off again under Files & Folders in System Settings."
            case .waiting: return "Switch \(Brand.name) on under Files & Folders in System Settings, or keep your catalogue elsewhere."
            default: return "Your catalogue goes in Documents unless you choose elsewhere. macOS asks once whether \(Brand.name) may use it."
            }
        },
        button: {
            switch DocumentsAccess.current {
            case .on: return "Turn Off\u{2026}"
            case .waiting: return "Open System Settings"
            default: return "Allow\u{2026}"
            }
        },
        act: { DocumentsAccess.current == .off ? DocumentsAccess.ask() : DocumentsAccess.openSettings() })

    #if !APPSTORE
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
            case .on: return "On. Palettes go into Adobe's library folders without a password. Turn Off takes that back."
            case .waiting: return "Allow \(Brand.name) under Login Items in System Settings, and it never asks for a password again."
            case .off: return "Adding a palette to an Adobe app asks for your password. Allow it once and it never asks again."
            case .nothingToDo: return "No Adobe apps were found on this Mac. There is nothing to set up."
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
    #endif
}

extension Notification.Name {
    /// Posted when a permission may have changed: a row was pressed, or an answer came back from macOS.
    static let permissionsChanged = Notification.Name("permissionsChanged")
}

enum ScreenAccess {
    /// Whether this copy of the app started with the permission. Read at launch (main.swift), since
    /// macOS only applies a grant to a copy started after it.
    static let grantedAtLaunch = CGPreflightScreenCaptureAccess()
    static var granted: Bool { CGPreflightScreenCaptureAccess() }
    /// Asked at some point on this Mac, so a refusal is told apart from never asked.
    static var asked: Bool {
        get { preferences.bool(forKey: "screenRecordingAsked") }
        set { preferences.set(newValue, forKey: "screenRecordingAsked") }
    }
    private static var askedThisRun = false
    /// Asked while this copy was running and not allowed when it started: only a restart makes it work.
    static var restartNeeded: Bool { askedThisRun && !grantedAtLaunch }

    static func ask() {
        asked = true
        askedThisRun = true
        _ = CGRequestScreenCaptureAccess()
        NotificationCenter.default.post(name: .permissionsChanged, object: nil)
    }
    static func openSettings() {
        askedThisRun = true
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(u) }
        NotificationCenter.default.post(name: .permissionsChanged, object: nil)
    }
}

enum DocumentsAccess {
    static var folder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents") }

    /// Whether `url` is Documents or inside it, which is what makes macOS ask.
    static func inside(_ url: URL, documents: URL = folder) -> Bool {
        let p = url.standardizedFileURL.path, d = documents.standardizedFileURL.path
        return p == d || p.hasPrefix(d + "/")
    }

    /// This launch is about to read something kept in Documents, and nothing on this Mac has yet
    /// said why macOS will ask. The Store build never asks: the sandbox reaches folders through the panel.
    static var neededAtLaunch: Bool {
        #if APPSTORE
        return false
        #else
        guard !allowed else { return false }
        let c = Catalogues.standard
        var places = [c.root] + c.registry.map { URL(fileURLWithPath: $0.path) }
        if let p = ProjectFiles.folder { places.append(p) }
        if let s = SyncSettings.folder { places.append(s) }
        return places.contains { inside($0) }
        #endif
    }
    static var allowed: Bool {
        get { preferences.bool(forKey: "documentsAllowed") }
        set { preferences.set(newValue, forKey: "documentsAllowed") }
    }
    static var refused: Bool {
        get { preferences.bool(forKey: "documentsRefused") }
        set { preferences.set(newValue, forKey: "documentsRefused") }
    }
    /// Where things stand now. Once macOS has been asked, reading the folder answers without a prompt,
    /// so the answer is read afresh each time: a switch flipped in System Settings shows at once.
    static var current: PermissionState {
        guard allowed || refused else { return .off }
        let ok = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
        allowed = ok; refused = !ok
        return ok ? .on : .waiting
    }

    /// Reading the folder is what makes macOS ask, and it waits for the answer, so it is read off the main thread.
    static func ask() {
        let path = folder.path
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
            DispatchQueue.main.async {
                allowed = ok
                refused = !ok
                NotificationCenter.default.post(name: .permissionsChanged, object: nil)
            }
        }
    }
    static func openSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") { NSWorkspace.shared.open(u) }
        NotificationCenter.default.post(name: .permissionsChanged, object: nil)
    }
}

/// One permission as a row. `refresh()` reads the state again.
final class PermissionRow: NSView {
    private let permission: Permission
    private let line = NSView()
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let button = SwissButton("", .secondary)
    /// The width of the setup's lead button, so the two line up on the right.
    static let buttonWidth: CGFloat = 176
    var onError: ((Error) -> Void)?

    init(_ p: Permission, textWidth: CGFloat = 330) {
        permission = p
        super.init(frame: .zero)
        let title = Design.text(p.title, .heading)
        detail.font = Design.Text.caption.font()
        detail.textColor = Design.quiet
        detail.preferredMaxLayoutWidth = textWidth
        line.wantsLayer = true
        button.fixedWidth = Self.buttonWidth
        button.target = self
        button.action = #selector(pressed)
        let words = NSStackView(views: [title, detail])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 3
        let row = NSStackView(views: [words, NSView(), button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        for v in [row, line] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            words.widthAnchor.constraint(equalToConstant: textWidth),
            line.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 12),
            line.leadingAnchor.constraint(equalTo: leadingAnchor), line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: 1), line.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh() {
        // The hairline under the row says where things stand: ink when allowed, the quiet grey when not,
        // the accent while macOS is being asked.
        line.layer?.backgroundColor = Design.ink.cgColor
        detail.attributedStringValue = Design.attributed(permission.detail(), .caption, colour: Design.quiet)
        if let t = permission.button() { button.title = t; button.isHidden = false } else { button.isHidden = true }
        button.trailing = permission.state() == .on ? .tick : .cross
    }

    @objc private func pressed() {
        do { try permission.act() } catch { onError?(error) }
        refresh()
        NotificationCenter.default.post(name: .permissionsChanged, object: nil)
    }
}

/// A column of rows that looks again whenever the app comes to the front, since allowing things
/// happens in System Settings.
final class PermissionsView: NSStackView {
    private var rows: [PermissionRow] = []

    init(_ list: [Permission] = Permission.all, textWidth: CGFloat = 330, spacing gap: CGFloat = 18, onError: @escaping (Error) -> Void) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = gap
        for p in list {
            let r = PermissionRow(p, textWidth: textWidth)
            r.onError = onError
            rows.append(r)
            addArrangedSubview(r)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .permissionsChanged, object: nil)
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
        let title = NSTextField(labelWithString: "Welcome to \(Brand.name)")
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
