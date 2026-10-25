import AppKit
import UniformTypeIdentifiers
import CryptoKit
import ImageIO
import CoreImage

/// References are index entries, never editable copies masquerading as native palettes.
struct WorkspaceImportedAsset: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var type: String
    var path: String
    var external: Bool
    var member: UUID?
    var bucket: UUID?
    func url(in root: URL) throws -> URL {
        if external {
            guard path.hasPrefix("/") else { throw failure("The linked file has an invalid location.") }
            return FolderAccess.held[path] ?? URL(fileURLWithPath: path)
        }
        return try Handler_File_Manager.contained(path, under: root)
    }
}

enum WorkspaceImport {
    enum ImageTransfer { case copy, move, reference }
    struct Renaming:Equatable {
        enum Template:String,CaseIterable {case original="Original File Name",custom="Custom Name",customSequence="Custom Name - Sequence",filenameSequence="File Name - Sequence"}
        var enabled=false
        var template:Template = .original
        var customName=""
        var startNumber=1
        func name(for source:URL,index:Int)->String {
            guard enabled else{return source.lastPathComponent}
            let original=source.deletingPathExtension().lastPathComponent
            let typed=customName.trimmingCharacters(in:.whitespacesAndNewlines)
            let custom=typed.isEmpty ? "":filesystemName(typed)
            let base:String
            switch template {
            case .original:base=original
            case .custom:base=custom.isEmpty ? original:custom
            case .customSequence:base=(custom.isEmpty ? original:custom)+"-"+String(format:"%03d",startNumber+index)
            case .filenameSequence:base=original+"-"+String(format:"%03d",startNumber+index)
            }
            return source.pathExtension.isEmpty ? base:base+"."+source.pathExtension
        }
    }
    enum ImageDestination {
        case catalogue(member: UUID, bucket: UUID)
        case library
        /// Files live in this user-selected folder; the active catalogue tracks the references.
        case custom(URL)
    }
    static let supportedTypes: Set<String> = ["Palettes", "ASE"]
    static let types = SimpleAssetType.setupImportTypes.map(\.setupTitle)
    private static func seenSourcesKey(_ catalogue:URL)->String {
        let digest=SHA256.hash(data:Data(catalogue.standardizedFileURL.path.utf8))
        return "Workspace.Import.SeenSources."+digest.map{String(format:"%02x",$0)}.joined()
    }
    static func seenSources(in catalogue:URL)->Set<String> {
        Set(AppPreferences.shared.stringArray(forKey:seenSourcesKey(catalogue)) ?? [])
    }
    static func rememberSources(_ urls:[URL],in catalogue:URL) {
        let key=seenSourcesKey(catalogue)
        var paths=seenSources(in:catalogue)
        paths.formUnion(urls.map{$0.standardizedFileURL.path})
        AppPreferences.shared.set(paths.sorted(),forKey:key)
    }
    static func importExtensions(for kind:String)->[String] {
        kind == "ASE" ? ["ase"] : kind == "Palettes" ? ["colpal","colpalette","colplt","css","scss","json"] : []
    }
    struct Destination: Equatable {
        var title: String
        var path: String
        var member: UUID?
        var parent: UUID?
        var bucket: UUID?
        var depth: Int
        var heading = false
        var groupID: UUID?
        var locked = false
        var customPath: String? = nil
        var key: String { if let customPath { return "disk/" + customPath }; if let groupID { return "group/" + groupID.uuidString }; if heading{return "heading/"+path};return "\(member?.uuidString ?? "library")/\(parent?.uuidString ?? "")/\(bucket?.uuidString ?? "")" }
        var appearanceKey:String {
            if let customPath { return "disk:"+customPath }
            if path.hasPrefix("Custom Folders") { return "custom-folders" }
            if let groupID{return "collection:"+groupID.uuidString}
            if let parent{return parent.uuidString}
            return member.map{String(describing:StudioFrame.Place.project($0))} ?? "catalogue"
        }
    }
    static func matches(_ node: SchemaNode, type: String) -> Bool {
        type == "ASE" ? SchemaTrial.type(of: node).caseInsensitiveCompare("ASE") == .orderedSame : SchemaTrial.role(of: node) == .palettes
    }
    /// Project the actual hierarchy into destination rows. Asset buckets are implicit.
    /// Typed leaf pages are hidden; containers with a matching bucket remain addressable.
    static func destinations(library: Library, schema: SchemaTrial.SchemaFile, type: String) -> [Destination] {
        var result: [Destination] = []
        for collection in schema.collections {
            let members = library.orderedProjects.filter { SchemaTrial.collection(of: $0.id, among: schema.collections, places: schema.places).id == collection.id }
            guard !members.isEmpty else { continue }
            result.append(.init(title: collection.name, path: collection.name, depth: 0, heading: true, groupID: collection.id))
            func member(_ value: Project, ancestors: [String], depth: Int) {
                let tree = schema.stacks?[value.id.uuidString] ?? collection.stack
                if type != "Palettes" {
                    func walk(_ node:SchemaNode,names:[String],level:Int){
                        let bucket=node.children.first{matches($0,type:type)}
                        result.append(.init(title:names.last ?? value.name,path:names.joined(separator:" / "),member:value.id,parent:node.id,bucket:bucket?.id,depth:level,locked:value.isLocked))
                        for child in node.children where isDestinationContainer(child,type:type){walk(child,names:names+[child.name],level:level+1)}
                    }
                    walk(tree,names:ancestors+[value.name],level:depth)
                    return
                }
                func walk(_ node: SchemaNode, names: [String], level: Int) {
                    let path=names.joined(separator:" / ")
                    result.append(.init(title:names.last ?? value.name,path:path,member:value.id,depth:level,heading:true,locked:value.isLocked))
                    let relevant=node.children.filter{matches($0,type:type) || isDestinationContainer($0,type:type)}
                    for child in relevant {
                        if matches(child,type:type) {
                            result.append(.init(title:child.name,path:path+" / "+child.name,member:value.id,parent:node.id,bucket:child.id,depth:level+1,locked:value.isLocked))
                        } else {walk(child,names:names+[child.name],level:level+1)}
                    }
                    if relevant.isEmpty && level == depth {
                        result.append(.init(title:type,path:path+" / "+type,member:value.id,parent:node.id,depth:level+1,locked:value.isLocked))
                    }
                }
                walk(tree, names: ancestors + [value.name], level: depth)
            }
            func level(_ folder: UUID?, ancestors: [String], depth: Int) {
                for value in members where SchemaTrial.folder(of: value.id, among: schema.collections, places: schema.places) == folder { member(value, ancestors: ancestors, depth: depth) }
                for child in collection.children(of: folder) {
                    result.append(.init(title: child.name, path: (ancestors + [child.name]).joined(separator: " / "), depth: depth, heading: true, groupID: child.id))
                    level(child.id, ancestors: ancestors + [child.name], depth: depth + 1)
                }
            }
            level(nil, ancestors: [collection.name], depth: 1)
        }
        result.append(Destination(title: "My Library", path: "My Library", depth: 0, heading:type == "Palettes"))
        if type == "Palettes"{result.append(Destination(title:type,path:"My Library / "+type,depth:1))}
        result += customDestinations()
        return result
    }
    private static let customFolderKey="Workspace.Import.CustomDestinations"
    static func diskDestination(_ url:URL, title:String?=nil, depth:Int=2)->Destination {
        let folder=url.standardizedFileURL
        return Destination(title:title ?? folder.lastPathComponent,path:"Custom Folders / "+folder.path,depth:depth,customPath:folder.path)
    }
    static func customDestinations()->[Destination] {
        let locations=WorkspaceImageIntakePane.standardRootLocations()
        let groups:[(String,[(URL,String)])]=[
            ("Common Folders",locations.common),("Internal Drives",locations.internalDrives),
            ("External Drives",locations.externalDrives),("Network Drives",locations.networkDrives)
        ]
        var rows=[Destination(title:"Custom Folders",path:"Custom Folders",depth:0,heading:true)]
        for (title,folders) in groups where !folders.isEmpty {
            rows.append(Destination(title:title,path:"Custom Folders / "+title,depth:1,heading:true))
            rows += folders.map{diskDestination($0.0,title:$0.1)}
        }
        let pinned=AppPreferences.shared.stringArray(forKey:customFolderKey) ?? []
        let standard=Set(groups.flatMap{$0.1.map{$0.0.standardizedFileURL.path}})
        rows += pinned.filter{!standard.contains($0)}.map{diskDestination(URL(fileURLWithPath:$0,isDirectory:true),depth:1)}
        return rows
    }
    static func isDestinationContainer(_ node: SchemaNode, type: String) -> Bool {
        guard SchemaTrial.role(of: node) == nil, !matches(node, type: "ASE") else { return false }
        if node.children.contains(where:{matches($0,type:type) || isDestinationContainer($0,type:type)}){return true}
        return type != "Palettes" && !SchemaTrial.nestedNames.contains { $0.caseInsensitiveCompare(SchemaTrial.type(of: node)) == .orderedSame }
    }
    final class DestinationNode: NSObject {
        let destination: Destination
        var children: [DestinationNode] = []
        var diskChildrenLoaded = false
        var loadingDiskChildren = false
        init(_ destination: Destination) { self.destination = destination }
    }
    static func destinationTree(_ rows: [Destination]) -> [DestinationNode] {
        var roots: [DestinationNode] = [], ancestors: [DestinationNode] = []
        for row in rows {
            while ancestors.count > row.depth { ancestors.removeLast() }
            let node = DestinationNode(row)
            if let parent = ancestors.last { parent.children.append(node) } else { roots.append(node) }
            ancestors.append(node)
        }
        return roots
    }
    /// A private branch override, never a change to a collection's shared template.
    static func addingBucket(to target: Destination, type: String, schema: SchemaTrial.SchemaFile) throws -> (SchemaTrial.SchemaFile, UUID?) {
        guard let member = target.member, let parent = target.parent else { return (schema, nil) }
        let collection = SchemaTrial.collection(of: member, among: schema.collections, places: schema.places)
        let tree = schema.stacks?[member.uuidString] ?? collection.stack
        guard let node = SchemaTrial.rows(of: tree).first(where: { $0.node.id == parent })?.node else { throw failure("The destination changed. Choose it again.") }
        if let bucket = node.children.first(where: { matches($0, type: type) }) { return (schema, bucket.id) }
        let bucket = SchemaNode(name: type, role: type == "Palettes" ? .palettes : nil, kind: type)
        var next = schema
        var stacks = next.stacks ?? [:]
        stacks[member.uuidString] = SchemaTrial.changing(parent, in: tree) { $0.children.append(bucket) }
        next.stacks = stacks
        return (next, bucket.id)
    }
    static func supportsRecord(_ type:String)->Bool {
        supportedTypes.contains(type) || ["Images","Photographs"].contains(type)
    }
    static func records(store: LibraryStore) -> [(WorkspaceImportedAsset, URL)] {
        var indexes = [store.url]
        if let home = store.assetsHome { indexes.insert(GlobalAssets(home: home).index, at: 0) }
        return indexes.flatMap { index in
            (CatalogueTree.catalogue(in: index.deletingLastPathComponent())?.importedAssets ?? []).filter { supportsRecord($0.type) }.map { ($0, index) }
        }
    }
    /// Compatibility entry point for the image page's existing bucket action.
    static func addImages(_ urls: [URL], member: UUID, bucket: UUID, kind: String, transfer: ImageTransfer, store: LibraryStore) throws -> Int {
        try addImages(urls, destination: .catalogue(member: member, bucket: bucket), kind: kind, transfer: transfer, store: store)
    }
    /// Copy/Move chooses a physical folder in Rail 2. Reference retains the original path.
    static func addImages(_ urls: [URL], destination choice: ImageDestination, kind: String, transfer: ImageTransfer, store: LibraryStore, collectionID:UUID? = nil) throws -> Int {
        guard kind == "Photographs" || kind == "Images", !urls.isEmpty else { throw failure("Choose images to add.") }
        let manager = Handler_File_Manager.shared
        let destination: URL
        let index: URL
        let ownerRoot: URL
        let member: UUID?
        let bucket: UUID?
        let externallyStored: Bool
        switch choice {
        case .catalogue(let selectedMember, let selectedBucket):
            guard let catalogue = CatalogueTree.catalogue(in: store.root),
                  let entry = catalogue.collections.flatMap({ $0.allMembers.map(\.member) }).first(where: { $0.id == selectedMember }),
                  let home = CatalogueTree.folder(ofWorkGroup: selectedMember, in: store.root) else { throw failure("The image destination is unavailable.") }
            let schema = store.schema
            let collection = SchemaTrial.collection(of: selectedMember, among: schema.collections, places: schema.places)
            let tree = schema.stacks?[selectedMember.uuidString] ?? collection.stack
            func folder(_ node: SchemaNode, below parent: URL) throws -> URL? {
                let path = entry.buckets[node.id.uuidString] ?? filesystemName(node.name)
                let candidate = try Handler_File_Manager.contained(path, under: parent)
                if node.id == selectedBucket { return candidate }
                for child in node.children { if let found = try folder(child, below: candidate) { return found } }
                return nil
            }
            guard let found = try tree.children.compactMap({ try folder($0, below: home) }).first else { throw failure("The image bucket was removed. Choose it again.") }
            destination=found;index=store.url;ownerRoot=store.root;member=selectedMember;bucket=selectedBucket;externallyStored=false
        case .library:
            guard let workspace=store.assetsHome else { throw failure("Choose a workspace before importing to My Library.") }
            let assets=GlobalAssets(home:workspace)
            try assets.migrateLibraryIndex()
            index=assets.libraryIndex;ownerRoot=assets.root;member=nil;bucket=nil
            destination=assets.root.appendingPathComponent(kind);externallyStored=false
        case .custom(let folder):
            let values=try folder.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard values.isDirectory == true,values.isSymbolicLink != true else {throw failure("Choose an existing folder for the images.")}
            try FolderAccess.authorize(folder)
            destination=folder.standardizedFileURL;index=store.url;ownerRoot=store.root;member=nil;bucket=nil;externallyStored=true
        }
        let sourceFiles = try urls.map { url -> URL in
            let file = url.standardizedFileURL
            let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            let imageSource=CGImageSourceCreateWithURL(file as CFURL,nil)
            let readable=imageSource.map{CGImageSourceGetCount($0)>0} ?? (CIImage(contentsOf:file) != nil)
            guard values.isDirectory != true, values.isSymbolicLink != true,
                  readable else { throw failure("A selected file is not a readable image: " + file.lastPathComponent) }
            return file
        }
        return try manager.withTransaction(home: store.assetsHome ?? store.root) {
            if transfer != .reference { try manager.createDirectory(destination) }
            var made: [WorkspaceImportedAsset] = []
            for source in sourceFiles {
                var target=source
                if transfer == .reference { try FolderAccess.authorize(source) } else {
                    target=destination.appendingPathComponent(source.lastPathComponent)
                    var suffix=2
                    while FileManager.default.fileExists(atPath:target.path) || made.contains(where:{$0.name == target.lastPathComponent}) {
                        target=destination.appendingPathComponent(source.deletingPathExtension().lastPathComponent+" \(suffix)."+source.pathExtension)
                        suffix += 1
                    }
                    guard source != target else { throw failure("The image is already in this folder: " + source.lastPathComponent) }
                    switch transfer {
                    case .copy: try manager.copyVerified(source,to:target)
                    case .move:
                        let before = try FileRevision.read(source)
                        try manager.move(source,to:target)
                        guard try FileRevision.read(target) == before else { throw failure("The moved image could not be verified.") }
                    case .reference: break
                    }
                }
                let external=transfer == .reference || externallyStored
                made.append(.init(name:target.lastPathComponent,type:kind,path:external ? target.path:CatalogueTree.relative(target,to:ownerRoot),external:external,member:member,bucket:bucket))
            }
            var added=0
            var created:[WorkspaceImportedAsset]=[]
            try updateRecords(at:index) { rows in
                for record in made where !rows.contains(where:{$0.path == record.path && $0.member == record.member && $0.bucket == record.bucket && $0.type == record.type}) {rows.append(record);created.append(record);added += 1}
            }
            if let collectionID,!created.isEmpty {try AssetCollections.appendInTransaction(created.map(AssetCollectionItem.imported),to:collectionID,in:store)}
            return added
        }
    }
    static func updateRecords(at index: URL, _ change: (inout [WorkspaceImportedAsset]) throws -> Void) throws {
        try Handler_File_Manager.shared.update(index) { object in
            var records = try object["importedAssets"].map { try ColourFiles.decoder().decode([WorkspaceImportedAsset].self, from: JSONSerialization.data(withJSONObject: $0)) } ?? []
            try change(&records)
            object["importedAssets"] = try JSONSerialization.jsonObject(with: ColourFiles.encoder().encode(records))
        }
    }
    static func changeReference(_ record: WorkspaceImportedAsset, index: URL, replacement: URL?, store: LibraryStore) throws {
        try Handler_File_Manager.shared.withTransaction(home: store.assetsHome ?? store.root) {
            let old = try record.url(in: index.deletingLastPathComponent())
            try updateRecords(at: index) { rows in
                guard let i = rows.firstIndex(where: { $0.id == record.id }) else { throw failure("The reference was removed.") }
                if let replacement { rows[i].path = replacement.path; rows[i].external = true }
                else { rows.remove(at: i) }
            }
            if replacement == nil {
                try AssetCollections.removeDeletedInTransaction([AssetCollectionItem.imported(record).key,"Palette/"+record.id.uuidString],in:store)
            }
            if record.type == "ASE" {
                var sources = try ASERegistry.resolved(store.root)
                if let replacement {
                    for i in sources.indices where sources[i].url.standardizedFileURL == old.standardizedFileURL { sources[i].path = replacement.path }
                } else if !records(store: store).contains(where: { (try? $0.0.url(in: $0.1.deletingLastPathComponent()).standardizedFileURL) == old.standardizedFileURL }) {
                    let file = AppbridgeStore.File(id: UUID(), source: UUID(), url: old, swatches: [], problem: nil, digest: "")
                    sources = AppbridgeStore.detaching(file, from: sources)
                }
                try ASERegistry.write(sources, root: store.root)
            }
        }

    }
    static func perform(urls: [URL], type: String, reference: Bool, target: Destination, allowBucket: Bool, store: LibraryStore, fault: ((String) throws -> Void)? = nil) throws {
        _ = try perform(urls: urls, type: type, transfer: reference ? .reference:.copy, targets: [target], allowBucket: allowBucket, store: store, fault: fault)
    }
    static func perform(urls: [URL], type: String, reference: Bool, targets: [Destination], allowBucket: Bool, store: LibraryStore, fault: ((String) throws -> Void)? = nil) throws {
        _ = try perform(urls: urls, type: type, transfer: reference ? .reference:.copy, targets: targets, allowBucket: allowBucket, store: store, fault: fault)
    }
    @discardableResult static func perform(urls: [URL], type: String, transfer: ImageTransfer, targets: [Destination], allowBucket: Bool, store: LibraryStore, rename:Renaming = .init(), skipExisting:Bool = false, collectionID:UUID? = nil, fault: ((String) throws -> Void)? = nil) throws -> Set<String> {
        guard supportedTypes.contains(type), !urls.isEmpty, !targets.isEmpty else { throw failure("Choose a supported import type, destination and file.") }
        guard targets.allSatisfy({ !$0.heading }) else { throw failure("Choose an asset-owning branch, not a collection heading.") }
        guard transfer != .reference || targets.allSatisfy({$0.customPath == nil}) else {throw failure("Choose Copy or Move to place files in a Custom Folder. Reference links to catalogue or My Library destinations.")}
        guard transfer != .reference || !rename.enabled else{throw failure("File Renaming requires Copy or Move; references keep their original names.")}
        guard !rename.enabled || (rename.template != .custom && rename.template != .customSequence) || !rename.customName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {throw failure("Enter a Custom Name before importing.")}
        let reference = transfer == .reference
        var seen = Set<String>()
        let targets = targets.filter { seen.insert($0.key).inserted }
        // Validate every file before changing the tree or writing any bytes.
        let input = try urls.map { url -> (URL, Data, [ImportedPalette]) in
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 16 * 1024 * 1024 else { throw failure("The selected file exceeds the 16 MB import limit.") }
            let data = try Data(contentsOf: url)
            guard data.count <= 16 * 1024 * 1024 else { throw failure("\(url.lastPathComponent) exceeds the 16 MB import limit.") }
            if type == "ASE" { _ = try AdobeASE.read(data); return (url, data, []) }
            let palettes = PaletteImport.read(data, fallback: url.deletingPathExtension().lastPathComponent)
            guard !palettes.isEmpty, palettes.allSatisfy({ $0.asset?.palette.isTypography != true }) else { throw failure("No supported colour palettes found in \(url.lastPathComponent).") }
            return (url, data, palettes)
        }
        if transfer == .move {
            let ownedRoots=[store.root,store.assetsHome].compactMap{$0}.map{$0.resolvingSymlinksInPath().standardizedFileURL.path}
            for (url,_,_) in input {
                let source=url.resolvingSymlinksInPath().standardizedFileURL.path
                guard !ownedRoots.contains(where:{source == $0 || source.hasPrefix($0+"/")}) else {
                    throw failure("A file already inside this catalogue or My Library cannot be moved during import.")
                }
            }
        }
        let manager = Handler_File_Manager.shared
        var copiedASE: [URL] = []
        var skippedSources=Set<String>()
        var importedSources=Set<String>()
        var collectedItems:[AssetCollectionItem]=[]
        do {
            try manager.withTransaction(home: store.assetsHome ?? store.root, fault: fault) {
                var lib = try store.load()
                guard store.pendingReconciliation == nil else { throw failure("Resolve the catalogue's disk changes before importing.") }
                let schema = store.schema
                var nextSchema = schema
                let current = destinations(library: lib, schema: schema, type: type)
                // Resolve every destination before any mutation; never redirect stale selections.
                let resolved = try targets.map { target -> Destination in
                    if let path=target.customPath {
                        let folder=URL(fileURLWithPath:path,isDirectory:true).standardizedFileURL
                        let values=try folder.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
                        guard values.isDirectory == true,values.isSymbolicLink != true else {throw failure("The Custom Folder is unavailable. Choose it again.")}
                        #if APPSTORE
                        guard FolderAccess.covers(folder) else {throw failure("Grant access to this Custom Folder before importing.")}
                        #endif
                        return diskDestination(folder,title:target.title,depth:target.depth)
                    }
                    guard let fresh = current.first(where: { !$0.heading && $0.member == target.member && $0.parent == target.parent }),
                          !fresh.locked else { throw failure("A selected destination is missing or locked. Choose it again.") }
                    if fresh.member != nil && fresh.bucket == nil && !allowBucket {
                        throw failure("Confirm the new \(type) buckets before importing.")
                    }
                    return fresh
                }
                for target in resolved {
                    lib = try store.load()
                    var bucket = target.bucket
                    if target.member != nil && bucket == nil {
                        (nextSchema, bucket) = try addingBucket(to: target, type: type, schema: nextSchema)
                    }
                    if type == "Palettes" && !reference && target.customPath == nil {
                        for (source, _, palettes) in input {
                            for incoming in palettes {
                                var incoming = incoming
                                if rename.enabled {incoming.name=URL(fileURLWithPath:rename.name(for:source,index:input.firstIndex(where:{$0.0 == source}) ?? 0)).deletingPathExtension().lastPathComponent}
                                if skipExisting && lib.palettes(in:target.member).contains(where:{$0.name.caseInsensitiveCompare(incoming.name) == .orderedSame}) {
                                    skippedSources.insert(source.standardizedFileURL.path);continue
                                }
                                incoming.name = uniqueName(incoming.name, among: lib.palettes(in: target.member).map(\.name))
                                let previous = Set(lib.swatches.map(\.id))
                                _ = lib.merge([incoming], into: target.member)
                                importedSources.insert(source.standardizedFileURL.path)
                                if let made=lib.palettes(in:target.member).first(where:{$0.name == incoming.name}) {collectedItems.append(.palette(made.id,name:made.name))}
                                for i in lib.swatches.indices where !previous.contains(lib.swatches[i].id) { lib.swatches[i].bucketID = bucket }
                            }
                        }
                    }
                    if target.customPath == nil {try store.save(lib, schema: nextSchema)}
                    if type == "Palettes" && !reference && target.customPath == nil { continue }
                    let index = target.customPath != nil ? store.url : target.member == nil ? store.assetsHome.map { GlobalAssets(home: $0).index } ?? store.url : store.url
                    let root = index.deletingLastPathComponent()
                    var directory = target.customPath.map{URL(fileURLWithPath:$0,isDirectory:true)} ?? root.appendingPathComponent(ASERegistry.directory)
                    if let member = target.member, let bucket {
                        guard let cat = CatalogueTree.catalogue(in: store.root),
                              let entry = cat.collections.flatMap({ $0.allMembers.map(\.member) }).first(where: { $0.id == member }),
                              let home = CatalogueTree.folder(ofWorkGroup: member, in: store.root) else { throw failure("The destination folder could not be resolved.") }
                        let tree = nextSchema.stacks?[member.uuidString] ?? SchemaTrial.collection(of: member, among: nextSchema.collections, places: nextSchema.places).stack
                        func find(_ node: SchemaNode, under: URL) throws -> URL? {
                            let location = try Handler_File_Manager.contained(entry.buckets[node.id.uuidString] ?? filesystemName(node.name), under: under)
                            if node.id == bucket { return location }
                            for child in node.children { if let found = try find(child, under: location) { return found } }
                            return nil
                        }
                        let found = try tree.children.compactMap { try find($0, under: home) }.first
                        guard let found else { throw failure("The destination bucket is unavailable.") }
                        directory = found
                    }
                    var records: [WorkspaceImportedAsset] = []
                    var aseSources = type == "ASE" ? try ASERegistry.resolved(store.root) : []
                    for (fileIndex,(source, bytes, _)) in input.enumerated() {
                        var destination = source
                        if reference { try FolderAccess.authorize(source) }
                        else {
                            try manager.createDirectory(directory)
                            let chosenName=rename.name(for:source,index:fileIndex)
                            destination = directory.appendingPathComponent(chosenName)
                            if skipExisting && FileManager.default.fileExists(atPath:destination.path) {
                                skippedSources.insert(source.standardizedFileURL.path);continue
                            }
                            var n = 2
                            while FileManager.default.fileExists(atPath: destination.path) {
                                let named=URL(fileURLWithPath:chosenName)
                                destination = directory.appendingPathComponent(named.deletingPathExtension().lastPathComponent + " \(n)." + named.pathExtension); n += 1
                            }
                            try manager.publishRaw(bytes, to: destination, createOnly: true)
                            if type == "ASE" {copiedASE.append(destination)}
                        }
                        _ = try FileEditAccess.ensure(for: destination)
                        let external = reference || target.customPath != nil
                        let path = external ? destination.path : String(destination.path.dropFirst(root.path.count + 1))
                        var record=WorkspaceImportedAsset(name: destination.deletingPathExtension().lastPathComponent, type: type, path: path, external: external, member: target.member, bucket: bucket)
                        records.append(record);collectedItems.append(.imported(record))
                        importedSources.insert(source.standardizedFileURL.path)
                        if type == "ASE", !aseSources.contains(where: { $0.url.standardizedFileURL == destination.standardizedFileURL }) { aseSources.append(.init(path: destination.path, folder: false)) }
                    }
                    try updateRecords(at: index) { existing in
                        for record in records where !existing.contains(where: { $0.path == record.path && $0.member == record.member && $0.bucket == record.bucket && $0.type == record.type }) { existing.append(record) }
                    }
                    if type == "ASE" { try ASERegistry.write(aseSources, root: store.root) }
                }
                if let collectionID,!collectedItems.isEmpty {try AssetCollections.appendInTransaction(collectedItems,to:collectionID,in:store)}
                if transfer == .move {
                    var removed=Set<String>()
                    for (source,bytes,_) in input where !skippedSources.contains(source.standardizedFileURL.path) && removed.insert(source.standardizedFileURL.path).inserted {
                        guard try FileRevision.read(source).digest == Sharing.sha256(bytes) else {throw failure("The source changed during import: \(source.lastPathComponent). It was left in place.")}
                        try manager.trash(source)
                        let sidecar=FileEditAccess.sidecar(for:source)
                        if FileManager.default.fileExists(atPath:sidecar.path){try manager.trash(sidecar)}
                    }
                }
            }
            copiedASE.forEach { ASEIcon.apply(to: $0) }

        } catch {
            // A failed transaction may have rolled back a just-created schema override.
            _ = try? store.load()
            throw error
        }
        return importedSources
    }
}

