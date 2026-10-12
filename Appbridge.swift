import AppKit
import UniformTypeIdentifiers
import UserNotifications
import CryptoKit

/// Compact ancestor names while retaining the two directories that identify the location.
enum AppbridgePath {
    static func display(_ path: String) -> String {
        let homePath = (path as NSString).abbreviatingWithTildeInPath
        let parts = homePath.split(separator: "/").map(String.init)
        let abbreviated = parts.enumerated().map { index, part in
            guard index < parts.count - 2, part != "~" else { return part }
            return part.hasPrefix(".") ? String(part.prefix(2)) : String(part.prefix(1))
        }.joined(separator: "/")
        return (homePath.hasPrefix("/") ? "/" : "") + abbreviated
    }
}

/// ASE's source values stay intact. Display colours are previews, never a replacement for the file.
enum AdobeASE {
    static let empty = Data([0x41, 0x53, 0x45, 0x46, 0, 1, 0, 0, 0, 0, 0, 0])
    struct Swatch {
        let name: String
        let group: String
        let model: String
        let values: [Double]
        let type: Int
        var preview: NSColor {
            switch model {
            case "RGB ": return NSColor(srgbRed: values[0], green: values[1], blue: values[2], alpha: 1)
            case "Gray": return NSColor(srgbRed: values[0], green: values[0], blue: values[0], alpha: 1)
            case "CMYK": return NSColor(deviceCyan: values[0], magenta: values[1], yellow: values[2], black: values[3], alpha: 1).usingColorSpace(.sRGB) ?? .gray
            default: return Design.hex(RGBSpace.srgb.text(RGBSpace.srgb.values(of: ColourDefinition.lab(values[0] * 100, values[1], values[2]).master)))
            }
        }
        var cmykText: String {
            if model == "CMYK" { return values.map { String(format: "%.0f", $0 * 100) }.joined(separator: ", ") }
            return ColourFormat.cmyk.text(hexOf(preview) ?? "#000000")
        }
        var detail: String {
            let components = values.enumerated().map { i, v in String(format: "%.2f", model == "LAB " && i == 0 ? v * 100 : v) }.joined(separator: ", ")
            return "\(model.trimmingCharacters(in: .whitespaces)) \(components)" + (type == 1 ? " · Spot" : "")
        }
    }
    struct Reader {
        let bytes: [UInt8]
        var at = 0
        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, count <= bytes.count - at else { throw failure("This ASE file is truncated.") }
            defer { at += count }; return Array(bytes[at..<at + count])
        }
        mutating func number(_ count: Int) throws -> Int { try take(count).reduce(0) { $0 << 8 | Int($1) } }
        mutating func text() throws -> String {
            let count = try number(2)
            guard count > 0 else { throw failure("An ASE name has no terminator.") }
            var units: [UInt16] = []
            for _ in 0..<count { units.append(UInt16(try number(2))) }
            guard units.removeLast() == 0 else { throw failure("An ASE name is not terminated.") }
            return String(decoding: units, as: UTF16.self)
        }
    }
    static func read(_ data: Data) throws -> [Swatch] {
        guard data.count <= 16 * 1024 * 1024 else { throw failure("This ASE file exceeds the 16 MB limit.") }
        var r = Reader(bytes: Array(data))
        guard try r.take(4) == Array("ASEF".utf8), try r.number(2) == 1 else { throw failure("Choose an Adobe Swatch Exchange (.ase) version 1 file.") }
        _ = try r.number(2)
        let blocks = try r.number(4)
        guard blocks <= 100_000 else { throw failure("This ASE file has too many blocks.") }
        var groups: [String] = [], result: [Swatch] = []
        for _ in 0..<blocks {
            let type = try r.number(2), size = try r.number(4)
            var block = Reader(bytes: try r.take(size))
            switch type {
            case 0xC001: groups.append(try block.text())
            case 0xC002:
                guard !groups.isEmpty else { throw failure("The ASE groups are unbalanced.") }; groups.removeLast()
            case 1:
                let name = try block.text(), model = String(decoding: try block.take(4), as: UTF8.self)
                let count: Int
                switch model { case "RGB ", "LAB ": count = 3; case "CMYK": count = 4; case "Gray": count = 1; default: throw failure("Unsupported ASE colour model: \(model).") }
                var values: [Double] = []
                for _ in 0..<count {
                    let v = Double(Float(bitPattern: UInt32(try block.number(4))))
                    guard v.isFinite else { throw failure("The ASE file contains a non-finite colour value.") }
                    values.append(v)
                }
                let kind = try block.number(2)
                guard kind <= 2 else { throw failure("The ASE file contains an unknown swatch type.") }
                guard values.enumerated().allSatisfy({ model == "LAB " && $0.offset > 0 ? (-128...127).contains($0.element) : (0...1).contains($0.element) }) else { throw failure("The ASE file contains out-of-range colour values.") }
                result.append(Swatch(name: name, group: groups.joined(separator: " / "), model: model, values: values, type: kind))
            default: break // Unknown extension blocks do not change the read-only preview.
            }
        }
        guard groups.isEmpty, r.at == r.bytes.count else { throw failure("The ASE block structure is incomplete.") }
        return result
    }
    /// Append complete groups without re-encoding any existing block, including extensions.
    static func appending(_ palette: ExportPalette, to original: Data) throws -> Data {
        _ = try read(original)
        guard !palette.colours.isEmpty else { throw failure("This palette has no colours to add.") }
        guard ([palette.name] + palette.colours.map { $0.name }).allSatisfy({ $0.utf16.count < 65535 }),
              palette.colours.allSatisfy({ ColourValues($0.hex) != nil }) else {
            throw failure("This palette contains an unsupported colour or an oversized name.")
        }
        guard let addition = ExportFormat.ase.data([palette]) else { throw failure("The palette could not be encoded.") }
        var reader = Reader(bytes: Array(original)); reader.at = 8
        let count = try reader.number(4) + palette.colours.count + 2
        guard count <= 100_000 else { throw failure("The resulting ASE file has too many blocks.") }
        var result = original
        let header = withUnsafeBytes(of: UInt32(count).bigEndian) { Data($0) }
        result.replaceSubrange(8..<12, with: header)
        result.append(addition.dropFirst(12))
        _ = try read(result)
        return result
    }

    /// Coordinate with other file presenters, reject stale previews, back up, then replace atomically.
    static func append(_ palette: ExportPalette, at url: URL, expectedDigest: String, backupDirectory: URL? = nil) throws {
        var coordinationError: NSError?, writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { target in
            do {
                let values = try target.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
                guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 16 * 1024 * 1024 else { throw failure("This ASE file cannot be edited safely.") }
                let original = try Data(contentsOf: target)
                let digest = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
                guard digest == expectedDigest else { throw failure("This ASE file changed since it was opened. Its preview will refresh; drop the palette again.") }
                let result = try appending(palette, to: original)
                let directory = backupDirectory ?? target.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let backup = directory.appendingPathComponent(target.lastPathComponent + "." + UUID().uuidString + ".bak")
                try original.write(to: backup, options: .withoutOverwriting)
                try result.write(to: target, options: .atomic)
            } catch { writeError = error }
        }
        if let error = coordinationError { throw error }
        if let error = writeError { throw error }
    }

}

