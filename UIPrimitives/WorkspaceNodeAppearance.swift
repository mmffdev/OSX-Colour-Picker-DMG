import AppKit
import UniformTypeIdentifiers
import ImageIO

/// Shared row appearance for the live Library tree and import destination projections.
/// Stable node keys let future node-colour edits appear in every projection.
enum WorkspaceNodeAppearance {
    static let colourKey="Workspace.Library.NodeColours"
    static func colour(_ key:String)->NSColor? {
        if let records=AppPreferences.shared.object(forKey:colourKey) as? [[String:String]],
           let hex=records.first(where:{$0["id"] == key})?["colour"] {return Design.hex(hex)}
        return key == "catalogue" ? Design.houseYellow:nil
    }
    static func set(_ hex:String,for key:String) {
        var records=AppPreferences.shared.object(forKey:colourKey) as? [[String:String]] ?? []
        records.removeAll{$0["id"] == key}
        records.append(["id":key,"colour":hex])
        AppPreferences.shared.set(records,forKey:colourKey)
    }
    static func ink(_ key:String)->NSColor? {
        guard let colour=colour(key) else{return nil}
        return Theme.takesLightText(on:hexOf(colour) ?? "#FFFFFF") ? .white:.black
    }
}

/// Shared workspace navigation contract, also shown alongside the catalogue schema.
enum WorkspaceSidebarStructure {
    static let title="Workspace",favourites="My Favourites",library="My Library"
    static let paletteTitle="Palettes",iccTitle="ICC Profiles"
    static func sectionTitles(catalogue:String)->[String]{["Catalogues",favourites,catalogue,library]}
    static func summary(catalogue:String)->String{
        "Catalogues — Select A Catalogue · Import Catalogue…\nMy Favourites\n"+catalogue+" — Catalogue Files And Editable Structure\nMy Library\n    Library\n        Palettes — Library Palettes\n        ICC Profiles — Linked And System Profiles\nWorkspace branches are fixed navigation; the catalogue structure above remains editable."
    }
}
