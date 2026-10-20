import AppKit

/// Shared note access. Native palettes carry notes in .colpal; external files use adjacent .colcar sidecars.
enum AssetNotes {
    typealias Record = AssetNote

    private struct Sidecar: Codable {
        var format = "colorgain-asset-sidecar"
        var version = 1
        var notes: Record?
    }
    private struct LooseSidecar: Codable {
        var format = "colorgain-loose-notes"
        var version = 1
        var records: [String: Record]
    }
    private static var records: [String: Record] = [:]
    private static var loaded = Set<String>()
    private static var sidecarCheckedAt:[String:Date]=[:]
    private static var sidecarVersions:[String:String]=[:]
    private static var pendingSidecars=Set<String>()
    private static var sidecarErrors:[String:String]=[:]
    private static var fileOrder:[String]=[]
    private static var looseRecords: [String: Record]?
    private static var looseURL: URL = {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("Colorgain",isDirectory:true).appendingPathComponent("Loose Assets.colcar")
    }()
    static func configureLooseStore(beside catalogue: URL) {
        let target=catalogue.deletingLastPathComponent().appendingPathComponent("Loose Assets.colcar")
        guard target.standardizedFileURL != looseURL.standardizedFileURL else { return }
        looseURL=target;looseRecords=nil;records.removeAll();loaded.removeAll()
    }

