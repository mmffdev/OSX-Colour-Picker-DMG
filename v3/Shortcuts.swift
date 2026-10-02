import AppKit
import Carbon.HIToolbox

// ---------- Keyboard shortcuts the user can change ----------
//
// Settings → Shortcuts. Every command of the app's own in the menu bar can be given a different
// shortcut. Cut, Copy, Paste, Quit and the like keep theirs, and nothing else may take them.

struct ShortcutModifiers: OptionSet, Hashable {
    let rawValue: Int
    static let command = ShortcutModifiers(rawValue: 1)
    static let shift = ShortcutModifiers(rawValue: 2)
    static let option = ShortcutModifiers(rawValue: 4)
    static let control = ShortcutModifiers(rawValue: 8)
}

struct Shortcut: Equatable {
    /// The key as a menu item wants it: the unshifted character, lowercase.
    var key: String
    var modifiers: ShortcutModifiers

    /// How it is kept in preferences.
    var encoded: String { "\(modifiers.rawValue):\(key)" }

    init(key: String, modifiers: ShortcutModifiers) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let raw = Int(parts[0]), !parts[1].isEmpty else { return nil }
        self.init(key: String(parts[1]), modifiers: ShortcutModifiers(rawValue: raw))
    }

    /// As the menu bar writes it: ⌃⌥⇧⌘ then the key.
    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "\u{2303}" }
        if modifiers.contains(.option) { text += "\u{2325}" }
        if modifiers.contains(.shift) { text += "\u{21E7}" }
        if modifiers.contains(.command) { text += "\u{2318}" }
        return text + (Shortcut.keyNames[key] ?? key.uppercased())
    }

    private static let keyNames: [String: String] = {
        var names = [" ": "Space", "\r": "\u{21A9}", "\t": "\u{21E5}", "\u{1B}": "\u{238B}", "\u{7F}": "\u{232B}", "\u{08}": "\u{232B}",
                     "\u{F700}": "\u{2191}", "\u{F701}": "\u{2193}", "\u{F702}": "\u{2190}", "\u{F703}": "\u{2192}", "\u{F728}": "\u{2326}"]
        for n in 1...20 { names[String(UnicodeScalar(0xF703 + n)!)] = "F\(n)" }
        return names
    }()
}

/// Why a shortcut cannot be used.
enum ShortcutProblem: Equatable {
    case needsModifier
    /// A shortcut every Mac app is expected to honour; the name says what it does.
    case reserved(String)
    /// Switched on in System Settings, so macOS takes it before the app ever sees it.
    case system
    /// Already on another command of this app.
    case taken(String)

    func message(for shortcut: Shortcut) -> String {
        switch self {
        case .needsModifier: return "A shortcut needs \u{2318} or \u{2303} in it."
        case .reserved(let what): return "\(shortcut.display) is \(what) on every Mac, so it is kept for that."
        case .system: return "macOS uses \(shortcut.display) itself (System Settings \u{203A} Keyboard \u{203A} Keyboard Shortcuts)."
        case .taken(let what): return "\(shortcut.display) is already used by \(what)."
        }
    }
}

enum Shortcuts {
    /// Shortcuts macOS or its conventions own, on top of the ones in the app's own Edit, app and Window menus.
    static let standard: [(Shortcut, String)] = [
        (Shortcut(key: "w", modifiers: .command), "Close Window"),
        (Shortcut(key: "z", modifiers: .command), "Undo"),
        (Shortcut(key: "z", modifiers: [.command, .shift]), "Redo"),
        (Shortcut(key: "\t", modifiers: .command), "switch apps"),
        (Shortcut(key: "\t", modifiers: [.command, .shift]), "switch apps"),
        (Shortcut(key: "`", modifiers: .command), "switch windows"),
        (Shortcut(key: " ", modifiers: .command), "Spotlight"),
        (Shortcut(key: " ", modifiers: [.command, .control]), "the emoji picker"),
        (Shortcut(key: "\u{1B}", modifiers: [.command, .option]), "Force Quit"),
        (Shortcut(key: "q", modifiers: [.command, .control]), "Lock Screen"),
        (Shortcut(key: "q", modifiers: [.command, .shift]), "Log Out"),
        (Shortcut(key: "h", modifiers: [.command, .option]), "Hide Others"),
        (Shortcut(key: "f", modifiers: [.command, .control]), "Full Screen"),
        (Shortcut(key: "d", modifiers: [.command, .option]), "show or hide the Dock"),
        (Shortcut(key: "/", modifiers: [.command, .shift]), "Help"),
    ]

