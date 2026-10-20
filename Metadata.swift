import AppKit

/// Metadata common to native Colorgain assets. Photography-specific IPTC/XMP fields stay reserved
/// for the future photo workflow; these fields are useful for palettes, swatches and print delivery.
struct AssetMetadata: Codable, Equatable {
    var title: String? = nil
    var description: String? = nil
    var creator: String? = nil
    var rights: String? = nil
    var source: String? = nil
    var identifier: String? = nil
    var subjectCode: String? = nil
    var printProcess: String? = nil
    var spotColourNames: [String]? = nil
    var colourStandard: String? = nil
    var keywords: [String]? = nil
    /// Designer-defined and asset-specific fields; unknown keys round-trip with the asset.
    var extra: [String:String]? = nil
    var changedAt: Date? = nil
    var isEmpty: Bool { [title,description,creator,rights,source,identifier,subjectCode,printProcess,colourStandard].allSatisfy { ($0 ?? "").isEmpty } && (keywords ?? []).isEmpty && (spotColourNames ?? []).isEmpty && (extra ?? [:]).values.allSatisfy(\.isEmpty) }
    mutating func tidy() {
        title=title?.trimmedMetadata; description=description?.trimmedMetadata; creator=creator?.trimmedMetadata
        rights=rights?.trimmedMetadata; source=source?.trimmedMetadata; identifier=identifier?.trimmedMetadata
        subjectCode=subjectCode?.trimmedMetadata; printProcess=printProcess?.trimmedMetadata; colourStandard=colourStandard?.trimmedMetadata
        keywords=Library.cleanTags(keywords ?? []); spotColourNames=Library.cleanTags(spotColourNames ?? [])
        extra=extra?.compactMapValues { $0.trimmedMetadata }
        if extra?.isEmpty == true { extra=nil }
        if isEmpty { self = AssetMetadata() } else {
            // Native asset JSON stores dates in milliseconds. Use the same precision here so
            // an in-memory edit and its immediate readback represent the identical instant.
            changedAt=Date(timeIntervalSince1970:(Date().timeIntervalSince1970*1000).rounded()/1000)
        }
    }
}
private extension String { var trimmedMetadata: String? { let v=trimmingCharacters(in:.whitespacesAndNewlines); return v.isEmpty ? nil : v } }

struct KeywordSet: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var terms: [String]
}

enum MetadataPresetStore {
    static let key="Metadata.presets.v1"
    static func all()->[String:AssetMetadata]{guard let data=AppPreferences.shared.data(forKey:key),let value=try? JSONDecoder().decode([String:AssetMetadata].self,from:data) else{return [:]};return value}
    static func save(_ value:AssetMetadata,named raw:String){let name=raw.trimmingCharacters(in:.whitespacesAndNewlines);guard !name.isEmpty else{return};var all=all();all[name]=value;if let data=try? JSONEncoder().encode(all){AppPreferences.shared.set(data,forKey:key)}}
    static func remove(_ name:String){var values=all();values.removeValue(forKey:name);if let data=try? JSONEncoder().encode(values){AppPreferences.shared.set(data,forKey:key)}}
}

/// Per-catalogue metadata defaults and workflow preset choices live in the .coldat manifest.
struct MetadataConfiguration: Codable {
    var master=AssetMetadata()
    var creationPreset:String?=nil
    var exportPreset:String?=nil
    var inspectorPreset:String?=nil
    private static let key="metadataConfiguration"
    static func load()->Self {
        guard let record=try? AppDataStore.current.read()[key],
              let data=try? JSONSerialization.data(withJSONObject:record),
              let value=try? JSONDecoder().decode(Self.self,from:data) else{return Self()}
        return value
    }
    func save(){
        do {
            let data=try JSONEncoder().encode(self)
            let value=try JSONSerialization.jsonObject(with:data)
            try AppDataStore.current.update { $0[Self.key]=value }
        } catch { NSLog("Metadata settings: %@",error.localizedDescription) }
    }
    static func forNewAsset()->AssetMetadata? {
        let config=load();var value=config.master
        if let name=config.creationPreset,let preset=MetadataPresetStore.all()[name] {
            for item in AssetMetadataSchema.items {
                let text=AssetMetadataSchema.value(item,in:preset)
                if !text.isEmpty {AssetMetadataSchema.assign(text,for:item,to:&value)}
            }
            for (key,text) in preset.extra ?? [:] where !text.isEmpty {
                var extra=value.extra ?? [:];extra[key]=text;value.extra=extra
            }
        }
        return value.isEmpty ? nil:value
    }
}

