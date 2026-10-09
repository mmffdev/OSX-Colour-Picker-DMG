import Foundation
import CryptoKit

// ---------- Sharing: a level of the catalogue as one checked file, and bringing one in ----------
//
// Any of four levels goes out as one zip: the whole catalogue, a collection, a work group (a member,
// or a level between with its members) or a palette. The zip holds the files as the tree keeps them,
// under the subject's own folder, and a manifest naming the level, every file and its SHA-256. The
// person exporting ticks what goes, down to a single palette.
//
// Coming in, a zip is opened into a staging folder and checked before the catalogue is touched: the
// manifest, the structure the level calls for, every file's digest, and whether it can land where
// it is pointed. What is already in the catalogue is found by id, by the colours themselves, or by
// name in the same place, and each twin is replaced, skipped, renamed or kept beside the old. Only
// then is anything written, as one change the history can undo.

enum ShareLevel: String, Codable, CaseIterable {
    case catalogue, collection, workGroup, palette
    var title: String {
        switch self {
        case .catalogue: return "Catalogue"
        case .collection: return "Collection"
        case .workGroup: return "Work Group"
        case .palette: return "Palette"
        }
    }
}

struct ShareManifest: Codable, Equatable {
    struct Named: Codable, Equatable { var id: UUID; var name: String }
    struct File: Codable, Equatable { var path: String; var bytes: Int; var sha256: String }
    var format = "colour-share"
    var version = 1
    var generator = ColourFiles.generator
    var level: ShareLevel
    var exportedAt: Date
    var catalogue: Named
    var subject: Named
    var files: [File]
    static let fileName = "manifest.colmanifest"
}

/// One row of what a share holds, as the Contents step lists it: a folder or a file of the tree, with what is beneath it.
struct ShareNode: Equatable {
    enum Kind: Equatable { case catalogue, collection, group, member, bucket, library, pool, templates, template, palette }
    /// The node's path, relative to the share's root; unique, and the key the ticks are kept by.
    let id: String
    let kind: Kind
    let name: String
    /// The files that are the node's own: its document, or the palette itself, and any loose file beside its document.
    var files: [String]
    var children: [ShareNode]
    /// Every file the node and everything beneath it own.
    var allFiles: [String] { files + children.flatMap { $0.allFiles } }
    /// Every node beneath, itself first.
    var flattened: [(node: ShareNode, level: Int)] {
        func walk(_ n: ShareNode, _ level: Int) -> [(ShareNode, Int)] { [(n, level)] + n.children.flatMap { walk($0, level + 1) } }
        return walk(self, 0)
    }
    var palettes: Int { (kind == .palette ? 1 : 0) + children.reduce(0) { $0 + $1.palettes } }
    func node(_ id: String) -> ShareNode? { self.id == id ? self : children.lazy.compactMap { $0.node(id) }.first }
    /// The ids of the node's ancestors in a tree, root first.
    static func ancestors(of id: String, in root: ShareNode) -> [String] {
        func walk(_ n: ShareNode, _ path: [String]) -> [String]? {
            if n.id == id { return path }
            for c in n.children { if let found = walk(c, path + [n.id]) { return found } }
            return nil
        }
        return walk(root, []) ?? []
    }
}

enum ShareFault: LocalizedError {
    case notAShare(String)
    case wrongLevel(ShareLevel, String)
    case failed([String])
    var errorDescription: String? {
        switch self {
        case .notAShare(let why): return "This is not a Colorgain share: \(why)."
        case .wrongLevel(let level, let why): return "This is a \(level.title.lowercased()) share, and \(why)."
        case .failed(let problems): return problems.joined(separator: "\n")
        }
    }
}

enum Sharing {
    private static let fm = FileManager.default
    private static var e: JSONEncoder { ColourFiles.encoder() }
    private static var d: JSONDecoder { ColourFiles.decoder() }

    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// A path under `base`, with "/" between its parts.
    static func relative(_ url: URL, to base: URL) -> String {
        Array(url.pathComponents.dropFirst(base.pathComponents.count)).joined(separator: "/")
    }

    // MARK: What a level holds

