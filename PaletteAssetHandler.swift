import Foundation

/// "Brand.colpalette": one palette and the library's record of each colour it uses.
struct PaletteDocument: Codable, Equatable {
    var format = "colour-palette"
    var version = 1
    var generator = ColourFiles.generator
    /// The project it sits in; nil for a palette on its own.
    var project: UUID?
    var palette: Swatch
    var colours: [Colour]
    /// The name the file was written under, without its extension: a file found under another name was renamed in Finder.
    var file: String? = nil
    /// The catalogue it was written in.
    var catalogue: UUID? = nil
}


/// Portable review data belongs to the palette, independent of its catalogue or owner.
struct PaletteReview:Codable,Equatable {
    enum Flag:String,Codable,CaseIterable {
        case orange,red,purple,blue,yellow,green,grey
        var title:String {rawValue.capitalized}
        var hex:String {
            switch self {
            case .orange:return "#FF9500"
            case .red:return "#FF453A"
            case .purple:return "#AF52DE"
            case .blue:return "#007AFF"
            case .yellow:return "#FFCC00"
            case .green:return "#28CD41"
            case .grey:return "#8E8E93"
            }
        }
    }
    var rating:Int=0
    var ratingChangedAt:Date?
    var flag:Flag?
    var flagChangedAt:Date?
}