/// Portable catalogue-owned index. Bookmarks stay machine-local, never inside an archive.
enum ASERegistry {
    struct Document: Codable {
        var version = 1
        var sources: [AppbridgeStore.Source] = []
        var legacyMigrated: Bool? = nil
    }
    static let directory = "Library/ASE"
    static func url(in root: URL, name: String? = nil) -> URL {
        if let name { return root.appendingPathComponent(filesystemName(name) + ".colase") }
        let existing = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?.first { $0.pathExtension == "colase" }
        return existing ?? root.appendingPathComponent(root.lastPathComponent + ".colase")
    }
    static func read(_ root: URL) throws -> Document {
        let file = url(in: root)
        guard FileManager.default.fileExists(atPath: file.path) else { return Document() }
        let data = try Data(contentsOf: file)
        guard data.count <= 4 * 1024 * 1024 else { throw failure("The ASE registry is too large.") }
        let value = try JSONDecoder().decode(Document.self, from: data)
        guard value.version == 1, value.sources.count <= 2000,
              Set(value.sources.map { $0.id }).count == value.sources.count else { throw failure("Unsupported or invalid ASE registry.") }
        for source in value.sources where !source.path.hasPrefix("/") {
            guard source.path.hasPrefix(directory + "/"), !source.path.split(separator: "/").contains("..") else { throw failure("Invalid relative ASE location.") }
        }
        return value
    }
    static func resolved(_ root: URL) throws -> [AppbridgeStore.Source] {
        try read(root).sources.map { source in
            var source = source
            if !source.path.hasPrefix("/") { source.path = root.appendingPathComponent(source.path).path }
            return source
        }
    }
    static func write(_ sources: [AppbridgeStore.Source], root: URL, name: String? = nil) throws {
        let portable = sources.map { value -> AppbridgeStore.Source in
            var value = value
            if value.path.hasPrefix(root.path + "/" + directory + "/") { value.path = String(value.path.dropFirst(root.path.count + 1)) }
            return value
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Document(sources: portable, legacyMigrated: (try? read(root))?.legacyMigrated)).write(to: url(in: root, name: name), options: .atomic)
    }
    static func seed(_ root: URL, name: String? = nil) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url(in: root).path) { try write([], root: root, name: name) }
        if let name {
            let existing = url(in: root), named = url(in: root, name: name)
            if existing != named, !fm.fileExists(atPath: named.path) { try fm.moveItem(at: existing, to: named) }
        }
        // Preserve older bundled files. Never remove or replace the old directory.
        let old = root.appendingPathComponent("AppBridge/ASE")
        if fm.fileExists(atPath: old.path), try read(root).legacyMigrated != true {
            var sources = try resolved(root)
            if let walker = fm.enumerator(at: old, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
                for case let file as URL in walker where file.pathExtension.lowercased() == "ase" {
                    let v = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard v.isRegularFile == true, v.isSymbolicLink != true else { continue }
                    let relative = String(file.path.dropFirst(old.path.count + 1))
                    let target = root.appendingPathComponent(directory).appendingPathComponent(relative)
                    if !fm.fileExists(atPath: target.path) {
                        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try fm.copyItem(at: file, to: target)
                    }
                    if !sources.contains(where: { $0.path == target.path }) { sources.append(.init(path: target.path, folder: false)) }
                }
            }
            try write(sources, root: root)
            var document = try read(root); document.legacyMigrated = true
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(document).write(to: url(in: root), options: .atomic)
        }
    }
    static func harvest(root: URL, selected: Set<UUID>) throws -> [Zip.Entry] {
        let links = try resolved(root).filter { !$0.folder && selected.contains($0.id) }
        var entries: [Zip.Entry] = [], exported: [AppbridgeStore.Source] = [], total = 0
        for link in links {
            let file = link.url
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 16 * 1024 * 1024 else { throw failure("Cannot export " + file.lastPathComponent) }
            let data = try Data(contentsOf: file); _ = try AdobeASE.read(data); total += data.count
            guard total <= 256 * 1024 * 1024, entries.count < 1000 else { throw failure("The selected ASE files exceed the export limit.") }
            let path = directory + "/" + link.id.uuidString + "/" + filesystemName(file.lastPathComponent)
            entries.append(.init(path: path, data: data))
            var copy = link; copy.originalPath = link.originalPath ?? file.path; copy.path = path
            exported.append(copy)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        entries.append(.init(path: url(in: root).lastPathComponent, data: try encoder.encode(Document(sources: exported))))
        return entries
    }
}