    /// The tree of a subject in a catalogue: the whole catalogue, a collection's or work group's folder, or one palette file.
    /// Every node's id is its path relative to the share's root, which is the subject folder's parent, or the catalogue's root.
    static func tree(level: ShareLevel, subject: URL, root: URL) -> ShareNode {
        let base = level == .catalogue ? root : subject.deletingLastPathComponent()
        func rel(_ u: URL) -> String { relative(u, to: base) }
        func looseFiles(in dir: URL, except keep: Set<String>) -> [String] {
            CatalogueTree.names(in: dir).map { dir.appendingPathComponent($0) }.filter { !CatalogueTree.isFolder($0) && !keep.contains($0.lastPathComponent) }.map(rel)
        }
        func paletteNodes(in dir: URL) -> [ShareNode] {
            CatalogueTree.files(of: dir, extension: ColourFiles.palette).map { url in
                let doc = CatalogueTree.read(PaletteDocument.self, at: url)
                return ShareNode(id: rel(url), kind: .palette, name: doc?.palette.name ?? url.deletingPathExtension().lastPathComponent, files: [rel(url)], children: [])
            }
        }
        /// A member's groups: every folder that is not a work group, with its palettes and the folders inside it.
        func buckets(in dir: URL) -> [ShareNode] {
            CatalogueTree.subfolders(of: dir).filter { CatalogueTree.document(in: $0, extension: TreeFiles.workGroup) == nil }.map { sub in
                let palettes = paletteNodes(in: sub)
                let keep = Set(palettes.map { ($0.id as NSString).lastPathComponent })
                return ShareNode(id: rel(sub), kind: .bucket, name: sub.lastPathComponent, files: looseFiles(in: sub, except: keep), children: palettes + buckets(in: sub))
            }
        }
        func workGroup(_ dir: URL) -> ShareNode? {
            guard let file = CatalogueTree.document(in: dir, extension: TreeFiles.workGroup), let doc = CatalogueTree.read(WorkGroupDocument.self, at: file) else { return nil }
            if doc.kind == .group {
                let members = CatalogueTree.subfolders(of: dir).compactMap(workGroup)
                return ShareNode(id: rel(dir), kind: .group, name: doc.name, files: [rel(file)] + looseFiles(in: dir, except: [file.lastPathComponent]), children: members)
            }
            return ShareNode(id: rel(dir), kind: .member, name: doc.name, files: [rel(file)] + looseFiles(in: dir, except: [file.lastPathComponent]), children: paletteNodes(in: dir) + buckets(in: dir))
        }
        func collection(_ dir: URL) -> ShareNode? {
            guard let file = CatalogueTree.document(in: dir, extension: TreeFiles.collection), let doc = CatalogueTree.read(CollectionDocument.self, at: file) else { return nil }
            return ShareNode(id: rel(dir), kind: .collection, name: doc.name, files: [rel(file)] + looseFiles(in: dir, except: [file.lastPathComponent]), children: CatalogueTree.subfolders(of: dir).compactMap(workGroup))
        }
        switch level {
        case .palette:
            let doc = CatalogueTree.read(PaletteDocument.self, at: subject)
            return ShareNode(id: rel(subject), kind: .palette, name: doc?.palette.name ?? subject.deletingPathExtension().lastPathComponent, files: [rel(subject)], children: [])
        case .workGroup:
            return workGroup(subject) ?? ShareNode(id: rel(subject), kind: .member, name: subject.lastPathComponent, files: [], children: [])
        case .collection:
            return collection(subject) ?? ShareNode(id: rel(subject), kind: .collection, name: subject.lastPathComponent, files: [], children: [])
        case .catalogue:
            let index = CatalogueFiles.index(in: root)
            var children: [ShareNode] = []
            let library = root.appendingPathComponent(TreeFiles.library)
            if CatalogueTree.isFolder(library) {
                let pools = TreeFiles.pools.map { root.appendingPathComponent(TreeFiles.library).appendingPathComponent($0) }.filter(CatalogueTree.isFolder).map { pool -> ShareNode in
                    let palettes = paletteNodes(in: pool)
                    return ShareNode(id: rel(pool), kind: .pool, name: pool.lastPathComponent, files: looseFiles(in: pool, except: Set(palettes.map { ($0.id as NSString).lastPathComponent })), children: palettes)
                }
                children.append(ShareNode(id: rel(library), kind: .library, name: "Library", files: [], children: pools))
            }
            let templates = root.appendingPathComponent(TreeFiles.templates)
            if CatalogueTree.isFolder(templates) {
                let each = CatalogueTree.files(of: templates, extension: TreeFiles.template).map { url in
                    ShareNode(id: rel(url), kind: .template, name: CatalogueTree.read(TemplateDocument.self, at: url)?.name ?? url.deletingPathExtension().lastPathComponent, files: [rel(url)], children: [])
                }
                children.append(ShareNode(id: rel(templates), kind: .templates, name: "Templates", files: [], children: each))
            }
            for sub in CatalogueTree.subfolders(of: root) where !TreeFiles.reserved.contains(sub.lastPathComponent) {
                if let c = collection(sub) { children.append(c) }
            }
            let name = index.map { CatalogueTree.read(CatalogueIndex.self, at: $0)?.name ?? $0.deletingPathExtension().lastPathComponent } ?? root.lastPathComponent
            return ShareNode(id: "", kind: .catalogue, name: name, files: index.map { [rel($0)] } ?? [], children: children)
        }
    }