/// The single bidirectional contract for a palette asset, including every swatch and its metadata.
/// Storage owners still coordinate catalogue/global transactions; this handler owns the asset bytes.
enum PaletteAssetHandler {
    typealias Asset=PaletteDocument
    enum Fault:LocalizedError {
        case unsupported,invalidRating
        var errorDescription:String? {
            switch self {
            case .unsupported:return "This palette file format or version is not supported."
            case .invalidRating:return "A palette rating must be between zero and five."
            }
        }
    }
    static func read(_ data:Data)throws->Asset {
        let asset=try ColourFiles.decoder().decode(Asset.self,from:data)
        try validate(asset);return asset
    }
    static func read(_ url:URL)throws->Asset {try read(Handler_File_Manager.shared.read(url))}
    static func data(_ asset:Asset)throws->Data {try validate(asset);return try Handler_File_Manager.shared.documentBytes(ColourFiles.encoder().encode(asset),extension:asset.format == "colour-typography" ? "coltyp" : "colpal")}
    static func store(_ asset:Asset,at url:URL)throws {try Handler_File_Manager.shared.write(data(asset),to:url)}
    static func document(_ palette:Swatch,in library:Library,member:UUID?,file:String,catalogue:UUID?=nil)->Asset {
        let keys=Set(palette.entries.map(\.hex)+(palette.styles ?? []).flatMap{[$0.ink,$0.paper]})
        var portable=palette
        // The selected purpose of an owned palette is held in its member's purpose document.
        if member != nil {portable.purpose=nil;portable.purposeChangedAt=nil}
        var asset=Asset(project:member,palette:portable,colours:library.colours.filter{keys.contains($0.hex)},file:file)
        asset.catalogue=catalogue
        if palette.isTypography {asset.format="colour-typography"}
        return asset
    }
    static func adopting(_ asset:Asset,id:UUID,project:UUID?,name:String)throws->Swatch {
        var record=try JSONSerialization.jsonObject(with:ColourFiles.encoder().encode(asset.palette)) as! [String:Any]
        record["id"]=id.uuidString;record["name"]=name
        record["projectID"]=project?.uuidString
        for key in ["bucketID","claim","position","placedAt","listPosition","listPlacedAt","favouritePosition","favouritePlacedAt"] {record.removeValue(forKey:key)}
        record["copiedFrom"]=asset.palette.id.uuidString
        return try ColourFiles.decoder().decode(Swatch.self,from:JSONSerialization.data(withJSONObject:record))
    }
    private static func validate(_ asset:Asset)throws {
        guard ["colour-palette","colour-typography"].contains(asset.format),asset.version == 1 else{throw Fault.unsupported}
        guard (0...5).contains(asset.palette.review?.rating ?? 0) else{throw Fault.invalidRating}
    }
    struct Presentation {
        let palette:Swatch
        let swatches:[SwatchEntry]
        let colours:[Colour]
        let useCount:Int
        let isTarget:Bool
        var rating:Int {palette.review?.rating ?? 0}
        var flag:PaletteReview.Flag? {palette.review?.flag}
    }
    /// The loaded library is populated from these same asset files. Do not reread disk per row/draw.
    static func presentation(_ palette:Swatch,in library:Library)->Presentation {
        var lineage:Set<UUID>=[palette.id]
        var changed=true
        while changed {
            let before=lineage.count
            for copy in library.swatches where copy.copiedFrom.map({lineage.contains($0)}) == true {lineage.insert(copy.id)}
            changed=before != lineage.count
        }
        let projects=Set(library.swatches.filter{lineage.contains($0.id)}.compactMap(\.projectID))
        let keys=Set(palette.entries.map(\.hex))
        return Presentation(palette:palette,swatches:palette.entries,colours:library.colours.filter{keys.contains($0.hex)},useCount:projects.count,isTarget:library.activeSwatchID == palette.id)
    }
    struct Filter:Equatable {
        var rating:Int?
        /// Nil means all flags; an empty string means unflagged.
        var flag:String?
        var order:Order = .newest
        func matches(_ palette:Swatch)->Bool {
            (rating == nil || (palette.review?.rating ?? 0) == rating) &&
            (flag == nil || (palette.review?.flag?.rawValue ?? "") == flag)
        }
    }
    static func filtered(_ palettes:[Swatch],by filter:Filter,in library:Library)->[Swatch] {
        ordered(palettes.filter{filter.matches($0)},by:filter.order,in:library)
    }
    enum Order:String,CaseIterable {
        case newest="Newest",oldest="Oldest",name="Name",starred="Starred",useCount="Project Use Count",rating="Rating",flag="Flag"
    }
    static func ordered(_ palettes:[Swatch],by order:Order,in library:Library)->[Swatch] {
        let uses=order == .useCount ? Dictionary(uniqueKeysWithValues:palettes.map{($0.id,presentation($0,in:library).useCount)}):[:]
        return palettes.sorted {a,b in
            switch order {
            case .newest:if a.createdAt != b.createdAt{return a.createdAt > b.createdAt}
            case .oldest:if a.createdAt != b.createdAt{return a.createdAt < b.createdAt}
            case .name:break
            case .starred:if a.favourite != b.favourite{return a.favourite}
            case .useCount:if uses[a.id] != uses[b.id]{return (uses[a.id] ?? 0) > (uses[b.id] ?? 0)}
            case .rating:if (a.review?.rating ?? 0) != (b.review?.rating ?? 0){return (a.review?.rating ?? 0) > (b.review?.rating ?? 0)}
            case .flag:if a.review?.flag != b.review?.flag{return (a.review?.flag?.rawValue ?? "zz") < (b.review?.flag?.rawValue ?? "zz")}
            }
            let result=a.name.localizedStandardCompare(b.name)
            return result == .orderedSame ? a.id.uuidString < b.id.uuidString:result == .orderedAscending
        }
    }
    static func setRating(_ value:Int,on id:UUID,in library:inout Library,at date:Date=Date()) {
        guard let i=library.swatches.firstIndex(where:{$0.id == id}) else{return}
        var review=library.swatches[i].review ?? PaletteReview()
        review.rating=min(5,max(0,value));review.ratingChangedAt=date;library.swatches[i].review=review
    }
    static func setFlag(_ flag:PaletteReview.Flag?,on id:UUID,in library:inout Library,at date:Date=Date()) {
        guard let i=library.swatches.firstIndex(where:{$0.id == id}) else{return}
        var review=library.swatches[i].review ?? PaletteReview()
        review.flag=flag;review.flagChangedAt=date;library.swatches[i].review=review
    }
    static func mergedReview(_ a:PaletteReview?,_ b:PaletteReview?)->PaletteReview? {
        guard a != nil || b != nil else{return nil}
        var value=a ?? PaletteReview()
        if let b {
            if a == nil || (b.ratingChangedAt ?? .distantPast) > (value.ratingChangedAt ?? .distantPast){value.rating=b.rating;value.ratingChangedAt=b.ratingChangedAt}
            if a == nil || (b.flagChangedAt ?? .distantPast) > (value.flagChangedAt ?? .distantPast){value.flag=b.flag;value.flagChangedAt=b.flagChangedAt}
        }
        return value
    }
}
