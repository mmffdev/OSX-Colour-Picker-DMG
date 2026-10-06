import AppKit

// ---------- Before the app opens: a permission this launch needs ----------
//
// When a launch is about to read a folder macOS guards, and nothing has yet said why macOS will
// ask, this small window comes first: what is about to be asked and why, with the switch right
// there. Once every permission in it is on, it carries on by itself; Continue carries on either
// way. Built for every version of the app: hand it the permissions and what to do next.

final class PermissionGate: NSWindowController {
    private static var keep: PermissionGate?
    private let permissions: [Permission]
    private let then: () -> Void
    private var done = false

    static func show(_ permissions: [Permission], then: @escaping () -> Void) {
        let g = PermissionGate(permissions, then: then)
        keep = g
        g.window?.center()
        g.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(_ permissions: [Permission], then: @escaping () -> Void) {
        self.permissions = permissions
        self.then = then
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        win.title = Brand.name
        win.isReleasedWhenClosed = false
        super.init(window: win)

        let title = NSTextField(labelWithString: "Before \(Brand.name) Opens")
        title.font = PageStyle.titleFont
        let story = NSTextField(wrappingLabelWithString: "Your catalogues are kept in Documents. Allow \(Brand.name) to open that folder here, before anything loads, and macOS will not ask again.")
        story.font = NSFont.systemFont(ofSize: TextSize.body)
        story.preferredMaxLayoutWidth = 484
        let list = PermissionsView(permissions, textWidth: 360) { [weak win] error in
            guard let w = win else { return }
            NSAlert(error: error).beginSheetModal(for: w)
        }
        let go = ThemedButton(title: "Continue", image: nil, target: nil, action: nil)
        go.prominent = Brand.master
        go.keyEquivalent = "\r"
        go.target = self
        go.action = #selector(carryOn)
        let bar = ActionBar(leading: [], trailing: [go])

        let column = NSStackView(views: [title, story, list, bar])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 16
        column.setCustomSpacing(10, after: title)
        column.setCustomSpacing(22, after: list)
        column.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 20, right: 28)
        column.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: content.topAnchor), column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor), column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            column.widthAnchor.constraint(equalToConstant: 540),
            bar.widthAnchor.constraint(equalToConstant: 484),
        ])
        win.contentView = content
        win.setContentSize(content.fittingSize)
        NotificationCenter.default.addObserver(self, selector: #selector(answered), name: .permissionsChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Allowed: let the green light be seen, then carry on.
    @objc private func answered() {
        guard permissions.allSatisfy({ $0.state() == .on }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.carryOn() }
    }

    @objc private func carryOn() {
        guard !done else { return }
        done = true
        NotificationCenter.default.removeObserver(self)
        window?.close()
        Self.keep = nil
        then()
    }
}
