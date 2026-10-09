import Foundation
import CryptoKit

// ---------- Sharing: any level of the catalogue as one checked file, and bringing one in ----------
//
// A share is a small catalogue of its own. Any of four levels goes out: the whole catalogue, a
// collection, a work group (a member, or a level between with its members) or a palette. The app
// cuts that branch from the structure, with what is ticked beneath it and the collection and level
// between it sat in, writes it as a catalogue in a scratch folder, and zips it with a manifest naming
// the level, where the subject came from, and every file with its SHA-256. A palette goes as its one
// file. The person exporting ticks what goes, down to a single palette.
//
// Coming in, a zip is opened into a staging folder and checked before the catalogue is touched: the
// manifest, the shape the level calls for, every file's digest, and whether it can land where it is
// pointed. The staging folder is read as a catalogue, by the same reader as any other. The place it
// came from is offered first, and any other place it may go is a choice. What is already in the
// catalogue is found by id, by the colours themselves, or by name in the same place, and each twin is
// replaced, skipped, renamed or kept beside the old. Only then is anything written, as one change the
// history can undo.

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
    /// Where the subject sat in the catalogue it came from, so bringing it in can follow the same blueprint.
    struct Origin: Codable, Equatable { var collection: Named?; var group: Named?; var member: Named? }
    var format = "colour-share"
    var version = 2
    var generator = ColourFiles.generator
    var level: ShareLevel
    var exportedAt: Date
    var catalogue: Named
    var subject: Named
    var origin: Origin?
    var files: [File]
    static let fileName = "manifest.colmanifest"
}

/// One row of what a share holds, as the Contents step lists it, with what is beneath it.
struct ShareNode: Equatable {
    enum Kind: Equatable { case catalogue, collection, group, member, bucket, library, pool, templates, template, palette }
    /// The id of what the row stands for; the Library, its pools, the Templates and a member's groups have ids of words. The key the ticks are kept by.
    let id: String
    let kind: Kind
    let name: String
    var children: [ShareNode]
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
    static func relative(_ url: URL, to base: URL) -> String { CatalogueTree.relative(url, to: base) }

    // MARK: What a level holds

    /// The tree of a subject, from the library and schema: the whole catalogue, a collection, a member or a level between,
    /// or one palette. Every node's id is the id of what it stands for, so a tick follows the thing, not a path.
    static func tree(level: ShareLevel, subject: UUID?, in lib: Library, schema: SchemaTrial.SchemaFile, catalogueName: String) -> ShareNode {
        func paletteNode(_ s: Swatch) -> ShareNode { ShareNode(id: s.id.uuidString, kind: .palette, name: s.name, children: []) }
        func memberNode(_ p: Project) -> ShareNode {
            let held = lib.palettes(in: p.id)
            let tree = schema.stacks?[p.id.uuidString] ?? SchemaTrial.collection(of: p.id, among: schema.collections, places: schema.places).stack
            func groups(_ n: SchemaNode) -> [ShareNode] {
                n.children.map { child in
                    var kids: [ShareNode] = []
                    switch SchemaTrial.role(of: child) {
                    case .palettes?: kids = held.filter { !$0.isTypography }.map(paletteNode)
                    case .typography?: kids = held.filter { $0.isTypography }.map(paletteNode)
                    default: break
                    }
                    return ShareNode(id: "bucket:\(p.id.uuidString):\(child.id.uuidString)", kind: .bucket, name: child.name, children: kids + groups(child))
                }
            }
            var children = groups(tree)
            let roles = Set(SchemaTrial.rows(of: tree).compactMap { SchemaTrial.role(of: $0.node) })
            // Palettes whose kind has no group in the member's schema still go, straight under the member.
            if !roles.contains(.palettes) { children += held.filter { !$0.isTypography }.map(paletteNode) }
            if !roles.contains(.typography) { children += held.filter { $0.isTypography }.map(paletteNode) }
            return ShareNode(id: p.id.uuidString, kind: .member, name: p.name, children: children)
        }
        func members(of c: SchemaCollection, folder: UUID?) -> [Project] {
            lib.orderedProjects.filter { SchemaTrial.collection(of: $0.id, among: schema.collections, places: schema.places).id == c.id
                && SchemaTrial.folder(of: $0.id, among: schema.collections, places: schema.places) == folder }
        }
        func groupNode(_ f: SchemaFolder, in c: SchemaCollection) -> ShareNode {
            ShareNode(id: f.id.uuidString, kind: .group, name: f.name, children: members(of: c, folder: f.id).map(memberNode))
        }
        func collectionNode(_ c: SchemaCollection) -> ShareNode {
            ShareNode(id: c.id.uuidString, kind: .collection, name: c.name, children: c.folders.map { groupNode($0, in: c) } + members(of: c, folder: nil).map(memberNode))
        }
        switch level {
        case .palette:
            guard let id = subject, let s = lib.swatch(id) else { return ShareNode(id: "", kind: .palette, name: "Palette", children: []) }
            return paletteNode(s)
        case .workGroup:
            if let id = subject, let p = lib.project(id) { return memberNode(p) }
            for c in schema.collections { if let f = c.folders.first(where: { $0.id == subject }) { return groupNode(f, in: c) } }
            return ShareNode(id: "", kind: .member, name: "Member", children: [])
        case .collection:
            guard let c = schema.collections.first(where: { $0.id == subject }) else { return ShareNode(id: "", kind: .collection, name: "Collection", children: []) }
            return collectionNode(c)
        case .catalogue:
            let loose = lib.palettes(in: nil)
            let pools = [ShareNode(id: "pool:" + TreeFiles.palettesPool, kind: .pool, name: TreeFiles.palettesPool, children: loose.filter { !$0.isTypography }.map(paletteNode)),
                         ShareNode(id: "pool:" + TreeFiles.typographyPool, kind: .pool, name: TreeFiles.typographyPool, children: loose.filter { $0.isTypography }.map(paletteNode))]
            var children = [ShareNode(id: "library", kind: .library, name: TreeFiles.library, children: pools)]
            if let t = schema.templates, !t.isEmpty {
                children.append(ShareNode(id: "templates", kind: .templates, name: "Templates", children: t.map { ShareNode(id: $0.id.uuidString, kind: .template, name: $0.name, children: []) }))
            }
            children += schema.collections.map(collectionNode)
            return ShareNode(id: "", kind: .catalogue, name: catalogueName, children: children)
        }
    }