/// Colorgain's own ASE document mark. The Adobe binary remains standards-compliant.
enum ASEIcon {
    static var image: NSImage {
        NSImage(size: NSSize(width: 32, height: 40), flipped: true) { rect in
            let path = NSBezierPath(); path.move(to: NSPoint(x: 2, y: 0)); path.line(to: NSPoint(x: 22, y: 0)); path.line(to: NSPoint(x: 32, y: 10)); path.line(to: NSPoint(x: 32, y: 40)); path.line(to: NSPoint(x: 2, y: 40)); path.close()
            NSGradient(starting: NSColor(srgbRed: 0.95, green: 0.16, blue: 0.38, alpha: 1), ending: NSColor(srgbRed: 1, green: 0.29, blue: 0.10, alpha: 1))?.draw(in: path, angle: 90)
            NSColor.white.setFill(); let fold = NSBezierPath(); fold.move(to: NSPoint(x: 22, y: 0)); fold.line(to: NSPoint(x: 22, y: 10)); fold.line(to: NSPoint(x: 32, y: 10)); fold.close(); fold.fill()
            for i in 0..<3 { NSColor.white.withAlphaComponent(1 - CGFloat(i) * 0.2).setFill(); NSBezierPath(rect: NSRect(x: 8 + CGFloat(i) * 6, y: 15, width: 5, height: 12 - CGFloat(i) * 2)).fill() }
            NSAttributedString(string: "ASE", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]).draw(at: NSPoint(x: 10, y: 30))
            return true
        }
    }
    static func apply(to url: URL) { _ = NSWorkspace.shared.setIcon(image, forFile: url.path, options: []) }
}

