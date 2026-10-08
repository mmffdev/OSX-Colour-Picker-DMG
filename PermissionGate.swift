import AppKit

// ---------- Before the app opens: a permission this launch needs ----------
//
// When a launch is about to read a folder macOS guards, and nothing has yet said why macOS will
// ask, this panel comes first: what is about to be asked and why, with the switch right there.
// Once every permission in it is on, it carries on by itself; Continue carries on either way.
// Built for every version of the app: hand it the permissions and what to do next.
//
// Drawn on the wizard's frame (c_c_c_design_grid_wizard.md), shorter: the band and the label line
// across the top, the two-tone title in columns 1 to 5, the lead and the permission rows in 7 to 12
// with the capitals of their first line level with the title's, and Continue on a row of its own at
// the right margin. Paper ground, square corners, one shadow, no title bar. It floats above other
// apps' windows until it is answered: macOS does not let an app take the front on its own, and a
// gate that slips behind the window it was opened from looks like nothing happened.

final class PermissionGate: NSWindowController {
    typealias W = Design.Wizard
    /// The panel's height, on the beat: the wizard's width, two thirds of its height.
    static let height: CGFloat = 440

    private static var keep: PermissionGate?
    private let permissions: [Permission]
    private let then: () -> Void
    private var done = false
    private let go = SwissButton("Continue", .primary)

    static func show(_ permissions: [Permission], then: @escaping () -> Void) {
        let g = PermissionGate(permissions, then: then)
        keep = g
        g.window?.center()
        g.showWindow(nil)
        g.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(_ permissions: [Permission], then: @escaping () -> Void) {
        self.permissions = permissions
        self.then = then
        let size = NSSize(width: W.size.width, height: Self.height)
        let win = SetupWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.title = Brand.name
        win.isReleasedWhenClosed = false
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        win.level = .floating
        super.init(window: win)

        let frame = NSView(frame: NSRect(origin: .zero, size: size))
        frame.wantsLayer = true
        frame.layer?.backgroundColor = Design.paper.cgColor
        frame.layer?.cornerRadius = W.radius
        frame.layer?.masksToBounds = true

        let band = NSView()
        band.wantsLayer = true
        band.layer?.backgroundColor = Design.active.cgColor
        let logo = Logo()
        let label = Design.text(String(format: "Permission 01 of %02d", permissions.count), .label, colour: Design.quiet)

        let title = NSTextField(wrappingLabelWithString: "")
        title.maximumNumberOfLines = 3
        let s = NSMutableAttributedString(attributedString: Design.attributed("Before", .title, size: 44, lineHeight: true))
        s.append(Design.attributed("\n\(Brand.name) opens", .title, size: 44, colour: Design.soft, lineHeight: true))
        title.attributedStringValue = s

        let width = W.span(7, 12)
        let lead = SetupFrame.lead("Your catalogues are kept in Documents. Allow \(Brand.name) to open that folder now, before anything loads, and macOS will not ask again.", width: width)
        let list = PermissionsView(permissions, textWidth: width - PermissionRow.buttonWidth - W.gutter, spacing: Design.beat(3)) { [weak win] error in
            guard let w = win else { return }
            NSAlert(error: error).beginSheetModal(for: w)
        }
        let words = NSStackView(views: [lead, list])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = Design.beat(8)

        go.fixedWidth = PermissionRow.buttonWidth
        go.keyEquivalent = "\r"
        go.target = self
        go.action = #selector(carryOn)
        let actions = NSStackView(views: [go])
        actions.orientation = .horizontal
        actions.alignment = .lastBaseline

        for v in [band, logo, label, title, words, actions] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; frame.addSubview(v) }
        NSLayoutConstraint.activate([
            band.topAnchor.constraint(equalTo: frame.topAnchor), band.leadingAnchor.constraint(equalTo: frame.leadingAnchor),
            band.trailingAnchor.constraint(equalTo: frame.trailingAnchor), band.heightAnchor.constraint(equalToConstant: W.band),
            // The top line as the wizard's: the mark at column 1, the label one gutter after it, one baseline.
            logo.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: W.margin),
            logo.lastBaselineAnchor.constraint(equalTo: frame.topAnchor, constant: 44),
            label.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: W.gutter),
            label.lastBaselineAnchor.constraint(equalTo: logo.lastBaselineAnchor),
            title.topAnchor.constraint(equalTo: frame.topAnchor, constant: 96),
            title.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: W.column(1)),
            title.widthAnchor.constraint(equalToConstant: W.span(1, 5)),
            words.topAnchor.constraint(equalTo: frame.topAnchor, constant: 96 + SetupFrame.capAlignment),
            words.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: W.column(7)),
            words.widthAnchor.constraint(equalToConstant: width),
            // Continue on a row of its own at the foot, the same distance up as the wizard's cards, never moved by the words above.
            actions.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -W.margin),
            actions.bottomAnchor.constraint(equalTo: frame.bottomAnchor, constant: -40),
            actions.topAnchor.constraint(greaterThanOrEqualTo: words.bottomAnchor, constant: Design.beat(6)),
        ])
        win.contentView = frame
        NotificationCenter.default.addObserver(self, selector: #selector(answered), name: .permissionsChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Allowed: let the ink hairline be seen, then carry on.
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