    /// The files a set of ticks takes: every ticked node's own files, with the files of its ancestors, which hold what it sits in.
    static func files(ticked: Set<String>, in tree: ShareNode) -> [String] {
        var out: [String] = [], seen = Set<String>()
        for (node, _) in tree.flattened where ticked.contains(node.id) {
            for f in ShareNode.ancestors(of: node.id, in: tree).compactMap({ tree.node($0) }).flatMap({ $0.files }) + node.files where seen.insert(f).inserted { out.append(f) }
        }
        return out
    }

    // MARK: Export

    /// Writes the share: the ticked files under their paths, and the manifest first. With `ticked` nil everything goes.
    @discardableResult
    static func export(level: ShareLevel, subject: URL, root: URL, catalogue: ShareManifest.Named, ticked: Set<String>? = nil, strip: (tags: Bool, notes: Bool) = (false, false), to url: URL, now: Date = Date()) throws -> ShareManifest {
        let tree = self.tree(level: level, subject: subject, root: root)
        let base = level == .catalogue ? root : subject.deletingLastPathComponent()
        let paths = ticked.map { files(ticked: $0, in: tree) } ?? tree.allFiles
        var entries: [Zip.Entry] = [], listed: [ShareManifest.File] = []
        for path in paths where !path.hasSuffix("." + ColourFiles.history) {
            var data = try Data(contentsOf: base.appendingPathComponent(path))
            // Tags and notes are the catalogue's own words: left out when asked, from each palette's file and from the index's global tags.
            if (strip.tags || strip.notes), path.hasSuffix("." + ColourFiles.palette), var doc = try? d.decode(PaletteDocument.self, from: data) {
                if strip.tags { doc.palette.tags = nil; doc.palette.tagsChangedAt = nil; doc.colours = doc.colours.map { c in Colour(hex: c.hex, pickedAt: c.pickedAt, source: c.source, master: c.master, kind: c.kind) } }
                if strip.notes { doc.palette.entries = doc.palette.entries.map { e in var x = e; x.note = nil; x.noteChangedAt = nil; return x } }
                data = try e.encode(doc)
            }
            if strip.tags, path.hasSuffix("." + ColourFiles.catalogue), var index = CatalogueTree.decode(data) { index.tags = []; data = try e.encode(index) }
            if strip.tags, path.hasSuffix("." + TreeFiles.workGroup), var doc = try? d.decode(WorkGroupDocument.self, from: data) { doc.tags = nil; data = try e.encode(doc) }
            entries.append(Zip.Entry(path: path, data: data))
            listed.append(ShareManifest.File(path: path, bytes: data.count, sha256: sha256(data)))
        }
        let subjectID: UUID = {
            switch level {
            case .catalogue: return catalogue.id
            case .collection: return CatalogueTree.document(in: subject, extension: TreeFiles.collection).flatMap { CatalogueTree.read(CollectionDocument.self, at: $0)?.id } ?? UUID()
            case .workGroup: return CatalogueTree.document(in: subject, extension: TreeFiles.workGroup).flatMap { CatalogueTree.read(WorkGroupDocument.self, at: $0)?.id } ?? UUID()
            case .palette: return CatalogueTree.read(PaletteDocument.self, at: subject)?.palette.id ?? UUID()
            }
        }()
        let manifest = ShareManifest(level: level, exportedAt: now, catalogue: catalogue, subject: ShareManifest.Named(id: subjectID, name: tree.name), files: listed)
        try Zip.write([Zip.Entry(path: ShareManifest.fileName, data: try e.encode(manifest))] + entries, to: url, at: now)
        return manifest
    }

    // MARK: Checking what came

    struct Inspection {
        var manifest: ShareManifest
        var entries: [Zip.Entry]
        /// What is wrong, in words; nothing wrong is an empty list.
        var problems: [String]
        var ok: Bool { problems.isEmpty }
        var tree: ShareNode
    }

