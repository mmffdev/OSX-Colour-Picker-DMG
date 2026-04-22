import AppKit

// ---------- Shared helpers ----------

let shutterPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"

let libraryURL: URL = {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = support.appendingPathComponent("MMFFDev Colour")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("library.json")
}()

struct Swatch: Codable {
    let hex: String
    let pickedAt: Date
}

func loadLibrary() -> [Swatch] {
    guard let data = try? Data(contentsOf: libraryURL) else { return [] }
    let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
    return (try? d.decode([Swatch].self, from: data)) ?? []
}

func saveLibrary(_ swatches: [Swatch]) {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.prettyPrinted]
    if let data = try? e.encode(swatches) {
        try? data.write(to: libraryURL, options: .atomic)
    }
}

func playShutter() {
    let p = Process()
    p.launchPath = "/usr/bin/afplay"
    p.arguments = [shutterPath]
    try? p.run()
}

func copyToClipboard(_ s: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(s, forType: .string)
}

func hexOf(_ color: NSColor) -> String? {
    guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
    let r = Int(round(rgb.redComponent * 255))
    let g = Int(round(rgb.greenComponent * 255))
    let b = Int(round(rgb.blueComponent * 255))
    return String(format: "#%02X%02X%02X", r, g, b)
}

func colorFromHex(_ hex: String) -> NSColor? {
    var h = hex
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
    return NSColor(
        red: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: 1)
}

func appendPickToLibrary(_ hex: String) {
    var lib = loadLibrary()
    lib.removeAll { $0.hex.uppercased() == hex.uppercased() }
    lib.insert(Swatch(hex: hex, pickedAt: Date()), at: 0)
    saveLibrary(lib)
}

// ---------- Pick mode (hotkey-triggered) ----------

func runPickMode() -> Never {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)

    let sampler = NSColorSampler()
    let semaphore = DispatchSemaphore(value: 0)
    var picked: String?

    sampler.show { color in
        defer { semaphore.signal() }
        guard let color = color, let hex = hexOf(color) else { return }
        playShutter()
        copyToClipboard(hex)
        appendPickToLibrary(hex)
        picked = hex
    }

    while semaphore.wait(timeout: .now()) == .timedOut {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    if let h = picked { print(h); exit(0) }
    exit(1)
}

// ---------- Library mode (window) ----------

final class SwatchItem: NSCollectionViewItem {
    var hex: String = ""
    private let swatchView = NSView()
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        self.view = NSView()
        view.wantsLayer = true
        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 10
        swatchView.layer?.borderWidth = 1
        swatchView.layer?.borderColor = NSColor.separatorColor.cgColor
        view.addSubview(swatchView)
        label.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        view.addSubview(label)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let w = view.bounds.width
        let h = view.bounds.height
        let labelH: CGFloat = 16
        swatchView.frame = NSRect(x: 0, y: labelH + 4, width: w, height: h - labelH - 4)
        label.frame = NSRect(x: 0, y: 0, width: w, height: labelH)
    }

    override var isSelected: Bool {
        didSet {
            swatchView.layer?.borderWidth = isSelected ? 3 : 1
            swatchView.layer?.borderColor = (isSelected ? NSColor.controlAccentColor : .separatorColor).cgColor
        }
    }

    func configure(hex: String) {
        self.hex = hex
        label.stringValue = hex
        swatchView.layer?.backgroundColor = colorFromHex(hex)?.cgColor ?? NSColor.gray.cgColor
    }
}

