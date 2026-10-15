import Foundation
import AppKit
import UniformTypeIdentifiers

struct MetadataFilterColumn: Codable, Equatable {
    var field: String
    var values: [String] = []
    var hierarchical = true
}

struct MetadataFilterPreset: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var columns: [MetadataFilterColumn]
    var version = 1
}

struct MetadataFilterField: Equatable, Identifiable {
    let id: String
    let title: String
    let group: String
    var keys: [String]
    var hierarchical = false

    static let all: [MetadataFilterField] = [
        .init(id:"captureDate",title:"Capture Date",group:"File",keys:["EXIF.DateTimeOriginal","TIFF.DateTime","IPTC.DateCreated","XMP.CreateDate"],hierarchical:true),
        .init(id:"year",title:"Year",group:"File",keys:["EXIF.DateTimeOriginal","TIFF.DateTime","IPTC.DateCreated","XMP.CreateDate"],hierarchical:true),
        .init(id:"month",title:"Month",group:"File",keys:["EXIF.DateTimeOriginal","TIFF.DateTime","IPTC.DateCreated","XMP.CreateDate"],hierarchical:true),
        .init(id:"day",title:"Day",group:"File",keys:["EXIF.DateTimeOriginal","TIFF.DateTime","IPTC.DateCreated","XMP.CreateDate"],hierarchical:true),
        .init(id:"fileName",title:"File Name",group:"File",keys:["File.Name"]),
        .init(id:"fileType",title:"File Type",group:"File",keys:["File.Type"]),
        .init(id:"mediaType",title:"Media Type",group:"File",keys:["File.MediaType"]),
        .init(id:"folder",title:"Folder",group:"File",keys:["File.Folder"]),
        .init(id:"flag",title:"Flag",group:"Review",keys:["XMP.Marked","Colorgain.Flag"]),
        .init(id:"rating",title:"Rating",group:"Review",keys:["XMP.Rating","Colorgain.Rating"]),
        .init(id:"exported",title:"Exported Files",group:"Review",keys:["Colorgain.Exported"]),
        .init(id:"label",title:"Label",group:"Review",keys:["XMP.Label"]),
        .init(id:"keyword",title:"Keyword",group:"Review",keys:["IPTC.Keywords","XMP.Subject","XMP.Keywords"]),
        .init(id:"editState",title:"Edit State",group:"Review",keys:["Colorgain.EditState","XMP.History"]),
        .init(id:"camera",title:"Camera",group:"Camera",keys:["EXIF.Make","EXIF.Model","TIFF.Make","TIFF.Model"]),
        .init(id:"cameraSerial",title:"Camera Serial Number",group:"Camera",keys:["EXIF.BodySerialNumber","MakerNote.SerialNumber"]),
        .init(id:"lens",title:"Lens",group:"Camera",keys:["EXIF.LensModel","EXIF.LensMake","MakerNote.Lens"]),
        .init(id:"focalLength",title:"Focal Length",group:"Camera",keys:["EXIF.FocalLength"]),
        .init(id:"shutterSpeed",title:"Shutter Speed",group:"Camera",keys:["EXIF.ExposureTime","EXIF.ShutterSpeedValue"]),
        .init(id:"aperture",title:"Aperture",group:"Camera",keys:["EXIF.FNumber","EXIF.ApertureValue"]),
        .init(id:"iso",title:"ISO Speed",group:"Camera",keys:["EXIF.ISOSpeedRatings","EXIF.PhotographicSensitivity"]),
        .init(id:"flash",title:"Flash State",group:"Camera",keys:["EXIF.Flash"]),
        .init(id:"gps",title:"GPS Data",group:"Location",keys:["GPS.Latitude","GPS.Longitude","GPS.Altitude"]),
        .init(id:"mapLocation",title:"Map Location",group:"Location",keys:["XMP.Location","IPTC.Location"]),
        .init(id:"location",title:"Location",group:"Location",keys:["IPTC.SubLocation","XMP.Location"]),
        .init(id:"city",title:"City",group:"Location",keys:["IPTC.City","XMP.City"]),
        .init(id:"state",title:"State / Province",group:"Location",keys:["IPTC.State","XMP.State"]),
        .init(id:"country",title:"Country / Region",group:"Location",keys:["IPTC.CountryName","XMP.Country"]),
        .init(id:"creator",title:"Creator",group:"Rights",keys:["IPTC.Byline","XMP.Creator"]),
        .init(id:"copyright",title:"Copyright Status",group:"Rights",keys:["IPTC.CopyrightNotice","XMP.Rights"]),
        .init(id:"job",title:"Job / Title",group:"Rights",keys:["IPTC.ObjectName","XMP.Title"]),
        .init(id:"doi",title:"DOI",group:"Rights",keys:["DOI","XMP.Identifier","IPTC.Source"]),
        .init(id:"unknown",title:"Unknown",group:"Other",keys:[])
    ]