    /// The first reason `shortcut` cannot go on the command `id`, or nil when it can.
    /// `keyCode` is the key that was pressed, when known; `system` lists what macOS has claimed.
    static func problem(with shortcut: Shortcut, keyCode: Int?, for id: String, reserved: [(Shortcut, String)],
                        system: [(keyCode: Int, modifiers: ShortcutModifiers)], assigned: [(id: String, title: String, shortcut: Shortcut)]) -> ShortcutProblem? {
        if shortcut.modifiers.isDisjoint(with: [.command, .control]) { return .needsModifier }
        if let hit = reserved.first(where: { $0.0 == shortcut }) { return .reserved(hit.1) }
        if let code = keyCode, system.contains(where: { $0.keyCode == code && $0.modifiers == shortcut.modifiers }) { return .system }
        if let hit = assigned.first(where: { $0.shortcut == shortcut && $0.id != id }) { return .taken(hit.title) }
        return nil
    }

    // ---------- The menu bar ----------

    /// Commands whose shortcuts are the same in every Mac app, and stay that way.
    private static let fixedActions: Set<String> = ["cut:", "copy:", "paste:", "selectAll:", "hide:", "terminate:", "performMiniaturize:",
                                                    "performZoom:", "showSettings", "orderFrontStandardAboutPanel:"]
    private static var defaults: [String: Shortcut] = [:]
    /// The app's own commands, as the menu bar was built. macOS adds items of its own later
    /// (Start Dictation, Emoji & Symbols); those are not the app's to change.
    private static var own: Set<String> = []
    private static weak var bar: NSMenu?

    struct Command {
        let id: String, title: String
        fileprivate let item: NSMenuItem
        var shortcut: Shortcut? { Shortcuts.shortcut(of: item) }
    }

    private static func shortcut(of item: NSMenuItem) -> Shortcut? {
        item.keyEquivalent.isEmpty ? nil : Shortcut(key: item.keyEquivalent, modifiers: ShortcutModifiers(item.keyEquivalentModifierMask))
    }

    /// Top-level menu items with an action, split into the app's own and the standard ones.
    private static func items(fixed: Bool) -> [(id: String, item: NSMenuItem)] {
        var seen = Set<String>()
        return (bar?.items ?? []).flatMap { $0.submenu?.items ?? [] }.compactMap { item in
            guard let action = item.action, !item.hasSubmenu else { return nil }
            let id = NSStringFromSelector(action)
            guard own.contains(id), seen.insert(id).inserted else { return nil }
            return fixedActions.contains(id) == fixed ? (id, item) : nil
        }
    }

    /// The commands that can be given a shortcut, in menu order.
    static var commands: [Command] {
        items(fixed: false).map { Command(id: $0.id, title: $0.item.title.replacingOccurrences(of: "\u{2026}", with: ""), item: $0.item) }
    }

    /// How a command's shortcut is written right now, for text that tells the user what to press.
    static func display(for id: String) -> String? { commands.first { $0.id == id }?.shortcut?.display }

    /// Everything that may not be taken: the standard list plus the fixed commands in the menus.
    static var reserved: [(Shortcut, String)] {
        standard + items(fixed: true).compactMap { entry in shortcut(of: entry.item).map { ($0, entry.item.title) } }
    }

    /// Call once the menu bar is built: remembers the shortcuts it came with, then puts the user's on.
    static func install(on bar: NSMenu) {
        self.bar = bar
        own = Set(bar.items.flatMap { $0.submenu?.items ?? [] }.compactMap { $0.action.map(NSStringFromSelector) })
        defaults = [:]
        for entry in items(fixed: false) { defaults[entry.id] = shortcut(of: entry.item) }
        apply()
    }

