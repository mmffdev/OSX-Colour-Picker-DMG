import AppKit

/// A catalogue is a folder of related documents. Picking its index alone does not grant
/// a sandboxed app access to the member files beside it.
enum CatalogueOpen {
    static func selected(_ file: URL, over window: NSWindow, completion: @escaping (Result<String?, Error>) -> Void) {
        let isCatalogue = [ColourFiles.catalogue, ColourFiles.legacyCatalogue].contains(file.pathExtension.lowercased())
        func open() {
            let scoped = file.startAccessingSecurityScopedResource()
            defer { if scoped { file.stopAccessingSecurityScopedResource() } }
            do {
                let name = isCatalogue ? try Catalogues.standard.adopt(file) : try Catalogues.standard.importFile(file)
                completion(.success(name))
            } catch { completion(.failure(error)) }
        }
        #if APPSTORE
        let folder = file.deletingLastPathComponent().standardizedFileURL
        if isCatalogue && !FolderAccess.covers(folder) {
            let panel = NSOpenPanel()
            panel.title = "Allow Catalogue Folder"
            panel.message = "To open \(file.lastPathComponent), Colorgain needs its containing folder and the palette and member files inside it. Select the “\(folder.lastPathComponent)” folder. Access will be remembered on this Mac."
            panel.prompt = "Allow And Open"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = false
            panel.allowsMultipleSelection = false
            panel.directoryURL = folder
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let chosen = panel.url else { completion(.success(nil)); return }
                guard chosen.standardizedFileURL.resolvingSymlinksInPath() == folder.resolvingSymlinksInPath() else {
                    completion(.failure(failure("Select the folder containing \(file.lastPathComponent): \(folder.path). No catalogue was opened or changed.")))
                    return
                }
                do { try FolderAccess.authorize(chosen); open() }
                catch { completion(.failure(error)) }
            }
            return
        }
        #endif
        open()
    }
}