final class AppbridgeStore: NSObject, UNUserNotificationCenterDelegate {
    struct Source: Codable, Identifiable {
        var id = UUID()
        var path: String
        var folder: Bool
        var monitoring = false
        var notifications = false
        var excluded: [String]? = nil
        var originalPath: String? = nil
        var url: URL { FolderAccess.held[path] ?? URL(fileURLWithPath: path) }
    }
    struct File {
        let id: UUID
        let source: UUID
        let url: URL
        let swatches: [AdobeASE.Swatch]
        let problem: String?
        let digest: String
    }
    private(set) var sources: [Source] = []
    private(set) var files: [File] = []
    private(set) var notices: [String] = []
    var selected: UUID?
    var onChange: (() -> Void)?
    var onNotice: ((String) -> Void)?
    private var watches: [UUID: CatalogueWatch] = [:]
    private var identifiers: [String: UUID] = [:]
    private var generation = 0
    private var configurationError: String?
    private var pendingOpen: String?
    private var baselinedSources = Set<UUID>()
    private let queue = DispatchQueue(label: "com.colorgain.appbridge.scan", qos: .utility)
    var current: File? { files.first { $0.id == selected } }
    private var root: URL?
    private var timer: Timer?
    private var locationSignature: String?
    private var seededCatalogues = false
    override init() { super.init() }
    deinit { timer?.invalidate() }
    func bind(to directory: URL) {
        guard root != directory else { return }
        generation += 1; timer?.invalidate(); watches.values.forEach { $0.stop() }
        root = directory; files = []; sources = []; selected = nil; configurationError = nil; baselinedSources = []
        do {
            if !seededCatalogues {
                seededCatalogues = true
                for name in Catalogues.standard.names() {
                    let folder = Catalogues.standard.directory(for: name)
                    if FileManager.default.fileExists(atPath: folder.path) {
                        do { try ASERegistry.seed(folder, name: name) } catch { notices.append("Could not update " + name + ": " + error.localizedDescription) }
                    }
                }
            }
            try ASERegistry.seed(directory)
            locationSignature = nil
            sources = try ASERegistry.resolved(directory)
            let manifest = try AppDataStore.current.read()
            if manifest["appbridgeMigratedToCatalogue"] == nil, let legacy = manifest["appbridge"] {
                let previous = try JSONDecoder().decode([Source].self, from: JSONSerialization.data(withJSONObject: legacy))
                for item in previous where !sources.contains(where: { $0.path == item.path }) { sources.append(item) }
                try save(sources)
                try AppDataStore.current.update { $0["appbridgeMigratedToCatalogue"] = directory.path }
            }
            scan(); restartWatches()
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.checkLocations() }
        } catch { configurationError = error.localizedDescription; notices = [error.localizedDescription] }
    }
    /// Isolated source snapshot for layout regression tests; no disk reads or watchers.
    init(previewSources: [Source]) { sources = previewSources; super.init() }
    private func save(_ proposed: [Source]) throws {
        if let configurationError { throw failure("The saved Appbridge connections could not be read: " + configurationError) }
        guard let root else { throw failure("Open a catalogue first.") }
        try ASERegistry.write(proposed, root: root)
        sources = proposed
    }
    func add(_ url: URL, folder: Bool) {
        do {
            try FolderAccess.authorize(url)
            if !folder {
                var updated = sources
                for i in updated.indices { updated[i].excluded?.removeAll { $0 == url.standardizedFileURL.path } }
                try save(updated)
            }
            guard !sources.contains(where: { $0.url.path == url.path || (!folder && $0.folder && url.path.hasPrefix($0.url.path + "/")) }) else { if !folder { pendingOpen = url.path }; scan(); return }
            try save(sources + [Source(path: url.path, folder: folder, monitoring: folder, notifications: folder)])
            if folder { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
            selected = nil; if !folder { pendingOpen = url.path }; scan(); restartWatches()
        } catch { report(error.localizedDescription) }
    }
    func remove(_ id: UUID) {
        do { try save(sources.filter { $0.id != id }); selected = nil; restartWatches(); scan() }
        catch { report(error.localizedDescription) }
    }
    func detach(_ file: File) {
        do {
            var updated = sources.filter { $0.folder || $0.url.standardizedFileURL != file.url.standardizedFileURL }
            for i in updated.indices where updated[i].folder && file.url.path.hasPrefix(updated[i].url.path + "/") {
                updated[i].excluded = Array(Set((updated[i].excluded ?? []) + [file.url.standardizedFileURL.path])).sorted()
            }
            try save(updated)
            files.removeAll { $0.id == file.id }
            if selected == file.id { selected = nil }
            onChange?(); restartWatches(); scan()
        } catch { report(error.localizedDescription) }
    }
    func duplicate(_ file: File) {
        copyASE(from: file.url, intoBucket: false, suggestedName: file.url.deletingPathExtension().lastPathComponent + " Copy.ase", attach: true)
    }
    func confirmDelete(_ file: File, over view: NSView) {
        let modal = SwissFocusModal(title: "Move ASE File To Trash?", message: "This deletes the actual file from its folder—not just its Appbridge link. Other apps and catalogues using this file will lose access to it.")
        let details = Design.text(file.url.lastPathComponent + "\n" + file.url.deletingLastPathComponent().path + "\n\nYou can restore it from macOS Trash until Trash is emptied. To keep the file on disk, cancel and use Detach instead.", .body)
        details.maximumNumberOfLines = 0; details.lineBreakMode = .byWordWrapping
        modal.content(details, height: 140)
        modal.button("Cancel") { [weak modal] in modal?.dismissOverlay() }
        modal.button("Move File To Trash", primary: true) { [weak self, weak modal] in
            modal?.dismissOverlay(); self?.delete(file)
        }
        modal.present(over: view)
    }
    private func delete(_ file: File) {
        do { try FileManager.default.trashItem(at: file.url, resultingItemURL: nil); detach(file) }
        catch { report("Could not move the file to Trash: " + error.localizedDescription) }
    }
    func toggle(_ id: UUID, notifications: Bool = false) {
        guard let i = sources.firstIndex(where: { $0.id == id }) else { return }
        var updated = sources
        if notifications { updated[i].notifications.toggle() } else { updated[i].monitoring.toggle() }
        do {
            try save(updated); restartWatches(); onChange?()
            if notifications && updated[i].notifications {
                let centre = UNUserNotificationCenter.current(); centre.delegate = self
                centre.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
                    DispatchQueue.main.async { if !granted { self?.report(error?.localizedDescription ?? "macOS notifications are disabled. Enable them in System Settings; in-app changes remain visible.") } }
                }
            }
        } catch { report(error.localizedDescription) }
    }
    var creationDirectory: URL? { root?.appendingPathComponent(ASERegistry.directory) }
    var missing: [File] { files.filter { $0.digest == "unavailable" && $0.url.pathExtension.lowercased() == "ase" } }
    var buckets: [Source] { sources.filter { $0.folder } }
    func containsInBucket(_ url: URL) -> Bool {
        buckets.contains { url.standardizedFileURL.path.hasPrefix($0.url.standardizedFileURL.path + "/") }
    }
    func exportCurrent() {
        guard let file = current, file.problem == nil else { return }
        copyASE(from: file.url, intoBucket: false)
    }
    func copyASE(from source: URL, intoBucket: Bool, suggestedName: String? = nil, attach: Bool = false) {
        if intoBucket && buckets.isEmpty { report("Connect an ASE bucket folder in Appbridge settings first."); return }
        let panel = NSSavePanel()
        panel.title = intoBucket ? "Import ASE Into Your Bucket" : "Export ASE Copy"
        panel.message = intoBucket ? "Choose a new filename inside one of your connected bucket folders. The source file stays unchanged." : "Save a copy of this ASE library. The managed original stays unchanged."
        panel.allowedContentTypes = [UTType(filenameExtension: "ase") ?? .data]
        panel.nameFieldStringValue = suggestedName ?? source.lastPathComponent
        if intoBucket { panel.directoryURL = buckets.first?.url }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard source.standardizedFileURL != destination.standardizedFileURL else { report("Choose a different filename for the copy."); return }
        guard !intoBucket || containsInBucket(destination) else { report("Connect that folder as a bucket first, then import again."); return }
        do {
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 16 * 1024 * 1024 else { throw failure("This ASE file exceeds the 16 MB limit.") }
            let data = try Data(contentsOf: source)
            _ = try AdobeASE.read(data)
            try data.write(to: destination, options: .withoutOverwriting)
            ASEIcon.apply(to: destination)
            if attach { add(destination, folder: false) }
            else if intoBucket { pendingOpen = destination.path; scan() }
            report("Saved " + destination.lastPathComponent)
        } catch { report("Could not save the copy: " + error.localizedDescription) }
    }
    private(set) var writing = false
    func append(_ palette: ExportPalette) -> Bool {
        guard let file = current, file.problem == nil, !writing else { return false }
        writing = true
        let backups = AppDataStore.current.root.appendingPathComponent("Backups/Appbridge", isDirectory: true)
        queue.async { [weak self] in
            let message: String
            var needsCopy = false
            do {
                try AdobeASE.append(palette, at: file.url, expectedDigest: file.digest, backupDirectory: backups)
                message = "Added \(palette.colours.count) swatches to \(file.url.lastPathComponent). Original saved in Backups/Appbridge."
            } catch {
                let problem = error as NSError
                needsCopy = problem.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError].contains(problem.code)
                message = "Could not add swatches: " + error.localizedDescription
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.writing = false
                if needsCopy { self.saveEditableCopy(palette, from: file) }
                else { self.report(message); self.scan() }
            }
        }
        return true
    }
    private func saveEditableCopy(_ palette: ExportPalette, from file: File) {
        let panel = NSSavePanel()
        panel.title = "Save An Editable Copy"
        panel.message = "This Adobe preset cannot be changed in its current location. Save a copy containing its existing swatches plus the palette you dropped."
        panel.allowedContentTypes = [UTType(filenameExtension: "ase") ?? .data]
        panel.nameFieldStringValue = file.url.deletingPathExtension().lastPathComponent + " Copy.ase"
        panel.canCreateDirectories = true
        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let destination = panel.url else { return }
            guard destination.standardizedFileURL != file.url.standardizedFileURL else {
                self.report("Choose a different location for the editable copy."); return
            }
            self.writing = true
            self.queue.async {
                var problem: String?
                do {
                    let original = try Data(contentsOf: file.url)
                    let digest = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
                    guard digest == file.digest else { throw failure("The source changed. Refresh it and drop the palette again.") }
                    try AdobeASE.appending(palette, to: original).write(to: destination, options: .atomic)
                } catch { problem = error.localizedDescription }
                DispatchQueue.main.async {
                    self.writing = false
                    if let problem { self.report("Could not save the copy: " + problem) }
                    else { self.add(destination, folder: false); self.report("Saved \(destination.lastPathComponent) with \(palette.colours.count) added swatches.") }
                }
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: complete) }
        else { panel.begin(completionHandler: complete) }
    }
    func report(_ message: String) { onNotice?(message); notices.insert(message, at: 0); notices = Array(notices.prefix(20)); onChange?() }
    private func restartWatches() {
        watches.values.forEach { $0.stop() }; watches.removeAll()
        for source in sources where source.monitoring && source.folder {
            let watch = CatalogueWatch(root: source.url) { [weak self] in self?.scan(changed: source.id) }
            watch.start(); watches[source.id] = watch
        }
    }
    private func checkLocations() {
        let snapshot = sources, ticket = generation
        queue.async { [weak self] in
            let signature = snapshot.filter { !$0.folder }.map { source -> String in
                let values = try? source.url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return source.path + "|" + String(describing: values?.contentModificationDate) + "|" + String(describing: values?.fileSize)
            }.joined(separator: "\n")
            DispatchQueue.main.async {
                guard let self, self.generation == ticket, self.locationSignature != signature else { return }
                self.locationSignature = signature; self.scan()
            }
        }
    }
    func scan(changed: UUID? = nil) {
        generation += 1
        guard configurationError == nil else { return }
        let ticket = generation, snapshot = sources
        queue.async { [weak self] in
            var found: [(UUID, URL, [AdobeASE.Swatch], String?, String)] = []
            for source in snapshot {
                var urls: [URL] = []
                do {
                    if source.folder {
                        _ = try FileManager.default.contentsOfDirectory(at: source.url, includingPropertiesForKeys: nil)
                        var enumerationError: Error?
                        if let walker = FileManager.default.enumerator(at: source.url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in enumerationError = error; return false }) {
                            for case let url as URL in walker {
                                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                                if values.isSymbolicLink == true { walker.skipDescendants(); continue }
                                if values.isRegularFile == true && url.pathExtension.lowercased() == "ase" { urls.append(url) }
                                if urls.count > 1000 { throw failure("This folder contains more than 1,000 ASE files. Choose a smaller folder.") }
                            }
                        }
                        if let error = enumerationError { throw error }
                    } else { urls = [source.url] }
                    urls.removeAll { (source.excluded ?? []).contains($0.standardizedFileURL.path) }
                    for url in urls.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
                        do {
                            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                            guard size <= 16 * 1024 * 1024 else { throw failure("This ASE file exceeds the 16 MB limit.") }
                            let data = try Data(contentsOf: url), digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                            do { found.append((source.id, url, try AdobeASE.read(data), nil, digest)) }
                            catch { found.append((source.id, url, [], error.localizedDescription, digest)) }
                        } catch { found.append((source.id, url, [], "Missing or inaccessible: " + url.path, "unavailable")) }
                    }
                } catch { found.append((source.id, source.url, [], "Reconnect this location: \(error.localizedDescription)", "unavailable")) }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, ticket == self.generation else { return }
                let previousSelection = self.selected
                let old = Dictionary(self.files.map { ("\($0.source)/\($0.url.path)", $0.digest) }, uniquingKeysWith: { a, _ in a })
                var unique = Set<String>()
                let found = found.filter { unique.insert($0.1.standardizedFileURL.path).inserted }
                var updated = self.sources
                for (_, url, _, _, _) in found where url.pathExtension.lowercased() == "ase" {
                    if !updated.contains(where: { !$0.folder && $0.path == url.path }) { updated.append(Source(path: url.path, folder: false)) }
                }
                if updated.count != self.sources.count { do { try self.save(updated) } catch { self.report(error.localizedDescription) } }
                self.files = found.map { source, url, colours, problem, digest in
                    let key = "\(source)/\(url.path)"
                    let id = self.identifiers[key] ?? UUID(); self.identifiers[key] = id
                    return File(id: id, source: source, url: url, swatches: colours, problem: problem, digest: digest)
                }
                if let selected = self.selected, !self.files.contains(where: { $0.id == selected }) { self.selected = nil }
                if let path = self.pendingOpen { self.selected = self.files.first { $0.url.path == path }?.id; self.pendingOpen = nil }
                let changedSources = self.baselinedSources
                self.baselinedSources = Set(snapshot.map { $0.id })
                for changed in changedSources {
                    guard let source = self.sources.first(where: { $0.id == changed }), source.monitoring else { continue }
                    let latest = Dictionary(self.files.map { ("\($0.source)/\($0.url.path)", $0.digest) }, uniquingKeysWith: { a, _ in a })
                    let keys = Set(old.keys).union(latest.keys).filter { $0.hasPrefix("\(changed)/") && old[$0] != latest[$0] }
                    if !keys.isEmpty {
                        let message = "\(source.url.lastPathComponent): \(keys.count) ASE file\(keys.count == 1 ? "" : "s") changed."
                        self.report(message)
                        if source.notifications {
                            let content = UNMutableNotificationContent(); content.title = "Appbridge"; content.body = message; content.sound = .default
                            let centre = UNUserNotificationCenter.current(); centre.delegate = self
                            centre.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { _ in }
                        }
                    }
                }
                let latest = Dictionary(self.files.map { ("\($0.source)/\($0.url.path)", $0.digest) }, uniquingKeysWith: { a, _ in a })
                if old != latest || previousSelection != self.selected { self.onChange?() }
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
}