    /// Opens the zip and checks it: the manifest, every file against its digest, nothing unlisted, and the shape its level calls for.
    static func inspect(_ url: URL) throws -> Inspection {
        let entries = try Zip.read(url)
        guard let m = entries.first(where: { $0.path == ShareManifest.fileName }) else { throw ShareFault.notAShare("there is no manifest in it") }
        guard let manifest = try? d.decode(ShareManifest.self, from: m.data), manifest.format == "colour-share" else { throw ShareFault.notAShare("its manifest could not be read") }
        var problems: [String] = []
        let byPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        for f in manifest.files {
            guard let entry = byPath[f.path] else { problems.append("\(f.path) is listed but missing"); continue }
            if entry.data.count != f.bytes { problems.append("\(f.path) is \(entry.data.count) bytes, not the \(f.bytes) listed") }
            else if sha256(entry.data) != f.sha256 { problems.append("\(f.path) does not match its digest: it was changed after it was exported") }
        }
        let listed = Set(manifest.files.map { $0.path })
        for entry in entries where entry.path != ShareManifest.fileName && !listed.contains(entry.path) { problems.append("\(entry.path) is in the file but not in its manifest") }
        // The shape the level calls for.
        let tops = Set(entries.filter { $0.path != ShareManifest.fileName }.map { $0.path.split(separator: "/").first.map(String.init) ?? "" })
        switch manifest.level {
        case .catalogue:
            if !entries.contains(where: { !$0.path.contains("/") && $0.path.hasSuffix("." + ColourFiles.catalogue) }) { problems.append("a catalogue share needs its index at the top, and this has none") }
        case .collection:
            if tops.count != 1 || !entries.contains(where: { $0.path.hasSuffix("." + TreeFiles.collection) && $0.path.split(separator: "/").count == 2 }) { problems.append("a collection share is one folder with its collection file inside, and this is not") }
        case .workGroup:
            if tops.count != 1 || !entries.contains(where: { $0.path.hasSuffix("." + TreeFiles.workGroup) && $0.path.split(separator: "/").count == 2 }) { problems.append("a work group share is one folder with its work group file inside, and this is not") }
        case .palette:
            if entries.filter({ $0.path != ShareManifest.fileName }).count != 1 || !entries.contains(where: { !$0.path.contains("/") && $0.path.hasSuffix("." + ColourFiles.palette) }) { problems.append("a palette share is one palette file, and this is not") }
        }
        // The tree, from the entries themselves, so the Contents step can list what is there before anything is written.
        let staging = try stage(entries: entries)
        defer { discard(staging) }
        let tree = treeOfStaging(staging, level: manifest.level)
        return Inspection(manifest: manifest, entries: entries, problems: problems, tree: tree)
    }

    private static func treeOfStaging(_ staging: URL, level: ShareLevel) -> ShareNode {
        switch level {
        case .catalogue: return tree(level: .catalogue, subject: staging, root: staging)
        case .palette:
            let file = CatalogueTree.files(of: staging, extension: ColourFiles.palette).first ?? staging
            return tree(level: .palette, subject: file, root: staging)
        case .collection, .workGroup:
            let folder = CatalogueTree.subfolders(of: staging).first ?? staging
            return tree(level: level, subject: folder, root: staging)
        }
    }

    // MARK: Staging

    /// Where shares are unpacked while they are checked and chosen from: the app's own temporary folder, inside the container under the sandbox.
    static var stagingRoot: URL { fm.temporaryDirectory.appendingPathComponent("Colorgain Staging") }

    /// Writes the entries into a fresh folder of their own.
    static func stage(entries: [Zip.Entry]) throws -> URL {
        let dir = stagingRoot.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for entry in entries where entry.path != ShareManifest.fileName {
            // Nothing may reach outside the staging folder, whatever the path says.
            let parts = entry.path.split(separator: "/").map(String.init)
            guard !parts.contains(".."), !parts.isEmpty else { continue }
            let url = parts.reduce(dir) { $0.appendingPathComponent($1) }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try entry.data.write(to: url)
        }
        return dir
    }
    static func stage(_ inspection: Inspection) throws -> URL { try stage(entries: inspection.entries) }
    static func discard(_ staging: URL) { try? fm.removeItem(at: staging) }

    /// What was staged, read as a library of its own: a catalogue whole, or a collection or work group wrapped in a makeshift
    /// catalogue so the tree reader can take it; a palette on its own.
    struct Staged {
        var level: ShareLevel
        var root: URL
        var library: Library
        var schema: SchemaTrial.SchemaFile
        /// For a palette share: the palette and the colours it uses.
        var palette: (Swatch, [Colour])?
        /// Where each member, collection and palette of the staged library came from, by id, as the tree's node id.
        var paths: [UUID: String] = [:]
    }