    func values(in item: TileGrid.Item) -> [String] {
        if id == "fileName" { return [item.title] }
        if id == "fileType" { return [URL(fileURLWithPath:item.title).pathExtension.uppercased()].filter{!$0.isEmpty} }
        if id == "mediaType" { return [UTType(filenameExtension:URL(fileURLWithPath:item.title).pathExtension)?.conforms(to:.rawImage) == true ? "RAW Image" : "Image"] }
        if id == "folder" { return item.imagePath.map{[URL(fileURLWithPath:$0).deletingLastPathComponent().lastPathComponent]} ?? [] }
        if ["captureDate","year","month","day"].contains(id),let date=item.captureDate {
            let c=Calendar.current.dateComponents([.year,.month,.day],from:date)
            switch id {case "year":return c.year.map{[String($0)]} ?? [];case "month":return c.month.map{[String(format:"%02d",$0)]} ?? [];case "day":return c.day.map{[String(format:"%02d",$0)]} ?? [];default:return [ISO8601DateFormatter().string(from:date)]}
        }
        let found=keys.flatMap{key in item.metadata[key].map{[$0]} ?? []}
        if !found.isEmpty{return Array(Set(found)).sorted{$0.localizedStandardCompare($1) == .orderedAscending}}
        let matched=item.metadata.filter{key,_ in keys.contains(where:{ candidate in key.localizedCaseInsensitiveContains(candidate) })}.map(\.value)
        if !matched.isEmpty{return Array(Set(matched)).sorted{$0.localizedStandardCompare($1) == .orderedAscending}}
        return item.metadata.isEmpty ? [] : []
    }
}

/// Portable presets live in .colcat; .coldata is a repairable per-catalogue index mirror.
struct MetadataFilterStore {
    let catalogueURL: URL
    var appData: AppDataStore = .current

    func read(catalogueID: UUID) throws -> [MetadataFilterPreset] {
        guard let file=CatalogueTree.catalogue(in:catalogueURL.deletingLastPathComponent()),file.id == catalogueID else {throw failure("The catalogue filter data could not be matched to this catalogue.")}
        let filters=file.metadataFilters ?? []
        return filters
    }

    func write(_ filters:[MetadataFilterPreset],catalogueID:UUID) throws {
        guard var file=CatalogueTree.catalogue(in:catalogueURL.deletingLastPathComponent()),file.id == catalogueID else{throw failure("The catalogue filter data could not be matched to this catalogue.")}
        file.metadataFilters=filters
        try Handler_File_Manager.shared.withTransaction(home: appData.root) {
            try Handler_File_Manager.shared.write(ColourFiles.encoder().encode(file), to: catalogueURL)
            try updateMirror(filters,catalogueID:catalogueID)
        }
    }

    private func updateMirror(_ filters:[MetadataFilterPreset],catalogueID:UUID) throws {
        let payload=try filters.map{try ColourFiles.encoder().encode($0).jsonObject}
        try appData.update { manifest in
            var byCatalogue=manifest["metadataFiltersByCatalogue"] as? [String:Any] ?? [:]
            byCatalogue[catalogueID.uuidString]=payload
            manifest["metadataFiltersByCatalogue"]=byCatalogue
        }
    }
}