    static func key(for item: TileGrid.Item, palette: UUID? = nil, scope: String? = nil) -> String? {
        if let path = item.imagePath { return "file:" + URL(fileURLWithPath: path).standardizedFileURL.path }
        if let id = item.id { return "asset:" + id.uuidString }
        if let hex = item.hex { return "colour:" + (palette?.uuidString ?? scope ?? "library") + ":" + hex.uppercased() }
        if let identity = item.selectionID { return "asset-key:" + (scope ?? "library") + ":" + identity }
        return item.title.isEmpty ? nil : "named:" + (scope ?? "library") + ":" + item.title
    }
    static func cache(_ record: Record?, for key: String) {
        records[key] = record
        loaded.insert(key)
    }
    private static func sidecar(for key: String) -> URL? {
        guard key.hasPrefix("file:") else { return nil }
        return URL(fileURLWithPath: String(key.dropFirst(5)) + ".colcar")
    }
    private static func version(of url:URL)->String? {
        guard let attributes=try? FileManager.default.attributesOfItem(atPath:url.path),
              let size=attributes[.size] as? NSNumber else{return nil}
        return "\(size.intValue)|\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
    }
    /// Drawing never opens a file. Visible file notes are checked on a worker and repainted
    /// when their sidecar version changes; a short TTL also notices Finder edits.
    static func hasNoteForDrawing(_ key:String,changed:@escaping()->Void)->Bool {
        guard let url=sidecar(for:key) else{return loaded.contains(key) && records[key]?.hasContent == true}
        let known=records[key]?.hasContent == true
        if let checked=sidecarCheckedAt[key],Date().timeIntervalSince(checked)<10{return known}
        guard pendingSidecars.insert(key).inserted else{return known}
        DispatchQueue.global(qos:.utility).async {
            let attributes=try? FileManager.default.attributesOfItem(atPath:url.path)
            let size=(attributes?[.size] as? NSNumber)?.intValue ?? 0
            let version="\(size)|\((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
            let record:Record?
            let issue:String?
            if size > 2*1024*1024 {record=nil;issue="The note sidecar exceeds 2 MB."}
            else if size > 0 {
                if let data=try? Data(contentsOf:url),data.count <= 2*1024*1024,
                   let decoded=try? JSONDecoder().decode(Sidecar.self,from:data) {record=decoded.notes;issue=nil}
                else{record=nil;issue="The note sidecar could not be read."}
            } else {record=nil;issue=nil}
            DispatchQueue.main.async {
                pendingSidecars.remove(key)
                sidecarCheckedAt[key]=Date()
                guard sidecarVersions[key] != version || !loaded.contains(key) else{return}
                sidecarVersions[key]=version
                sidecarErrors[key]=issue
                let firstLoad = !loaded.contains(key)
                records[key]=record;loaded.insert(key)
                if firstLoad {fileOrder.append(key)}
                if fileOrder.count > 2048 {
                    for old in fileOrder.prefix(512) {
                        loaded.remove(old);records.removeValue(forKey:old);sidecarVersions.removeValue(forKey:old)
                        sidecarCheckedAt.removeValue(forKey:old);sidecarErrors.removeValue(forKey:old)
                    }
                    fileOrder.removeFirst(512)
                }
                changed()
            }
        }
        return known
    }
    static func record(_ key: String) -> Record? {
        if loaded.contains(key) { return records[key] }
        loaded.insert(key)
        if let url = sidecar(for:key) {
            guard FileManager.default.fileExists(atPath:url.path) else{return nil}
            guard let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size <= 2*1024*1024,
                  let data = try? Data(contentsOf:url), let sidecar = try? JSONDecoder().decode(Sidecar.self,from:data) else {
                sidecarErrors[key]="The note sidecar is too large or damaged. The original file was preserved."
                return nil
            }
            sidecarErrors.removeValue(forKey:key)
            sidecarVersions[key]=version(of:url)
            sidecarCheckedAt[key]=Date()
            records[key] = sidecar.notes
            return sidecar.notes
        }
        if looseRecords == nil { looseRecords=(try? Data(contentsOf:looseURL)).flatMap{try? JSONDecoder().decode(LooseSidecar.self,from:$0).records} ?? [:] }
        records[key]=looseRecords?[key]
        return looseRecords?[key]
    }
    static func hasNote(_ key: String) -> Bool { record(key)?.hasContent == true }
    static func issue(for key:String)->String?{sidecarErrors[key]}
    static func save(_ record: Record, for key: String) throws {
        if let url = sidecar(for:key) {
            if let expected=sidecarVersions[key],expected != version(of:url) {
                throw failure("The note sidecar changed in Finder. Reopen it before saving.")
            }
            if FileManager.default.fileExists(atPath:url.path) {
                guard let size=try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize,size <= 2*1024*1024,
                      let existing=try? Data(contentsOf:url),
                      (try? JSONDecoder().decode(Sidecar.self,from:existing)) != nil else {
                    throw failure("The existing note sidecar is damaged or too large. It has not been replaced.")
                }
            }
            let data = try JSONEncoder().encode(Sidecar(notes:record.hasContent ? record:nil))
            try data.write(to:url,options:.atomic)
            sidecarVersions[key]=version(of:url)
        } else {
            let url=looseURL
            var values=looseRecords ?? (try? Data(contentsOf:url)).flatMap{try? JSONDecoder().decode(LooseSidecar.self,from:$0).records} ?? [:]
            values[key]=record.hasContent ? record:nil
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(LooseSidecar(records:values)).write(to:url,options:.atomic)
            looseRecords=values
        }
        cache(record.hasContent ? record:nil,for:key)
        sidecarCheckedAt[key] = .distantPast
    }
}

final class AssetNotesEditor: NSView {
    override var isFlipped: Bool { true }
    private let titleLabel = Design.text("Asset Notes", .header)
    private let nameLabel = Design.text("Name", .caption)
    private let descriptionLabel = Design.text("Description", .caption)
    private let previewLabel = Design.text("Preview", .caption)
    private let name = SwissBlockTextField(frame: .zero)
    private let descriptionText = SwissBlockTextView(frame: .zero)
    private let descriptionScroll = NSScrollView(frame: .zero)
    private let preview = NSView(frame: .zero)
    private let save = SwissButton("Save Notes", .primary, target: nil, action: nil)
    private let cancel = SwissButton("Cancel", .secondary, target: nil, action: nil)
    private let item: TileGrid.Item
    private let key: String
    private let feedback: (String) -> Void
    weak var modal: SwissFocusModal?
    var onChange: (() -> Void)?
    var onSave: ((AssetNotes.Record) throws -> Void)?