    static func read(staging: URL, level: ShareLevel) throws -> Staged {
        var staged = Staged(level: level, root: staging, library: Library(), schema: .fresh, palette: nil)
        switch level {
        case .palette:
            guard let file = CatalogueTree.files(of: staging, extension: ColourFiles.palette).first, let doc = CatalogueTree.read(PaletteDocument.self, at: file) else { throw ShareFault.notAShare("the palette could not be read") }
            var p = doc.palette
            p.projectID = nil
            staged.palette = (p, doc.colours)
            staged.paths[p.id] = relative(file, to: staging)
            return staged
        case .catalogue:
            break
        case .collection:
            // The one folder is a collection: an index naming it makes the staging a catalogue.
            guard let folder = CatalogueTree.subfolders(of: staging).first, let file = CatalogueTree.document(in: folder, extension: TreeFiles.collection), let doc = CatalogueTree.read(CollectionDocument.self, at: file) else { throw ShareFault.notAShare("the collection could not be read") }
            try writeIndex(at: staging, collections: [doc.id])
        case .workGroup:
            // The one folder is a work group: it goes inside a makeshift collection, which an index names.
            guard let folder = CatalogueTree.subfolders(of: staging).first else { throw ShareFault.notAShare("the work group could not be read") }
            let wrap = staging.appendingPathComponent("Imported")
            try fm.createDirectory(at: wrap, withIntermediateDirectories: true)
            try fm.moveItem(at: folder, to: wrap.appendingPathComponent(folder.lastPathComponent))
            let id = UUID()
            let collection = CollectionDocument(id: id, name: "Imported", about: "", folder: "Imported", groupName: nil, template: SchemaTrial.start, templateID: nil, members: [], changedAt: Date())
            try e.encode(collection).write(to: wrap.appendingPathComponent("Imported." + TreeFiles.collection))
            try writeIndex(at: staging, collections: [id])
        }
        let loaded = try CatalogueTree.read(root: staging)
        staged.library = loaded.library
        staged.schema = loaded.schema
        for p in loaded.library.projects { if let url = CatalogueTree.folder(ofWorkGroup: p.id, in: staging) { staged.paths[p.id] = relative(url, to: staging) } }
        for c in loaded.schema.collections {
            for f in c.folders { if let url = CatalogueTree.folder(ofWorkGroup: f.id, in: staging) { staged.paths[f.id] = relative(url, to: staging) } }
        }
        for s in loaded.library.swatches { if let url = CatalogueTree.file(ofPalette: s.id, in: staging) { staged.paths[s.id] = relative(url, to: staging) } }
        for sub in CatalogueTree.subfolders(of: staging) {
            if let file = CatalogueTree.document(in: sub, extension: TreeFiles.collection), let doc = CatalogueTree.read(CollectionDocument.self, at: file) { staged.paths[doc.id] = relative(sub, to: staging) }
        }
        return staged
    }

    private static func writeIndex(at root: URL, collections: [UUID], now: Date = Date()) throws {
        let index = CatalogueIndex(id: UUID(), name: "Staged", createdAt: now, changedAt: now, library: 2, collections: collections, templates: [], colours: [], tags: [], activePalette: nil, deleted: [], about: nil)
        try e.encode(index).write(to: root.appendingPathComponent("Staged." + ColourFiles.catalogue))
    }

    // MARK: Where it lands

    enum Placement: Equatable, Hashable {
        /// The catalogue itself: a catalogue or collection share merges into it.
        case catalogue
        /// A collection, for a work group; with a level between, when the collection groups its members.
        case collection(UUID, UUID?)
        /// A member, for a palette.
        case member(UUID)
        /// The Library pool, for a palette.
        case pool
    }

    /// The places a share of this level may land, in rail order, each with its name.
    static func placements(for level: ShareLevel, in lib: Library, schema: SchemaTrial.SchemaFile) -> [(Placement, String)] {
        switch level {
        case .catalogue, .collection: return [(.catalogue, "This catalogue")]
        case .workGroup:
            var out: [(Placement, String)] = []
            for c in schema.collections {
                out.append((.collection(c.id, nil), c.name))
                for f in c.folders { out.append((.collection(c.id, f.id), "\(c.name): \(f.name)")) }
            }
            return out
        case .palette:
            var out: [(Placement, String)] = [(.pool, "Library")]
            for c in schema.collections {
                for p in lib.orderedProjects where SchemaTrial.collection(of: p.id, among: schema.collections, places: schema.places).id == c.id {
                    out.append((.member(p.id), "\(c.name): \(p.name)"))
                }
            }
            return out
        }
    }

    // MARK: Twins

    struct Duplicate: Equatable, Hashable {
        enum Kind: Equatable, Hashable { case collection, group, member, palette }
        enum Why: Equatable, Hashable { case sameID, sameColours, sameName }
        var kind: Kind
        var id: UUID
        var name: String
        var why: Why
        /// What it clashes with, by name.
        var existing: String
    }
    enum Resolution: String, CaseIterable {
        case replace, skip, rename, keepBoth
        var title: String {
            switch self {
            case .replace: return "Replace"
            case .skip: return "Skip"
            case .rename: return "Rename"
            case .keepBoth: return "Keep Both"
            }
        }
    }

