import AppKit

// Run with: MMFFDevColour3 --halo-demo
// A window with four buttons, each wearing a halo, and a swatch card with its halo button, to try the dial before it is attached anywhere
// in the app. Add --snapshot <folder> to write a picture of each dial there and quit.

final class HaloDemo: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var halos: [HaloMenu] = []
    private var card: ColourCard?
    private let status = NSTextField(labelWithString: "Rest the pointer on a button, or press it for the keyboard.")

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Halo demo"
        let say: (String) -> () -> Void = { [weak self] text in { self?.status.stringValue = text } }

        let swatch = HaloMenu(label: "Swatch", caption: "#FF6600", hint: "Scroll or use the arrow keys", actions: [
            HaloAction(id: "copy", label: "Copy hex", symbol: "doc.on.doc", description: "Put #FF6600 on the clipboard", onSelect: say("Copied")),
            HaloAction(id: "rename", label: "Rename", symbol: "pencil",
                       edit: ("Trinidad", "Trinidad", "Return saves \u{00B7} Empty resets", { [weak self] in self?.status.stringValue = "Renamed to \($0)" })),
            HaloAction(id: "star", label: "Favourite", symbol: "star", checked: true, onSelect: say("Favourite")),
            HaloAction(id: "export", label: "Export", symbol: "square.and.arrow.up", description: "Nothing to export yet", disabled: true, onSelect: say("Export")),
            HaloAction(id: "move", label: "Move to palette", symbol: "folder", description: "Choose a palette", children: {
                ["Brand", "Web", "Print", "Packaging", "Archive"].map { name in
                    HaloAction(id: name, label: name, symbol: "folder", description: "Move to this palette", onSelect: say("Moved to \(name)"))
                } + [HaloAction(id: "new", label: "New palette", symbol: "plus", description: "Choose a kind", children: {
                    ["Blank", "Tints", "Shades", "Triad"].map { kind in
                        HaloAction(id: kind, label: kind, symbol: "square.grid.2x2", onSelect: say("New \(kind) palette"))
                    }
                })]
            }),
            HaloAction(id: "delete", label: "Delete", symbol: "trash", confirmation: ("Slide to delete", "Arrow keys slide, Return confirms"), onSelect: say("Deleted")),
        ])

        let palette = HaloMenu(label: "Palette", hint: "Choose what to do with it", actions: [
            HaloAction(id: "open", label: "Open", symbol: "arrow.up.right.square", onSelect: say("Open")),
            HaloAction(id: "share", label: "Share", symbol: "person.2", description: "Send to the team", onSelect: say("Share")),
            HaloAction(id: "duplicate", label: "Duplicate", symbol: "plus.square.on.square", onSelect: say("Duplicate")),
            HaloAction(id: "archive", label: "Archive", symbol: "archivebox", onSelect: say("Archive")),
        ])
        palette.typeBadge = (NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil) ?? NSImage(), "Palette", "Brand")

        let sort = HaloMenu(label: "Sort", caption: "Sort by", actions: ["Newest", "Oldest", "Hue", "Lightness", "Name"].map { name in
            HaloAction(id: name, label: name, symbol: "arrow.up.arrow.down", checked: name == "Hue", onSelect: say("Sorted by \(name)"))
        })
        sort.showPositions = true

        let details = HaloMenu(label: "Colour", actions: [
            HaloAction(id: "copy", label: "Copy", symbol: "doc.on.doc", description: "Copy every format", onSelect: say("Copied")),
            HaloAction(id: "pick", label: "Pick again", symbol: "eyedropper", onSelect: say("Pick")),
            HaloAction(id: "info", label: "Details", symbol: "info.circle", onSelect: say("Details")),
        ])
        details.metadata = [("Hex", "#FF6600"), ("RGB", "255, 102, 0"), ("Picked", "2 Oct 2026")]

        halos = [swatch, palette, sort, details]
        let row = NSStackView(views: zip(["Swatch", "Palette", "Sort", "Colour"], halos).map { title, halo in
            let button = NSButton(title: title, target: nil, action: nil)
            halo.attach(to: button)
            return button
        })
        row.spacing = 24
        // A real swatch card: its halo button opens the first dial in the middle of the window.
        let card = ColourCard()
        card.configure(hex: "#DD7157")
        card.onHalo = { [weak self] trigger in
            guard let self = self else { return }
            _ = self
            swatch.open(over: trigger)
        }
        self.card = card
        card.view.translatesAutoresizingMaskIntoConstraints = false
        card.view.widthAnchor.constraint(equalToConstant: 300).isActive = true
        card.view.heightAnchor.constraint(equalToConstant: ColourCard.height).isActive = true
        let column = NSStackView(views: [row, status, card.view])
        column.orientation = .vertical
        column.spacing = 16
        column.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            column.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24),
        ])
        window.center()
        let arguments = CommandLine.arguments
        // Taking pictures: stay behind whatever is in use.
        if arguments.contains("--snapshot") { window.orderBack(nil) } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        if let at = arguments.firstIndex(of: "--snapshot"), at + 1 < arguments.count {
            snapshot(into: URL(fileURLWithPath: arguments[at + 1]), row.views)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Opens each halo in turn, waits for it to settle, and saves what it drew.
    private func snapshot(into folder: URL, _ buttons: [NSView]) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var shots: [(name: String, prepare: () -> Void)] = []
        for (at, name) in ["swatch", "palette", "sort", "colour"].enumerated() {
            shots.append((name, { [weak self] in self?.halos[at].open(from: buttons[at]) }))
        }
        shots.append(("confirm", { [weak self] in
            self?.halos[0].open(from: buttons[0])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let dial = self?.window.childWindows?.first?.contentView
                let items = dial?.accessibilityChildren() as? [NSAccessibilityElement]
                _ = items?.first { $0.accessibilityLabel() == "Delete" }?.accessibilityPerformPress()
            }
        }))
        if let content = window.contentView, let image = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
            content.cacheDisplay(in: content.bounds, to: image)
            try? image.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("card.png"))
        }
        shots.append(("rename", { [weak self] in
            self?.halos[0].open(from: buttons[0])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let dial = self?.window.childWindows?.first?.contentView
                let items = dial?.accessibilityChildren() as? [NSAccessibilityElement]
                _ = items?.first { $0.accessibilityLabel() == "Rename" }?.accessibilityPerformPress()
            }
        }))
        // The rings that grow outside the first: opened over the card's own button, then one and two levels out.
        func press(_ labels: [String], after delay: TimeInterval = 0.4) {
            guard let label = labels.first else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                let dial = self?.window.childWindows?.first?.contentView
                let items = dial?.accessibilityChildren() as? [NSAccessibilityElement]
                _ = items?.first { $0.accessibilityLabel() == label }?.accessibilityPerformPress()
                press(Array(labels.dropFirst()), after: 0.3)
            }
        }
        shots.append(("ring2", { [weak self] in self?.card?.pressHalo(); press(["Move to palette"]) }))
        shots.append(("ring3", { [weak self] in self?.card?.pressHalo(); press(["Move to palette", "New palette"]) }))
        shots.append(("letters", { [weak self] in
            guard let self = self else { return }
            self.halos[0].actions = HaloSettingsPanel.letters(back: {})
            self.card?.pressHalo(); press(["Up", "Up"])
        }))
        shots.append(("ring2-growing", { [weak self] in self?.card?.pressHalo(); press(["Move to palette"], after: 1.12) }))
        func next(_ at: Int) {
            guard at < shots.count else { NSApp.terminate(nil); return }
            shots[at].prepare()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                if let dial = self?.window.childWindows?.first?.contentView, let image = dial.bitmapImageRepForCachingDisplay(in: dial.bounds) {
                    dial.cacheDisplay(in: dial.bounds, to: image)
                    try? image.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(shots[at].name).png"))
                }
                self?.halos.forEach { $0.close() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { next(at + 1) }
            }
        }
        next(0)
    }
}

func runHaloDemo() {
    let app = NSApplication.shared
    let delegate = HaloDemo()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
}