final class GridCollectionView: NSCollectionView {
    weak var controller: LibraryWindowController?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { // delete, forward delete
            controller?.deleteSelected()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class LibraryWindowController: NSWindowController, NSCollectionViewDelegate, NSCollectionViewDataSource {
    private var library: [Swatch] = []
    private var collectionView: GridCollectionView!
    private var emptyLabel: NSTextField!
    private var countLabel: NSTextField!

    convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.title = "MMFFDev Colour"
        win.center()
        win.setFrameAutosaveName("MMFFDevColourMainWindow")
        self.init(window: win)
        build()
        reload()
        NotificationCenter.default.addObserver(
            self, selector: #selector(reloadOnFocus),
            name: NSWindow.didBecomeKeyNotification, object: win)
    }

    private func build() {
        guard let content = window?.contentView else { return }

        let toolbarHeight: CGFloat = 48
        let toolbar = NSView(frame: NSRect(x: 0, y: content.bounds.height - toolbarHeight,
                                           width: content.bounds.width, height: toolbarHeight))
        toolbar.autoresizingMask = [.width, .minYMargin]
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let pickBtn = NSButton(title: "Pick a Colour", target: self, action: #selector(pickFromWindow))
        pickBtn.bezelStyle = .rounded
        pickBtn.keyEquivalent = "p"
        pickBtn.keyEquivalentModifierMask = [.command]
        pickBtn.frame = NSRect(x: 16, y: 10, width: 140, height: 28)
        toolbar.addSubview(pickBtn)

        countLabel = NSTextField(labelWithString: "")
        countLabel.textColor = .secondaryLabelColor
        countLabel.font = NSFont.systemFont(ofSize: 12)
        countLabel.frame = NSRect(x: 170, y: 14, width: 300, height: 20)
        countLabel.autoresizingMask = [.width]
        toolbar.addSubview(countLabel)

        let divider = NSBox(frame: NSRect(x: 0, y: content.bounds.height - toolbarHeight - 1,
                                          width: content.bounds.width, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width, .minYMargin]

        content.addSubview(toolbar)
        content.addSubview(divider)

        // Scroll + collection
        let scrollFrame = NSRect(x: 0, y: 0,
                                 width: content.bounds.width,
                                 height: content.bounds.height - toolbarHeight - 1)
        let scroll = NSScrollView(frame: scrollFrame)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 100, height: 108)
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        layout.minimumInteritemSpacing = 14
        layout.minimumLineSpacing = 14

        let cv = GridCollectionView(frame: scroll.bounds)
        cv.controller = self
        cv.collectionViewLayout = layout
        cv.dataSource = self
        cv.delegate = self
        cv.isSelectable = true
        cv.allowsMultipleSelection = true
        cv.backgroundColors = [.clear]
        cv.register(SwatchItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("swatch"))

        let ctxMenu = NSMenu()
        ctxMenu.addItem(NSMenuItem(title: "Copy Hex", action: #selector(copySelected), keyEquivalent: "c"))
        ctxMenu.addItem(NSMenuItem(title: "Delete", action: #selector(deleteSelected), keyEquivalent: ""))
        ctxMenu.items.forEach { $0.target = self }
        cv.menu = ctxMenu

        scroll.documentView = cv
        content.addSubview(scroll)
        collectionView = cv

        emptyLabel = NSTextField(labelWithString: "No colours yet — press ⌃⌘C anywhere or click \u{201C}Pick a Colour\u{201D}.")
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.alignment = .center
        emptyLabel.frame = NSRect(
            x: 0, y: scrollFrame.height / 2 - 10,
            width: scrollFrame.width, height: 20)
        emptyLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        scroll.addSubview(emptyLabel)
    }

    @objc private func reloadOnFocus() { reload() }

    func reload() {
        library = loadLibrary()
        collectionView.reloadData()
        countLabel.stringValue = library.isEmpty ? "" : "\(library.count) colour\(library.count == 1 ? "" : "s")"
        emptyLabel.isHidden = !library.isEmpty
    }

    // MARK: Data source
    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection s: Int) -> Int { library.count }
    func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt ip: IndexPath) -> NSCollectionViewItem {
        let item = cv.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("swatch"), for: ip) as! SwatchItem
        item.configure(hex: library[ip.item].hex)
        return item
    }

    func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let ip = indexPaths.first else { return }
        let hex = library[ip.item].hex
        copyToClipboard(hex)
        playShutter()
    }

    // MARK: Actions
    @objc func copySelected() {
        guard let ip = collectionView.selectionIndexPaths.first else { return }
        copyToClipboard(library[ip.item].hex)
        playShutter()
    }

    @objc func deleteSelected() {
        let idxs = collectionView.selectionIndexPaths.map { $0.item }.sorted(by: >)
        guard !idxs.isEmpty else { return }
        for i in idxs where i < library.count { library.remove(at: i) }
        saveLibrary(library)
        reload()
    }

    @objc func pickFromWindow() {
        let sampler = NSColorSampler()
        sampler.show { [weak self] color in
            guard let color = color, let hex = hexOf(color) else { return }
            playShutter()
            copyToClipboard(hex)
            appendPickToLibrary(hex)
            self?.reload()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var wc: LibraryWindowController?
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)

        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "About MMFFDev Colour",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(
            title: "Quit MMFFDev Colour",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu

        wc = LibraryWindowController()
        wc?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

// ---------- Entry point ----------

if CommandLine.arguments.contains("--pick") {
    runPickMode()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