    /// The colours a palette holds, as the keys the catalogue holds them by: hex for an sRGB colour, the colour's own key beyond it.
    private static func coloursOf(_ s: Swatch) -> Set<String> { Set(s.entries.map { $0.hex } + (s.styles ?? []).flatMap { [$0.ink, $0.paper] }) }

    /// What in the share is already in the catalogue, among what is ticked, where it would land.
    static func duplicates(in staged: Staged, ticked: Set<String>?, into lib: Library, schema: SchemaTrial.SchemaFile, placement: Placement) -> [Duplicate] {
        var out: [Duplicate] = []
        func included(_ id: UUID) -> Bool { ticked.map { t in staged.paths[id].map { t.contains($0) } ?? true } ?? true }
        func paletteTwins(_ s: Swatch, home: UUID?) {
            if let have = lib.swatch(s.id) { out.append(Duplicate(kind: .palette, id: s.id, name: s.name, why: .sameID, existing: have.name)); return }
            let colours = coloursOf(s)
            if !colours.isEmpty, let same = lib.swatches.first(where: { coloursOf($0) == colours && $0.isTypography == s.isTypography }) { out.append(Duplicate(kind: .palette, id: s.id, name: s.name, why: .sameColours, existing: same.name)); return }
            if let same = lib.palettes(in: home).first(where: { $0.name.lowercased() == s.name.lowercased() }) { out.append(Duplicate(kind: .palette, id: s.id, name: s.name, why: .sameName, existing: same.name)) }
        }
        if let (p, _) = staged.palette {
            let home: UUID? = { if case .member(let m) = placement { return m }; return nil }()
            paletteTwins(p, home: home)
            return out
        }
        let all = staged.schema.collections, places = staged.schema.places
        for c in all where staged.level != .workGroup && included(c.id) {
            if let have = schema.collections.first(where: { $0.id == c.id }) { out.append(Duplicate(kind: .collection, id: c.id, name: c.name, why: .sameID, existing: have.name)) }
            else if let same = schema.collections.first(where: { $0.name.lowercased() == c.name.lowercased() }) { out.append(Duplicate(kind: .collection, id: c.id, name: c.name, why: .sameName, existing: same.name)) }
            for f in c.folders where included(f.id) {
                if schema.collections.contains(where: { $0.folders.contains { $0.id == f.id } }) { out.append(Duplicate(kind: .group, id: f.id, name: f.name, why: .sameID, existing: f.name)) }
            }
        }
        for p in staged.library.orderedProjects where included(p.id) {
            let homeCollection: UUID? = {
                if case .collection(let c, _) = placement { return c }
                return SchemaTrial.collection(of: p.id, among: all, places: places).id
            }()
            if let have = lib.project(p.id) { out.append(Duplicate(kind: .member, id: p.id, name: p.name, why: .sameID, existing: have.name)) }
            else if let same = lib.orderedProjects.first(where: { $0.name.lowercased() == p.name.lowercased() && SchemaTrial.collection(of: $0.id, among: schema.collections, places: schema.places).id == homeCollection }) {
                out.append(Duplicate(kind: .member, id: p.id, name: p.name, why: .sameName, existing: same.name))
            }
            for s in staged.library.palettes(in: p.id) where included(s.id) { paletteTwins(s, home: lib.project(p.id) != nil ? p.id : nil) }
        }
        for s in staged.library.palettes(in: nil) where included(s.id) { paletteTwins(s, home: nil) }
        return out
    }

    // MARK: Bringing it in

    struct Choices {
        var ticked: Set<String>?
        var placement: Placement
        var resolutions: [UUID: Resolution] = [:]
        /// The answer for anything not answered on its own.
        var otherwise: Resolution = .keepBoth
    }
    struct Outcome: Equatable {
        var added = 0, replaced = 0, skipped = 0, renamed = 0
        var members = 0, palettes = 0
    }