final class AppbridgePage: NSView, PageSection {
    var onCreate: (() -> Void)?
    let store: AppbridgeStore
    var onResize: (() -> Void)?
    var onOpen: ((UUID) -> Void)?
    private let connect = SwissButton("Connect Folder…", .secondary)
    private let openFile = SwissButton("Import ASE File…", .secondary)
    private let refresh = SwissButton("Refresh", .secondary)
    private let newFile = SwissButton("New ASE File…", .primary)
    private let procreate = [SwissButton("New Swatches File…", .primary), SwissButton("Import Swatches File…", .secondary), SwissButton("Connect Folder…", .secondary), SwissButton("Refresh", .secondary)]
    private let files = AppbridgeFileList()
    private var adobe: [SwissButton] { [newFile, openFile, connect, refresh] }
    private var u: CGFloat { Design.App.unit }
    private var contentX: CGFloat { SettingsSheet.contentColumn(width: bounds.width, window: window?.frame.width ?? Design.App.size.width) }
    override var isFlipped: Bool { true }
    init(store: AppbridgeStore) {
        self.store = store; super.init(frame: .zero)
        for (button, action) in [(connect, #selector(connectFolder)), (openFile, #selector(openASE)), (refresh, #selector(rescan)), (newFile, #selector(createASE))] { button.target = self; button.action = action; addSubview(button) }
        for button in procreate { button.isEnabled = false; button.toolTip = "Procreate file support is not connected yet."; addSubview(button) }
        addSubview(files)
        files.onOpen = { [weak self] id in
            guard let self else { return }; if self.store.missing.contains(where: { $0.id == id }) { self.store.showMissing(over: self) } else { self.onOpen?(id) }
        }
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }
    func reload() {
        files.reload(store)
        needsLayout = true; needsDisplay = true; onResize?()
    }
    /// Both sections share the same grid geometry, including the reserved list viewport.
    private func listTop(guide: CGFloat, buttons: [SwissButton], place: Bool) -> CGFloat {
        let x = contentX, width = max(0, bounds.width - x)
        let columnWidth = max(0, (width - Design.App.gutter) / 2)
        let twoColumns = buttons.allSatisfy { $0.intrinsicContentSize.width <= columnWidth }
        var baseline = guide + 4 * u
        for (index, button) in buttons.enumerated() {
            let row = twoColumns ? index / 2 : index
            let bx = x + (twoColumns && index % 2 == 1 ? columnWidth + Design.App.gutter : 0)
            baseline = guide + CGFloat(4 + row * 2) * u
            let w = min(twoColumns ? columnWidth : width, button.intrinsicContentSize.width)
            if place { button.frame = NSRect(x: bx, y: SettingsSheet.buttonTop(baseline: baseline), width: w, height: 32) }
        }
        return baseline + 2 * u - Design.App.textBaseline + Design.App.gutter
    }
    private var listHeight: CGFloat { max(u, files.contentHeight) }
    private var noticeHeight: CGFloat { store.notices.isEmpty ? 0 : u }
    var sectionAnchors: [(String,CGFloat)] { [("Adobe",SettingsSheet.headerGuide+1),("Procreate",secondGuide+1)] }
    private var secondGuide: CGFloat { listTop(guide: SettingsSheet.headerGuide, buttons: adobe, place: false) + listHeight + noticeHeight + Design.App.textBaseline }
    func height(forWidth width: CGFloat) -> CGFloat { listTop(guide: secondGuide, buttons: procreate, place: false) + 2 * u + Design.App.textBaseline }
    override func layout() {
        super.layout()
        let top = listTop(guide: SettingsSheet.headerGuide, buttons: adobe, place: true)
        _ = listTop(guide: secondGuide, buttons: procreate, place: true)
        files.frame = NSRect(x: contentX, y: top, width: max(0, bounds.width - contentX), height: listHeight)
        files.needsLayout = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let x = contentX, w = bounds.width
        SettingsSheet.title("Appbridge.")
        SettingsSheet.introduction("External libraries", "Create, attach and manage your swatch files.", x: x, width: w)
        SettingsSheet.section(1, "Adobe", guide: SettingsSheet.headerGuide, contentX: x, width: w)
        SettingsSheet.paragraph("Import an ASE file or connect a folder. Select a filename below to open its swatches.", x: x, firstBaseline: SettingsSheet.headerGuide + 2 * u, width: w - x, height: 2 * u)
        let top = listTop(guide: SettingsSheet.headerGuide, buttons: adobe, place: false)
        Design.attributed("Attached files", .bodyStrong).draw(x: x, baseline: top - u + Design.App.textBaseline, width: w - x)
        if let notice = store.notices.first {
            SettingsSheet.paragraph(notice, x: x, firstBaseline: top + listHeight + Design.App.textBaseline, width: w - x, height: u)
        }
        SettingsSheet.section(2, "Procreate", guide: secondGuide, contentX: x, width: w)
        SettingsSheet.paragraph("Procreate libraries will use this same layout. File support is not connected yet.", x: x, firstBaseline: secondGuide + 2 * u, width: w - x, height: 2 * u)
        let proTop = listTop(guide: secondGuide, buttons: procreate, place: false)
        Design.attributed("Attached files", .bodyStrong).draw(x: x, baseline: proTop - u + Design.App.textBaseline, width: w - x)
        hairline(x: x, y: proTop - 1, width: w - x, Design.rule)
        Design.attributed("No Procreate files attached.", .body, colour: Design.quiet).draw(x: x, baseline: proTop + Design.App.textBaseline, width: w - x)
        SettingsSheet.divider(above: proTop + u + Design.App.textBaseline, width: w)
    }
    @objc private func rescan() { store.scan() }
    @objc private func createASE() { onCreate?() }
    @objc private func connectFolder() { choose(folder: true) }
    @objc private func openASE() {
        let panel = NSOpenPanel(); panel.title = "Import ASE File"
        panel.allowedContentTypes = [UTType(filenameExtension: "ase") ?? .data]
        panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.add(url, folder: false) }
    }
    private func choose(folder: Bool) {
        let panel = NSOpenPanel(); panel.title = folder ? "Connect ASE Bucket Folder" : "Open ASE File"
        panel.canChooseDirectories = folder; panel.canChooseFiles = !folder; panel.allowsMultipleSelection = true
        if !folder { panel.allowedContentTypes = [UTType(filenameExtension: "ase") ?? .data] }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.add(url, folder: folder) }
    }
}


