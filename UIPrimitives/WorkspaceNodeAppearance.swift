import AppKit
import UniformTypeIdentifiers
import ImageIO

/// Shared row appearance for the live Library tree and import destination projections.
/// Stable node keys let future node-colour edits appear in every projection.
enum WorkspaceNodeAppearance {
    static let colourKey="Workspace.Library.NodeColours"
    /// A schema bucket ID is reused by every project seeded from that schema.
    /// Scope its appearance to the owning project in every tree projection.
    static func projectNodeKey(project:UUID,node:UUID)->String {
        let key="project:\(project.uuidString):schema:\(node.uuidString)"
        var records=AppPreferences.shared.object(forKey:colourKey) as? [[String:String]] ?? []
        if !records.contains(where:{$0["id"] == key}),
           var legacy=records.first(where:{$0["id"] == node.uuidString}) {
            legacy["id"]=key
            records.append(legacy)
            AppPreferences.shared.set(records,forKey:colourKey)
        }
        return key
    }
    static func colour(_ key:String)->NSColor? {
        if let records=AppPreferences.shared.object(forKey:colourKey) as? [[String:String]],
           let hex=records.first(where:{$0["id"] == key})?["colour"] {return Design.hex(hex)}
        return nil
    }
    static func textColour(_ key:String)->NSColor? {
        guard let records=AppPreferences.shared.object(forKey:colourKey) as? [[String:String]],
              let hex=records.first(where:{$0["id"] == key})?["textColour"] else{return nil}
        return Design.hex(hex)
    }
    static func borderColour(_ key:String)->NSColor? {
        guard let records=AppPreferences.shared.object(forKey:colourKey) as? [[String:String]],
              let hex=records.first(where:{$0["id"] == key})?["borderColour"] else{return nil}
        return Design.hex(hex)
    }
    static func set(_ hex:String?,for key:String) {setValue(hex,field:"colour",for:key)}
    static func setText(_ hex:String?,for key:String) {setValue(hex,field:"textColour",for:key)}
    static func setBorder(_ hex:String?,for key:String) {setValue(hex,field:"borderColour",for:key)}
    private static func setValue(_ hex:String?,field:String,for key:String) {
        var records=AppPreferences.shared.object(forKey:colourKey) as? [[String:String]] ?? []
        var record=records.first(where:{$0["id"] == key}) ?? ["id":key]
        records.removeAll{$0["id"] == key}
        record[field]=hex
        if record.count > 1 {records.append(record)}
        AppPreferences.shared.set(records,forKey:colourKey)
    }
    static func ink(_ key:String)->NSColor? {
        if let textColour=textColour(key){return textColour}
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