private extension Data {
    var jsonObject: Any { (try? JSONSerialization.jsonObject(with:self,options:[.fragmentsAllowed])) ?? NSNull() }
}

private final class MetadataFilterColumnView:NSView {
    let fieldControl=WorkspaceMenuControl()
    var column=MetadataFilterColumn(field:"captureDate"){didSet{fieldControl.title=MetadataFilterField.all.first{$0.id==column.field}?.title ?? column.field;needsDisplay=true}}
    var options:[(String,Int)]=[] {didSet{offset=min(offset,max(0,options.count-1));needsDisplay=true}}
    var onField:(()->Void)?
    var onValuesChanged:((Set<String>)->Void)?
    private var offset=0
    private let rowHeight:CGFloat=24
    override var isFlipped:Bool{true}
    override init(frame:NSRect){super.init(frame:frame);fieldControl.onPress={[weak self] in self?.onField?()};addSubview(fieldControl)}
    required init?(coder:NSCoder){fatalError()}
    override func layout(){super.layout();fieldControl.frame=NSRect(x:0,y:0,width:bounds.width,height:28)}
    override func draw(_ dirtyRect:NSRect){
        hairline(x:0,y:29,width:bounds.width,Design.rule)
        let visible=max(0,Int((bounds.height-30)/rowHeight))
        for row in 0..<visible {
            let i=offset+row;guard options.indices.contains(i) else{break}
            let (value,count)=options[i],box=NSRect(x:0,y:30+CGFloat(row)*rowHeight,width:bounds.width,height:rowHeight)
            if column.values.contains(value){fill(box,Design.mist)}
            Design.attributed(value,.body,colour:Design.ink).draw(x:8,baseline:box.minY+17,width:max(0,box.width-48))
            Design.attributed(String(count),.caption,colour:Design.quiet).draw(right:box.maxX-8,baseline:box.minY+17)
            if row<visible-1 && i<options.count-1{hairline(x:8,y:box.maxY,width:box.width-16,Design.rule)}
        }
        if options.isEmpty{Design.attributed("No values yet",.body,colour:Design.quiet).draw(x:8,baseline:48)}
    }
    override func mouseDown(with event:NSEvent){
        let p=convert(event.locationInWindow,from:nil);guard p.y>=30 else{return}
        let row=Int((p.y-30)/rowHeight),index=offset+row;guard options.indices.contains(index) else{return}
        var selected=Set(column.values);let value=options[index].0
        if selected.contains(value){selected.remove(value)}else{selected.insert(value)}
        column.values=selected.sorted{$0.localizedStandardCompare($1) == .orderedAscending};onValuesChanged?(selected);needsDisplay=true
    }
    override func scrollWheel(with event:NSEvent){let step=event.scrollingDeltaY == 0 ? 1:Int(event.scrollingDeltaY.sign == .minus ? 3:-3);offset=max(0,min(max(0,options.count-1),offset+step));needsDisplay=true}
}