/// App-wide vocabulary/keyword authority in .coldat. Catalogue copies remain a local lookup index;
/// native asset files remain the portable source of each asset's actual values and assignments.
enum AssetMetadataRegistry {
    private static let manifestKey="assetMetadata"
    static func keywordSets()->[KeywordSet]{guard let dict=try? AppDataStore.current.read()[manifestKey] as? [String:Any],let rows=dict["sets"] as? [[String:Any]],let data=try? JSONSerialization.data(withJSONObject:rows) else{return []};return (try? JSONDecoder().decode([KeywordSet].self,from:data)) ?? []}
    static func saveKeywordSet(_ set:KeywordSet){do{let data=try JSONEncoder().encode(set),row=try JSONSerialization.jsonObject(with:data) as? [String:Any] ?? [:];try AppDataStore.current.update{manifest in var dict=manifest[manifestKey] as? [String:Any] ?? [:];var rows=dict["sets"] as? [[String:Any]] ?? [];rows.removeAll{($0["id"] as? String)==set.id.uuidString};rows.append(row);dict["sets"]=rows;manifest[manifestKey]=dict}}catch{NSLog("Keyword set: %@",error.localizedDescription)}}
    static func merge(_ metadata:[AssetMetadata],keywords:[String],tags:[TagInfo]) {
        let metadataValues:[String]=metadata.flatMap { entry in
            let fields:[String?]=[entry.title,entry.creator,entry.rights,entry.source,entry.subjectCode,entry.printProcess,entry.colourStandard]
            return fields.compactMap{$0} + (entry.keywords ?? []) + (entry.spotColourNames ?? [])
        }
        let incoming=metadataValues + keywords + tags.map(\.name) + tags.flatMap{$0.synonyms ?? []}
        let clean=Library.cleanTags(incoming)
        guard !clean.isEmpty || !tags.isEmpty else{return}
        let store=AppDataStore.current
        let current=(try? store.read()[manifestKey] as? [String:Any]) ?? [:]
        let known=Set((current["values"] as? [String] ?? []).map{$0.lowercased()})
        let oldTags=Dictionary(uniqueKeysWithValues:(current["keywords"] as? [[String:Any]] ?? []).compactMap{row in (row["name"] as? String).map{($0.lowercased(),row)}})
        let tagsChanged=tags.contains{tag in
            guard let row=oldTags[tag.name.lowercased()] else{return true}
            return (row["parentID"] as? String) != tag.parentID?.uuidString || (row["synonyms"] as? [String] ?? []) != (tag.synonyms ?? []) || (row["set"] as? String) != tag.keywordSet || (row["colour"] as? String) != tag.colour || (row["removed"] as? Bool) != (tag.removed ?? false)
        }
        guard clean.contains(where:{!known.contains($0.lowercased())}) || tagsChanged else{return}
        do {
            try store.update { manifest in
                var registry=manifest[manifestKey] as? [String:Any] ?? [:]
                var values=registry["values"] as? [String] ?? []
                var seen=Set(values.map{$0.lowercased()})
                for value in clean where seen.insert(value.lowercased()).inserted { values.append(value) }
                registry["values"]=values.sorted{$0.localizedCaseInsensitiveCompare($1) == .orderedAscending}
                var definitions=registry["keywords"] as? [[String:Any]] ?? []
                var byName=Dictionary(uniqueKeysWithValues:definitions.compactMap{row in (row["name"] as? String).map{($0.lowercased(),row)}})
                for tag in tags {
                    var row:[String:Any] = ["name":tag.name,"changedAt":tag.changedAt.timeIntervalSince1970]
                    if let parent=tag.parentID{row["parentID"]=parent.uuidString};if let synonyms=tag.synonyms{row["synonyms"]=synonyms};if let set=tag.keywordSet{row["set"]=set};if let colour=tag.colour{row["colour"]=colour};row["removed"]=tag.removed ?? false
                    byName[tag.name.lowercased()]=row
                }
                definitions=byName.values.sorted{(($0["name"] as? String) ?? "").localizedCaseInsensitiveCompare(($1["name"] as? String) ?? "") == .orderedAscending}
                registry["keywords"]=definitions;manifest[manifestKey]=registry
            }
        }catch{NSLog("Metadata vocabulary: %@",error.localizedDescription)}
    }
}

