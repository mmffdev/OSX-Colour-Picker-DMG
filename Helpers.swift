import AppKit
import UniformTypeIdentifiers

let shutterPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"

func playShutter() {
    guard Prefs.sounds else { return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
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
    guard let (r, g, b) = rgbComponents(hex) else { return nil }
    return NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
}

func plural(_ n: Int, _ word: String, _ many: String? = nil) -> String {
    "\(n) \(n == 1 ? word : (many ?? word + "s"))"
}

func symbol(_ name: String, _ description: String, size: CGFloat? = nil, weight: NSFont.Weight = .regular) -> NSImage {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
    guard let size = size else { return image }
    return image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: weight)) ?? image
}

func symbolButton(_ name: String, tooltip: String, target: AnyObject, action: Selector) -> NSButton {
    let b = NSButton(image: symbol(name, tooltip), target: target, action: action)
    b.isBordered = false
    b.toolTip = tooltip
    b.setAccessibilityLabel(tooltip)
    b.contentTintColor = .secondaryLabelColor
    return b
}

/// The app's type scale, Apple's: 13 for anything read, 11 for labels over fields and captions,
/// never smaller; 20 for a page title. Text drawn inside swatch tiles is sized to fit and is the one exception.
enum TextSize {
    static let title: CGFloat = 22
    static let body: CGFloat = 13
    static let caption: CGFloat = 11
}

func caption(_ s: String, size: CGFloat = TextSize.caption) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.textColor = .secondaryLabelColor
    l.font = NSFont.systemFont(ofSize: size)
    l.lineBreakMode = .byTruncatingTail
    return l
}

/// Looks like the other pop-up buttons in a bar, but a press runs its action instead of opening
/// a menu — for a popover that has to stay open while several things are ticked.
final class PopoverButton: NSPopUpButton {
    init(title: String) {
        super.init(frame: .zero, pullsDown: true)
        addItem(withTitle: title)
        controlSize = .small
        font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if let action = action { NSApp.sendAction(action, to: target, from: self) }
    }
}

/// A popover holding a column of tick boxes, left edges in line, with room around them.
func tickPopover(_ boxes: [NSButton]) -> NSPopover {
    let column = NSStackView(views: boxes)
    column.orientation = .vertical
    column.alignment = .leading
    column.spacing = 8
    column.translatesAutoresizingMaskIntoConstraints = false
    let holder = NSViewController()
    holder.view = NSView()
    holder.view.addSubview(column)
    NSLayoutConstraint.activate([
        column.topAnchor.constraint(equalTo: holder.view.topAnchor, constant: 14),
        column.bottomAnchor.constraint(equalTo: holder.view.bottomAnchor, constant: -14),
        column.leadingAnchor.constraint(equalTo: holder.view.leadingAnchor, constant: 16),
        column.trailingAnchor.constraint(equalTo: holder.view.trailingAnchor, constant: -22),
    ])
    let popover = NSPopover()
    popover.contentViewController = holder
    popover.contentSize = holder.view.fittingSize
    popover.behavior = .transient
    return popover
}

func hairline() -> NSBox {
    let b = NSBox()
    b.boxType = .separator
    // Without a height of its own, a tall window can stretch the line and squeeze its neighbour to nothing.
    b.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return b
}