final class MetadataFilterPanel:NSView {
    private static weak var activeMenuOwner:MetadataFilterPanel?
    var onFiltered:(([TileGrid.Item])->Void)?
    private var records:[TileGrid.Item]=[]
    private var columns:[MetadataFilterColumn]=[
        .init(field:"captureDate",hierarchical:true),.init(field:"camera"),.init(field:"lens")
    ] {didSet{rebuildColumns();apply()}}
    private var columnViews:[MetadataFilterColumnView]=[]
    private var presets:[MetadataFilterPreset]=[]
    private var store:MetadataFilterStore?
    private var catalogueID:UUID?
    private var selectedPresetID:UUID?
    private var refreshRevision = 0
    private var valuesNeedRefresh = true
    private let presetControl=WorkspaceMenuControl()
    private let saveAction=WorkspaceTextActionControl("Save")
    private let editAction=WorkspaceTextActionControl("Edit")
    private let removeAction=WorkspaceTextActionControl("Remove")
    private let addColumnAction=WorkspaceTextActionControl("+ Column")
    private var dropped:SwissDropdown.MenuPanel?
    override var isFlipped:Bool{true}
    override init(frame:NSRect){
        super.init(frame:frame);wantsLayer=true;layer?.backgroundColor=Design.card.cgColor
        presetControl.title="Saved Filters";presetControl.onPress={[weak self] in self?.openPresets()}
        saveAction.onPress={[weak self] in self?.savePreset()};editAction.onPress={[weak self] in self?.editPreset()}
        removeAction.onPress={[weak self] in self?.removePreset()};addColumnAction.onPress={[weak self] in self?.addColumn()}
        [presetControl,saveAction,editAction,removeAction,addColumnAction].forEach(addSubview)
        rebuildColumns()
    }
    required init?(coder:NSCoder){fatalError()}
    func configure(records:[TileGrid.Item],store:MetadataFilterStore?,catalogueID:UUID){
        refreshRevision += 1 // Invalidate work for the previous page, even while hidden.
        self.records=records
        if self.catalogueID != catalogueID || self.store?.catalogueURL != store?.catalogueURL {
            self.catalogueID=catalogueID;self.store=store;selectedPresetID=nil
            do{presets=try store?.read(catalogueID:catalogueID) ?? []}catch{presets=[];FileIncidentCoordinator.report(error,at:store?.catalogueURL ?? URL(fileURLWithPath:"Catalogue.colcat"))}
            presetControl.title=presets.isEmpty ? "Saved Filters" : "Select Filter"
        }
        valuesNeedRefresh = true
        refreshIfNeeded()
    }
    func update(records:[TileGrid.Item]){refreshRevision += 1;self.records=records;valuesNeedRefresh=true;refreshIfNeeded()}
    func refreshIfNeeded(){guard !isHidden,valuesNeedRefresh else{return};refreshValues()}
    private func rebuildColumns(){
        columnViews.forEach{$0.removeFromSuperview()};columnViews=[]
        for index in columns.indices {
            let view=MetadataFilterColumnView(frame:.zero);view.column=columns[index]
            view.onField={[weak self,weak view] in guard let self,let view,let i=self.columnViews.firstIndex(of:view) else{return};self.openFields(for:i)}
            view.onValuesChanged={[weak self,weak view] values in guard let self,let view,let i=self.columnViews.firstIndex(of:view) else{return};self.columns[i]=view.column;self.refreshValues()}
            addSubview(view);columnViews.append(view)
        }
        needsLayout=true;needsDisplay=true;refreshValues()
    }
    private func addColumn(){guard columns.count<8 else{return};columns.append(MetadataFilterColumn(field:"fileType"));rebuildColumns()}
    private func openFields(for index:Int){
        guard window != nil else{return}
        let fields=MetadataFilterField.all.filter{$0.id != "unknown"}
        let menu=SwissDropdown.MenuPanel(items:fields.map{$0.title},chosen:fields.first{$0.id==columns[index].field}?.title ?? "",width:220){[weak self] choice in
            guard let self,fields.indices.contains(choice) else{return}
            self.columns[index].field=fields[choice].id;self.columns[index].values=[];self.columns[index].hierarchical=fields[choice].hierarchical
            self.columnViews[index].column=self.columns[index];self.refreshValues();self.closeMenu()
        }
        show(menu,from:columnViews[index].fieldControl)
    }
    private func openPresets(){
        guard window != nil else{return}
        let names=presets.map{$0.name};let menu=SwissDropdown.MenuPanel(items:names.isEmpty ? ["No Saved Filters"]:names,chosen:selectedPresetID.flatMap{id in presets.first{$0.id==id}?.name} ?? "",width:220){[weak self] index in
            guard let self,self.presets.indices.contains(index) else{return}
            let preset=self.presets[index];self.columns=preset.columns;self.selectedPresetID=preset.id;self.presetControl.title=preset.name;self.closeMenu();self.apply()
        }
        show(menu,from:presetControl)
    }
    private func show(_ menu:SwissDropdown.MenuPanel,from control:NSView){
        guard let window else{return}
        Self.activeMenuOwner?.closeMenu()
        closeMenu()
        Self.activeMenuOwner=self
        let rect=window.convertToScreen(control.convert(control.bounds,to:nil))
        menu.place(below:NSPoint(x:rect.minX,y:rect.minY-4))
        window.addChildWindow(menu,ordered:.above)
        dropped=menu
    }
    private func closeMenu(){
        if let dropped{dropped.parent?.removeChildWindow(dropped);dropped.orderOut(nil)}
        dropped=nil
        if Self.activeMenuOwner === self { Self.activeMenuOwner=nil }
    }
    private func savePreset(){
        let alert=NSAlert();alert.messageText="Save Metadata Filter";alert.informativeText="Name this filter to reuse it in Import and Library.";alert.addButton(withTitle:"Save");alert.addButton(withTitle:"Cancel")
        let field=NSTextField(string:"");field.frame=NSRect(x:0,y:0,width:260,height:24);alert.accessoryView=field
        guard alert.runModal() == .alertFirstButtonReturn else{return};let name=field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);guard !name.isEmpty else{return}
        let preset=MetadataFilterPreset(name:name,columns:columns);presets.append(preset);selectedPresetID=preset.id;presetControl.title=name;persist()
    }
    private func editPreset(){
        guard let id=selectedPresetID,let index=presets.firstIndex(where:{$0.id==id}) else{savePreset();return}
        presets[index].columns=columns;persist()
    }
    private func removePreset(){
        guard let id=selectedPresetID,let index=presets.firstIndex(where:{$0.id==id}) else{return}
        let alert=NSAlert();alert.messageText="Remove \(presets[index].name)?";alert.informativeText="This removes the saved filter from this catalogue.";alert.addButton(withTitle:"Remove");alert.addButton(withTitle:"Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else{return};presets.remove(at:index);selectedPresetID=nil;presetControl.title="Saved Filters";persist()
    }
    private func persist(){guard let store,let catalogueID else{return};do{try store.write(presets,catalogueID:catalogueID)}catch{FileIncidentCoordinator.report(error,at:store.catalogueURL)}}
    private func refreshValues(){
        refreshRevision += 1
        let revision=refreshRevision, snapshot=records, columnSnapshot=columns
        valuesNeedRefresh=false
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            var survivors=snapshot
            var results:[([(String,Int)],MetadataFilterColumn)]=[]
            for column in columnSnapshot {
                let field=MetadataFilterField.all.first{$0.id==column.field} ?? MetadataFilterField.all[0]
                var counts:[String:Int]=[:]
                for item in survivors {let values=field.values(in:item);for value in values.isEmpty ? ["Unknown"]:values{counts[value,default:0]+=1}}
                let options=counts.map{($0.key,$0.value)}.sorted{$0.0.localizedStandardCompare($1.0) == .orderedAscending}
                results.append((options,column))
                let chosen=Set(column.values)
                if !chosen.isEmpty {survivors=survivors.filter{item in let values=field.values(in:item);return !chosen.isDisjoint(with:values.isEmpty ? ["Unknown"]:values)}}
            }
            DispatchQueue.main.async { [weak self] in
                guard let self,revision==self.refreshRevision else{return}
                for index in results.indices where self.columnViews.indices.contains(index){self.columnViews[index].options=results[index].0;self.columnViews[index].column=results[index].1}
                self.onFiltered?(survivors)
            }
        }
    }
    private func apply(){valuesNeedRefresh=true;refreshIfNeeded()}
    override func layout(){super.layout();presetControl.frame=NSRect(x:8,y:0,width:160,height:30);saveAction.frame=NSRect(x:180,y:0,width:48,height:30);editAction.frame=NSRect(x:236,y:0,width:40,height:30);removeAction.frame=NSRect(x:284,y:0,width:64,height:30);addColumnAction.frame=NSRect(x:360,y:0,width:76,height:30)
        let top:CGFloat=36,gap:CGFloat=8,width=max(0,(bounds.width-CGFloat(max(0,columns.count-1))*gap)/CGFloat(max(1,columns.count)))
        for (index,view) in columnViews.enumerated(){view.frame=NSRect(x:CGFloat(index)*(width+gap),y:top,width:width,height:max(0,bounds.height-top))}
    }
}
