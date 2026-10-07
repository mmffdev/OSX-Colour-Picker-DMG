import AppKit

// ---------- The halo trainer: a setup's last step ----------
//
// The real halo, dead centre of the page, grown from a point once the page has arrived, with one
// line under it saying what to do next. Three moves and it is learned: turn the ring to Favourite and
// choose it, go deeper through Move To Palette, slide to confirm a Delete. Nothing it does reaches a
// catalogue or the clipboard. Built to serve every version of the app: hand it a colour and a name.

final class HaloTrainer: NSView {
    struct Lesson { let id: String; let text: String }
    static let lessons = [
        Lesson(id: "turn", text: "Scroll, or use the arrow keys, until Favourite sits under the wedge. Then click it, or press Return."),
        Lesson(id: "deeper", text: "Turn to Move To Palette and choose it. A ring grows outside the first: pick a palette on it."),
        Lesson(id: "confirm", text: "Turn to Delete and choose it, then slide across the centre. It is only practice, so nothing goes."),
    ]
    static let palettes = ["Brand", "Web", "Print", "Packaging", "Archive"]

    /// The lessons done so far, in the order they are listed.
    static func progress(_ learned: Set<String>) -> (done: Int, of: Int) { (lessons.filter { learned.contains($0.id) }.count, lessons.count) }

    private(set) var learned: Set<String> = []
    var allLearned: Bool { Self.progress(learned).done == Self.lessons.count }
    var onChange: (() -> Void)?

    private let name: String, hex: String
    private let halo: HaloMenu
    /// Where the dial opens: an unseen point in the middle, and a button over the dial's ground to open it again.
    private let anchor = NSView()
    private let reopen = SwissButton("Open The Halo Again", .quiet)
    /// What to do next, in the Body style, for the page to place beside the dial.
    let instruction = Design.text("", .body, wraps: true)
    private var favourite = false
    private var begun = false

    init(colour: NSColor, name: String, hex: String) {
        self.name = name
        self.hex = hex
        halo = HaloMenu(label: "Swatch", caption: name, hint: "Scroll to turn, click to choose", actions: [])
        super.init(frame: .zero)
        halo.actions = actions()
        halo.onOpenChange = { [weak self] open in self?.reopen.isHidden = open; self?.say() }
        reopen.target = self
        reopen.action = #selector(openHalo)
        reopen.isHidden = true
        instruction.preferredMaxLayoutWidth = Design.Wizard.span(1, 5)
        for v in [anchor, reopen] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            // The page's height less the actions row; the dial floats, so its outer ring may pass the edge.
            heightAnchor.constraint(equalToConstant: 400),
            anchor.centerXAnchor.constraint(equalTo: centerXAnchor), anchor.centerYAnchor.constraint(equalTo: centerYAnchor),
            anchor.widthAnchor.constraint(equalToConstant: 1), anchor.heightAnchor.constraint(equalToConstant: 1),
            reopen.centerXAnchor.constraint(equalTo: centerXAnchor), reopen.centerYAnchor.constraint(equalTo: anchor.centerYAnchor),
        ])
        say()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Opens the dial from its point, the first time the step is seen.
    func begin() {
        guard !begun else { return }
        begun = true
        openHalo()
    }

    /// Closes the halo, for when the step is left.
    func stop() { halo.close() }

    @objc private func openHalo() { if !halo.isOpen { halo.open(over: anchor) } }

    private func say(_ text: String? = nil) {
        let next = Self.lessons.first { !learned.contains($0.id) }
        let s = text ?? (allLearned ? "That is the halo. Every colour, palette and project has one." : next?.text ?? "")
        instruction.attributedStringValue = Design.attributed(s, .body, lineHeight: true)
    }

    private func actions() -> [HaloAction] {
        let say: (String) -> () -> Void = { [weak self] text in { self?.say(text) } }
        return [
            HaloAction(id: "copy", label: "Copy Hex", symbol: "doc.on.doc", description: "Put \(hex) on the clipboard",
                       onSelect: say("In the app that copies \(hex). Here the clipboard is left alone. Open it again and carry on.")),
            HaloAction(id: "rename", label: "Rename", symbol: "pencil",
                       edit: (name, name, "Return saves", { [weak self] t in self?.say("Renamed to \(t). Only practice.") })),
            HaloAction(id: "star", label: "Favourite", symbol: "star", checked: favourite,
                       onSelect: { [weak self] in self?.favouriteChosen() }),
            HaloAction(id: "share", label: "Share", symbol: "square.and.arrow.up", description: "Send it to someone",
                       onSelect: say("In the app, the share sheet opens here.")),
            HaloAction(id: "move", label: "Move To Palette", symbol: "folder", description: "Choose a palette", children: { [weak self] in
                Self.palettes.map { p in
                    HaloAction(id: p, label: p, symbol: "folder", description: "Move it here", onSelect: { [weak self] in
                        self?.learn("deeper")
                        self?.say("Moved to \(p). Only practice.")
                    })
                }
            }),
            HaloAction(id: "delete", label: "Delete", symbol: "trash", confirmation: ("Slide to delete", "Arrow keys slide, Return confirms"),
                       onSelect: { [weak self] in
                           guard let self = self else { return }
                           self.learn("confirm")
                           self.say("Deleted. Only practice: \(self.name) is still here.")
                       }),
        ]
    }

    private func favouriteChosen() {
        favourite.toggle()
        halo.actions = actions()
        learn("turn")
        say(favourite ? "Favourite. The dot beside it means it is on." : "Favourite is off again.")
    }

    func learn(_ id: String) {
        guard Self.lessons.contains(where: { $0.id == id }), !learned.contains(id) else { return }
        learned.insert(id)
        onChange?()
        if allLearned { say() }
    }
}
