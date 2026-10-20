import AppKit
import UniformTypeIdentifiers

/// Portable library index plus its neighbouring payloads. Imports merge; they never replace a workspace.
enum MyLibraryFile {
    static func inspect(_ selected:URL)throws -> (URL,CatalogueFile,Library) {
        let isDirectory=try selected.resourceValues(forKeys:[.isDirectoryKey]).isDirectory == true
        let root=isDirectory ? selected:selected.deletingLastPathComponent()
        let index=root.appendingPathComponent("my_library.collib")
        try Handler_File_Manager.shared.requireAvailableCatalogue(index)
        let doc=try ColourFiles.decoder().decode(CatalogueFile.self,from:Handler_File_Manager.shared.read(index))
        guard doc.collections.isEmpty else{throw failure("This library contains client-owned work. Import it as a catalogue instead.")}
        for record in doc.importedAssets ?? [] where !record.external {
            guard try FileRevision.read(record.url(in:root)).digest != nil else{throw failure("A library asset is missing: \(record.name)")}
        }
        let loaded=try CatalogueTree.read(root:root)
        return (root,doc,loaded.library)
    }
    static func export(home:URL,to destination:URL)throws {
        let assets=GlobalAssets(home:home),manager=Handler_File_Manager.shared
        try assets.migrateLibraryIndex();try manager.requireAvailableCatalogue(assets.libraryIndex)
        guard !FileManager.default.fileExists(atPath:destination.path),!destination.standardizedFileURL.path.hasPrefix(assets.root.standardizedFileURL.path+"/") else{throw failure("Choose a new folder outside My Library.")}
        try manager.copyVerified(assets.root,to:destination)
        do {
            _ = try inspect(destination)
        } catch {throw failure("The export could not be verified. The source is unchanged. Review the partial copy at \(destination.path): \(error.localizedDescription)")}
    }
    static func merge(_ selected:URL,home:URL)throws {
        let (root,doc,incoming)=try inspect(selected),assets=GlobalAssets(home:home),manager=Handler_File_Manager.shared
        guard root.standardizedFileURL != assets.root.standardizedFileURL else{throw failure("This is already your active My Library.")}
        try assets.migrateLibraryIndex()
        var library=try assets.load(),records=CatalogueTree.catalogue(in:assets.root)?.importedAssets ?? [],map:[UUID:UUID]=[:],copies:[(URL,URL)]=[]
        let before=try manager.copySnapshot(root)
        for palette in incoming.swatches {
            let digest=try SimpleCatalogueImport.content(palette,in:incoming)
            if let same=try library.swatches.first(where:{try SimpleCatalogueImport.content($0,in:library) == digest}){map[palette.id]=same.id;continue}
            var added=library.swatches.contains(where:{$0.id == palette.id}) ? try SimpleCatalogueImport.independent(palette):palette
            added.projectID=nil;added.bucketID=nil;added.name=uniqueName(added.name,among:library.swatches.map(\.name));map[palette.id]=added.id;library.swatches.append(added)
        }
        for colour in incoming.colours {
            if let existing=library.colours.first(where:{$0.hex == colour.hex}),existing.definition != colour.definition {throw failure("A colour definition conflicts with this library. Resolve it before importing; nothing was replaced.")}
            if !library.colours.contains(where:{$0.hex == colour.hex}){library.colours.append(colour)}
        }
        for profile in incoming.colourProfiles {
            if let existing=library.colourProfiles.first(where:{$0.id == profile.id}),existing != profile {throw failure("A profile identity has different contents. Nothing was replaced.")}
            if !library.colourProfiles.contains(where:{$0.id == profile.id}){library.colourProfiles.append(profile)}
        }
        for record in doc.importedAssets ?? [] {
            if let same=try records.first(where:{ candidate in
                guard candidate.type == record.type,candidate.external == record.external else{return false}
                if candidate.external{return candidate.path == record.path}
                let source=try record.url(in:root),target=try candidate.url(in:assets.root)
                guard let digest=try FileRevision.read(source).digest else{throw failure("A source library asset is missing.")}
                return try digest == FileRevision.read(target).digest
            }){map[record.id]=same.id;continue}
            var added=record
            if records.contains(where:{$0.id == record.id}){added.id=UUID()}
            added.name=uniqueName(added.name,among:records.map(\.name));added.member=nil;added.bucket=nil
            if !record.external {
                let source=try record.url(in:root)
                added.path="Imported/"+added.id.uuidString+"/"+source.lastPathComponent
                copies.append((source,try added.url(in:assets.root)))
            }
            map[record.id]=added.id;records.append(added)
        }
        for tag in incoming.tagInfo where !library.tagInfo.contains(where:{$0.name == tag.name && $0.projectID == nil}){library.tagInfo.append(tag)}
        try manager.withTransaction(home:home) {
            for (source,target) in copies {try manager.copyVerified(source,to:target)}
            try assets.save(library)
            guard var target=CatalogueTree.catalogue(in:assets.root) else{throw failure("My Library could not be verified.")}
            target.importedAssets=records
            var seen=Set<String>()
            target.libraryAssetTypes=(assets.assetTypes+(doc.libraryAssetTypes ?? [])).filter{seen.insert($0).inserted}
            try manager.write(ColourFiles.encoder().encode(target),to:assets.libraryIndex)
            try manager.requireAvailableCatalogue(assets.libraryIndex)
            guard try manager.copySnapshot(root) == before else{throw failure("The source changed during import. Please retry.")}
        }
    }
    static func chooseImport(library:LibraryController,over host:NSView){
        guard let window=host.window else{return}
        let panel=NSOpenPanel();panel.title="Import My Library";panel.allowedContentTypes=[UTType(filenameExtension:"collib") ?? .data];panel.canChooseDirectories=true;panel.canChooseFiles=true
        panel.message="Choose my_library.collib with its neighbouring asset folders. Exact duplicates are reused; different assets are kept separately."
        panel.beginSheetModal(for:window){response in guard response == .OK,let url=panel.url else{return}
            reviewImport(url,library:library,over:host)
        }
    }
    static func reviewImport(_ url:URL,library:LibraryController,over host:NSView){
        guard let window=host.window else{return}
        do {
            try FolderAccess.authorize(url.hasDirectoryPath ? url:url.deletingLastPathComponent())
            let (_,doc,contents)=try inspect(url)
            let modal=SwissFocusModal(title:"Import My Library",message:"Add \(contents.swatches.count) palettes and \(doc.importedAssets?.count ?? 0) other assets. Existing assets remain. External references retain their original locations.")
            modal.button("Import Library",primary:true){do{try merge(url,home:Catalogues.standard.root);library.reload();modal.dismissOverlay()}catch{NSAlert(error:error).beginSheetModal(for:window)}}
            modal.button("Cancel"){modal.dismissOverlay()};modal.present(over:host)
        }catch{NSAlert(error:error).beginSheetModal(for:window)}
    }
    static func chooseExport(over host:NSView){
        guard let window=host.window else{return}
        let panel=NSOpenPanel();panel.title="Export My Library";panel.prompt="Export Here";panel.canChooseDirectories=true;panel.canChooseFiles=false
        panel.message="Creates a My Library folder containing my_library.collib and its assets. Keep these together."
        panel.beginSheetModal(for:window){response in guard response == .OK,let folder=panel.url else{return}
            do{try FolderAccess.authorize(folder);let names=try FileManager.default.contentsOfDirectory(atPath:folder.path);let destination=folder.appendingPathComponent(uniqueName("My Library",among:names));try export(home:Catalogues.standard.root,to:destination);NSWorkspace.shared.activateFileViewerSelecting([destination])}catch{NSAlert(error:error).beginSheetModal(for:window)}
        }
    }
}