final class WorkspaceImportHandlingPane:NSView,WorkspacePanelContentMetrics {
    private let skip=SwissCheckbox("Skip Existing Names")
    private let explanation=Design.text("Matching names receive a numbered copy.",.body,colour:Design.quiet,wraps:true)
    var skipExisting=false {didSet{skip.state=skipExisting ? .on:.off;explanation.stringValue=skipExisting ? "Matching names are skipped. Move keeps any skipped originals." : "Matching names receive a numbered copy.";onChange?(skipExisting)}}
    var onChange:((Bool)->Void)?
    var minimumContentHeight:CGFloat{76}
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);addSubview(skip);addSubview(explanation);skip.target=self;skip.action=#selector(changed)}
    required init?(coder:NSCoder){fatalError()}
    @objc private func changed(){skipExisting=skip.state == .on}
    override func layout(){super.layout();skip.frame=NSRect(x:16,y:8,width:max(0,bounds.width-32),height:28);explanation.frame=NSRect(x:16,y:42,width:max(0,bounds.width-32),height:32)}
}

final class WorkspaceImportRenamePane:NSView,WorkspacePanelContentMetrics,NSTextFieldDelegate {
    private let enabled=SwissCheckbox("Rename Files")
    private let template=AnalysisMenu("Rename Template",WorkspaceImport.Renaming.Template.allCases.map(\.rawValue))
    private let templateLabel=Design.text("Template",.caption,colour:Design.quiet)
    private let nameLabel=Design.text("Custom Name",.caption,colour:Design.quiet)
    private let startLabel=Design.text("Start Number",.caption,colour:Design.quiet)
    private let name=SwissBlockTextField(frame:.zero)
    private let start=SwissBlockTextField(frame:.zero)
    private let sample=Design.text("Sample: Palette.colpal",.body,colour:Design.quiet,wraps:true)
    var sampleFile=URL(fileURLWithPath:"Palette.colpal") {didSet{refresh()}}
    var options=WorkspaceImport.Renaming() {didSet{onChange?(options);refresh()}}
    var onChange:((WorkspaceImport.Renaming)->Void)?
    var minimumContentHeight:CGFloat{194}
    override var isFlipped:Bool{true}
    override init(frame:NSRect){
        super.init(frame:frame)
        for view in [enabled,templateLabel,template,nameLabel,name,startLabel,start,sample] as [NSView]{addSubview(view)}
        enabled.target=self;enabled.action=#selector(toggle)
        template.changed={[weak self] index in guard let self,WorkspaceImport.Renaming.Template.allCases.indices.contains(index) else{return};self.options.template=WorkspaceImport.Renaming.Template.allCases[index]}
        name.delegate=self;start.delegate=self
        for field in [name,start]{field.isBezeled=false;field.drawsBackground=false;field.font=Design.Text.body.font();field.textColor=Design.ink;field.focusRingType = .none}
        start.stringValue="1";name.placeholderString="Enter a name"
        refresh()
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func toggle(){options.enabled=enabled.state == .on}
    func controlTextDidChange(_ notification:Notification){options.customName=name.stringValue;options.startNumber=max(0,Int(start.stringValue) ?? 1)}
    private func refresh(){
        enabled.state=options.enabled ? .on:.off
        template.isEnabled=options.enabled
        let custom=options.template == .custom || options.template == .customSequence
        name.isEnabled=options.enabled && custom;start.isEnabled=options.enabled && (options.template == .customSequence || options.template == .filenameSequence)
        template.selectItem(withTitle:options.template.rawValue)
        sample.stringValue="Sample: "+options.name(for:sampleFile,index:0)
        needsDisplay=true
    }
    override func layout(){
        super.layout();let width=max(0,bounds.width-32),fieldX:CGFloat=120,fieldWidth=max(0,bounds.width-fieldX-16)
        enabled.frame=NSRect(x:16,y:4,width:width,height:28)
        for (label,y) in [(templateLabel,38.0),(nameLabel,76.0),(startLabel,114.0)] {label.frame=NSRect(x:16,y:y,width:96,height:28)}
        template.frame=NSRect(x:fieldX,y:38,width:fieldWidth,height:28)
        name.frame=NSRect(x:fieldX+8,y:76,width:max(0,fieldWidth-16),height:28)
        start.frame=NSRect(x:fieldX+8,y:114,width:max(0,fieldWidth-16),height:28)
        sample.frame=NSRect(x:16,y:154,width:width,height:36)
    }
    override func draw(_ dirtyRect:NSRect){
        for field in [name,start] {let box=field.frame;Design.card.setFill();box.fill();Design.rule.setStroke();NSBezierPath(roundedRect:box.insetBy(dx:0.5,dy:0.5),xRadius:4,yRadius:4).stroke()}
    }
}

final class WorkspaceImportCollectionPane:NSView,WorkspacePanelContentMetrics {
    private weak var controller:LibraryController?
    private let enabled=SwissCheckbox("Add to Collection")
    private let choice=AnalysisMenu("Collection",[])
    private let explanation=Design.text("An imported asset can belong to several Collections.",.body,colour:Design.quiet,wraps:true)
    private var collections:[AssetCollectionEntry]=[]
    var selectedID:UUID?
    var onChange:((UUID?)->Void)?
    var onCreated:(()->Void)?
    var minimumContentHeight:CGFloat{112}
    override var isFlipped:Bool{true}
    init(controller:LibraryController){
        self.controller=controller;super.init(frame:.zero)
        for view in [enabled,choice,explanation] as [NSView]{addSubview(view)}
        enabled.target=self;enabled.action=#selector(changed)
        choice.changed={[weak self] index in guard let self,self.collections.indices.contains(index) else{return};self.selectedID=self.enabled.state == .on ? self.collections[index].id:nil;self.onChange?(self.selectedID)}
        refresh()
    }
    required init?(coder:NSCoder){fatalError()}
    func refresh(){
        guard let controller else{return}
        collections=AssetCollections.list(in:controller.store)
        let previous=selectedID
        let index=collections.firstIndex{$0.id == previous} ?? 0
        choice.options(collections.isEmpty ? ["No Collections Yet"]:collections.map(\.name),selected:index)
        choice.isEnabled=enabled.state == .on && !collections.isEmpty
        if enabled.state == .on && collections.isEmpty {enabled.state = .off}
        selectedID=enabled.state == .on && collections.indices.contains(index) ? collections[index].id:nil
        onChange?(selectedID)
        explanation.stringValue=collections.isEmpty ? "Create a Collection with + above, then choose it here." : "Imported assets also appear in the selected Collection."
    }
    @objc private func changed(){
        if enabled.state == .on && collections.isEmpty {enabled.state = .off;createCollection();return}
        choice.isEnabled=enabled.state == .on && !collections.isEmpty
        let index=choice.indexOfSelectedItem
        selectedID=enabled.state == .on && collections.indices.contains(index) ? collections[index].id:nil
        onChange?(selectedID)
    }
    func createCollection(){
        guard let controller else{return}
        let modal=SwissFocusModal(title:"New Collection",message:"Name the Collection for imported assets.")
        let field=modal.field("Collection Name",value:"")
        modal.button("Create",primary:true){[weak self,weak modal] in
            guard let self else{return}
            do{let id=try AssetCollections.create(field.stringValue,in:controller.store);modal?.dismissOverlay();self.enabled.state = .on;self.selectedID=id;self.refresh();self.onCreated?()}
            catch{controller.flash(error.localizedDescription)}
        }
        modal.button("Cancel"){[weak modal] in modal?.dismissOverlay()};modal.present(over:self)
    }
    override func layout(){super.layout();let width=max(0,bounds.width-32);enabled.frame=NSRect(x:16,y:4,width:width,height:28);choice.frame=NSRect(x:16,y:40,width:width,height:32);explanation.frame=NSRect(x:16,y:78,width:width,height:32)}
}

final class WorkspaceImportPane: NSView, WorkspacePanelContentMetrics, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private weak var controller: LibraryController?
    private let type = AnalysisMenu("Artefact Type", ["Choose Artefact Type"] + WorkspaceImport.types)
    private let destination = WorkspaceBranchTree()
    private var roots: [WorkspaceImport.DestinationNode] = []
    private var expanded = Set<String>()
    private var rebuilding = false
    private var cataloguePath = ""
    private let assets = AnalysisMenu("Imported Files And References", [])
    private let methodButtons:[WorkspaceImportMethodButton] = {
        zip(["Copy","Move","Reference"],["doc.on.doc","arrow.right","link"]).map{title,symbol in
            let button=WorkspaceImportMethodButton(frame:.zero);button.title=title;button.symbol=symbol;return button
        }
    }()
    private let importButton = WorkspaceImportActionButton(frame:.zero)
    private var importInProgress=false
    private var transfer:WorkspaceImport.ImageTransfer = .copy
    private let openButton = SwissButton("Open…", .secondary)
    private let manageButton = SwissButton("Manage…", .secondary)
    private let typeLabel = Design.text("Artefact Type", .caption)
    private let destinationLabel = Design.text("Destination", .caption)
    private let filesLabel = Design.text("Files And References", .caption)
    private let note = Design.text("", .body, colour: Design.quiet)
    private var destinations: [WorkspaceImport.Destination] = []
    private var records: [(WorkspaceImportedAsset, URL)] = []
    var onContentHeightChange: (() -> Void)?
    var onFilesChanged: (() -> Void)?
    var showsRecords = true { didSet { refresh() } }
    var sourceFiles:[URL]=[] {didSet{updateNote();onSourceFilesChanged?(sourceFiles)}}
    var onSourceFilesChanged:(([URL])->Void)?
    var renaming=WorkspaceImport.Renaming() {didSet{updateNote()}}
    var skipExisting=false
    var collectionID:UUID? {didSet{updateNote()}}
    /// On the Import page the viewport owns file selection; never fall back to a file picker.
    var requiresGridSelection=false
    /// The Import route owns the type menu in its actionbar; this view then starts at Destinations.
    var typeInActionbar = false { didSet { typeLabel.isHidden=typeInActionbar;type.isHidden=typeInActionbar;refreshExtent() } }
    var onOpenASE: ((URL) -> Void)?
    var onOpenPalette: ((UUID) -> Void)?
    private var treeHeight: CGFloat { ready ? WorkspaceBranchTree.rowsHeight(destination.numberOfRows)+2*WorkspaceBranchTree.edgePadding : 0 }
    private var methodTop:CGFloat{typeInActionbar ? 12:80}
    private var noteTop:CGFloat{methodTop+56}
    private var destinationTop:CGFloat{methodTop+136}
    private var treeTop:CGFloat{destinationTop+24}
    private var actionsTop: CGFloat { treeTop + treeHeight + 16 }
    var minimumContentHeight: CGFloat { records.isEmpty ? actionsTop + 32 : actionsTop + 140 }
    private var ready: Bool { WorkspaceImport.supportedTypes.contains(selectedType) }
    override var isFlipped: Bool { true }
    init(controller: LibraryController) {
        self.controller = controller
        super.init(frame: .zero)
        for view in [typeLabel, type, note, destinationLabel, destination, importButton, filesLabel, assets, openButton, manageButton] { addSubview(view) }
        for (index,button) in methodButtons.enumerated(){button.tag=index;button.target=self;button.action=#selector(selectMethod(_:));addSubview(button)}
        note.maximumNumberOfLines = 0; note.lineBreakMode = .byWordWrapping
        type.changed = { [weak self] _ in self?.refresh(reset: true) }
        let column = NSTableColumn(identifier: .init("ImportDestinations"))
        destination.addTableColumn(column); destination.outlineTableColumn = column
        destination.headerView = nil; destination.rowHeight = 34; destination.intercellSpacing = NSSize(width:0,height:WorkspaceBranchTree.rowSpacing)
        destination.indentationPerLevel = 0; destination.backgroundColor = Design.card
        destination.style = .plain; destination.focusRingType = .none
        destination.leadingDisclosure = true; destination.expandsOnSelection = false
        destination.swatchFamily = .charcoal
        destination.swatchFamilyForItem={item in
            guard let node=item as? WorkspaceImport.DestinationNode else{return .charcoal}
            let target=node.destination
            if target.path.hasPrefix("Custom Folders") {return .drives}
            return target.member == nil && target.groupID == nil ? .yellow:.charcoal
        }
        destination.rowColour={item in guard let node=item as? WorkspaceImport.DestinationNode else{return nil};return WorkspaceNodeAppearance.colour(node.destination.appearanceKey)}
        destination.rowBorder={item in guard let node=item as? WorkspaceImport.DestinationNode else{return nil};return WorkspaceNodeAppearance.borderColour(node.destination.appearanceKey)}
        destination.rowInk={item in guard let node=item as? WorkspaceImport.DestinationNode else{return nil};return WorkspaceNodeAppearance.ink(node.destination.appearanceKey)}
        destination.allowsMultipleSelection = true; destination.allowsEmptySelection = true
        destination.delegate = self; destination.dataSource = self
        destination.setAccessibilityLabel("Import Destinations. Command-click to select multiple branches.")
        destination.installConnectors(in: self)
        importButton.title="Import";importButton.target = self; importButton.action = #selector(importFiles)
        openButton.target = self; openButton.action = #selector(openFile)
        manageButton.target = self; manageButton.action = #selector(manageFile)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    func selectType(_ kind: String) {
        guard let index = WorkspaceImport.types.firstIndex(of: kind) else { return }
        type.selectItem(at: index + 1); refresh(reset: true)
    }
    func selectDestination(member:UUID?,bucket:UUID?) {
        func path(in nodes:[WorkspaceImport.DestinationNode])->[WorkspaceImport.DestinationNode]? {
            for node in nodes {
                let target=node.destination
                if !target.heading && !target.locked && target.member == member && target.bucket == bucket && target.customPath == nil{return [node]}
                if let children=path(in:node.children){return [node]+children}
            }
            return nil
        }
        guard let nodes=path(in:roots),let target=nodes.last else{return}
        for ancestor in nodes.dropLast(){destination.expandItem(ancestor)}
        let row=destination.row(forItem:target)
        guard row >= 0 else{return}
        destination.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
        destination.scrollRowToVisible(row)
        updateNote()
    }
    func refresh(reset: Bool = false) {
        guard let controller else { return }
        let sameCatalogue = cataloguePath == controller.store.root.path
        let prior = reset || !sameCatalogue ? Set<String>() : Set(selected.map(\.key))
        if !sameCatalogue { expanded.removeAll(); cataloguePath = controller.store.root.path }
        let schema = SchemaTrial.schema(for: controller.store.root) ?? controller.store.schema
        destinations = ready ? WorkspaceImport.destinations(library: controller.library, schema: schema, type: selectedType) : []
        roots = WorkspaceImport.destinationTree(destinations)
        rebuilding = true
        destination.reloadData()
        let openAll=reset || !sameCatalogue
        func restore(_ nodes: [WorkspaceImport.DestinationNode]) {
            for node in nodes {
                if (openAll && node.destination.heading || expanded.contains(node.destination.key)) && (!node.children.isEmpty || node.destination.customPath != nil) {
                    if openAll && node.destination.heading {expanded.insert(node.destination.key)}
                    destination.expandItem(node); restore(node.children)
                    if node.destination.customPath != nil {loadDiskChildren(node)}
                }
            }
        }
        restore(roots)
        let selection = IndexSet((0..<destination.numberOfRows).filter { row in
            guard let node = destination.item(atRow: row) as? WorkspaceImport.DestinationNode else { return false }
            return !node.destination.locked && prior.contains(node.destination.key)
        })
        destination.selectRowIndexes(selection, byExtendingSelection: false)
        rebuilding = false
        destination.isHidden = !ready; destinationLabel.isHidden = !ready
        destination.refreshSurfaces()
        let selectedRecord = records.indices.contains(assets.indexOfSelectedItem) ? records[assets.indexOfSelectedItem].0.id : nil
        records = showsRecords ? WorkspaceImport.records(store: controller.store).filter { $0.0.type == selectedType } : []
        assets.options(records.map { $0.0.name + ($0.0.external ? " · Linked" : " · Imported") }, selected: records.firstIndex { $0.0.id == selectedRecord } ?? 0)
        for view in [filesLabel, assets, openButton, manageButton] { view.isHidden = records.isEmpty }
        updateNote(); refreshExtent()
    }
    private var selectedType: String { type.titleOfSelectedItem ?? "Choose Artefact Type" }
    private var selected: [WorkspaceImport.Destination] {
        destination.selectedRowIndexes.compactMap { (destination.item(atRow: $0) as? WorkspaceImport.DestinationNode)?.destination }.filter { !$0.heading && !$0.locked }
    }
    private func updateNote() {
        let targets = selected
        let incompatibleReference=transfer == .reference && targets.contains{$0.customPath != nil}
        let incompatibleRename=transfer == .reference && renaming.enabled
        importButton.isEnabled = ready && !targets.isEmpty && !importInProgress && !incompatibleReference && !incompatibleRename
        for (index,button) in methodButtons.enumerated(){button.chosen=index == (transfer == .copy ? 0:transfer == .move ? 1:2)}
        importButton.symbol=transfer == .reference ? "link":"square.and.arrow.down"
        destinationLabel.stringValue = targets.isEmpty ? "Destinations" : "Destinations · \(targets.count) Selected"
        if selectedType == "Choose Artefact Type" { note.stringValue = "Choose an artefact type to see its available destinations." }
        else if !ready { note.stringValue = "\(selectedType) import is not connected yet. Choose Palettes or ASE." }
        else {
            let missing = targets.filter { $0.member != nil && $0.bucket == nil }.count
            let action=transfer == .copy ? "Copy keeps the originals." : transfer == .move ? "Move removes the originals after every destination succeeds." : "Reference links to the originals in place."
            let target:String
            if targets.count == 1,let chosen=targets.first {
                let typedBucket=chosen.bucket != nil || (chosen.member == nil && chosen.customPath == nil)
                let path=chosen.path+(typedBucket && !chosen.path.hasSuffix("/ \(selectedType)") ? " / \(selectedType)" : "")
                target="Destination: \(path)."
            } else {target=targets.isEmpty ? "Choose a destination below." : "\(targets.count) destinations selected."}
            let missingNote=missing > 0 ? " \(missing) location(s) need a \(selectedType) bucket; you will be asked first." : ""
            note.stringValue=incompatibleReference ? "Choose Copy or Move to place files in a Custom Folder. Reference links to catalogue or My Library destinations." : incompatibleRename ? "Turn off File Renaming to add a Reference; the original file name stays in place." : "\(selectedType) → \(controller?.catalogue ?? "Catalogue"). \(action) \(target)\(missingNote)"
        }
    }
    private func refreshExtent() {
        needsLayout = true
        onContentHeightChange?()
        var ancestor = superview
        while let view = ancestor {
            if let panel = view as? WorkspacePanel { panel.rail?.arrange(); break }
            ancestor = view.superview
        }
    }
    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 32)
        typeLabel.frame = NSRect(x: 16, y: 12, width: width, height: 20)
        type.frame = NSRect(x: 16, y: 36, width: width, height: 32)
        let gap:CGFloat=4,buttonWidth=max(0,(width-gap*2)/3)
        for (index,button) in methodButtons.enumerated(){button.frame=NSRect(x:16+CGFloat(index)*(buttonWidth+gap),y:methodTop,width:buttonWidth,height:40)}
        note.frame = NSRect(x: 16, y: noteTop, width: width, height: 72)
        destinationLabel.frame = NSRect(x: 16, y: destinationTop, width: width, height: 20)
        destination.frame = NSRect(x: 0, y: treeTop+WorkspaceBranchTree.edgePadding, width: bounds.width, height: max(0,treeHeight-2*WorkspaceBranchTree.edgePadding))
        destination.tableColumns.first?.width = bounds.width
        destination.layoutConnectors()
        importButton.frame = NSRect(x: 16, y: actionsTop, width: width, height: 42)
        filesLabel.frame = NSRect(x: 16, y: actionsTop + 48, width: width, height: 20)
        assets.frame = NSRect(x: 16, y: actionsTop + 72, width: width, height: 32)
        openButton.frame = NSRect(x: 16, y: actionsTop + 108, width: 100, height: 32)
        manageButton.frame = NSRect(x: 124, y: actionsTop + 108, width: max(0, width - 108), height: 32)
    }
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? WorkspaceImport.DestinationNode)?.children.count ?? roots.count }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { (item as? WorkspaceImport.DestinationNode)?.children[index] ?? roots[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        let node=item as! WorkspaceImport.DestinationNode
        return node.destination.customPath != nil && !node.diskChildrenLoaded || !node.children.isEmpty
    }
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        let row = (item as! WorkspaceImport.DestinationNode).destination
        return !row.heading && !row.locked
    }
    func outlineView(_ outlineView: NSOutlineView, selectionIndexesForProposedSelection selection: IndexSet) -> IndexSet {
        IndexSet(selection.filter { row in
            guard let node = outlineView.item(atRow: row) as? WorkspaceImport.DestinationNode else { return false }
            return !node.destination.heading && !node.destination.locked
        })
    }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let row = WorkspaceBranchTree.Row(); row.accordion = destination; return row
    }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let node = item as! WorkspaceImport.DestinationNode, row = node.destination
        let cell = WorkspaceBranchTree.Cell(frame: .zero)
        cell.compactMetadata = true; cell.leadingDisclosure = true; cell.star.isHidden = true
        cell.symbol = row.locked ? "lock" : "folder"
        let label = NSTextField(labelWithString: row.title)
        label.font = Design.Text.body.font(); label.textColor = Design.ink
        label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label); cell.textField = label
        cell.toolTip = row.path + (row.locked ? " · Locked" : "")
        cell.setAccessibilityLabel(row.path + (row.locked ? ", Locked" : row.heading ? ", Group" : ", Import Destination"))
        return cell
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !rebuilding else { return }; updateNote(); destination.refreshSurfaces()
    }
    func outlineViewItemDidExpand(_ notification: Notification) { expansionChanged(notification, open: true) }
    func outlineViewItemDidCollapse(_ notification: Notification) { expansionChanged(notification, open: false) }
    private func expansionChanged(_ notification: Notification, open: Bool) {
        guard !rebuilding, let node = notification.userInfo?["NSObject"] as? WorkspaceImport.DestinationNode else { return }
        if open { expanded.insert(node.destination.key) } else { expanded.remove(node.destination.key) }
        if open {loadDiskChildren(node)}
        destination.refreshSurfaces(); updateNote(); refreshExtent()
    }
    private func loadDiskChildren(_ node:WorkspaceImport.DestinationNode) {
        guard let path=node.destination.customPath,!node.diskChildrenLoaded,!node.loadingDiskChildren else{return}
        let folder=URL(fileURLWithPath:path,isDirectory:true)
        #if APPSTORE
        guard FolderAccess.covers(folder) else {requestDiskAccess(folder);return}
        #endif
        node.loadingDiskChildren=true
        DispatchQueue.global(qos:.userInitiated).async {[weak self,weak node] in
            let result=Result{try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey],options:[.skipsHiddenFiles,.skipsPackageDescendants])}
            let children=(try? result.get())?.compactMap{url -> WorkspaceImport.DestinationNode? in
                guard let values=try? url.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey]),values.isDirectory == true,values.isSymbolicLink != true else{return nil}
                return WorkspaceImport.DestinationNode(WorkspaceImport.diskDestination(url,depth:node?.destination.depth ?? 2))
            }.sorted{$0.destination.title.localizedStandardCompare($1.destination.title) == .orderedAscending} ?? []
            DispatchQueue.main.async {[weak self,weak node] in
                guard let self,let node else{return}
                node.loadingDiskChildren=false
                if case .failure(let error)=result {self.controller?.flash("Cannot browse \(folder.lastPathComponent): \(error.localizedDescription)");return}
                node.children=children;node.diskChildrenLoaded=true
                if self.destination.row(forItem:node) >= 0 {
                    let wasOpen=self.destination.isItemExpanded(node)
                    self.rebuilding=true;self.destination.reloadItem(node,reloadChildren:true)
                    if wasOpen {self.destination.expandItem(node)}
                    self.rebuilding=false
                    self.destination.refreshSurfaces();self.refreshExtent()
                }
            }
        }
    }
    #if APPSTORE
    private func requestDiskAccess(_ folder:URL) {
        guard let window else{return}
        let panel=NSOpenPanel();panel.canChooseDirectories=true;panel.canChooseFiles=false
        panel.directoryURL=folder;panel.prompt="Allow Access"
        panel.message="Choose this folder or one of its parents so Colorgain can browse the destination tree."
        panel.beginSheetModal(for:window){[weak self] response in
            guard let self,response == .OK,let chosen=panel.url else{return}
            do {try FolderAccess.authorize(chosen,renew:true)}catch{NSApp.presentError(error);return}
            self.refresh()
        }
    }
    #endif
    @objc private func selectMethod(_ sender:WorkspaceImportMethodButton){transfer=sender.tag == 1 ? .move:sender.tag == 2 ? .reference:.copy;updateNote()}
    @objc private func importFiles() { choose() }
    private func choose() {
        guard let controller, ready, !selected.isEmpty, let window else { return }
        if requiresGridSelection && sourceFiles.isEmpty {
            controller.flash("Select at least one file in the Import grid.")
            return
        }
        let targets = selected
        let kind = selectedType, store = controller.store
        let transfer=transfer, renaming=renaming, skipExisting=skipExisting, collectionID=collectionID
        func completeImport(_ urls:[URL]) {
            guard controller.store === store else { controller.flash("The catalogue changed. Choose the destination again."); return }
            let complete: (Bool) -> Void = { [weak self] allow in
                guard let self else { return }
                self.importInProgress=true;self.updateNote()
                let progress=SwissFocusModal(title:"Importing \(kind)",message:"Processing \(plural(urls.count,"file")) for \(plural(targets.count,"destination"))…")
                let bar=NSProgressIndicator(frame:.zero)
                bar.style = .bar;bar.isIndeterminate=true;bar.controlSize = .regular
                progress.content(bar,height:20);progress.present(over:self);bar.startAnimation(nil)
                DispatchQueue.global(qos:.userInitiated).async { [weak self] in
                    let result=Result {try WorkspaceImport.perform(urls:urls,type:kind,transfer:transfer,targets:targets,allowBucket:allow,store:store,rename:renaming,skipExisting:skipExisting,collectionID:collectionID)}
                    DispatchQueue.main.async {
                        guard let self else{return}
                        bar.stopAnimation(nil);progress.dismissOverlay()
                        self.importInProgress=false
                        self.updateNote()
                        switch result {
                        case .success(let imported):
                            WorkspaceImport.rememberSources(urls.filter{imported.contains($0.standardizedFileURL.path)},in:store.root)
                            controller.reload();self.onFilesChanged?();self.refresh()
                            let message="\(transfer == .reference ? "Linked":transfer == .move ? "Moved":"Imported") \(imported.count) file(s) into \(targets.count) destination(s)\(urls.count > imported.count ? "; \(urls.count-imported.count) skipped" : "")"
                            self.note.stringValue=message;controller.flash(message)
                        case .failure(let error):self.note.stringValue=error.localizedDescription;controller.flash(error.localizedDescription)
                        }
                    }
                }
            }
            let missing = targets.filter { $0.member != nil && $0.bucket == nil }
            if !missing.isEmpty {
                let modal = SwissFocusModal(title: "Add \(kind) Buckets?", message: "Add a \(kind) bucket at each location listed below, then continue the import?")
                let paths = Design.text(missing.map(\.path).joined(separator: "\n\n"), .body)
                paths.maximumNumberOfLines = 0; paths.lineBreakMode = .byWordWrapping
                let height = paths.attributedStringValue.boundingRect(with: NSSize(width: 448, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
                modal.content(paths, height: ceil(height) + 8)
                modal.button("Add \(kind) And Continue", primary: true) { modal.dismissOverlay(); complete(true) }
                modal.button("Cancel") { modal.dismissOverlay() }
                modal.present(over: self)
            } else { complete(false) }
        }
        if !sourceFiles.isEmpty {completeImport(sourceFiles);return}
        let panel = NSOpenPanel()
        panel.title = transfer == .reference ? "Add \(kind) References" : "Import \(kind)"
        panel.prompt = "Import"
        panel.message = targets.map(\.path).joined(separator: "\n") + (transfer == .reference ? "\nOriginal files stay in place." : transfer == .move ? "\nThe originals are removed after all imports succeed." : "\nEach destination receives an independent copy.")
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        let extensions = WorkspaceImport.importExtensions(for:kind)
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            completeImport(panel.urls)
        }
    }
    func open(id: UUID) {
        guard let controller, let found = WorkspaceImport.records(store: controller.store).first(where: { $0.0.id == id }) else { return }
        if let index = WorkspaceImport.types.firstIndex(of: found.0.type) { type.selectItem(at: index + 1) }
        refresh(); assets.selectItem(at: records.firstIndex { $0.0.id == id } ?? 0); openFile()
    }
    @objc private func openFile() {
        guard records.indices.contains(assets.indexOfSelectedItem) else { return }
        let (record, index) = records[assets.indexOfSelectedItem]
        if record.type == "Palettes" { onOpenPalette?(record.id); return }
        do {
            let url = try record.url(in: index.deletingLastPathComponent())
            guard FileManager.default.isReadableFile(atPath: url.path) else { throw failure("The file is offline or unavailable. Use Manage to locate it again.") }
            if record.type == "ASE" { onOpenASE?(url); return }
            onOpenPalette?(record.id)
        } catch { controller?.flash(error.localizedDescription) }
    }
    func manage(id: UUID) {
        guard let controller, let found = WorkspaceImport.records(store: controller.store).first(where: { $0.0.id == id }) else { return }
        if let i = WorkspaceImport.types.firstIndex(of: found.0.type) { type.selectItem(at: i + 1) }
        refresh(); assets.selectItem(at: records.firstIndex { $0.0.id == id } ?? 0); manageFile()
    }
    @objc private func manageFile() {
        guard records.indices.contains(assets.indexOfSelectedItem) else { return }
        let (record, index) = records[assets.indexOfSelectedItem]
        let modal = SwissFocusModal(title: record.name, message: "\(record.external ? "Linked original" : "Imported file"): \(record.path)")
        if record.type != "Palettes", let url = try? record.url(in: index.deletingLastPathComponent()) {
            let editing = FileEditAccess.owns(url)
            modal.button(editing ? "Lock Editing" : "Unlock Editing") { [weak self] in
                do { try FileEditAccess.setEditing(!editing, source: url); modal.dismissOverlay(); self?.controller?.reload() }
                catch { self?.controller?.flash(error.localizedDescription) }
            }
        }
        if record.external {
            modal.button("Locate File…") { [weak self] in
                modal.dismissOverlay(); guard let self, let window = self.window else { return }
                let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
                panel.allowedContentTypes = WorkspaceImport.importExtensions(for:record.type).compactMap { UTType(filenameExtension: $0) }
                panel.beginSheetModal(for: window) { [weak self] response in
                    guard response == .OK, let url = panel.url, let self else { return }
                    do {
                        let data = try Data(contentsOf: url)
                        if record.type == "ASE" { _ = try AdobeASE.read(data) }
                        else if PaletteImport.read(data, fallback: record.name).isEmpty { throw failure("This file contains no supported palettes.") }
                        try FolderAccess.authorize(url)
                        guard let controller = self.controller else { return }
                        try WorkspaceImport.changeReference(record, index: index, replacement: url, store: controller.store)
                        controller.reload(); self.onFilesChanged?(); self.refresh()
                    } catch { self.controller?.flash(error.localizedDescription) }
                }
            }
        }
        modal.button("Remove Reference Only") { [weak self] in
            do {
                guard let self, let controller = self.controller else { return }
                try WorkspaceImport.changeReference(record, index: index, replacement: nil, store: controller.store)
                modal.dismissOverlay(); controller.reload(); self.onFilesChanged?(); self.refresh()
            }
            catch { self?.controller?.flash(error.localizedDescription) }
        }
        modal.button("Cancel") { modal.dismissOverlay() }; modal.present(over: self)
    }
}

