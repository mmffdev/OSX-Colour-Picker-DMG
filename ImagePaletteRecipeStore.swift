import Foundation

/// A reusable extraction recipe contains settings only; it never captures an image or palette name.
struct ImagePaletteSettings:Codable {
    var method:ImagePaletteRecipe.Method
    var region:ImagePaletteRecipe.Region
    var minimumColours:Int
    var maximumColours:Int
    var targetColours:Int
    var sampleSide:Int
    var minimumDifference:Double
    var minimumShare:Double
    var exposure:Double
    var contrast:Double
    var saturation:Double
    var highlights:Double
    var shadows:Double
    var warmth:Double
    var tint:Double

    init(_ recipe:ImagePaletteRecipe) {
        method=recipe.method;region=recipe.region
        minimumColours=recipe.minimumColours;maximumColours=recipe.maximumColours;targetColours=recipe.targetColours
        sampleSide=recipe.sampleSide;minimumDifference=recipe.minimumDifference;minimumShare=recipe.minimumShare
        exposure=recipe.exposure;contrast=recipe.contrast;saturation=recipe.saturation
        highlights=recipe.highlights;shadows=recipe.shadows;warmth=recipe.warmth;tint=recipe.tint
    }
    func apply(to recipe:inout ImagePaletteRecipe) {
        recipe.method=method;recipe.region=region
        recipe.minimumColours=minimumColours;recipe.maximumColours=maximumColours;recipe.targetColours=targetColours
        recipe.sampleSide=sampleSide;recipe.minimumDifference=minimumDifference;recipe.minimumShare=minimumShare
        recipe.exposure=exposure;recipe.contrast=contrast;recipe.saturation=saturation
        recipe.highlights=highlights;recipe.shadows=shadows;recipe.warmth=warmth;recipe.tint=tint
    }
    var isValid:Bool {
        (1...32).contains(minimumColours) && (2...32).contains(maximumColours) && minimumColours <= maximumColours &&
        (minimumColours...maximumColours).contains(targetColours) && (128...1024).contains(sampleSide) &&
        (0...40).contains(minimumDifference) && (0...0.05).contains(minimumShare) &&
        (-4...4).contains(exposure) && (0.2...2.5).contains(contrast) && (0...2.5).contains(saturation) &&
        (0...2).contains(highlights) && (-1...1).contains(shadows) && (-2...2).contains(warmth) && (-2...2).contains(tint)
    }
}

struct ImagePalettePreset:Codable {
    var format="colimg"
    var version=1
    var name:String
    var settings:ImagePaletteSettings
}

struct ImagePaletteRecipeIndexItem:Codable,Equatable {
    var id:UUID
    var name:String
    var file:String
}

enum ImagePaletteRecipeStore {
    private static let key="imagePaletteRecipeIndex"
    static var folder:URL {AppDataStore.current.root.appendingPathComponent("Presets/Images",isDirectory:true)}
    private static func index()throws->[ImagePaletteRecipeIndexItem] {
        let object=try AppDataStore.current.read()
        guard let raw=object[key] else{return []}
        return try JSONDecoder().decode([ImagePaletteRecipeIndexItem].self,from:JSONSerialization.data(withJSONObject:raw))
    }
    static func list()->[ImagePaletteRecipeIndexItem] {
        let items=(try? index()) ?? []
        return items.filter{$0.file == $0.id.uuidString+".colimg" && FileManager.default.fileExists(atPath:folder.appendingPathComponent($0.file).path)}
            .sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}
    }
    @discardableResult static func save(name raw:String,settings:ImagePaletteSettings)throws->ImagePaletteRecipeIndexItem {
        let name=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else{throw failure("Enter a recipe name.")}
        guard settings.isValid else{throw failure("The recipe settings are outside their supported ranges.")}
        let store=AppDataStore.current,manager=Handler_File_Manager.shared
        let old=try index()
        let item=old.first{$0.name.caseInsensitiveCompare(name) == .orderedSame}
            ?? ImagePaletteRecipeIndexItem(id:UUID(),name:name,file:"")
        let saved=ImagePaletteRecipeIndexItem(id:item.id,name:name,file:item.id.uuidString+".colimg")
        let preset=ImagePalettePreset(name:name,settings:settings)
        try manager.withTransaction(home:store.root) {
            try manager.createDirectory(folder)
            try manager.write(JSONEncoder().encode(preset),to:folder.appendingPathComponent(saved.file))
            try store.update {manifest in
                let next=old.filter{$0.id != saved.id}+[saved]
                manifest[key]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(next))
            }
        }
        return saved
    }
    static func load(_ item:ImagePaletteRecipeIndexItem)throws->ImagePaletteSettings {
        guard item.file == item.id.uuidString+".colimg" else{throw failure("Invalid recipe record.")}
        let preset=try JSONDecoder().decode(ImagePalettePreset.self,from:Handler_File_Manager.shared.read(folder.appendingPathComponent(item.file)))
        guard preset.format == "colimg",preset.version == 1,preset.settings.isValid else{throw failure("This recipe is invalid or from an unsupported version.")}
        return preset.settings
    }
    /// Older image .coltrans files may contain a linked image. Import keeps only their settings.
    @discardableResult static func importFile(_ url:URL)throws->ImagePaletteRecipeIndexItem {
        guard ["colimg","coltrans"].contains(url.pathExtension.lowercased()) else{throw failure("Choose a .colimg recipe, or an older image .coltrans recipe.")}
        let data=try Data(contentsOf:url)
        guard data.count <= 64*1024 else{throw failure("Choose a recipe under 64 KB.")}
        if let preset=try? JSONDecoder().decode(ImagePalettePreset.self,from:data),preset.format == "colimg",preset.version == 1 {
            return try save(name:preset.name,settings:preset.settings)
        }
        let old=try JSONDecoder().decode(ImagePaletteRecipe.self,from:data)
        guard old.version == 1 else{throw failure("This recipe version is not supported.")}
        return try save(name:url.deletingPathExtension().lastPathComponent,settings:ImagePaletteSettings(old))
    }
}