    /// Writes the share into the catalogue as the choices say, as one change.
    static func commit(_ staged: Staged, choices: Choices, into lib: inout Library, schema: inout SchemaTrial.SchemaFile, at date: Date = Date()) -> Outcome {
        var out = Outcome()
        let twins = duplicates(in: staged, ticked: choices.ticked, into: lib, schema: schema, placement: choices.placement)
        func answer(_ id: UUID) -> Resolution? { twins.contains { $0.id == id } ? (choices.resolutions[id] ?? choices.otherwise) : nil }
        func included(_ id: UUID) -> Bool { choices.ticked.map { t in staged.paths[id].map { t.contains($0) } ?? true } ?? true }
        /// The twin a palette replaces, by id or by the colours it holds.
        func twin(of s: Swatch, in home: UUID?) -> UUID? {
            if lib.swatch(s.id) != nil { return s.id }
            let colours = coloursOf(s)
            if !colours.isEmpty, let same = lib.swatches.first(where: { coloursOf($0) == colours && $0.isTypography == s.isTypography }) { return same.id }
            return lib.palettes(in: home).first { $0.name.lowercased() == s.name.lowercased() }?.id
        }
        func takeColours(_ colours: [Colour]) {
            for c in colours where !lib.colours.contains(where: { $0.hex == c.hex }) { lib.colours.append(c) }
        }
        func takeTags(_ tags: [TagInfo], member: [UUID: UUID]) {
            for var t in tags where t.removed != true {
                if let p = t.projectID { guard let now = member[p] else { continue }; t.projectID = now }
                if lib.info(forTag: t.name) == nil { lib.tagInfo.append(t) }
            }
        }
        /// Puts one palette in, by the answer for it, into `home` (nil: the Library).
        func take(_ s: Swatch, colours: [Colour], into home: UUID?) {
            guard included(s.id) else { return }
            var p = s
            p.projectID = home
            switch answer(s.id) {
            case .skip?: out.skipped += 1; return
            case .replace?:
                if let old = twin(of: s, in: home), let at = lib.swatches.firstIndex(where: { $0.id == old }) {
                    p.position = lib.swatches[at].position
                    lib.swatches[at] = p
                } else { lib.swatches.append(p) }
                out.replaced += 1
            case .rename?:
                if lib.swatch(p.id) != nil { p = renamedCopy(p, date: date) }
                p.name = uniqueName(p.name, among: lib.swatches.map { $0.name })
                p.nameChangedAt = date
                lib.swatches.append(p)
                out.renamed += 1
            case .keepBoth?:
                if lib.swatch(p.id) != nil { p = renamedCopy(p, date: date) }
                lib.swatches.append(p)
                out.added += 1
            case nil:
                lib.swatches.append(p)
                out.added += 1
            }
            takeColours(colours)
            out.palettes += 1
        }
        /// A palette share, or everything in a staged library.
        if let (p, colours) = staged.palette {
            let home: UUID? = { if case .member(let m) = choices.placement { return m }; return nil }()
            take(p, colours: colours, into: home)
            return out
        }
        let all = staged.schema.collections, places = staged.schema.places
        /// Which incoming collection id became which, and which member.
        var collectionNow: [UUID: UUID] = [:], folderNow: [UUID: UUID] = [:], memberNow: [UUID: UUID] = [:]
        if staged.level != .workGroup {
            for c in all where included(c.id) {
                var made = c
                switch answer(c.id) {
                case .skip?: out.skipped += 1; continue
                case .replace?:
                    if let at = schema.collections.firstIndex(where: { $0.id == c.id || $0.name.lowercased() == c.name.lowercased() }) {
                        made.id = schema.collections[at].id
                        made.folders = schema.collections[at].folders
                        for f in c.folders where !made.folders.contains(where: { $0.id == f.id }) { made.folders.append(f) }
                        schema.collections[at] = made
                    } else { schema.collections.append(made) }
                    out.replaced += 1
                case .rename?, .keepBoth?:
                    if schema.collections.contains(where: { $0.id == c.id }) { made.id = UUID() }
                    if answer(c.id) == .rename || schema.collections.contains(where: { $0.name.lowercased() == c.name.lowercased() }) { made.name = uniqueName(c.name, among: schema.collections.map { $0.name }) }
                    made.folders = c.folders.map { f in var g = f; if schema.collections.contains(where: { $0.folders.contains { $0.id == f.id } }) { g.id = UUID() }; folderNow[f.id] = g.id; return g }
                    schema.collections.append(made)
                    if answer(c.id) == .rename { out.renamed += 1 } else { out.added += 1 }
                case nil:
                    if schema.collections.contains(where: { $0.id == c.id }) { made.id = UUID() }
                    schema.collections.append(made)
                    out.added += 1
                }
                collectionNow[c.id] = made.id
                for f in c.folders where folderNow[f.id] == nil { folderNow[f.id] = f.id }
            }
        }
        for p in staged.library.orderedProjects where included(p.id) {
            let from = SchemaTrial.collection(of: p.id, among: all, places: places).id
            let folderFrom = SchemaTrial.folder(of: p.id, among: all, places: places)
            // Where it lands: the placement for a work group share, else the collection it came in, as taken.
            var toCollection: UUID, toFolder: UUID?
            if case .collection(let c, let f) = choices.placement { toCollection = c; toFolder = f }
            else { guard let c = collectionNow[from] else { continue }; toCollection = c; toFolder = folderFrom.flatMap { folderNow[$0] } }
            if let f = toFolder, !(schema.collections.first { $0.id == toCollection }?.folders.contains { $0.id == f } ?? false) { toFolder = nil }
            var made = p
            made.folder = nil; made.fileKnown = nil
            var replacing = false
            switch answer(p.id) {
            case .skip?: out.skipped += 1; continue
            case .replace?:
                let old = lib.project(p.id)?.id ?? lib.orderedProjects.first { $0.name.lowercased() == p.name.lowercased() && SchemaTrial.collection(of: $0.id, among: schema.collections, places: schema.places).id == toCollection }?.id
                if let old = old {
                    made = made.withID(old)
                    made.position = lib.project(old)?.position
                    // Its palettes go, for the share's to take their place.
                    for s in lib.palettes(in: old) { lib.deleteSwatch(s.id, at: date) }
                    lib.projects.removeAll { $0.id == old }
                    replacing = true
                }
                out.replaced += 1
            case .rename?, .keepBoth?:
                if lib.project(p.id) != nil { made = made.withID(UUID()) }
                let names = lib.orderedProjects.filter { SchemaTrial.collection(of: $0.id, among: schema.collections, places: schema.places).id == toCollection }.map { $0.name }
                if answer(p.id) == .rename || names.contains(where: { $0.lowercased() == p.name.lowercased() }) { made.name = uniqueName(p.name, among: names); made.nameChangedAt = date }
                if answer(p.id) == .rename { out.renamed += 1 } else { out.added += 1 }
            case nil:
                if lib.project(p.id) != nil { made = made.withID(UUID()) }
                out.added += 1
            }
            if !replacing { made.position = (lib.projects.compactMap { $0.position }.max() ?? -1) + 1; made.positionChangedAt = date }
            lib.projects.append(made)
            memberNow[p.id] = made.id
            schema.places[made.id.uuidString] = SchemaPlace(collection: toCollection, folder: toFolder)
            if let own = staged.schema.stacks?[p.id.uuidString] { var stacks = schema.stacks ?? [:]; stacks[made.id.uuidString] = own; schema.stacks = stacks }
            out.members += 1
            for s in staged.library.palettes(in: p.id) { take(s, colours: staged.library.colours.filter { c in coloursOf(s).contains(c.hex) }, into: made.id) }
        }
        if staged.level == .catalogue {
            for s in staged.library.palettes(in: nil) { take(s, colours: staged.library.colours.filter { c in coloursOf(s).contains(c.hex) }, into: nil) }
            takeColours(staged.library.colours)
            for profile in staged.library.colourProfiles where !lib.colourProfiles.contains(where: { $0.id == profile.id }) { lib.colourProfiles.append(profile) }
            for t in staged.schema.templates ?? [] where !(schema.templates ?? []).contains(where: { $0.id == t.id }) { schema.templates = (schema.templates ?? []) + [t] }
        }
        takeTags(staged.library.tagInfo, member: memberNow)
        return out
    }

}