/// Linked palettes participate in the normal model. The store routes their edits to the original file, never an owned copy.
final class WorkspaceLinkedPalettes {
    struct Source {
        let record: WorkspaceImportedAsset
        let index: URL
        var problem: String?
    }
    private(set) var sources: [UUID: Source] = [:]
    private(set) var library = Library()
    private var cache: [UUID: (String, Library, Data)] = [:]
    private var originals: [UUID: Data] = [:]
    private func sourcePath(_ id: UUID) -> String? {
        guard let source = sources[id], let url = try? source.record.url(in: source.index.deletingLastPathComponent()) else { return nil }
        return url.resolvingSymlinksInPath().standardizedFileURL.path
    }
    func canEdit(_ id: UUID) -> Bool {
        guard sources[id] != nil else { return true }
        return sourcePath(id).map { FileEditAccess.owns(URL(fileURLWithPath: $0)) } == true && sources[id]?.problem == nil
    }
    func setEditing(_ enabled: Bool, id: UUID) throws {
        guard let source = sources[id], let path = sourcePath(id) else { throw failure("The linked source is unavailable.") }
        if !enabled {
            try FileEditAccess.setEditing(false, source: URL(fileURLWithPath: path))
            cache.removeValue(forKey: source.record.id)
            return
        }
        let url = try source.record.url(in: source.index.deletingLastPathComponent())
        guard source.problem == nil, FileManager.default.isReadableFile(atPath: path) else { throw failure("Locate the linked source before unlocking it.") }
        guard FileManager.default.isWritableFile(atPath: path) else { throw failure("The source does not allow writing. Grant write access to the original file, then unlock it here.") }
        guard let data = originals[source.record.id], (try? PaletteAssetHandler.read(data)) != nil else { throw failure("This source format cannot preserve palette edits. Import a Colorgain palette copy to edit it; the linked source remains unchanged.") }
        try FolderAccess.authorize(url)
        try FileEditAccess.setEditing(true, source: url)
        cache.removeValue(forKey: source.record.id)
        originals[source.record.id] = try Data(contentsOf: url)
    }

