import AppKit

// ---------- The halo trainer: a setup's last step ----------
//
// A practice swatch wearing the real halo, and four lessons beside it that tick as they are done:
// open it, turn the ring to Favourite and choose it, go deeper through Move To Palette, and slide to
// confirm a Delete. Nothing it does reaches a catalogue or the clipboard. Built to serve every
// version of the app: hand it a colour, its name and its hex.

final class HaloTrainer: NSView {
    struct Lesson { let id: String; let title: String; let text: String }
    static let lessons = [
        Lesson(id: "open", title: "Open It", text: "Rest the pointer on the round button on the swatch, or click it."),
        Lesson(id: "turn", title: "Turn The Ring", text: "Scroll, or use the arrow keys, until Favourite sits under the wedge. Then choose it."),
        Lesson(id: "deeper", title: "Go Deeper", text: "Choose Move To Palette. A ring grows outside the first: pick a palette on it."),
        Lesson(id: "confirm", title: "Slide To Confirm", text: "Choose Delete, then slide across the centre. It is only practice, so nothing goes."),
    ]
    static let palettes = ["Brand", "Web", "Print", "Packaging", "Archive"]

    /// The lessons done so far, in the order they are listed.
    static func progress(_ learned: Set<String>) -> (done: Int, of: Int) { (lessons.filter { learned.contains($0.id) }.count, lessons.count) }

    private(set) var learned: Set<String> = []
    var allLearned: Bool { Self.progress(learned).done == Self.lessons.count }
    var onChange: (() -> Void)?

    private let colour: NSColor, name: String, hex: String
    private let halo: HaloMenu
    private let trigger = NSButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var rows: [LessonRow] = []
    private var favourite = false

    init(colour: NSColor, name: String, hex: String) {
        self.colour = colour
        self.name = name
        self.hex = hex
        halo = HaloMenu(label: "Swatch", caption: name, hint: "Scroll to turn, click to choose", actions: [])
        super.init(frame: .zero)
        halo.actions = actions()
        halo.onOpenChange = { [weak self] open in if open { self?.learn("open") } }

        let swatch = PracticeSwatch(colour: colour, name: name, hex: hex, trigger: trigger)
        self.swatch = swatch
        trigger.isBordered = false
        trigger.image = symbol("smallcircle.filled.circle", "Open the halo", size: 15)
        trigger.contentTintColor = .labelColor
        trigger.toolTip = "Open the halo"
        // As on a palette page: a rest or a press opens the halo with its centre on the swatch.
        trigger.target = self
        trigger.action = #selector(openHalo)
        trigger.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))

        let stage = NSView()
        stage.wantsLayer = true
        stage.layer?.cornerRadius = 14
        stage.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
        swatch.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(swatch)

        status.font = NSFont.systemFont(ofSize: TextSize.caption)
        status.textColor = .secondaryLabelColor
        status.alignment = .center
        status.preferredMaxLayoutWidth = 280
        status.stringValue = "The halo opens in the middle of the swatch."

        let left = NSStackView(views: [stage, status])
        left.orientation = .vertical
        left.spacing = 10

        rows = Self.lessons.enumerated().map { LessonRow(number: $0.offset + 1, lesson: $0.element) }
        let list = NSStackView(views: rows)
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 6

        let row = NSStackView(views: [left, list])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 28
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            stage.widthAnchor.constraint(equalToConstant: 280), stage.heightAnchor.constraint(equalToConstant: 230),
            swatch.centerXAnchor.constraint(equalTo: stage.centerXAnchor), swatch.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            status.widthAnchor.constraint(equalToConstant: 280),
            list.widthAnchor.constraint(equalToConstant: 380),
        ])
        paint()
    }
    required init?(coder: NSCoder) { fatalError() }

    private weak var swatch: NSView?

    /// Closes the halo, for when the step is left.
    func stop() { halo.close() }

    @objc private func openHalo() { if !halo.isOpen, let s = swatch { halo.open(over: s) } }
    override func mouseEntered(with event: NSEvent) { openHalo() }

    private func actions() -> [HaloAction] {
        let say: (String) -> () -> Void = { [weak self] text in { self?.say(text) } }
        return [
            HaloAction(id: "copy", label: "Copy Hex", symbol: "doc.on.doc", description: "Put \(hex) on the clipboard",
                       onSelect: say("In the app that copies \(hex). Here the clipboard is left alone.")),
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

    private func say(_ text: String) { status.stringValue = text }

    func learn(_ id: String) {
        guard Self.lessons.contains(where: { $0.id == id }), !learned.contains(id) else { return }
        learned.insert(id)
        paint()
        onChange?()
    }

    private func paint() {
        let now = Self.lessons.firstIndex { !learned.contains($0.id) }
        for (i, r) in rows.enumerated() { r.set(done: learned.contains(Self.lessons[i].id), current: i == now) }
        if allLearned { say("That is the halo. Every colour, palette and project has one.") }
    }
}

/// A swatch as the app draws one: the colour, then its name and hex, and the round button that opens its halo.
private final class PracticeSwatch: NSView {
    private let colour: NSColor, name: String, hex: String

    init(colour: NSColor, name: String, hex: String, trigger: NSButton) {
        self.colour = colour
        self.name = name
        self.hex = hex
        super.init(frame: NSRect(x: 0, y: 0, width: 150, height: 130))
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = false
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        trigger.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trigger)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 150), heightAnchor.constraint(equalToConstant: 130),
            trigger.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            trigger.topAnchor.constraint(equalTo: topAnchor, constant: 56),
            trigger.widthAnchor.constraint(equalToConstant: 22), trigger.heightAnchor.constraint(equalToConstant: 22),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        card.fill()
        NSGraphicsContext.saveGraphicsState()
        card.addClip()
        colour.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 84).fill()
        NSGraphicsContext.restoreGraphicsState()
        // The button sits on the colour: a disc of the card's own ground behind it.
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.width - 31, y: 55, width: 24, height: 24)).fill()
        (name as NSString).draw(at: NSPoint(x: 10, y: 91), withAttributes: [.font: NSFont.systemFont(ofSize: TextSize.body, weight: .semibold), .foregroundColor: NSColor.labelColor])
        (hex as NSString).draw(at: NSPoint(x: 10, y: 109), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        card.lineWidth = 1
        card.stroke()
    }
}

