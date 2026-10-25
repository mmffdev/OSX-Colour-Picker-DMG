import AppKit
import CoreText
import CryptoKit

/// Information retained with a font import. The file, not a family name, is the imported asset.
struct FontAssetInfo: Codable, Equatable {
    struct Face: Codable, Equatable {
        var name: String
        var postScriptName: String
    }
    var family: String
    var faces: [Face]
    var tags: [String] = []
    var metadata: AssetMetadata? = nil
    var specimen: String = "The quick brown fox jumps over the lazy dog."
    var ink: String = "#242424"
    var paper: String = "#FFFFFF"
    var size: Double = 32
    var previewFamily: String? = nil
    var previewFace: String? = nil
    var previewWeight: Int? = nil
    var previewBold: Bool? = nil
    var previewItalic: Bool? = nil
    var previewFamilyMode: Bool? = nil
    var review: PaletteReview? = nil
    var favourite: Bool? = nil
}

enum FontBookBridge {
    private static let previewCache:NSCache<NSString,NSFont> = {
        let cache=NSCache<NSString,NSFont>();cache.countLimit=300;return cache
    }()
    static func preview(_ url:URL,size:CGFloat=29)->NSFont? {
        let stamp=(try? url.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key="\(url.standardizedFileURL.path)#\(stamp)#\(size)" as NSString
        if let cached=previewCache.object(forKey:key){return cached}
        guard let descriptor=(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first else{return nil}
        let font=CTFontCreateWithFontDescriptor(descriptor,size,nil) as NSFont
        previewCache.setObject(font,forKey:key)
        return font
    }
    static func describe(_ url: URL) throws -> FontAssetInfo {
        guard ["otf", "ttf", "ttc", "otc"].contains(url.pathExtension.lowercased()),
              let found = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              !found.isEmpty else { throw failure("Not a readable font: \(url.lastPathComponent)") }
        func value(_ descriptor: CTFontDescriptor, _ key: CFString) -> String? {
            CTFontDescriptorCopyAttribute(descriptor, key) as? String
        }
        let family = value(found[0], kCTFontFamilyNameAttribute) ?? url.deletingPathExtension().lastPathComponent
        let faces = found.map { descriptor in
            FontAssetInfo.Face(name: value(descriptor, kCTFontStyleNameAttribute) ?? "Regular",
                               postScriptName: value(descriptor, kCTFontNameAttribute) ?? family)
        }
        return FontAssetInfo(family: family, faces: faces)
    }

    /// A per-user Core Text registration makes an imported face visible to Font Book and other apps.
    /// Keep the backing URL stable for as long as it is registered.
    @discardableResult static func register(_ url: URL) -> Bool {
        var succeeded = true
        CTFontManagerRegisterFontURLs([url] as CFArray, .persistent, true) { errors, _ in
            if CFArrayGetCount(errors) > 0 { succeeded = false }
            return true
        }
        return succeeded
    }

    static func syncCollections(in store: LibraryStore) {
        let prefix = "Colorgain · \(store.root.lastPathComponent) · "
        let records = Dictionary(uniqueKeysWithValues: WorkspaceImport.records(store: store)
            .filter { $0.0.type == "Fonts" }.map { ($0.0.id, $0) })
        var active = Set<NSFontCollection.Name>()
        for collection in AssetCollections.list(in: store) {
            let descriptors: [NSFontDescriptor] = collection.items.compactMap { item in
                if item.kind == "Font" { return NSFontDescriptor(fontAttributes:[.family:item.identity]) }
                guard item.kind == "Fonts", let id = UUID(uuidString: item.identity),
                      let record = records[id], let name = record.0.font?.faces.first?.postScriptName else { return nil }
                return NSFontDescriptor(name: name, size: 0)
            }
            guard !descriptors.isEmpty else { continue }
            let name = NSFontCollection.Name(prefix + collection.name)
            active.insert(name)
            do { try NSFontCollection.show(NSFontCollection(descriptors: descriptors), withName: name, visibility: .user) }
            catch { Diagnostics.log("font-collection-sync", error: error) }
        }
        for name in NSFontCollection.allFontCollectionNames where name.rawValue.hasPrefix(prefix) && !active.contains(name) {
            do { try NSFontCollection.hide(withName: name, visibility: .user) }
            catch { Diagnostics.log("font-collection-sync", error: error) }
        }
    }
}

struct FontLibraryEntry {
    let id: UUID
    let info: FontAssetInfo
    let imported: (WorkspaceImportedAsset, URL)?
    var fileURL:URL? {imported.flatMap{try? $0.0.url(in:$0.1.deletingLastPathComponent())}}
    var formatLabel:String {
        guard let ext=fileURL?.pathExtension.uppercased(),!ext.isEmpty else{return "System"}
        return ext
    }
    var sourceCaption:String {
        guard let imported else{return "Installed On This Mac"}
        let filename=fileURL?.lastPathComponent ?? imported.0.name
        return "\(formatLabel) · \(filename) · \(info.faces.count) Faces"
    }
    var detailCaption:String {
        guard let imported else{return "Installed On This Mac"}
        let filename=fileURL?.lastPathComponent ?? imported.0.name
        return "\(filename) · \(info.faces.count) Faces"
    }
    var collectionItem: AssetCollectionItem {
        if let imported { return .imported(imported.0) }
        return .init(kind:"Font",identity:info.family,name:info.family)
    }
}

enum FontFormatStyle {
    static let groups=["OTF","TTF","TTC","OTC","System"]
    static func colour(_ format:String)->NSColor {
        switch format {
        case "OTF":return Design.hex("#5FB3A8")
        case "TTF":return Design.houseBlue
        case "TTC":return Design.orange
        case "OTC":return Design.hex("#A77CC5")
        case "System":return Design.hex("#8D8B85")
        default:return Design.rule
        }
    }
    static func heading(_ format:String)->String {
        switch format {
        case "OTF":return "OTF · OpenType Fonts"
        case "TTF":return "TTF · TrueType Fonts"
        case "TTC":return "TTC · TrueType Collections"
        case "OTC":return "OTC · OpenType Collections"
        default:return "System Fonts"
        }
    }
}

enum FontLibraryIndex {
    private static let preferencesKey="FontLibrary.Annotations"
    private static let favouriteKey="FontLibrary.FavouriteFamilies"
    private static func favourites()->Set<String> {Set(AppPreferences.shared.stringArray(forKey:favouriteKey) ?? [])}
    private static func annotations()->[String:FontAssetInfo] {
        guard let data=AppPreferences.shared.data(forKey:preferencesKey),
              let values=try? JSONDecoder().decode([String:FontAssetInfo].self,from:data) else{return [:]}
        return values
    }
    static func stableID(_ family:String)->UUID {
        let bytes=Array(SHA256.hash(data:Data(("font-family:"+family.lowercased()).utf8)).prefix(16))
        return UUID(uuid:(bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
    static func list(in store:LibraryStore)->[FontLibraryEntry] {
        let saved=annotations()
        let favourites=favourites()
        let imports=WorkspaceImport.records(store:store).filter{$0.0.type == "Fonts"}.compactMap{record,index -> FontLibraryEntry? in
            guard var info=record.font ?? (try? record.url(in:index.deletingLastPathComponent())).flatMap({try? FontBookBridge.describe($0)}) else{return nil}
            info.favourite=favourites.contains(info.family)
            return FontLibraryEntry(id:record.id,info:info,imported:(record,index))
        }
        let importedFamilies=Set(imports.map{$0.info.family.lowercased()})
        let installed=NSFontManager.shared.availableFontFamilies.filter{!importedFamilies.contains($0.lowercased())}.map{family -> FontLibraryEntry in
            var info=saved[family] ?? FontAssetInfo(family:family,faces:[])
            info.favourite=favourites.contains(family)
            return FontLibraryEntry(id:stableID(family),info:info,imported:nil)
        }
        return (imports+installed).sorted{$0.info.family.localizedStandardCompare($1.info.family) == .orderedAscending}
    }
    static func save(_ info:FontAssetInfo,entry:FontLibraryEntry) throws {
        if info.favourite != entry.info.favourite {
            var favourites=AppPreferences.shared.stringArray(forKey:favouriteKey) ?? []
            favourites.removeAll{$0.caseInsensitiveCompare(info.family) == .orderedSame}
            if info.favourite == true {favourites.append(info.family)}
            AppPreferences.shared.set(favourites,forKey:favouriteKey)
        }
        if let (record,index)=entry.imported {
            try WorkspaceImport.updateRecords(at:index) {records in
                guard let position=records.firstIndex(where:{$0.id == record.id}) else{throw failure("This font is no longer in the Library.")}
                records[position].font=info
            }
        } else {
            var saved=annotations();saved[info.family]=info
            AppPreferences.shared.set(try JSONEncoder().encode(saved),forKey:preferencesKey)
        }
    }
}

/// Installed fonts remain system-owned. Product buckets store references to their stable family IDs.
enum FontProjectAssignments {
    private static let key = "FontLibrary.ProductAssignments"
    private static func records() -> [String:[String]] {
        AppPreferences.shared.object(forKey:key) as? [String:[String]] ?? [:]
    }
    private static func bucketKey(project:UUID,bucket:UUID)->String {project.uuidString+"/"+bucket.uuidString}
    static func families(project:UUID,bucket:UUID)->[String] {records()[bucketKey(project:project,bucket:bucket)] ?? []}
    static func add(_ family:String,project:UUID,bucket:UUID) {
        var values=records(),items=values[bucketKey(project:project,bucket:bucket)] ?? []
        if !items.contains(where:{$0.caseInsensitiveCompare(family) == .orderedSame}) {items.append(family)}
        values[bucketKey(project:project,bucket:bucket)]=items
        AppPreferences.shared.set(values,forKey:key)
    }
    static func remove(_ family:String,project:UUID,bucket:UUID) {
        var values=records(),items=values[bucketKey(project:project,bucket:bucket)] ?? []
        items.removeAll{$0.caseInsensitiveCompare(family) == .orderedSame}
        values[bucketKey(project:project,bucket:bucket)]=items
        AppPreferences.shared.set(values,forKey:key)
    }
}

enum FontDrag {
    static let type=NSPasteboard.PasteboardType("com.colorgain.font")
    static func font(on board:NSPasteboard)->UUID? {
        board.pasteboardItems?.first?.string(forType:type).flatMap(UUID.init(uuidString:))
    }
    static func begin(_ id:UUID,name:String,event:NSEvent,in view:NSView & NSDraggingSource) {
        let item=NSPasteboardItem();item.setString(id.uuidString,forType:type)
        let size=NSSize(width:180,height:28)
        let image=NSImage(size:size,flipped:true){rect in
            Design.card.setFill();rect.fill()
            Design.attributed("Aa",.bodyStrong).draw(at:NSPoint(x:8,y:6))
            Design.attributed(name,.body).draw(x:38,baseline:19,width:134)
            Design.rule.setStroke();NSBezierPath(rect:rect.insetBy(dx:0.5,dy:0.5)).stroke()
            return true
        }
        let drag=NSDraggingItem(pasteboardWriter:item)
        let point=view.convert(event.locationInWindow,from:nil)
        drag.setDraggingFrame(NSRect(x:point.x-20,y:point.y-14,width:size.width,height:size.height),contents:image)
        view.beginDraggingSession(with:[drag],event:event,source:view)
    }
}