    static func paletteID(record: UUID, offset: Int) -> UUID {
        if offset == 0 { return record }
        let bytes = Array(SHA256.hash(data: Data("\(record.uuidString)/\(offset)".utf8)).prefix(16))
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
    func refresh(store: LibraryStore) {
        sources = [:]; library = Library(); originals = [:]
        let records = WorkspaceImport.records(store: store).filter { $0.0.type == "Palettes" && $0.0.external }
        let keep = Set(records.map { $0.0.id }); cache = cache.filter { keep.contains($0.key) }
        for (record, index) in records {
            var source = Source(record: record, index: index)
            var projected = Library()
            do {
                let url = try record.url(in: index.deletingLastPathComponent())
                let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard (values.fileSize ?? 0) <= 16_000_000 else { throw failure("This linked palette exceeds the 16 MB limit.") }
                let stamp = url.path + "|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values.fileSize ?? 0)|\(record.member?.uuidString ?? "")|\(record.bucket?.uuidString ?? "")"
                if let cached = cache[record.id], cached.0 == stamp { projected = cached.1; originals[record.id] = cached.2 }
                else {
                    let data = try Data(contentsOf: url)
                    originals[record.id] = data
                    let incoming = PaletteImport.read(data, fallback: record.name)
                    guard !incoming.isEmpty else { throw failure("The linked file contains no supported palettes.") }
                    for (offset, value) in incoming.enumerated() {
                        var temporary = Library()
                        temporary.merge([value], into: nil, at: values.contentModificationDate ?? Date(timeIntervalSince1970: 0))
                        guard let palette = temporary.swatches.first else { continue }
                        let asset = PaletteAssetHandler.document(palette, in: temporary, member: nil, file: record.name)
                        var displayed = try PaletteAssetHandler.adopting(asset, id: Self.paletteID(record: record.id, offset: offset), project: record.member, name: palette.name)
                        displayed.bucketID = record.bucket; displayed.copiedFrom = nil
                        projected.swatches.append(displayed)
                        for colour in temporary.colours where !projected.colours.contains(where: { $0.hex == colour.hex }) { projected.colours.append(colour) }
                    }
                    guard !projected.swatches.isEmpty else { throw failure("The linked file contains no supported palettes.") }
                    cache[record.id] = (stamp, projected, data)
                }
            } catch {
                source.problem = "Linked file unavailable. Use Manage Reference to locate it again. " + error.localizedDescription
                // Keep an actionable card, but never show stale colours as a current proof.
                var placeholder = Swatch(id: record.id, name: record.name, createdAt: Date(timeIntervalSince1970: 0), entries: [])
                placeholder.projectID = record.member; placeholder.bucketID = record.bucket
                projected.swatches = [placeholder]
            }
            for palette in projected.swatches { sources[palette.id] = source }
            library.swatches += projected.swatches
            for colour in projected.colours where !library.colours.contains(where: { $0.hex == colour.hex }) { library.colours.append(colour) }
        }
    }
    func saveChanges(in edited: Library, owned: Library) throws -> Library {
        if let target = edited.activeSwatchID, !canEdit(target) { throw failure("Unlock the linked palette before making it the picker target.") }
        let visibleBaseline = adding(to: owned)
        var writes: [URL: (Data, Data)] = [:]
        var removed: [UUID: Source] = [:]
        var moved: [UUID: (Source, Swatch)] = [:]
        for before in library.swatches {
            guard let source = sources[before.id] else { continue }
            guard let after = edited.swatch(before.id) else { removed[source.record.id] = source; continue }
            if after.projectID != before.projectID || after.bucketID != before.bucketID || after.name != before.name {
                moved[source.record.id] = (source, after)
            }
            let sourceColours = library.colours.filter { c in before.entries.contains { $0.hex == c.hex } }
            let oldColours = visibleBaseline.colours.filter { c in before.entries.contains { $0.hex == c.hex } }.sorted { $0.hex < $1.hex }
            let newColours = edited.colours.filter { c in after.entries.contains { $0.hex == c.hex } }.sorted { $0.hex < $1.hex }
            guard before != after || oldColours != newColours else { continue }
            guard canEdit(before.id) else { throw failure("Unlock the linked palette using the padlock in its orange header before editing it.") }
            guard source.problem == nil, let original = originals[source.record.id] else { throw failure("The linked source is unavailable. Locate it before saving changes.") }
            let url = try source.record.url(in: source.index.deletingLastPathComponent())
            guard FileManager.default.isWritableFile(atPath: url.path) else { throw failure("The linked source is not writable: " + url.path) }
            guard var asset = try? PaletteAssetHandler.read(original) else {
                throw failure("This linked format cannot preserve palette edits. Import an editable Colorgain palette copy before changing it. The source was not changed.")
            }
            // Keep source identity and source ownership. Assignment in this catalogue belongs only to the reference.
            let originalFields = try JSONSerialization.jsonObject(with: ColourFiles.encoder().encode(asset.palette)) as! [String: Any]
            var fields = try JSONSerialization.jsonObject(with: ColourFiles.encoder().encode(after)) as! [String: Any]
            for key in ["id", "projectID", "bucketID", "claim", "copiedFrom", "position", "placedAt", "listPosition", "listPlacedAt", "favouritePosition", "favouritePlacedAt"] { fields[key] = originalFields[key] }
            asset.palette = try ColourFiles.decoder().decode(Swatch.self, from: JSONSerialization.data(withJSONObject: fields))
            asset.colours = newColours.map { colour in
                // A shared catalogue colour may mask source metadata. Preserve the source
                // unless that visible colour was actually edited.
                oldColours.first(where: { $0.hex == colour.hex }) == colour
                    ? (sourceColours.first(where: { $0.hex == colour.hex }) ?? colour) : colour
            }
            let data = try ColourFiles.encoder().encode(asset)
            if let previous = writes[url], previous.0 != data { throw failure("Two references contain conflicting edits to the same source. Save one change at a time.") }
            writes[url] = (data, original)
        }
        for (url, value) in writes {
            try Handler_File_Manager.shared.write(value.0, to: url, expected: FileRevision(digest: Sharing.sha256(value.1)))
        }
        for (id, source) in removed {
            try WorkspaceImport.updateRecords(at: source.index) { $0.removeAll { $0.id == id } }
        }
        for (id, value) in moved where removed[id] == nil {
            try WorkspaceImport.updateRecords(at: value.0.index) { rows in
                guard let i = rows.firstIndex(where: { $0.id == id }) else { throw failure("The reference was removed before this edit could be saved.") }
                rows[i].member = value.1.projectID; rows[i].bucket = value.1.bucketID; rows[i].name = value.1.name
            }
        }
        var result = edited
        let ids = Set(sources.keys), ownedKeys = Set(owned.colours.map(\.hex))
        result.swatches.removeAll { ids.contains($0.id) }
        result.deleted.removeAll { tombstone in ids.contains { tombstone.key == $0.uuidString || tombstone.key.hasPrefix($0.uuidString + "/") } }
        let used = Set(result.swatches.flatMap { $0.entries.map(\.hex) + ($0.styles ?? []).flatMap { [$0.ink, $0.paper] } })
        let linkedKeys = Set(library.colours.map(\.hex) + edited.swatches.filter { ids.contains($0.id) }.flatMap { $0.entries.map(\.hex) })
        result.colours.removeAll { linkedKeys.contains($0.hex) && !ownedKeys.contains($0.hex) && !used.contains($0.hex) }
        if let target = result.activeSwatchID, ids.contains(target) { result.activeSwatchID = nil }
        return result
    }
    func adding(to owned: Library) -> Library {
        var displayed = owned
        displayed.swatches += library.swatches.filter { linked in !owned.swatches.contains { $0.id == linked.id } }
        for colour in library.colours where !displayed.colours.contains(where: { $0.hex == colour.hex }) { displayed.colours.append(colour) }
        return displayed
    }
}

/// The native menu and rail share the type catalogue, form and transaction above.
/// Only presentation differs: the menu opens a focused modal, never the docked panel.
final class WorkspaceImportMenu: NSObject {
    private weak var controller: LibraryController?
    var onWorkspace: ((URL) -> Void)?
    init(controller: LibraryController) { self.controller = controller; super.init() }
    func appendImportItems(to menu: NSMenu) {
        for (label, ext) in [("Workspace", "coldata"), ("Catalogue", "colcat")] {
            let item = NSMenuItem(title: "Import " + label + "…", action: #selector(openContainer(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = ext; menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(assetMenuItem())
    }
    @objc private func openContainer(_ sender: NSMenuItem) {
        guard let ext = sender.representedObject as? String,
              let window = StudioWindowController.shared?.window ?? NSApp.keyWindow else { return }
        if ext == "colcat",let controller {SimpleCatalogueImport.choose(over:window,library:controller);return}
        let panel = NSOpenPanel()
        panel.title = ext == "coldata" ? "Import Workspace" : "Import Catalogue"
        panel.prompt = "Import"; panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: ext)].compactMap { $0 }
        panel.message = ext == "coldata" ? "Choose colorgain.coldata to open its workspace and catalogue list." : "Choose a .colcat file to connect its catalogue in its existing location."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if ext == "coldata" { self.onWorkspace?(url) }
            else {
                CatalogueOpen.selected(url, over: window) { [weak self] result in
                    switch result {
                    case .success(let name):
                        guard let name else { return }
                        self?.controller?.open(catalogue: name)
                        StudioWindowController.shared?.frame.go(.catalogue)
                    case .failure(let error): self?.controller?.show(error)
                    }
                }
            }
        }
    }
    func assetMenuItem() -> NSMenuItem {
        let assets = NSMenuItem(title: "Import Assets", action: nil, keyEquivalent: "")
        let types = NSMenu(title: "Import Assets")
        for kind in WorkspaceImport.types {
            let available=WorkspaceImport.supportedTypes.contains(kind)
            let item = NSMenuItem(title: (available ? "" : "! ") + kind, action: #selector(openImport(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = kind
            if !available {
                item.action = nil; item.isEnabled = false
                item.toolTip = "Planned. This import type is not connected yet."
            }
            types.addItem(item)
        }
        assets.submenu = types
        return assets
    }
    @objc private func openImport(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? String,
              let window = StudioWindowController.shared?.window ?? NSApp.keyWindow else { return }
        window.makeKeyAndOrderFront(nil)
        StudioWindowController.shared?.frame.openImageImport(kind:kind)
    }
}