    init(item: TileGrid.Item, key: String, name displayName: String? = nil, feedback: @escaping (String) -> Void) {
        self.item = item; self.key = key; self.feedback = feedback
        super.init(frame: .zero)
        let existing = AssetNotes.record(key)
        if let issue=AssetNotes.issue(for:key){feedback(issue)}
        name.stringValue = displayName ?? existing?.name ?? item.title
        name.font = Design.Text.body.font(); name.textColor = Design.ink
        name.isBordered = false; name.backgroundColor = Design.card; name.isEditable = false; name.isSelectable = true
        name.focusRingType = .none; name.setAccessibilityLabel("Asset note name")
        descriptionText.string = existing?.description ?? ""
        descriptionText.font = Design.Text.body.font(); descriptionText.textColor = Design.ink
        descriptionText.backgroundColor = Design.card; descriptionText.isRichText = false
        descriptionText.isVerticallyResizable = true; descriptionText.isHorizontallyResizable = false
        descriptionText.textContainer?.widthTracksTextView = true
        descriptionText.setAccessibilityLabel("Asset description")
        descriptionScroll.documentView = descriptionText
        descriptionScroll.hasVerticalScroller = true; descriptionScroll.autohidesScrollers = true
        descriptionScroll.drawsBackground = false; descriptionScroll.borderType = .bezelBorder
        preview.wantsLayer = true; preview.layer?.backgroundColor = Design.mist.cgColor
        for view in [titleLabel,nameLabel,name,descriptionLabel,descriptionScroll,previewLabel,preview,save,cancel] { addSubview(view) }
        save.target = self; save.action = #selector(saveNotes)
        cancel.target = self; cancel.action = #selector(cancelNotes)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let w = bounds.width, inset: CGFloat = 4, gap: CGFloat = 28
        let left = max(240, (w-gap)/2), right = w-left-gap
        titleLabel.frame = NSRect(x: inset, y: 0, width: w, height: 34)
        nameLabel.frame = NSRect(x: inset, y: 64, width: left-inset, height: 20)
        name.frame = NSRect(x: inset, y: 91, width: left-inset, height: 32)
        descriptionLabel.frame = NSRect(x: inset, y: 151, width: left-inset, height: 20)
        descriptionScroll.frame = NSRect(x: inset, y: 180, width: left-inset, height: 205)
        descriptionText.frame = NSRect(x: 0, y: 0, width: left-inset-12, height: max(205, descriptionText.frame.height))
        previewLabel.frame = NSRect(x: left+gap, y: 64, width: right, height: 20)
        preview.frame = NSRect(x: left+gap, y: 91, width: right, height: 294)
        save.frame = NSRect(x: inset, y: bounds.height-48, width: 148, height: 34)
        cancel.frame = NSRect(x: 168, y: bounds.height-48, width: 110, height: 34)
        drawPreview()
    }
    private func drawPreview() {
        preview.subviews.forEach { $0.removeFromSuperview() }
        if let image = item.image {
            let imageView = NSImageView(frame: preview.bounds.insetBy(dx: 12, dy: 12))
            imageView.image = image; imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.autoresizingMask = [.width,.height]; preview.addSubview(imageView)
        } else if !item.colours.isEmpty {
            let strip = NSView(frame: preview.bounds.insetBy(dx: 12, dy: 12))
            strip.autoresizingMask = [.width,.height]; preview.addSubview(strip)
            let width = strip.bounds.width / CGFloat(item.colours.count)
            for (index, colour) in item.colours.enumerated() {
                let block = NSView(frame: NSRect(x: CGFloat(index)*width, y: 0, width: width+0.5, height: strip.bounds.height))
                block.wantsLayer = true; block.layer?.backgroundColor = colour.cgColor
                strip.addSubview(block)
            }
        } else {
            let label = Design.text(item.title, .body)
            label.frame = preview.bounds.insetBy(dx: 16, dy: 16)
            label.autoresizingMask = [.width,.height]; preview.addSubview(label)
        }
    }
    @objc private func saveNotes() {
        do {
            let record = AssetNotes.Record(name:name.stringValue,description:descriptionText.string)
            if let onSave { try onSave(record) } else { try AssetNotes.save(record, for:key) }
            onChange?(); modal?.dismissOverlay()
        } catch { feedback("Could not save notes: \(error.localizedDescription)") }
    }
    @objc private func cancelNotes() { modal?.dismissOverlay() }
}