/// A colour that stands for one palette wherever it appears — the bars under tiles and the dots
/// in the halo. Taken from the palette's id, so it never changes when the palette's contents do.
func identityColour(_ id: UUID) -> NSColor {
    let u = id.uuid
    let bytes = [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
    let seed = bytes.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
    let hue = CGFloat(seed % 360) / 360
    let lift = CGFloat((seed >> 9) % 3) * 0.08
    return NSColor(hue: hue, saturation: 0.62 - lift, brightness: 0.78 + lift, alpha: 1)
}

// ---------- Exports drawn with AppKit ----------

extension ExportPalette {
    /// A colour list the system colour panel understands.
    func colourList() -> NSColorList {
        let list = NSColorList(name: name)
        var taken: [String] = []
        for c in colours {
            guard let colour = colorFromHex(c.hex) else { continue }
            let key = uniqueName(c.name, among: taken)
            taken.append(key)
            list.setColor(colour, forKey: key)
        }
        return list
    }
}

/// A sheet of labelled tiles, for decks, mood boards and sharing.
func swatchSheet(_ palettes: [ExportPalette], scale: CGFloat = 2) -> Data? {
    let tile = NSSize(width: 150, height: 150), pad: CGFloat = 24, titleH: CGFloat = 40
    let perRow = max(1, min(6, palettes.map { $0.colours.count }.max() ?? 1))
    func rows(_ p: ExportPalette) -> Int { max(1, Int(ceil(Double(p.colours.count) / Double(perRow)))) }
    let width = pad * 2 + CGFloat(perRow) * tile.width
    let height = pad + palettes.reduce(CGFloat(0)) { $0 + titleH + CGFloat(rows($1)) * tile.height + pad }

    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.cgContext.scaleBy(x: scale, y: scale) // draw in points, store at 2x
    defer { NSGraphicsContext.restoreGraphicsState() }

    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let ink = NSColor(white: 0.12, alpha: 1)
    var y = height - pad
    for p in palettes {
        y -= titleH
        (p.name as NSString).draw(at: NSPoint(x: pad, y: y + 10),
                                  withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: ink])
        for (i, c) in p.colours.enumerated() {
            let col = i % perRow, row = i / perRow
            let cell = NSRect(x: pad + CGFloat(col) * tile.width, y: y - CGFloat(row + 1) * tile.height,
                              width: tile.width, height: tile.height)
            let chip = NSRect(x: cell.minX, y: cell.minY + 44, width: tile.width - 10, height: tile.height - 54)
            (colorFromHex(c.hex) ?? .gray).setFill()
            NSBezierPath(roundedRect: chip, xRadius: 8, yRadius: 8).fill()
            NSColor(white: 0, alpha: 0.12).setStroke()
            NSBezierPath(roundedRect: chip.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
            (c.name as NSString).draw(in: NSRect(x: cell.minX, y: cell.minY + 22, width: tile.width - 10, height: 18),
                                      withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: ink])
            (c.hex as NSString).draw(in: NSRect(x: cell.minX, y: cell.minY + 6, width: tile.width - 10, height: 16),
                                     withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                                                      .foregroundColor: NSColor(white: 0.4, alpha: 1)])
        }
        y -= CGFloat(rows(p)) * tile.height + pad
    }
    return rep.representation(using: .png, properties: [:])
}

/// Writes any export format, including the two that need AppKit.
func writeExport(_ format: ExportFormat, _ palettes: [ExportPalette], to url: URL, options: ExportOptions) throws {
    switch format {
    case .clr:
        let merged = palettes.count == 1 ? palettes[0]
            : ExportPalette(name: url.deletingPathExtension().lastPathComponent, colours: palettes.flatMap { $0.colours })
        try merged.colourList().write(to: url)
    case .png:
        guard let data = swatchSheet(palettes) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
    default:
        guard let data = format.data(palettes, options: options) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
    }
}

// ---------- Copying into folders the system owns ----------

enum AdminCopy { case copied, cancelled }

/// Copies files into `folder`, replacing any of the same name. First directly, which works where the
/// user may write (including Adobe folders they have unlocked). Then through the Adobe helper, if it is
/// on and the folder is one of Adobe's. Failing both, macOS is asked to do the copy as an administrator:
/// it shows its own password dialog, and the password never reaches this app.
func copyIntoFolder(_ files: [URL], _ folder: URL, prompt: String) throws -> AdminCopy {
    let fm = FileManager.default
    do {
        for f in files {
            let to = folder.appendingPathComponent(f.lastPathComponent)
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            try fm.copyItem(at: f, to: to)
        }
        return .copied
    } catch CocoaError.fileWriteNoPermission {
    } catch let e as NSError where e.domain == NSPOSIXErrorDomain && (e.code == EACCES || e.code == EPERM) {
    }
    if AdobeHelper.install(files, into: folder) { return .copied }
    return try runAsAdministrator(["/bin/cp", "-f"] + files.map { $0.path } + [folder.path + "/"], prompt: prompt)
}