    /// The branch a share cuts: the subject and what is ticked beneath it, with the collection and level between it sits in,
    /// as a library and schema of their own. With `ticked` nil everything beneath the subject goes.
    static func cut(level: ShareLevel, subject: UUID?, ticked: Set<String>?, strip: (tags: Bool, notes: Bool) = (false, false),
                    from lib: Library, schema: SchemaTrial.SchemaFile) -> (library: Library, schema: SchemaTrial.SchemaFile) {
        func on(_ id: UUID) -> Bool { ticked.map { $0.contains(id.uuidString) } ?? true }
        func collection(of p: UUID) -> SchemaCollection { SchemaTrial.collection(of: p, among: schema.collections, places: schema.places) }
        func folder(of p: UUID) -> UUID? { SchemaTrial.folder(of: p, among: schema.collections, places: schema.places) }
        var out = Library()
        out.version = lib.version
        var cut = SchemaTrial.SchemaFile(collections: [], places: [:])
        var members: [Project] = [], palettes: [Swatch] = []
        switch level {
        case .palette:
            if let id = subject, var s = lib.swatch(id) { s.projectID = nil; palettes = [s] }
        case .workGroup:
            if let id = subject, let p = lib.project(id) {
                var home = collection(of: id)
                home.folders = home.folders.filter { $0.id == folder(of: id) }
                cut.collections = [home]
                members = [p]
            } else if let c = schema.collections.first(where: { $0.folders.contains { $0.id == subject } }) {
                var home = c
                home.folders = c.folders.filter { $0.id == subject }
                cut.collections = [home]
                members = lib.orderedProjects.filter { collection(of: $0.id).id == c.id && folder(of: $0.id) == subject && on($0.id) }
            }
        case .collection:
            if let c = schema.collections.first(where: { $0.id == subject }) {
                var home = c
                home.folders = c.folders.filter { on($0.id) }
                cut.collections = [home]
                members = lib.orderedProjects.filter { p in collection(of: p.id).id == c.id && on(p.id) && (folder(of: p.id).map { f in home.folders.contains { $0.id == f } } ?? true) }
            }
        case .catalogue:
            cut.collections = schema.collections.filter { on($0.id) }.map { c in var k = c; k.folders = c.folders.filter { on($0.id) }; return k }
            members = lib.orderedProjects.filter { p in on(p.id) && cut.collections.contains { $0.id == collection(of: p.id).id }
                && (folder(of: p.id).map { f in cut.collections.contains { $0.folders.contains { $0.id == f } } } ?? true) }
            palettes = lib.palettes(in: nil).filter { on($0.id) }
            cut.templates = (schema.templates ?? []).filter { on($0.id) }
            if cut.templates?.isEmpty == true { cut.templates = nil }
        }
        for p in members {
            cut.places[p.id.uuidString] = SchemaPlace(collection: collection(of: p.id).id, folder: folder(of: p.id))
            if let own = schema.stacks?[p.id.uuidString] { cut.stacks = (cut.stacks ?? [:]).merging([p.id.uuidString: own]) { a, _ in a } }
            palettes += lib.palettes(in: p.id).filter { on($0.id) }
        }
        out.projects = members.map { var m = $0; m.folder = nil; m.fileKnown = nil; return m }
        out.swatches = palettes
        // The colours the palettes use; the whole catalogue also takes the colours no palette holds.
        let keys = Set(palettes.flatMap { s in s.entries.map { $0.hex } + (s.styles ?? []).flatMap { [$0.ink, $0.paper] } })
        let used = Set(lib.swatches.flatMap { s in s.entries.map { $0.hex } + (s.styles ?? []).flatMap { [$0.ink, $0.paper] } })
        out.colours = lib.colours.filter { keys.contains($0.hex) || (level == .catalogue && !used.contains($0.hex)) }
        // The tags they wear and the members' own; the profiles they work to.
        let kept = Set(members.map { $0.id })
        let worn = Set(palettes.flatMap { $0.tags ?? [] } + out.colours.flatMap { $0.tags ?? [] })
        out.tagInfo = lib.tagInfo.filter { t in t.projectID.map { kept.contains($0) } ?? (level == .catalogue || worn.contains(t.name)) }
        let profiles = Set(palettes.compactMap { $0.profile } + members.compactMap { $0.profile })
        out.colourProfiles = lib.colourProfiles.filter { level == .catalogue || profiles.contains($0.id) }
        if strip.tags {
            out.tagInfo = []
            out.swatches = out.swatches.map { var s = $0; s.tags = nil; s.tagsChangedAt = nil; return s }
            out.colours = out.colours.map { Colour(hex: $0.hex, pickedAt: $0.pickedAt, source: $0.source, master: $0.master, kind: $0.kind) }
        }
        if strip.notes { out.swatches = out.swatches.map { var s = $0; s.entries = s.entries.map { var x = $0; x.note = nil; x.noteChangedAt = nil; return x }; return s } }
        return (out, cut)
    }