/// Directory headings and file rows share Rail 1's 28-point rhythm.
private final class AppbridgeFileList: NSView {
    var onOpen: ((UUID) -> Void)?
    private struct Line {
        var text: String
        var caption = false
        var heading = false
        var buttons: [AppbridgeListButton] = []
        var file = false
        var directory = false
        var height: CGFloat { !file && !buttons.isEmpty ? 5 * Design.App.unit : Design.App.unit }
    }
    private var lines: [Line] = []
    var contentHeight: CGFloat { lines.reduce(0) { $0 + $1.height } }
    override var isFlipped: Bool { true }
    func reload(_ store: AppbridgeStore) {
        subviews.forEach { $0.removeFromSuperview() }; lines = []
        var directories = Set(store.files.map { $0.url.deletingLastPathComponent().path })
        directories.formUnion(store.sources.filter { $0.folder }.map { $0.url.path })
        var seen = Set<String>()
        for directory in directories.sorted() {
            if !lines.isEmpty { lines.append(Line(text: "")) }
            lines.append(Line(text: URL(fileURLWithPath: directory).lastPathComponent, heading: true))
            lines.append(Line(text: (directory as NSString).abbreviatingWithTildeInPath, caption: true, directory: true))
            for source in store.sources where source.folder && source.url.path == directory {
                let monitor = AppbridgeListButton("Monitor: " + (source.monitoring ? "On" : "Off")) { [weak store] in store?.toggle(source.id) }
                let notify = AppbridgeListButton("Notify: " + (source.notifications ? "On" : "Off")) { [weak store] in store?.toggle(source.id, notifications: true) }
                let detach = AppbridgeListButton("Detach Folder") { [weak store] in store?.remove(source.id) }
                monitor.trailingSymbol = source.monitoring ? "checkmark" : "xmark"
                notify.trailingSymbol = source.notifications ? "checkmark" : "xmark"
                detach.trailingSymbol = "powerplug"
                [monitor, notify, detach].forEach { $0.outlined = true }
                lines.append(Line(text: "", buttons: [monitor, notify, detach]))
            }
            let files = store.files.filter { $0.url.deletingLastPathComponent().path == directory }.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
            for file in files where seen.insert(file.url.standardizedFileURL.path).inserted {
                let open = AppbridgeListButton(file.url.lastPathComponent, symbol: "colorgain.ase") { [weak self] in self?.onOpen?(file.id) }
                open.toolTip = file.problem ?? file.url.path
                let duplicate = AppbridgeListButton((file.digest == "unavailable" ? "Locate missing " : "Duplicate ") + file.url.lastPathComponent, symbol: file.digest == "unavailable" ? "exclamationmark.triangle" : "doc.on.doc") { [weak store, weak self] in
                    guard let store, let self else { return }; if file.digest == "unavailable" { store.showMissing(over: self) } else { store.duplicate(file) }
                }
                duplicate.isEnabled = file.problem == nil || file.digest == "unavailable"
                let detach = AppbridgeListButton("Detach " + file.url.lastPathComponent, symbol: "minus.circle") { [weak store] in store?.detach(file) }
                let delete = AppbridgeListButton("Delete " + file.url.lastPathComponent, symbol: "trash") { [weak store, weak self] in
                    guard let store, let self else { return }; store.confirmDelete(file, over: self)
                }
                lines.append(Line(text: "", buttons: [open, duplicate, detach, delete], file: true))
            }
            if files.isEmpty { lines.append(Line(text: "No ASE files attached.", caption: true)) }
        }
        if lines.isEmpty { lines = [Line(text: "No ASE files attached. Import a file to begin.", caption: true)] }
        for line in lines { line.buttons.forEach { addSubview($0) } }
        needsLayout = true; needsDisplay = true
    }
    override func layout() {
        super.layout()
        let u = Design.App.unit
        var y: CGFloat = 0
        for line in lines {
            defer { y += line.height }
            if line.file {
                let widths: [CGFloat] = [u, u, u]
                var x = max(0, bounds.width - widths.reduce(0, +))
                line.buttons[0].frame = NSRect(x: 0, y: y, width: x, height: u)
                for j in 1...3 {
                    line.buttons[j].frame = NSRect(x: x, y: y, width: widths[j - 1], height: u)
                    x += widths[j - 1]
                }
            } else if !line.buttons.isEmpty {
                let gap = Design.App.gutter
                let w = max(0, (bounds.width - gap) / 2)
                for (j, button) in line.buttons.enumerated() { button.frame = NSRect(x: CGFloat(j % 2) * (w + gap), y: SettingsSheet.buttonTop(baseline: y + CGFloat(1 + (j / 2) * 2) * u + Design.App.textBaseline), width: w, height: SwissButton.height) }
            }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        var y: CGFloat = 0
        for line in lines {
            defer { y += line.height }
            if line.directory {
                let prefix = Design.attributed("Directory ", .bodyStrong)
                prefix.draw(x: 0, baseline: y + Design.App.textBaseline, width: bounds.width)
                Design.attributed(line.text, .caption, colour: Design.quiet).draw(x: prefix.size().width, baseline: y + Design.App.textBaseline, width: max(0, bounds.width - prefix.size().width))
            } else { Design.attributed(line.text, line.heading ? .bodyStrong : line.caption ? .caption : .body, colour: line.heading ? Design.ink : Design.quiet).draw(x: 0, baseline: y + Design.App.textBaseline, width: bounds.width) }
            if line.file || line.heading { hairline(x: 0, y: y + Design.App.unit - 1, width: bounds.width, Design.rule) }
            if line.file {
                for j in 1...2 {
                    fill(NSRect(x: line.buttons[j + 1].frame.minX, y: y + 5, width: 1, height: Design.App.unit - 10), Design.rule)
                }
            }
        }
    }
}

final class AppbridgeListButton: NSButton {
    var trailingSymbol: String?
    var outlined = false
    private let symbol: String?
    private let run: () -> Void
    private var hovering = false
    init(_ title: String, symbol: String? = nil, run: @escaping () -> Void) {
        self.symbol = symbol; self.run = run
        super.init(frame: .zero)
        self.title = title; isBordered = false; font = Design.Text.body.font()
        target = self; action = #selector(pressed)
        toolTip = title; setAccessibilityLabel(title)
        setButtonType(.momentaryChange)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if outlined { fill(bounds.insetBy(dx: 1, dy: 1), Design.card); Design.ink.setStroke(); NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)).stroke() }
        if symbol != "colorgain.ase" && isEnabled && (hovering || isHighlighted) { fill(bounds.insetBy(dx: 2, dy: 2), Design.mist) }
        if outlined {
            let label = Design.attributed(title, .action)
            label.draw(at: NSPoint(x: 14, y: (bounds.height - label.size().height) / 2))
            if let trailingSymbol {
                let x = bounds.width - 28
                fill(NSRect(x: x, y: 8, width: 1, height: bounds.height - 16), Design.rule)
                NSImage(systemSymbolName: trailingSymbol, accessibilityDescription: nil)?.draw(in: NSRect(x: x + 7, y: (bounds.height - 14) / 2, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            }
        } else if symbol == "colorgain.ase" {
            ASEIcon.image.draw(in: NSRect(x: 0, y: 3, width: 16, height: 20), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            Design.attributed(title, .body).draw(x: 24, baseline: Design.App.textBaseline, width: max(0, bounds.width - 32))
        } else if let symbol {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            image?.draw(in: NSRect(x: (bounds.width - 14) / 2, y: Design.App.textBaseline - 12, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.35, respectFlipped: true, hints: nil)
        } else {
            Design.attributed(title, .body, colour: isEnabled ? Design.ink : Design.quiet).draw(x: outlined ? 12 : 4, baseline: outlined ? Design.App.textBaseline - 2 : Design.App.textBaseline, width: max(0, bounds.width - (outlined ? 24 : 8)))
        }
        if window?.firstResponder === self { Design.ink.setStroke(); NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)).stroke() }
    }
    @objc private func pressed() { run() }
}


extension AppbridgeStore {
    func showMissing(over view: NSView) {
        let modal = SwissFocusModal(title: "Missing ASE Files", message: "These linked files have moved or cannot be accessed. Locate reconnects a file; Remove only removes its link from this catalogue.")
        let list = ASEMissingList(store: self)
        let scroll = FittedScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.documentView = list
        modal.content(scroll, height: min(280, max(56, CGFloat(missing.count) * 84)))
        list.frame.size = NSSize(width: 432, height: max(56, CGFloat(missing.count) * 84))
        modal.button("Close") { [weak modal] in modal?.dismissOverlay() }
        modal.present(over: view)
    }
    func locate(_ file: File, completion: @escaping () -> Void) {
        let panel = NSOpenPanel(); panel.title = "Locate " + file.url.lastPathComponent
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "ase") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let v = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard v.isSymbolicLink != true, (v.fileSize ?? 0) <= 16 * 1024 * 1024 else { throw failure("Choose an ASE file under 16 MB.") }
            _ = try AdobeASE.read(Data(contentsOf: url)); try FolderAccess.authorize(url)
            var updated = sources
            for i in updated.indices where updated[i].folder && file.url.path.hasPrefix(updated[i].path + "/") {
                updated[i].excluded = Array(Set((updated[i].excluded ?? []) + [file.url.path]))
            }
            if let i = updated.firstIndex(where: { !$0.folder && $0.path == file.url.path }) { updated[i].path = url.path; updated[i].originalPath = nil }
            else { updated.append(Source(path: url.path, folder: false)) }
            try save(updated); files.removeAll { $0.id == file.id }; scan(); onChange?(); completion()
        } catch { report(error.localizedDescription); NSApp.presentError(error) }
    }
}

