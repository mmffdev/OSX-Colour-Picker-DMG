import AppKit
import UniformTypeIdentifiers

/// RailInfo's reusable diagram library. A .colnode embeds the whole flow and every stage setting.
final class DiagramPresetPane:NSView, WorkspaceScrollableContent, InfoRailContent {
    override var isFlipped:Bool{true}
    var minimumContentHeight:CGFloat{bottom}
    var panelContentPadding:CGFloat{16}
    var onApply:((ColnodeDocument)->Void)?
    var onNotice:((String)->Void)?
    private let store:LibraryStore
    var graph:PaletteTransformGraph
    private var bottom:CGFloat=400
    private let heading=Design.text("Diagram Presets",.heading)
    private let explanation=Design.text("Save this branch and transform flow. Apply it to another palette with its own colours.",.body,wraps:true)
    private let nameField=SwissBlockTextField(frame:.zero)
    private let scopeMenu=AnalysisMenu("Save In",["Workspace","Workspace + Catalogue"])
    private let scopeHint=Design.text("Workspace stores this diagram in the app. Workspace + Catalogue keeps matching copies and indexes in both places.",.caption,wraps:true)
    private let save=SwissButton("Save Diagram",.primary)
    private let importButton=SwissButton("Import .colnode",.quiet)
    private let libraryTitle=Design.text("Saved Diagrams",.bodyStrong)
    private var rows:[(TransformPresetIndexItem,TransformPresetStore.Scope,NSTextField,[PaletteAssetIcon])]=[]
    private var editingItem:(TransformPresetIndexItem,TransformPresetStore.Scope)?
    init(graph:PaletteTransformGraph,store:LibraryStore) {
        self.graph=graph;self.store=store
        super.init(frame:.zero)
        for view in [heading,explanation,nameField,scopeMenu,scopeHint,save,importButton,libraryTitle]{addSubview(view)}
        nameField.placeholderAttributedString=Design.attributed("Diagram Name",.body,colour:Design.quiet)
        styleMetadataInput(nameField);nameField.setAccessibilityLabel("Diagram Name")
        save.target=self;save.action=#selector(savePressed)
        importButton.target=self;importButton.action=#selector(importPressed)
        reload()
    }
    required init?(coder:NSCoder){fatalError()}
    func escapeInfoRail()->Bool{false}
    private var selectedScope:TransformPresetStore.Scope{scopeMenu.indexOfSelectedItem==1 ? .both(store):.application}
    override func layout(){
        super.layout()
        let x:CGFloat=16,w=max(220,bounds.width-32)
        heading.frame=NSRect(x:x,y:20,width:w,height:28)
        explanation.frame=NSRect(x:x,y:56,width:w,height:70)
        nameField.frame=NSRect(x:x,y:142,width:w,height:30)
        scopeMenu.frame=NSRect(x:x,y:184,width:w,height:30)
        scopeHint.frame=NSRect(x:x,y:222,width:w,height:48)
        save.frame=NSRect(x:x,y:282,width:136,height:30)
        importButton.frame=NSRect(x:x+144,y:282,width:140,height:30)
        libraryTitle.frame=NSRect(x:x,y:342,width:w,height:22)
        var y:CGFloat=378
        for (_,_,label,icons) in rows {
            label.frame=NSRect(x:x,y:y+4,width:max(80,w-116),height:22)
            for (index,icon) in icons.enumerated(){icon.frame=NSRect(x:x+w-108+CGFloat(index)*28,y:y,width:24,height:28)}
            y+=42
        }
        bottom=y+16
    }
    private func reload(){
        for (_,_,label,icons) in rows {label.removeFromSuperview();icons.forEach{$0.removeFromSuperview()}}
        rows=[]
        do {
            let workspace=try TransformPresetStore.list(.application,kind:.diagram)
            let catalogue=try TransformPresetStore.list(.catalogue(store),kind:.diagram)
            let shared=Set(workspace.map(\.id)).intersection(catalogue.map(\.id))
            let entries:[(TransformPresetIndexItem,TransformPresetStore.Scope)]=workspace.map{($0,shared.contains($0.id) ? .both(store):.application)}
                + catalogue.filter{!shared.contains($0.id)}.map{($0,.catalogue(store))}
            for (item,scope) in entries {
                let scopeName:String
                switch scope {case .application:scopeName="Workspace";case .catalogue:scopeName="Catalogue";case .both:scopeName="Workspace + Catalogue"}
                let label=Design.text("\(item.name) · \(scopeName)",.body)
                let actions:[(String,String,()->Void)]=[
                    ("arrow.down.to.line","Apply \(item.name)",{[weak self] in self?.apply(item,scope:scope)}),
                    ("pencil","Rename \(item.name)",{[weak self] in self?.beginRename(item,scope:scope)}),
                    ("square.and.arrow.up","Export \(item.name)",{[weak self] in self?.export(item,scope:scope)}),
                    ("trash","Remove \(item.name)",{[weak self] in self?.remove(item,scope:scope)})
                ]
                let icons=actions.map{symbol,title,action -> PaletteAssetIcon in
                    let icon=PaletteAssetIcon(frame:.zero);icon.symbol=symbol;icon.toolTip=title;icon.setAccessibilityLabel(title);icon.run=action;addSubview(icon);return icon
                }
                addSubview(label);rows.append((item,scope,label,icons))
            }
        } catch {onNotice?(error.localizedDescription)}
        needsLayout=true;superview?.needsLayout=true
    }
    private func apply(_ item:TransformPresetIndexItem,scope:TransformPresetStore.Scope){
        do {onApply?(try TransformPresetStore.diagram(item,scope:scope))}
        catch {onNotice?(error.localizedDescription)}
    }
    private func beginRename(_ item:TransformPresetIndexItem,scope:TransformPresetStore.Scope){
        editingItem=(item,scope);nameField.stringValue=item.name;save.title="Rename Diagram";window?.makeFirstResponder(nameField)
    }
    @objc private func savePressed(){
        let name=nameField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty else{NSSound.beep();return}
        do {
            if let (item,scope)=editingItem {try TransformPresetStore.rename(item,to:name,scope:scope)}
            else {_ = try TransformPresetStore.save(ColnodeDocument(name:name,graph:graph),scope:selectedScope)}
            editingItem=nil;nameField.stringValue="";save.title="Save Diagram";reload();onNotice?("Saved \(name)")
        } catch {onNotice?(error.localizedDescription)}
    }
    @objc private func importPressed(){
        let panel=NSOpenPanel();panel.title="Import Diagram";panel.canChooseFiles=true;panel.canChooseDirectories=false
        panel.allowedContentTypes=[UTType(filenameExtension:"colnode")].compactMap{$0}
        guard panel.runModal()==(.OK),let url=panel.url else{return}
        do {let item=try TransformPresetStore.importFile(url,scope:selectedScope);reload();onNotice?("Imported \(item.name)")}
        catch {onNotice?(error.localizedDescription)}
    }
    private func export(_ item:TransformPresetIndexItem,scope:TransformPresetStore.Scope){
        let panel=NSSavePanel();panel.title="Export Diagram";panel.nameFieldStringValue=item.name+".colnode"
        guard panel.runModal()==(.OK),let url=panel.url else{return}
        do {try TransformPresetStore.exportedData(item,scope:scope).write(to:url,options:.atomic);onNotice?("Exported \(item.name)")}
        catch {onNotice?(error.localizedDescription)}
    }
    private func remove(_ item:TransformPresetIndexItem,scope:TransformPresetStore.Scope){
        do {try TransformPresetStore.remove(item,scope:scope);reload();onNotice?("Removed \(item.name)")}
        catch {onNotice?(error.localizedDescription)}
    }
}