/// One lesson: a numbered circle that turns to a green tick when done, its name and what to do.
private final class LessonRow: NSView {
    private let tick: LessonTick
    private let title: NSTextField
    private let text: NSTextField

    init(number: Int, lesson: HaloTrainer.Lesson) {
        tick = LessonTick(number: number)
        title = NSTextField(labelWithString: lesson.title)
        title.font = NSFont.systemFont(ofSize: TextSize.body, weight: .semibold)
        text = NSTextField(wrappingLabelWithString: lesson.text)
        text.font = NSFont.systemFont(ofSize: TextSize.caption)
        text.textColor = .secondaryLabelColor
        text.preferredMaxLayoutWidth = 320
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        let words = NSStackView(views: [title, text])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 2
        let row = NSStackView(views: [tick, words])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: 380),
            text.widthAnchor.constraint(equalToConstant: 320),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private var current = false
    func set(done: Bool, current: Bool) {
        let newlyDone = done && !tick.done
        tick.done = done
        tick.current = current
        self.current = current
        alphaValue = done || current ? 1 : 0.55
        needsDisplay = true
        if newlyDone, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let l = tick.layer {
            let pop = CABasicAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.6; pop.toValue = 1
            pop.duration = 0.35
            pop.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.4)
            l.add(pop, forKey: "pop")
        }
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = current ? NSColor.labelColor.withAlphaComponent(0.05).cgColor : NSColor.clear.cgColor
    }
}

private final class LessonTick: NSView {
    let number: Int
    var done = false { didSet { needsDisplay = true } }
    var current = false { didSet { needsDisplay = true } }

    init(number: Int) {
        self.number = number
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        wantsLayer = true
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 22), heightAnchor.constraint(equalToConstant: 22)])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let disc = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        let mark: String
        let ink: NSColor
        if done {
            NSColor.systemGreen.setFill(); disc.fill()
            mark = "\u{2713}"; ink = .white
        } else {
            (current ? Brand.master : NSColor.labelColor.withAlphaComponent(0.2)).setStroke()
            disc.lineWidth = 1.5; disc.stroke()
            mark = "\(number)"; ink = current ? .labelColor : .secondaryLabelColor
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: TextSize.caption, weight: .semibold), .foregroundColor: ink]
        let s = (mark as NSString).size(withAttributes: attrs)
        (mark as NSString).draw(at: NSPoint(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2), withAttributes: attrs)
    }
}
