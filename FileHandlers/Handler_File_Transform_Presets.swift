import Foundation

/// Portable transform files use the same coordinated, versioned native-file path as other assets.
final class Handler_File_Transform_Preset: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name:"Transform Preset",extensions:["coltra"],format:"coltra",versions:[1],maximumBytes:16*1024*1024)) { data in
            let document=try ColourFiles.decoder().decode(ColtraDocument.self,from:data)
            guard document.version==1,document.format=="coltra",!document.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                  document.amount.isFinite,document.settings.numbers.values.allSatisfy(\.isFinite) else {throw failure("Invalid transform preset.")}
            return try ColourFiles.encoder().encode(document)
        }
    }
}

final class Handler_File_Diagram_Preset: Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name:"Diagram Preset",extensions:["colnode"],format:"colnode",versions:[1],maximumBytes:128*1024*1024)) { data in
            let document=try ColourFiles.decoder().decode(ColnodeDocument.self,from:data)
            guard document.version==1,document.format=="colnode",!document.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
                  (1...2048).contains(document.graph.nodes.count),document.graph.branches.count <= 4096,
                  document.graph.root.definitions == [],document.graph.root.sourceKeys.isEmpty else {throw failure("Invalid portable diagram.")}
            return try ColourFiles.encoder().encode(document)
        }
    }
}

/// Image-palette recipes are reusable settings without a linked source photograph.
final class Handler_File_Image_Palette_Recipe:Handler_File_JSON {
    init() {
        super.init(FileDescriptor(name:"Image Palette Recipe",extensions:["colimg"],format:"colimg",versions:[1],maximumBytes:64*1024)) {data in
            let preset=try ColourFiles.decoder().decode(ImagePalettePreset.self,from:data)
            guard preset.format == "colimg",preset.version == 1,!preset.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,preset.settings.isValid else{throw failure("Invalid image palette recipe.")}
            return try ColourFiles.encoder().encode(preset)
        }
    }
}
