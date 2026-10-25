import Foundation

/// Portable node preset. The type in the header lets an imported file find its own editor.
struct ColtraDocument: Codable {
    var format = "coltra"
    var version = 1
    var transformType: PaletteTransformGraph.Formula
    var name: String
    var amount: Double
    var settings: TransformSettings
}

/// A complete reusable flow; source colours are replaced when applied to a palette.
struct ColnodeDocument: Codable {
    var format = "colnode"
    var version = 1
    var name: String
    var graph: PaletteTransformGraph
    init(name:String,graph:PaletteTransformGraph) {self.name=name;self.graph=graph.template()}
}

struct TransformPresetIndexItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case transform, diagram }
    var id: UUID
    var name: String
    var kind: Kind
    var transformType: PaletteTransformGraph.Formula?
    var file: String
}

enum TransformPresetStore {
    enum Scope { case application, catalogue(LibraryStore), both(LibraryStore) }
    private static func destinations(_ scope:Scope)->[Scope] {
        if case .both(let store)=scope {return [.application,.catalogue(store)]}
        return [scope]
    }
    private static let key = "transformPresetIndex"
    private static func root(_ scope: Scope) -> URL {
        let home:URL,old:URL
        switch scope {
        case .application,.both:
            home=AppDataStore.current.root
            old=home.appendingPathComponent("Transform Presets",isDirectory:true)
        case .catalogue(let store):
            home=store.root
            old=home.appendingPathComponent("Library/Transform Presets",isDirectory:true)
        }
        let target=home.appendingPathComponent("Presets/Transforms",isDirectory:true)
        let fm=FileManager.default
        if fm.fileExists(atPath:old.path) {
            do {
                try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                if !fm.fileExists(atPath:target.path) {try fm.moveItem(at:old,to:target)}
                else {
                    for file in try fm.contentsOfDirectory(at:old,includingPropertiesForKeys:nil) {
                        let moved=target.appendingPathComponent(file.lastPathComponent)
                        if !fm.fileExists(atPath:moved.path) {try fm.moveItem(at:file,to:moved)}
                    }
                    if try fm.contentsOfDirectory(atPath:old.path).isEmpty {try fm.removeItem(at:old)}
                }
            } catch {Diagnostics.log("transform-preset-folder-migration",error:error)}
        }
        return fm.fileExists(atPath:target.path) ? target:(fm.fileExists(atPath:old.path) ? old:target)
    }
    private static func indexURL(_ scope: Scope) -> URL {
        switch scope {
        case .application,.both: return AppDataStore.current.url
        case .catalogue(let store): return store.url
        }
    }
    private static func readIndex(_ scope: Scope) throws -> [TransformPresetIndexItem] {
        let object = try JSONSerialization.jsonObject(with: Handler_File_Manager.shared.read(indexURL(scope))) as? [String: Any] ?? [:]
        guard let raw = object[key] else { return [] }
        let data = try JSONSerialization.data(withJSONObject: raw)
        return try ColourFiles.decoder().decode([TransformPresetIndexItem].self, from: data)
    }
    private static func writeIndex(_ items: [TransformPresetIndexItem], scope: Scope) throws {
        let url = indexURL(scope)
        try Handler_File_Manager.shared.update(url) { object in
            object[key] = try JSONSerialization.jsonObject(with: ColourFiles.encoder().encode(items))
        }
    }
    /// Only metadata is read for the list. Preset files stay unopened until selected.
    static func list(_ scope: Scope, kind: TransformPresetIndexItem.Kind, type: PaletteTransformGraph.Formula? = nil) throws -> [TransformPresetIndexItem] {
        try readIndex(scope).filter { $0.kind == kind && (kind == .diagram || $0.transformType == type) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    @discardableResult static func save(_ document: ColtraDocument, scope: Scope) throws -> TransformPresetIndexItem {
        guard document.version == 1, document.format == "coltra", !document.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure("The transform preset is invalid.") }
        let id = UUID(), file = id.uuidString + ".coltra"
        let item = TransformPresetIndexItem(id: id, name: document.name, kind: .transform, transformType: document.transformType, file: file)
        try saveFile(ColourFiles.encoder().encode(document), item: item, scope: scope)
        return item
    }
    @discardableResult static func save(_ document: ColnodeDocument, scope: Scope) throws -> TransformPresetIndexItem {
        guard document.version == 1, document.format == "colnode", !document.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure("The diagram preset is invalid.") }
        let id = UUID(), file = id.uuidString + ".colnode"
        let item = TransformPresetIndexItem(id: id, name: document.name, kind: .diagram, transformType: nil, file: file)
        try saveFile(ColourFiles.encoder().encode(document), item: item, scope: scope)
        return item
    }
    private static func saveFile(_ data: Data, item: TransformPresetIndexItem, scope: Scope) throws {
        if case .both=scope,FileOperationTransaction.current == nil {
            return try Handler_File_Manager.shared.withTransaction(home:AppDataStore.current.root) {try saveFile(data,item:item,scope:scope)}
        }
        let targets=destinations(scope)
        let oldIndexes=try targets.map{try readIndex($0)}
        var written:[URL]=[]
        do {
            for target in targets {
                let folder=root(target)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let url=folder.appendingPathComponent(item.file)
                try Handler_File_Manager.shared.write(data,to:url)
                written.append(url)
            }
            for (target,index) in zip(targets,oldIndexes) {try writeIndex(index+[item],scope:target)}
        } catch {
            for (target,index) in zip(targets,oldIndexes) {try? writeIndex(index,scope:target)}
            for url in written {try? FileManager.default.removeItem(at:url)}
            throw error
        }
    }
    static func transform(_ item: TransformPresetIndexItem, scope: Scope) throws -> ColtraDocument {
        guard item.kind == .transform, item.file == item.id.uuidString + ".coltra" else { throw failure("Invalid transform preset index.") }
        let document = try ColourFiles.decoder().decode(ColtraDocument.self, from: Handler_File_Manager.shared.read(root(scope).appendingPathComponent(item.file)))
        guard document.format == "coltra", document.version == 1, document.transformType == item.transformType else { throw failure("The preset type does not match its index.") }
        return document
    }
    static func diagram(_ item: TransformPresetIndexItem, scope: Scope) throws -> ColnodeDocument {
        guard item.kind == .diagram, item.file == item.id.uuidString + ".colnode" else { throw failure("Invalid diagram preset index.") }
        let document = try ColourFiles.decoder().decode(ColnodeDocument.self, from: Handler_File_Manager.shared.read(root(scope).appendingPathComponent(item.file)))
        guard document.format == "colnode", document.version == 1 else { throw failure("The diagram preset version is not supported.") }
        return document
    }
    static func rename(_ item: TransformPresetIndexItem, to name: String, scope: Scope) throws {
        if case .both=scope,FileOperationTransaction.current == nil {
            return try Handler_File_Manager.shared.withTransaction(home:AppDataStore.current.root) {try rename(item,to:name,scope:scope)}
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw failure("Enter a preset name.") }
        let targets=destinations(scope)
        let oldIndexes=try targets.map{try readIndex($0)}
        guard oldIndexes.allSatisfy({$0.contains(where:{$0.id==item.id})}) else {throw failure("The preset is missing from one save location.")}
        let urls=targets.map{root($0).appendingPathComponent(item.file)}
        let oldData=try urls.map{try Handler_File_Manager.shared.read($0)}
        let newData=try zip(targets,oldData).map{target,data -> Data in
            if item.kind == .transform {
                var document=try ColourFiles.decoder().decode(ColtraDocument.self,from:data)
                guard document.transformType == item.transformType else {throw failure("The preset type does not match its index.")}
                document.name=trimmed;return try ColourFiles.encoder().encode(document)
            }
            var document=try ColourFiles.decoder().decode(ColnodeDocument.self,from:data)
            document.name=trimmed;return try ColourFiles.encoder().encode(document)
        }
        do {
            for (url,data) in zip(urls,newData) {try Handler_File_Manager.shared.write(data,to:url)}
            for (target,old) in zip(targets,oldIndexes) {
                var index=old;index[index.firstIndex(where:{$0.id==item.id})!].name=trimmed
                try writeIndex(index,scope:target)
            }
        } catch {
            for (url,data) in zip(urls,oldData) {try? Handler_File_Manager.shared.write(data,to:url)}
            for (target,index) in zip(targets,oldIndexes) {try? writeIndex(index,scope:target)}
            throw error
        }
    }
    static func remove(_ item: TransformPresetIndexItem, scope: Scope) throws {
        if case .both=scope,FileOperationTransaction.current == nil {
            return try Handler_File_Manager.shared.withTransaction(home:AppDataStore.current.root) {try remove(item,scope:scope)}
        }
        let targets=destinations(scope)
        let oldIndexes=try targets.map{try readIndex($0)}
        guard oldIndexes.allSatisfy({$0.contains(where:{$0.id==item.id})}) else {throw failure("The preset is missing from one save location.")}
        let urls=targets.map{root($0).appendingPathComponent(item.file)}
        let oldData=try urls.map{try Handler_File_Manager.shared.read($0)}
        do {
            for (target,old) in zip(targets,oldIndexes) {try writeIndex(old.filter{$0.id != item.id},scope:target)}
            for url in urls {
                try FileOperationTransaction.current?.prepare(url,after:nil)
                try FileManager.default.removeItem(at:url)
            }
        } catch {
            for (url,data) in zip(urls,oldData) {try? Handler_File_Manager.shared.write(data,to:url)}
            for (target,index) in zip(targets,oldIndexes) {try? writeIndex(index,scope:target)}
            throw error
        }
    }
    static func exportedData(_ item: TransformPresetIndexItem, scope: Scope) throws -> Data {
        if item.kind == .transform { _ = try transform(item, scope: scope) }
        else { _ = try diagram(item, scope: scope) }
        return try Handler_File_Manager.shared.read(root(scope).appendingPathComponent(item.file))
    }
    @discardableResult static func importFile(_ url: URL, scope: Scope) throws -> TransformPresetIndexItem {
        let data = try Data(contentsOf: url)
        let limit = url.pathExtension.lowercased() == "colnode" ? 128 : 16
        guard data.count <= limit * 1024 * 1024 else { throw failure("The preset file is too large.") }
        switch url.pathExtension.lowercased() {
        case "coltra":
            let document = try ColourFiles.decoder().decode(ColtraDocument.self, from: data)
            return try save(document, scope: scope)
        case "colnode":
            let document = try ColourFiles.decoder().decode(ColnodeDocument.self, from: data)
            return try save(document, scope: scope)
        default:throw failure("Choose a .coltra or .colnode file.")
        }
    }
}