    /// Where the subject sits, by name and id, for the manifest.
    static func origin(level: ShareLevel, subject: UUID?, in lib: Library, schema: SchemaTrial.SchemaFile) -> ShareManifest.Origin? {
        func place(of p: Project) -> ShareManifest.Origin {
            let c = SchemaTrial.collection(of: p.id, among: schema.collections, places: schema.places)
            let g = SchemaTrial.folder(of: p.id, among: schema.collections, places: schema.places).flatMap { f in c.folders.first { $0.id == f } }
            return ShareManifest.Origin(collection: .init(id: c.id, name: c.name), group: g.map { .init(id: $0.id, name: $0.name) }, member: nil)
        }
        switch level {
        case .palette:
            guard let id = subject, let member = lib.swatch(id)?.projectID, let p = lib.project(member) else { return nil }
            var o = place(of: p)
            o.member = .init(id: p.id, name: p.name)
            return o
        case .workGroup:
            if let id = subject, let p = lib.project(id) { return place(of: p) }
            if let c = schema.collections.first(where: { $0.folders.contains { $0.id == subject } }) { return ShareManifest.Origin(collection: .init(id: c.id, name: c.name), group: nil, member: nil) }
            return nil
        case .collection, .catalogue: return nil
        }
    }

    /// The files of a share, path and bytes, before the manifest: the cut written as a catalogue in a scratch folder, or the palette's one file.
    static func package(level: ShareLevel, subject: UUID?, ticked: Set<String>?, strip: (tags: Bool, notes: Bool) = (false, false),
                        from lib: Library, schema: SchemaTrial.SchemaFile, catalogueName: String) throws -> [Zip.Entry] {
        let (sub, cut) = self.cut(level: level, subject: subject, ticked: ticked, strip: strip, from: lib, schema: schema)
        if level == .palette {
            guard let s = sub.swatches.first else { throw ShareFault.notAShare("there is no palette to share") }
            let doc = CatalogueTree.paletteDocument(s, in: sub, member: nil, file: filesystemName(s.name))
            return [Zip.Entry(path: filesystemName(s.name) + "." + CatalogueTree.fileExtension(of: s), data: try e.encode(doc))]
        }
        let name = level == .catalogue ? catalogueName : tree(level: level, subject: subject, in: lib, schema: schema, catalogueName: catalogueName).name
        let dir = stagingRoot.appendingPathComponent("Out-" + UUID().uuidString).appendingPathComponent(filesystemName(name))
        defer { discard(dir.deletingLastPathComponent()) }
        try CatalogueTree.write(sub, schema: cut, index: dir.appendingPathComponent(filesystemName(name) + "." + ColourFiles.catalogue), name: name)
        var entries: [Zip.Entry] = []
        func walk(_ folder: URL) throws {
            for n in CatalogueTree.names(in: folder) {
                let url = folder.appendingPathComponent(n)
                if CatalogueTree.isFolder(url) { try walk(url) } else { entries.append(Zip.Entry(path: relative(url, to: dir), data: try Data(contentsOf: url))) }
            }
        }
        try walk(dir)
        return entries
    }