/// Runs one command as an administrator through macOS's own password dialog. Every word is passed
/// through AppleScript's "quoted form of", so no name, however odd, can be read by the shell as
/// anything but a word. The command is the only thing ever run with those rights.
func runAsAdministrator(_ words: [String], prompt: String) throws -> AdminCopy {
    func literal(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
    let source = "do shell script " + words.map { "quoted form of " + literal($0) }.joined(separator: " & \" \" & ")
        + " with prompt " + literal(prompt) + " with administrator privileges"
    var failure: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&failure)
    guard let failure = failure else { return .copied }
    if failure[NSAppleScript.errorNumber] as? Int == -128 { return .cancelled } // the user pressed Cancel
    throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [
        NSLocalizedDescriptionKey: "macOS would not run that as an administrator.",
        NSLocalizedRecoverySuggestionErrorKey: failure[NSAppleScript.errorMessage] as? String ?? ""])
}

/// One menu item per place an installed Adobe app keeps its libraries, each carrying an `AdobeSend`.
func adobeMenuItem(target: AnyObject, action: Selector, palette: UUID? = nil) -> NSMenuItem {
    let item = NSMenuItem(title: "Add To Adobe Apps", action: nil, keyEquivalent: "")
    let menu = NSMenu()
    for d in AdobeDestination.installed() {
        let i = menu.addItem(withTitle: d.title, action: action, keyEquivalent: "")
        i.target = target
        i.representedObject = AdobeSend(destination: d, palette: palette)
    }
    if menu.items.isEmpty { menu.addItem(withTitle: "No Adobe Apps Found", action: nil, keyEquivalent: "") }
    item.submenu = menu
    return item
}

struct AdobeSend {
    let destination: AdobeDestination
    /// nil for whatever the window is showing.
    let palette: UUID?
}

// ---------- Design pack files and git ----------

/// A plain square of the colour. The name and hex live in the file name, README and pack.json.
func swatchSquare(_ hex: String, size: Int = 512) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    (colorFromHex(hex) ?? .gray).setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

/// Writes the whole pack into a new folder under `parent`. Never overwrites an earlier pack.
func writeDesignPack(_ pack: DesignPack, into parent: URL, options: ExportOptions) throws -> URL {
    let fm = FileManager.default
    let existing = (try? fm.contentsOfDirectory(atPath: parent.path)) ?? []
    let root = parent.appendingPathComponent(uniqueName(pack.folderName, among: existing))
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    for (path, text) in pack.textFiles(options: options) {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    for p in pack.palettes {
        if let sheet = swatchSheet([p.export]) { try sheet.write(to: root.appendingPathComponent(p.sheet), options: .atomic) }
        for s in p.swatches {
            let url = root.appendingPathComponent(s.file)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let png = swatchSquare(s.hex) { try png.write(to: url, options: .atomic) }
        }
    }
    if let proof = swatchSheet(pack.palettes.map { $0.export }) { try proof.write(to: root.appendingPathComponent("proof-sheet.png"), options: .atomic) }
    return root
}

private let gitPath = "/usr/bin/git"
var gitAvailable: Bool { FileManager.default.isExecutableFile(atPath: gitPath) }

@discardableResult
private func runGit(_ args: [String], in dir: URL) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: gitPath)
    p.arguments = args
    p.currentDirectoryURL = dir
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
}

/// The repository the folder sits in, if any.
func gitRoot(of folder: URL) -> URL? {
    guard gitAvailable else { return nil }
    let r = runGit(["rev-parse", "--show-toplevel"], in: folder)
    return r.status == 0 && !r.output.isEmpty ? URL(fileURLWithPath: r.output) : nil
}

/// Stages the pack, commits it and pushes the current branch. Reports the first thing that goes wrong.
func gitCommitAndPush(repo: URL, path: URL, message: String) -> (ok: Bool, message: String) {
    for args in [["add", "--", path.path], ["commit", "-m", message, "--", path.path], ["push"]] {
        let r = runGit(args, in: repo)
        if r.status != 0 { return (false, "git \(args[0]): \(r.output.isEmpty ? "failed" : r.output)") }
    }
    return (true, "pushed")
}

// ---------- Grid shared by the palette page and All Swatches ----------