enum AssetMetadataSchema {
    static let fields: [(key:WritableKeyPath<AssetMetadata,String?>, label:String)] = [
        (\.title,"Title"),(\.description,"Description"),(\.creator,"Creator"),(\.rights,"Rights"),
        (\.source,"Source"),(\.identifier,"Identifier"),(\.subjectCode,"Subject Code"),
        (\.printProcess,"Print Process"),(\.colourStandard,"Colour Standard")
    ]
    struct Item {
        let id: Int
        let key: String
        let label: String
        let group: String
        let multiline: Bool
        init(_ id:Int,_ key:String,_ label:String,_ group:String,_ multiline:Bool=false) {
            self.id=id;self.key=key;self.label=label;self.group=group;self.multiline=multiline
        }
    }
    static let groups=["Identity","People & Project","Discovery","Rights & Credits","Dates & History","Colour & Production","File & Provenance","Delivery & Review","Custom Fields"]
    static func customID(_ key:String)->Int {
        var hash:UInt64=14695981039346656037
        for byte in key.utf8 { hash=(hash ^ UInt64(byte)) &* 1099511628211 }
        return 1000+Int(hash & 0x7fff_ffff)
    }
    static let items:[Item] = [
        Item(0,"title","Title","Identity"),Item(1,"description","Description","Identity",true),
        Item(5,"identifier","Identifier","Identity"),
        Item(2,"creator","Creator","People & Project"),
        Item(11,"studio","Studio","People & Project"),Item(12,"client","Client","People & Project"),
        Item(13,"project","Project","People & Project"),Item(14,"campaign","Campaign / Job","People & Project"),
        Item(15,"contributors","Contributors","People & Project"),Item(16,"contact","Contact","People & Project"),
        Item(10,"keywords","Keywords","Discovery"),Item(6,"subjectCode","Subject Code","Discovery"),
        Item(17,"category","Subject / Category","Discovery"),
        Item(18,"usageContext","Usage Context","Discovery"),Item(19,"language","Language","Discovery"),
        Item(3,"rights","Rights","Rights & Credits",true),
        Item(20,"rightsHolder","Rights Holder","Rights & Credits"),
        Item(21,"creditLine","Credit Line","Rights & Credits"),
        Item(22,"licence","Licence / Usage Terms","Rights & Credits",true),
        Item(23,"usageExpiry","Usage Expiry","Rights & Credits"),
        Item(8,"colourStandard","Colour Standard","Colour & Production"),
        Item(7,"printProcess","Print Process","Colour & Production"),
        Item(9,"spotColourNames","Spot Colour Names","Colour & Production"),
        Item(24,"workingSpace","Working Colour Space","Colour & Production"),
        Item(25,"iccProfile","ICC Profile","Colour & Production"),
        Item(26,"medium","Intended Medium","Colour & Production"),
        Item(27,"substrate","Substrate / Stock","Colour & Production"),
        Item(28,"proofCondition","Proof Condition","Colour & Production"),
        Item(4,"source","Source","File & Provenance"),
        Item(29,"approvalStatus","Approval Status","Delivery & Review"),
        Item(30,"approvedBy","Approved By","Delivery & Review"),
        Item(31,"deliveryDestination","Delivery Destination","Delivery & Review"),
        Item(32,"revisionNotes","Revision Notes","Delivery & Review",true),
        Item(33,"accessibilityNotes","Accessibility Notes","Delivery & Review",true),
        Item(34,"exportFormat","Export Format","Delivery & Review")
    ]
    static func value(_ item:Item,in metadata:AssetMetadata)->String {
        if fields.indices.contains(item.id) { return metadata[keyPath:fields[item.id].key] ?? "" }
        if item.id == 9 { return (metadata.spotColourNames ?? []).joined(separator:", ") }
        if item.id == 10 { return (metadata.keywords ?? []).joined(separator:", ") }
        return metadata.extra?[item.key] ?? ""
    }
    static func assign(_ text:String,for item:Item,to metadata:inout AssetMetadata) {
        if fields.indices.contains(item.id) { metadata[keyPath:fields[item.id].key]=text;return }
        if item.id == 9 { metadata.spotColourNames=Library.cleanTags(text.split(separator:",").map(String.init));return }
        if item.id == 10 { metadata.keywords=Library.cleanTags(text.split(separator:",").map(String.init));return }
        var extra=metadata.extra ?? [:];extra[item.key]=text;metadata.extra=extra
    }
    static func apply(_ source:AssetMetadata,to destination:inout AssetMetadata,including ids:Set<Int>) {
        for item in items where ids.contains(item.id) { assign(value(item,in:source),for:item,to:&destination) }
        let customKeys=(source.extra ?? [:]).keys.sorted().filter { key in !items.contains(where:{$0.key==key}) }
        for key in customKeys where ids.contains(customID(key)) {
            var extra=destination.extra ?? [:];extra[key]=source.extra?[key];destination.extra=extra
        }
    }
}