    private static func apply() {
        let saved = Prefs.shortcuts
        for entry in items(fixed: false) {
            // A saved empty string means the user took the shortcut off.
            let shortcut = saved[entry.id].map { Shortcut(encoded: $0) } ?? defaults[entry.id]
            entry.item.keyEquivalent = shortcut?.key ?? ""
            entry.item.keyEquivalentModifierMask = shortcut.map { NSEvent.ModifierFlags($0.modifiers) } ?? []
        }
    }

    /// Gives the command a shortcut, or none. Returns what is wrong instead when it cannot be used.
    @discardableResult
    static func set(_ shortcut: Shortcut?, keyCode: Int? = nil, for id: String) -> ShortcutProblem? {
        if let shortcut = shortcut {
            let assigned = commands.compactMap { c in c.shortcut.map { (id: c.id, title: c.title, shortcut: $0) } }
            if let problem = problem(with: shortcut, keyCode: keyCode, for: id, reserved: reserved, system: systemHotKeys(), assigned: assigned) {
                return problem
            }
        }
        var saved = Prefs.shortcuts
        if shortcut == defaults[id] { saved[id] = nil } else { saved[id] = shortcut?.encoded ?? "" }
        Prefs.shortcuts = saved
        apply()
        return nil
    }

    static func restoreDefaults() {
        Prefs.shortcuts = [:]
        apply()
    }

    /// The shortcuts switched on in System Settings: Spotlight, screenshots, Mission Control and so on.
    static func systemHotKeys() -> [(keyCode: Int, modifiers: ShortcutModifiers)] {
        var copied: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&copied) == noErr, let list = copied?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard entry["kHISymbolicHotKeyEnabled"] as? Bool == true, let code = entry["kHISymbolicHotKeyCode"] as? Int,
                  let carbon = entry["kHISymbolicHotKeyModifiers"] as? Int else { return nil }
            var modifiers: ShortcutModifiers = []
            if carbon & cmdKey != 0 { modifiers.insert(.command) }
            if carbon & shiftKey != 0 { modifiers.insert(.shift) }
            if carbon & optionKey != 0 { modifiers.insert(.option) }
            if carbon & controlKey != 0 { modifiers.insert(.control) }
            return (code, modifiers)
        }
    }
}

extension ShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
}

extension NSEvent.ModifierFlags {
    init(_ modifiers: ShortcutModifiers) {
        self = []
        if modifiers.contains(.command) { insert(.command) }
        if modifiers.contains(.shift) { insert(.shift) }
        if modifiers.contains(.option) { insert(.option) }
        if modifiers.contains(.control) { insert(.control) }
    }
}

/// A button that shows a shortcut and, once pressed, takes the next key combination typed.
/// Esc backs out; Delete takes the shortcut off.
final class ShortcutField: NSButton {
    /// A combination was typed (nil for Delete), with the key that was pressed.
    var onRecord: ((Shortcut?, Int?) -> Void)?
    var shortcut: Shortcut? { didSet { show() } }
    private var recording = false { didSet { show() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        widthAnchor.constraint(equalToConstant: 150).isActive = true
        show()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func show() {
        title = recording ? "Type shortcut\u{2026}" : (shortcut?.display ?? "None")
        toolTip = "Click, then type the new shortcut. Esc cancels; Delete removes it."
    }

    @objc private func startRecording() {
        recording = true
        window?.makeFirstResponder(self)
    }

    override var acceptsFirstResponder: Bool { true }
    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    // ⌘ combinations arrive here, before the menu bar can act on them; the rest arrive as key presses.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        take(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if recording { take(event) } else { super.keyDown(with: event) }
    }

    private func take(_ event: NSEvent) {
        let modifiers = ShortcutModifiers(event.modifierFlags)
        recording = false
        if modifiers.isEmpty, event.keyCode == 53 { return }                                             // Esc
        if modifiers.isEmpty, event.keyCode == 51 || event.keyCode == 117 { onRecord?(nil, nil); return } // Delete
        guard let key = event.characters(byApplyingModifiers: []), !key.isEmpty else { return }
        onRecord?(Shortcut(key: key, modifiers: modifiers), Int(event.keyCode))
    }
}