final class SwatchGridView: NSCollectionView {
    /// A plain click on a tile, including one that is already selected.
    var onClick: ((IndexPath) -> Void)?
    var onDelete: (() -> Void)?
    var onCopy: (() -> Void)?
    var onFavourite: (() -> Void)?
    /// A double-click on a tile; return true to take it, so it does nothing else.
    var onDoubleClick: ((IndexPath, NSEvent) -> Bool)?
    /// Where a shift-click measures its run from: the last tile clicked without Shift.
    private var anchor: IndexPath?
    /// When set, a click adds or removes the tile instead of selecting it.
    var onToggle: ((IndexPath) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let hit = indexPathForItem(at: p)
        if let toggle = onToggle {
            if let ip = hit { toggle(ip) }
            return
        }
        let held = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if event.clickCount == 2, let ip = hit, onDoubleClick?(ip, event) == true { return }
        // Shift-click takes every tile from the last one clicked to this one, in reading order.
        if held == .shift, let to = hit, let from = anchor ?? selectionIndexPaths.min(by: { $0.item < $1.item }),
           from.item < numberOfItems(inSection: 0) {
            let run = Set((min(from.item, to.item)...max(from.item, to.item)).map { IndexPath(item: $0, section: 0) })
            window?.makeFirstResponder(self)
            selectionIndexPaths = run
            delegate?.collectionView?(self, didSelectItemsAt: run)
            return
        }
        if hit != nil { anchor = hit }
        let plain = held.isEmpty
        super.mouseDown(with: event)
        if let ip = hit, plain, selectionIndexPaths.contains(ip) { onClick?(ip) }
    }

    override func keyDown(with event: NSEvent) {
        let held = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 51 || event.keyCode == 117 { onDelete?() } // delete, forward delete
        else if event.keyCode == 3, held == .shift, let star = onFavourite { star() } // shift-F
        else { super.keyDown(with: event) }
    }

    // Right-click acts on the tile under the pointer, not a stale selection.
    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        if let ip = indexPathForItem(at: p), !selectionIndexPaths.contains(ip) {
            deselectAll(nil)
            selectItems(at: [ip], scrollPosition: [])
        }
        return super.menu(for: event)
    }

    @objc func copy(_ sender: Any?) { onCopy?() }

    // Tiles are cheap, so a good stretch beyond the visible part is kept ready; scrolling then
    // moves over finished tiles instead of building each one as it comes into view.
    override func prepareContent(in rect: NSRect) {
        let ahead = max(visibleRect.height * 3, 1500)
        super.prepareContent(in: rect.insetBy(dx: 0, dy: -ahead).intersection(bounds))
    }
}

/// An even grid: as many columns as fit, each item stretched so the row is filled. Every frame
/// is worked out here from the visible width, and again whenever that width changes — window
/// resize, sidebar, builder rail.
final class GridLayout: NSCollectionViewLayout {
    /// Items are never narrower than this; they widen to fill the row.
    var minimumWidth: CGFloat = 100
    /// Between items, across and down. Zero makes neighbours touch.
    var spacing: CGFloat = 0
    var margins = NSEdgeInsets(top: 10, left: 14, bottom: 20, right: 14)
    /// Item width in, item height out.
    var height: (CGFloat) -> CGFloat = { $0 }

    private var frames: [NSRect] = []
    private var size = NSSize.zero
    private var width: CGFloat = 0

    /// The scroll view's visible width. The grid's own width can lag behind it while panes open and close.
    private var visibleWidth: CGFloat {
        collectionView?.enclosingScrollView?.contentView.bounds.width ?? collectionView?.bounds.width ?? 0
    }