/// Compact read-only loadout for the selected asset in Rail 2.
final class AssetMetadataPanel: NSView, WorkspacePanelContentMetrics {
    var minimumContentHeight: CGFloat { palette == nil ? 116:360 }
    var palette: Swatch? { didSet { updateFields() } }
    var onEdit: ((UUID)->Void)?
    var onSettings: (()->Void)?
    private let title=Design.text("Select An Asset",.bodyStrong)
    private let spectrum=MetadataFlippedView()
    private let preset=AnalysisMenu("Inspector Preset",[])
    private var labels:[NSTextField]=[]
    private var values:[NSTextField]=[]
    private let edit=SwissButton("Edit Metadata",.quiet)
    private let settings=SwissButton("Metadata Settings",.quiet)
    override init(frame:NSRect) {
        super.init(frame:frame)
        addSubview(title);addSubview(spectrum);addSubview(preset)
        for _ in 0..<6 {
            let label=Design.text("",.caption,colour:Design.quiet),value=Design.text("",.body)
            value.lineBreakMode = .byTruncatingTail
            labels.append(label);values.append(value);addSubview(label);addSubview(value)
        }
        edit.actionSymbol="pencil";edit.target=self;edit.action=#selector(editMetadata)
        settings.actionSymbol="slider.horizontal.3";settings.target=self;settings.action=#selector(openSettings)
        addSubview(edit);addSubview(settings)
        edit.isEnabled=false
        preset.changed={ [weak self] index in
            var config=MetadataConfiguration.load()
            config.inspectorPreset=index>0 ? self?.preset.titleOfSelectedItem:nil
            config.save();self?.updateFields()
        }
        updateFields()
    }
    required init?(coder:NSCoder){fatalError()}
    private func updateFields() {
        let names=MetadataPresetStore.all().keys.sorted(),config=MetadataConfiguration.load()
        preset.options(["All Fields"]+names,selected:names.firstIndex(of:config.inspectorPreset ?? "").map{$0+1} ?? 0)
        guard let p=palette else {
            title.stringValue="Select An Asset"
            edit.isEnabled=false;spectrum.isHidden=true;preset.isHidden=true;settings.isHidden=true
            for label in labels{label.isHidden=true}
            for value in values{value.isHidden=true}
            needsLayout=true;return
        }
        title.stringValue=p.metadata?.title ?? p.name;title.toolTip=title.stringValue
        edit.isEnabled=true;spectrum.isHidden=false;preset.isHidden=false;settings.isHidden=false
        spectrum.subviews.forEach{$0.removeFromSuperview()}
        for entry in p.entries.prefix(12) {
            let strip=NSView();strip.wantsLayer=true;strip.layer?.backgroundColor=Design.hex(entry.hex).cgColor;spectrum.addSubview(strip)
        }
        let format=DateFormatter();format.dateStyle = .medium;format.timeStyle = .none
        let m=p.metadata
        var rows:[(String,String)]=[
            ("Type",p.isTypography ? "Typography":"Palette"),
            ("Creator",m?.creator ?? "Add"),
            ("Created",format.string(from:p.createdAt)),
            ("Modified",format.string(from:m?.changedAt ?? p.createdAt)),
            ("Keywords",(m?.keywords ?? p.tagList).joined(separator:", ")),
            ("Rights",m?.rights ?? "Add")
        ]
        if let presetName=config.inspectorPreset,let selected=MetadataPresetStore.all()[presetName] {
            let chosen=AssetMetadataSchema.items.filter{!AssetMetadataSchema.value($0,in:selected).isEmpty}
            rows=chosen.prefix(6).map{($0.label,AssetMetadataSchema.value($0,in:m ?? AssetMetadata()))}
            if rows.isEmpty {rows=[("Created",format.string(from:p.createdAt))]}
        }
        for i in labels.indices {
            let visible=i<rows.count
            labels[i].isHidden = !visible;values[i].isHidden = !visible
            if visible {labels[i].stringValue=rows[i].0;values[i].stringValue=rows[i].1.isEmpty ? "Add":rows[i].1;values[i].toolTip=values[i].stringValue}
        }
        needsLayout=true
    }
    override func layout(){
        super.layout()
        let width=bounds.width-32
        title.frame=NSRect(x:16,y:bounds.height-28,width:width,height:20)
        spectrum.frame=NSRect(x:16,y:bounds.height-58,width:width,height:14)
        let count=spectrum.subviews.count
        for (i,strip) in spectrum.subviews.enumerated(){let step=width/CGFloat(max(1,count));strip.frame=NSRect(x:CGFloat(i)*step,y:0,width:step+0.5,height:14)}
        preset.frame=NSRect(x:16,y:bounds.height-100,width:width,height:30)
        for i in labels.indices {
            let y=bounds.height-126-CGFloat(i)*26
            labels[i].frame=NSRect(x:16,y:y,width:88,height:20)
            values[i].frame=NSRect(x:108,y:y,width:max(0,bounds.width-124),height:20)
        }
        edit.frame=NSRect(x:16,y:50,width:width,height:30)
        settings.frame=NSRect(x:16,y:16,width:width,height:30)
    }
    @objc private func editMetadata(){if let id=palette?.id{onEdit?(id)}}
    @objc private func openSettings(){onSettings?()}
}