    // MARK: Export

    /// Writes the share: the manifest first, then the files of the cut. With `ticked` nil everything goes.
    @discardableResult
    static func export(level: ShareLevel, subject: UUID?, from lib: Library, schema: SchemaTrial.SchemaFile, catalogue: ShareManifest.Named, ticked: Set<String>? = nil,
                       strip: (tags: Bool, notes: Bool) = (false, false), to url: URL, now: Date = Date()) throws -> ShareManifest {
        let entries = try package(level: level, subject: subject, ticked: ticked, strip: strip, from: lib, schema: schema, catalogueName: catalogue.name)
        let listed = entries.map { ShareManifest.File(path: $0.path, bytes: $0.data.count, sha256: sha256($0.data)) }
        let name = tree(level: level, subject: subject, in: lib, schema: schema, catalogueName: catalogue.name).name
        let manifest = ShareManifest(level: level, exportedAt: now, catalogue: catalogue, subject: ShareManifest.Named(id: subject ?? catalogue.id, name: name),
                                     origin: origin(level: level, subject: subject, in: lib, schema: schema), files: listed)
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

    private static let paletteExtensions: Set<String> = [ColourFiles.palette, ColourFiles.typography, ColourFiles.legacyPalette]

    /// Opens the zip and checks it: the manifest, every file against its digest, nothing unlisted, and the shape its level calls for.
    static func inspect(_ url: URL) throws -> Inspection {
        let entries = try Zip.read(url)
        guard let m = entries.first(where: { $0.path == ShareManifest.fileName }) else { throw ShareFault.notAShare("there is no manifest in it") }
        guard let manifest = try? d.decode(ShareManifest.self, from: m.data), manifest.format == "colour-share" else { throw ShareFault.notAShare("its manifest could not be read") }
        var problems: [String] = []
        if manifest.version < 2 { problems.append("it was made by an earlier version of Colorgain, whose shares this version no longer reads") }
        let byPath = Dictionary(entries.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        for f in manifest.files {
            guard let entry = byPath[f.path] else { problems.append("\(f.path) is listed but missing"); continue }
            if entry.data.count != f.bytes { problems.append("\(f.path) is \(entry.data.count) bytes, not the \(f.bytes) listed") }
            else if sha256(entry.data) != f.sha256 { problems.append("\(f.path) does not match its digest: it was changed after it was exported") }
        }
        let listed = Set(manifest.files.map { $0.path })
        for entry in entries where entry.path != ShareManifest.fileName && !listed.contains(entry.path) { problems.append("\(entry.path) is in the file but not in its manifest") }
        // The shape the level calls for: a catalogue file at the top, or for a palette its one file.
        let files = entries.filter { $0.path != ShareManifest.fileName }
        let top = files.filter { !$0.path.contains("/") }
        switch manifest.level {
        case .palette:
            if files.count != 1 || !top.contains(where: { paletteExtensions.contains(($0.path as NSString).pathExtension.lowercased()) }) { problems.append("a palette share is one palette file, and this is not") }
        case .catalogue, .collection, .workGroup:
            if top.filter({ ($0.path as NSString).pathExtension.lowercased() == ColourFiles.catalogue }).count != 1 { problems.append("a \(manifest.level.title.lowercased()) share carries one catalogue file at its top, and this does not") }
        }
        // The tree, read from the staged files themselves, so the Contents step can list what is there before anything is written.
        var tree = ShareNode(id: "", kind: .catalogue, name: manifest.subject.name, children: [])
        if problems.isEmpty {
            let staging = try stage(entries: entries)
            defer { discard(staging) }
            if let staged = try? read(staging: staging, level: manifest.level) {
                let subject = manifest.level == .palette ? staged.palette?.0.id : manifest.subject.id
                tree = self.tree(level: manifest.level, subject: subject, in: staged.library, schema: staged.schema, catalogueName: manifest.catalogue.name)
            } else { problems.append("its catalogue could not be read") }
        }
        return Inspection(manifest: manifest, entries: entries, problems: problems, tree: tree)
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

    /// What was staged, read as a library of its own: the share's catalogue, or a palette on its own.
    struct Staged {
        var level: ShareLevel
        var root: URL
        var library: Library
        var schema: SchemaTrial.SchemaFile
        /// For a palette share: the palette and the colours it uses.
        var palette: (Swatch, [Colour])?
        /// The node of the Contents tree each member, collection, level between and palette of the staged library is ticked by.
        var paths: [UUID: String] = [:]
    }

    static func read(staging: URL, level: ShareLevel) throws -> Staged {
        var staged = Staged(level: level, root: staging, library: Library(), schema: .fresh, palette: nil)
        if level == .palette {
            guard let file = CatalogueTree.names(in: staging).map({ staging.appendingPathComponent($0) }).first(where: { paletteExtensions.contains($0.pathExtension.lowercased()) }),
                  let doc = CatalogueTree.read(PaletteDocument.self, at: file) else { throw ShareFault.notAShare("the palette could not be read") }
            var p = doc.palette
            p.projectID = nil
            staged.palette = (p, doc.colours)
            staged.library.swatches = [p]
            staged.library.colours = doc.colours
            staged.paths[p.id] = p.id.uuidString
            return staged
        }
        let loaded = try CatalogueTree.read(root: staging)
        staged.library = loaded.library
        staged.schema = loaded.schema
        for p in loaded.library.projects { staged.paths[p.id] = p.id.uuidString }
        for s in loaded.library.swatches { staged.paths[s.id] = s.id.uuidString }
        for c in loaded.schema.collections {
            staged.paths[c.id] = c.id.uuidString
            for f in c.folders { staged.paths[f.id] = f.id.uuidString }
        }
        return staged
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

    /// The places a share of this level may land, each with its name: where it came from first, when this catalogue has that
    /// place, by id or by name, so following the blueprint is the first choice; then every other place in rail order.
    static func placements(for level: ShareLevel, in lib: Library, schema: SchemaTrial.SchemaFile, origin: ShareManifest.Origin? = nil) -> [(Placement, String)] {
        var all = everyPlacement(for: level, in: lib, schema: schema)
        func same(_ a: ShareManifest.Named?, id: UUID, name: String) -> Bool { a.map { $0.id == id || $0.name.lowercased() == name.lowercased() } ?? false }
        let first: Int? = all.firstIndex { place, _ in
            switch place {
            case .collection(let c, let f):
                guard let o = origin, let col = schema.collections.first(where: { $0.id == c }), same(o.collection, id: col.id, name: col.name) else { return false }
                if let g = o.group { return f.flatMap { id in col.folders.first { $0.id == id } }.map { same(g, id: $0.id, name: $0.name) } ?? false }
                return f == nil
            case .member(let m):
                guard let o = origin?.member, let p = lib.project(m) else { return false }
                return p.id == o.id || (p.name.lowercased() == o.name.lowercased() && same(origin?.collection, id: SchemaTrial.collection(of: m, among: schema.collections, places: schema.places).id,
                                                                                           name: SchemaTrial.collection(of: m, among: schema.collections, places: schema.places).name))
            default: return false
            }
        }
        if let i = first { all.insert(all.remove(at: i), at: 0) }
        return all
    }
    private static func everyPlacement(for level: ShareLevel, in lib: Library, schema: SchemaTrial.SchemaFile) -> [(Placement, String)] {
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