extension Project {
    /// The same record under another id.
    func withID(_ id: UUID) -> Project {
        Project(id: id, name: name, createdAt: createdAt, nameChangedAt: nameChangedAt, position: position, positionChangedAt: positionChangedAt, details: details,
                detailsChangedAt: detailsChangedAt, folder: nil, fileKnown: nil, locked: locked, profile: profile, profileChangedAt: profileChangedAt)
    }
}

extension Sharing {
    /// For the self-test: a palette under a new id.
    static func renamedCopyForTest(_ s: Swatch) -> Swatch { renamedCopy(s, date: Date()) }
    /// The same palette under a new id, its pairings renewed with it, so it stands beside the one it came from.
    private static func renamedCopy(_ s: Swatch, date: Date) -> Swatch {
        var p = Swatch(id: UUID(), name: s.name, createdAt: s.createdAt, entries: s.entries)
        p.nameChangedAt = s.nameChangedAt; p.isFavourite = s.isFavourite; p.favouriteChangedAt = s.favouriteChangedAt; p.isCustom = s.isCustom
        p.projectID = s.projectID; p.position = s.position; p.placedAt = s.placedAt; p.tags = s.tags; p.tagsChangedAt = s.tagsChangedAt
        p.styles = s.styles?.map { TypeStyle(id: UUID(), name: $0.name, ink: $0.ink, paper: $0.paper, heading: $0.heading, body: $0.body, headingFont: $0.headingFont, bodyFont: $0.bodyFont) }
        p.stylesChangedAt = s.stylesChangedAt; p.copiedFrom = s.id; p.profile = s.profile; p.profileChangedAt = s.profileChangedAt
        p.purposes = s.purposes; p.purpose = s.purpose; p.purposeChangedAt = s.purposeChangedAt
        return p
    }
}