/// The subject preview is independent of the metadata schema, so this editor can show any asset.
struct MetadataAssetSubject {
    let name: String
    let type: String
    let colours: [NSColor]
    let image: NSImage?
    let created: Date?
    let modified: Date?
    init(palette: Swatch) {
        name=palette.name
        type=palette.isTypography ? "Typography" : (palette.entries.count == 1 ? "Swatch" : "Palette")
        colours=palette.entries.prefix(12).map { Design.hex($0.hex) }
        image=nil
        created=palette.createdAt
        modified=palette.metadata?.changedAt
    }
    init(name:String,type:String,colours:[NSColor]=[],image:NSImage?=nil,created:Date?=nil,modified:Date?=nil) {
        self.name=name;self.type=type;self.colours=colours;self.image=image;self.created=created;self.modified=modified
    }
}
private final class MetadataFlippedView: NSView { override var isFlipped:Bool { true } }
private final class MetadataAssetView: NSView {
    override var isFlipped:Bool { true }
    private let subject:MetadataAssetSubject
    private let heading=Design.text("Selected Asset",.caption,colour:Design.quiet)
    private let name=Design.text("",.bodyStrong)
    private let details=Design.text("",.caption,colour:Design.quiet)
    private let created=Design.text("",.caption,colour:Design.quiet)
    private let modified=Design.text("",.caption,colour:Design.quiet)
    private let imageView=NSImageView()
    private let spectrum=MetadataFlippedView()
    init(_ subject:MetadataAssetSubject) {
        self.subject=subject;super.init(frame:.zero)
        addSubview(heading);addSubview(name);addSubview(details);addSubview(created);addSubview(modified)
        addSubview(spectrum);addSubview(imageView)
        name.stringValue=subject.name
        details.stringValue=subject.type + (subject.colours.isEmpty ? "" : " · \(subject.colours.count) Colours")
        let format=DateFormatter();format.dateStyle = .medium;format.timeStyle = .short
        created.stringValue=subject.created.map { "Created  " + format.string(from:$0) } ?? ""
        modified.stringValue=subject.modified.map { "Edited  " + format.string(from:$0) } ?? ""
        imageView.image=subject.image;imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.isHidden=subject.image == nil
        spectrum.isHidden=subject.image != nil
        spectrum.wantsLayer=true;spectrum.layer?.borderColor=Design.rule.cgColor;spectrum.layer?.borderWidth=1
        for colour in subject.colours {
            let strip=NSView();strip.wantsLayer=true;strip.layer?.backgroundColor=colour.cgColor;spectrum.addSubview(strip)
        }
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout() {
        super.layout()
        let inner=bounds.insetBy(dx:16,dy:0),width=inner.width
        heading.frame=NSRect(x:inner.minX,y:18,width:width,height:18)
        let previewHeight=min(220,max(100,width*0.77))
        spectrum.frame=NSRect(x:inner.minX,y:50,width:width,height:previewHeight)
        imageView.frame=spectrum.frame
        let count=spectrum.subviews.count
        for (index,strip) in spectrum.subviews.enumerated() {
            let step=width/CGFloat(max(1,count))
            strip.frame=NSRect(x:CGFloat(index)*step,y:0,width:step+0.5,height:previewHeight)
        }
        name.frame=NSRect(x:inner.minX,y:previewHeight+66,width:width,height:28)
        details.frame=NSRect(x:inner.minX,y:previewHeight+96,width:width,height:20)
        created.frame=NSRect(x:inner.minX,y:previewHeight+150,width:width,height:20)
        modified.frame=NSRect(x:inner.minX,y:previewHeight+174,width:width,height:20)
    }
}

/// Three fixed columns: reusable asset preview, section navigation, and scrollable editorial rows.
final class AssetMetadataForm: NSView {
    private struct Row {
        let item:AssetMetadataSchema.Item
        let label:NSTextField
        let field:NSTextField
        let check:SwissCheckbox
        var height:CGFloat { item.multiline ? 70:42 }
    }
    private final class Group {
        let title:String
        let header=MetadataFlippedView()
        let toggle=ClickCursorButton(frame:.zero)
        let check=SwissCheckbox("")
        let label:NSTextField
        var rows:[Row]=[]
        var facts:[(NSTextField,NSTextField)]=[]
        var collapsed=false
        var y:CGFloat=0
        init(_ title:String) {self.title=title;label=Design.text(title,.bodyStrong)}
    }
    private let palette:Swatch
    private let subject:MetadataAssetSubject
    private let initial:AssetMetadata
    private let selectedCount:Int
    private let preview:MetadataAssetView
    private let navigation=MetadataFlippedView()
    private let formPane=MetadataFlippedView()
    private let scroll=FittedScrollView()
    private let document=MetadataFlippedView()
    private let footer=MetadataFlippedView()
    private let firstRule=MetadataFlippedView()
    private let secondRule=MetadataFlippedView()
    private let footerRule=MetadataFlippedView()
    private let keywordHelp=Design.text("Keywords are search terms. Collections group assets separately.",.caption,colour:Design.quiet)
    private let title=Design.text("Metadata",.header)
    private let intro=Design.text("",.caption,colour:Design.quiet)
    private let navHeading=Design.text("Sections",.caption,colour:Design.quiet)
    private let preset:AnalysisMenu
    private let keywordSet:AnalysisMenu
    private let addField=SwissButton("Add Field",.quiet)
    private let savePreset=SwissButton("Save Preset",.quiet)
    private let checkAll=SwissButton("Check All",.quiet)
    private let checkNone=SwissButton("Check None",.quiet)
    private let checkFilled=SwissButton("Check Filled",.quiet)
    private let cancel=SwissButton("Cancel",.quiet)
    private let done=SwissButton("Done",.primary)
    private var groups:[Group]=[]
    private var navButtons:[ClickCursorButton]=[]
    private var customItems:[AssetMetadataSchema.Item]=[]
    private var fieldByID:[Int:NSTextField]=[:]
    private var include:[Int:SwissCheckbox]=[:]
    private var selectedGroup=0
    var onSave:((AssetMetadata,Set<Int>)->Void)?
    var onCancel:(()->Void)?
    override var isFlipped:Bool { true }
    init(palette:Swatch,selectedCount:Int=1) {
        self.palette=palette;self.subject=MetadataAssetSubject(palette:palette)
        self.selectedCount=selectedCount;self.initial=palette.metadata ?? AssetMetadata()
        self.preview=MetadataAssetView(MetadataAssetSubject(palette:palette))
        self.preset=AnalysisMenu("Metadata Preset",["Custom"]+MetadataPresetStore.all().keys.sorted())
        self.keywordSet=AnalysisMenu("Keyword Set",["Keyword Set"]+AssetMetadataRegistry.keywordSets().map(\.name).sorted())
        super.init(frame:.zero)
        build()
    }
    required init?(coder:NSCoder){fatalError()}
    private func build() {
        wantsLayer=true;layer?.backgroundColor=Design.card.cgColor
        addSubview(preview);addSubview(navigation);addSubview(formPane);addSubview(footer)
        for rule in [firstRule,secondRule,footerRule] {rule.wantsLayer=true;rule.layer?.backgroundColor=Design.rule.cgColor;addSubview(rule)}
        document.addSubview(keywordHelp)
        navigation.addSubview(navHeading)
        formPane.addSubview(title);formPane.addSubview(intro);formPane.addSubview(preset)
        formPane.addSubview(keywordSet);formPane.addSubview(addField);formPane.addSubview(savePreset)
        scroll.drawsBackground=false;scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        scroll.documentView=document;formPane.addSubview(scroll)
        intro.stringValue=selectedCount>1 ? "Editing \(selectedCount) assets · Check fields to apply" : "Edit details for this asset. File facts are read-only."
        for (index,name) in AssetMetadataSchema.groups.enumerated() {
            let group=Group(name);groups.append(group)
            let button=ClickCursorButton(frame:.zero);button.title=name;button.tag=index
            button.isBordered=false;button.font=Design.Text.body.font()
            button.alignment = .left;button.target=self;button.action=#selector(navigate(_:))
            button.setAccessibilityLabel("Show \(name)")
            button.wantsLayer=true;navigation.addSubview(button);navButtons.append(button)
            group.toggle.image=NSImage(systemSymbolName:"chevron.down",accessibilityDescription:"Collapse \(name)")
            group.toggle.isBordered=false;group.toggle.tag=index
            group.toggle.target=self;group.toggle.action=#selector(toggleGroup(_:))
            group.check.state = .on;group.check.tag=index
            group.check.target=self;group.check.action=#selector(checkGroup(_:))
            group.header.addSubview(group.toggle);group.header.addSubview(group.check);group.header.addSubview(group.label)
            document.addSubview(group.header)
        }
        for item in AssetMetadataSchema.items { append(item) }
        for key in (initial.extra ?? [:]).keys.sorted().filter({ key in !AssetMetadataSchema.items.contains(where:{$0.key==key}) }) {
            append(.init(AssetMetadataSchema.customID(key),key,key,"Custom Fields"))
        }
        populateFacts()
        preset.changed = { [weak self] index in self?.applyPreset(index) }
        keywordSet.changed = { [weak self] index in self?.applyKeywordSet(index) }
        for (button,symbol,action) in [(addField,"plus",#selector(addFieldPressed)),
                                       (savePreset,"bookmark",#selector(savePresetPressed)),
                                       (checkAll,"checkmark.square",#selector(checkAllPressed)),
                                       (checkNone,"square",#selector(checkNonePressed)),
                                       (checkFilled,"checkmark.square.fill",#selector(checkFilledPressed)),
                                       (cancel,"xmark",#selector(cancelPressed)),
                                       (done,"checkmark",#selector(donePressed))] {
            button.actionSymbol=symbol;button.target=self;button.action=action
        }
        for button in [checkAll,checkNone,checkFilled,cancel,done] { footer.addSubview(button) }
        refreshGroupChecks()
    }
    private func append(_ item:AssetMetadataSchema.Item) {
        guard let group=groups.first(where:{$0.title==item.group}) else{return}
        if item.id>=1000 { customItems.append(item) }
        let label=Design.text(item.label,.caption)
        let field=NSTextField(string:item.id>=1000 ? initial.extra?[item.key] ?? "" : AssetMetadataSchema.value(item,in:initial))
        field.font=Design.Text.body.font();field.textColor=Design.ink
        field.backgroundColor=Design.card;field.isBordered=true;field.focusRingType = .none
        field.usesSingleLineMode = !item.multiline
        if item.multiline { field.lineBreakMode = .byWordWrapping }
        field.setAccessibilityLabel(item.label)
        let check=SwissCheckbox("");check.state = .on;check.tag=item.id
        check.setAccessibilityLabel("Include \(item.label)")
        check.target=self;check.action=#selector(checkField(_:))
        document.addSubview(label);document.addSubview(field);document.addSubview(check)
        group.rows.append(Row(item:item,label:label,field:field,check:check))
        fieldByID[item.id]=field;include[item.id]=check
    }
    private func populateFacts() {
        let format=DateFormatter();format.dateStyle = .medium;format.timeStyle = .short
        let facts:[(String,String,String)]=[
            ("Dates & History","Created In Colorgain",format.string(from:palette.createdAt)),
            ("Dates & History","Last Edited In Colorgain",palette.metadata?.changedAt.map(format.string(from:)) ?? "—"),
            ("File & Provenance","Asset Type",subject.type),
            ("File & Provenance","Asset ID",palette.id.uuidString),
            ("File & Provenance","Original Filename",palette.name+".colpal")
        ]
        for (section,label,value) in facts {
            guard let group=groups.first(where:{$0.title==section}) else{continue}
            let a=Design.text(label,.caption,colour:Design.quiet),b=Design.text(value,.body)
            b.lineBreakMode = .byTruncatingMiddle;b.toolTip=value
            document.addSubview(a);document.addSubview(b);group.facts.append((a,b))
        }
    }
    override func layout() {
        super.layout()
        let footHeight:CGFloat=56,bodyHeight=max(0,bounds.height-footHeight)
        let previewWidth=min(260,max(180,bounds.width*0.205))
        let navWidth=min(218,max(154,bounds.width*0.16))
        preview.frame=NSRect(x:0,y:0,width:previewWidth,height:bodyHeight)
        navigation.frame=NSRect(x:previewWidth,y:0,width:navWidth,height:bodyHeight)
        formPane.frame=NSRect(x:previewWidth+navWidth,y:0,width:max(0,bounds.width-previewWidth-navWidth),height:bodyHeight)
        footer.frame=NSRect(x:0,y:bodyHeight,width:bounds.width,height:footHeight)
        firstRule.frame=NSRect(x:previewWidth,y:0,width:1,height:bodyHeight)
        secondRule.frame=NSRect(x:previewWidth+navWidth,y:0,width:1,height:bodyHeight)
        footerRule.frame=NSRect(x:0,y:bodyHeight,width:bounds.width,height:1)
        navHeading.frame=NSRect(x:16,y:20,width:navWidth-32,height:18)
        for (i,button) in navButtons.enumerated() {
            button.frame=NSRect(x:8,y:52+CGFloat(i)*38,width:navWidth-16,height:34)
            button.layer?.cornerRadius=4
            button.layer?.backgroundColor=i==selectedGroup ? Design.houseYellow.cgColor:NSColor.clear.cgColor
            button.contentTintColor=i==selectedGroup ? .black:Design.ink
        }
        let formWidth=formPane.bounds.width
        title.frame=NSRect(x:24,y:14,width:max(0,formWidth-48),height:27)
        intro.frame=NSRect(x:24,y:42,width:max(0,formWidth-48),height:20)
        preset.frame=NSRect(x:24,y:72,width:190,height:30)
        keywordSet.frame=NSRect(x:224,y:72,width:170,height:30)
        addField.frame=NSRect(x:max(404,formWidth-202),y:72,width:90,height:32)
        savePreset.frame=NSRect(x:max(496,formWidth-110),y:72,width:100,height:32)
        scroll.frame=NSRect(x:0,y:116,width:formWidth,height:max(0,bodyHeight-116))
        layoutDocument(width:max(420,formWidth-20))
        let buttonY:CGFloat=12
        checkAll.frame=NSRect(x:18,y:buttonY,width:94,height:32)
        checkNone.frame=NSRect(x:132,y:buttonY,width:102,height:32)
        checkFilled.frame=NSRect(x:254,y:buttonY,width:116,height:32)
        done.frame=NSRect(x:bounds.width-104,y:buttonY,width:78,height:32)
        cancel.frame=NSRect(x:bounds.width-204,y:buttonY,width:84,height:32)
    }
    private func layoutDocument(width:CGFloat) {
        let left:CGFloat=24,labelWidth:CGFloat=150,fieldX:CGFloat=190
        let fieldWidth=max(150,width-fieldX-74)
        var y:CGFloat=8
        for (index,group) in groups.enumerated() {
            group.y=y
            group.header.frame=NSRect(x:left,y:y,width:width-left-24,height:38)
            group.toggle.frame=NSRect(x:0,y:7,width:24,height:24)
            group.check.frame=NSRect(x:28,y:7,width:26,height:24)
            group.label.frame=NSRect(x:62,y:8,width:width-left-100,height:22)
            y += 46
            let hidden=group.collapsed
            for row in group.rows {
                row.label.isHidden=hidden;row.field.isHidden=hidden;row.check.isHidden=hidden
                if hidden {continue}
                row.label.frame=NSRect(x:left+12,y:y+8,width:labelWidth-12,height:20)
                row.field.frame=NSRect(x:fieldX,y:y,width:fieldWidth,height:row.height-10)
                row.check.frame=NSRect(x:fieldX+fieldWidth+8,y:y+7,width:26,height:26)
                y += row.height
            }
            for (label,value) in group.facts {
                label.isHidden=hidden;value.isHidden=hidden
                if hidden {continue}
                label.frame=NSRect(x:left+12,y:y+5,width:labelWidth-12,height:20)
                value.frame=NSRect(x:fieldX,y:y+5,width:fieldWidth,height:20)
                y += 34
            }
            if index==2 {
                keywordHelp.isHidden=hidden
                if !hidden {keywordHelp.frame=NSRect(x:fieldX,y:y,width:fieldWidth,height:28);y += 34}
            }
            y += 24
        }
        document.frame=NSRect(x:0,y:0,width:width,height:max(y,scroll.contentSize.height))
    }
    private func refreshGroupChecks() {
        for group in groups {
            let on=group.rows.filter{$0.check.state == .on}.count
            group.check.state=on==0 ? .off:(on==group.rows.count ? .on:.mixed)
            group.check.allowsMixedState=true
        }
    }
    @objc private func navigate(_ sender:NSButton) {
        selectedGroup=sender.tag
        needsLayout=true;layoutSubtreeIfNeeded()
        guard groups.indices.contains(selectedGroup) else{return}
        let top=groups[selectedGroup].y
        scroll.contentView.scroll(to:NSPoint(x:0,y:top));scroll.reflectScrolledClipView(scroll.contentView)
    }
    @objc private func toggleGroup(_ sender:NSButton) {
        guard groups.indices.contains(sender.tag) else{return}
        let group=groups[sender.tag];group.collapsed.toggle()
        group.toggle.image=NSImage(systemSymbolName:group.collapsed ? "chevron.right":"chevron.down",accessibilityDescription:group.collapsed ? "Expand \(group.title)":"Collapse \(group.title)")
        needsLayout=true
    }
    @objc private func checkGroup(_ sender:SwissCheckbox) {
        guard groups.indices.contains(sender.tag) else{return}
        let active=sender.state != .off
        groups[sender.tag].rows.forEach{$0.check.state=active ? .on:.off}
        refreshGroupChecks()
    }
    @objc private func checkField(_ sender:SwissCheckbox) {refreshGroupChecks()}
    @objc private func checkAllPressed(){setAll(.on)}
    @objc private func checkNonePressed(){setAll(.off)}
    @objc private func checkFilledPressed(){
        for group in groups {for row in group.rows {row.check.state=row.field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? .off:.on}}
        refreshGroupChecks()
    }
    private func setAll(_ state:NSControl.StateValue){include.values.forEach{$0.state=state};refreshGroupChecks()}
    private func currentValue()->AssetMetadata {
        var value=initial
        for group in groups {for row in group.rows {AssetMetadataSchema.assign(row.field.stringValue,for:row.item,to:&value)}}
        value.tidy();return value
    }
    private func applyPreset(_ index:Int){
        guard index>0,let name=preset.titleOfSelectedItem,let value=MetadataPresetStore.all()[name] else{return}
        for group in groups {for row in group.rows {row.field.stringValue=AssetMetadataSchema.value(row.item,in:value)}}
    }
    private func applyKeywordSet(_ index:Int){
        let sets=AssetMetadataRegistry.keywordSets().sorted{$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending}
        guard index>0,sets.indices.contains(index-1) else{return}
        fieldByID[10]?.stringValue=sets[index-1].terms.joined(separator:", ")
    }
    @objc private func addFieldPressed(){
        let alert=NSAlert();alert.messageText="Add Metadata Field"
        alert.informativeText="Give this asset a field for details that the standard list does not cover."
        let field=NSTextField(string:"");field.placeholderString="Field name";field.frame=NSRect(x:0,y:0,width:300,height:28)
        alert.accessoryView=field;alert.addButton(withTitle:"Add Field");alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        let name=field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else{return}
        let key=name.lowercased().replacingOccurrences(of:" ",with:"_")
        guard !groups.flatMap(\.rows).contains(where:{$0.item.key==key}) else{return}
        let item=AssetMetadataSchema.Item(AssetMetadataSchema.customID(key),key,name,"Custom Fields")
        append(item);selectedGroup=groups.count-1;needsLayout=true
        navigate(navButtons[selectedGroup])
    }
    @objc private func savePresetPressed(){
        let alert=NSAlert();alert.messageText="Save Metadata Preset"
        let field=NSTextField(string:"New Preset");field.frame=NSRect(x:0,y:0,width:280,height:28)
        alert.accessoryView=field;alert.addButton(withTitle:"Save");alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else{return}
        MetadataPresetStore.save(currentValue(),named:field.stringValue)
        preset.options(["Custom"]+MetadataPresetStore.all().keys.sorted())
    }
    @objc private func donePressed(){
        onSave?(currentValue(),Set(include.compactMap{$0.value.state == .on ? $0.key:nil}))
    }
    @objc private func cancelPressed(){onCancel?()}
}

enum AssetMetadataEditor {
    static func present(_ palette:Swatch, selectedCount:Int=1, over root:NSView, save:@escaping(AssetMetadata,Set<Int>)->Void){
        let form=AssetMetadataForm(palette:palette,selectedCount:selectedCount);let modal=SwissFocusModal(content:form,size:NSSize(width:1440,height:820))
        form.onSave={ value,fields in save(value,fields);modal.dismissOverlay() };form.onCancel={modal.dismissOverlay()};modal.present(over:root)
    }
}