    override func prepare() {
        super.prepare()
        guard let cv = collectionView else { return }
        width = visibleWidth
        let count = cv.numberOfSections > 0 ? cv.numberOfItems(inSection: 0) : 0
        let usable = max(minimumWidth, width - margins.left - margins.right)
        let columns = max(1, Int((usable + spacing) / (minimumWidth + spacing)))
        let w = floor((usable - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        let h = height(w).rounded()
        let used = w * CGFloat(columns) + spacing * CGFloat(columns - 1)
        let left = max(0, floor((width - used) / 2))
        frames = (0..<count).map { i in
            NSRect(x: left + CGFloat(i % columns) * (w + spacing),
                   y: margins.top + CGFloat(i / columns) * (h + spacing), width: w, height: h)
        }
        let rows = CGFloat((count + columns - 1) / columns)
        size = NSSize(width: width, height: margins.top + rows * h + max(0, rows - 1) * spacing + margins.bottom)
    }

    override var collectionViewContentSize: NSSize { size }

    private func attributes(_ i: Int) -> NSCollectionViewLayoutAttributes {
        let a = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: i, section: 0))
        a.frame = frames[i]
        return a
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        frames.indices.filter { frames[$0].intersects(rect) }.map(attributes)
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        frames.indices.contains(indexPath.item) ? attributes(indexPath.item) : nil
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        abs(visibleWidth - width) > 0.5
    }

    /// Call when the page is laid out. The visible width can change while the grid's own bounds
    /// do not — a grid first measured before the window had its size stays zero wide, and blank.
    func fitVisibleWidth() {
        if abs(visibleWidth - width) > 0.5 { invalidateLayout() }
    }
}

/// A scroll view that reports when the user keeps scrolling past either end.
final class PagingScrollView: NSScrollView {
    /// +1 past the bottom, -1 past the top.
    var onPage: ((Int) -> Void)?
    private var pushed: CGFloat = 0
    private var lastPage = Date.distantPast

    override func scrollWheel(with event: NSEvent) {
        guard let page = onPage, Prefs.wheelChangesPalette, let doc = documentView, event.momentumPhase == [] else {
            super.scrollWheel(with: event)
            return
        }
        let visible = contentView.bounds
        let room = doc.frame.height - visible.height
        let atTop = visible.minY <= 0.5, atBottom = visible.minY >= room - 0.5
        let dy = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12)
        let outward = (dy > 0 && atTop) || (dy < 0 && atBottom)

        guard outward else {
            pushed = 0
            super.scrollWheel(with: event)
            return
        }
        if event.phase == .began { pushed = 0 }
        pushed += dy
        // One palette per push: a firm scroll, then a pause before the next.
        if abs(pushed) > 70, Date().timeIntervalSince(lastPage) > 0.45 {
            lastPage = Date()
            let direction = pushed < 0 ? 1 : -1
            pushed = 0
            page(direction)
        }
    }
}

// ---------- Drop target ----------

/// Shown over the content while an image is being dragged in: grey dashed frame, icon, caption.
final class DropOverlayView: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "Drop image to create a palette")

    override init(frame: NSRect) {
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
        icon.image = symbol("square.and.arrow.down", "Drop here", size: 54, weight: .light)
        icon.contentTintColor = .secondaryLabelColor
        label.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    // Never takes clicks or drags away from what is underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        bounds.fill()
        let frame = NSBezierPath(roundedRect: bounds.insetBy(dx: 18, dy: 18), xRadius: 16, yRadius: 16)
        NSColor.gray.withAlphaComponent(0.10).setFill()
        frame.fill()
        frame.lineWidth = 2
        frame.setLineDash([10, 7], count: 2, phase: 0)
        NSColor.gray.setStroke()
        frame.stroke()
    }
}

/// A view that accepts image files dragged in from Finder.
final class DropTargetView: NSView {
    var onDropImage: ((URL) -> Void)?
    private let overlay = DropOverlayView(frame: .zero)

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func imageURL(in info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]) as? [URL]
        return urls?.first
    }

    private func setOverlay(visible: Bool) {
        if visible {
            overlay.frame = bounds
            addSubview(overlay, positioned: .above, relativeTo: nil)
        } else {
            overlay.removeFromSuperview()
        }
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation {
        guard imageURL(in: info) != nil else { return [] }
        setOverlay(visible: true)
        return .copy
    }

    override func draggingExited(_ info: NSDraggingInfo?) { setOverlay(visible: false) }
    override func draggingEnded(_ info: NSDraggingInfo) { setOverlay(visible: false) }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        setOverlay(visible: false)
        guard let url = imageURL(in: info) else { return false }
        onDropImage?(url)
        return true
    }
}