private final class ASEMissingList: NSView {
    let store: AppbridgeStore
    override var isFlipped: Bool { true }
    init(store: AppbridgeStore) { self.store = store; super.init(frame: .zero); rebuild() }
    required init?(coder: NSCoder) { fatalError() }
    func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        for (i, file) in store.missing.enumerated() {
            let y = CGFloat(i) * 84
            let icon = NSImageView(frame: NSRect(x: 0, y: y, width: 20, height: 25)); icon.image = ASEIcon.image; addSubview(icon)
            let name = Design.text(file.url.lastPathComponent, .bodyStrong); name.frame = NSRect(x: 28, y: y, width: 390, height: 24); addSubview(name)
            let path = Design.text(file.url.deletingLastPathComponent().path, .caption); path.frame = NSRect(x: 28, y: y + 25, width: 390, height: 24); path.lineBreakMode = .byTruncatingMiddle; addSubview(path)
            let locate = AppbridgeListButton("Locate…") { [weak self] in guard let self else { return }; self.store.locate(file) { [weak self] in self?.rebuild() } }
            let remove = AppbridgeListButton("Remove") { [weak self] in guard let self else { return }; self.store.detach(file); self.rebuild() }
            locate.frame = NSRect(x: 28, y: y + 50, width: 100, height: 28); remove.frame = NSRect(x: 140, y: y + 50, width: 100, height: 28)
            addSubview(locate); addSubview(remove)
        }
        if store.missing.isEmpty { let label = Design.text("No missing ASE files.", .body); label.frame = NSRect(x: 0, y: 0, width: 400, height: 28); addSubview(label) }
        frame.size.height = max(56, CGFloat(store.missing.count) * 84)
    }
}

/// Title-sized filename entry with the requested blinking block insertion cursor.
final class ASENameEditor: NSTextView {
    var onSave: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var pulse: Timer?
    private var visibleCaret = true
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pulse?.invalidate(); pulse = nil
        insertionPointColor = .clear
        guard window != nil else { return }
        pulse = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }; self.visibleCaret.toggle(); self.needsDisplay = true
        }
    }
    deinit { pulse?.invalidate() }
    override func insertNewline(_ sender: Any?) { onSave?(string) }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {}
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard visibleCaret, let window, window.firstResponder === self, selectedRange().length == 0 else { return }
        let screen = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        let caret = convert(window.convertFromScreen(screen), from: nil)
        Design.ink.setFill()
        NSRect(x: caret.minX, y: caret.minY + 2, width: 6, height: max(16, (font?.capHeight ?? 16) + 3)).fill()
    }
}
