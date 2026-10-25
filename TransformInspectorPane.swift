import AppKit
import UniformTypeIdentifiers

/// Shared rail editor for a transform's parameters and its portable .coltra presets.
final class TransformInspectorPane: NSView, WorkspaceScrollableContent, InfoRailContent {
    override var isFlipped: Bool { true }
    var minimumContentHeight: CGFloat { contentBottom }
    var panelContentPadding: CGFloat { 16 }
    var onUpdate: ((PaletteTransformGraph.Stage) -> Void)?
    var onNotice: ((String) -> Void)?
    var onChooseSpectra: ((String, Int) -> [XYZ]?)?
    private let store: LibraryStore
    private let referenceOptions: [(String,[XYZ])]
    private var stage: PaletteTransformGraph.Stage
    private let colourCount: Int
    private let inputColours:[ColourDefinition]
    private let mergeOptions:[(UUID,String)]
    private var mergeMenu:AnalysisMenu?
    private var contentBottom: CGFloat = 540
    private let heading = Design.text("Transform", .heading)
    private let detail = Design.text("Edit settings at full precision.", .caption, wraps:true)
    private let status = Design.text("", .caption, wraps:true)
    private let presetsHeading = Design.text("Presets", .bodyStrong)
    private let nameField = SwissBlockTextField(frame:.zero)
    private let scopeMenu = AnalysisMenu("Save In", ["Workspace", "Workspace + Catalogue"])
    private let scopeHint = Design.text("Workspace stores this preset in the app. Workspace + Catalogue keeps matching copies and indexes in both places.",.caption,wraps:true)
    private let lockHint=Design.text("Checked colours stay fixed. Unchecked colours move to the new spacing.",.caption,wraps:true)
    private let mergeLabel=Design.text("Source Branch",.caption)
    private let save = SwissButton("Save Preset", .primary)
    private let importButton = SwissButton("Import .coltra", .quiet)
    private let sourceButton = SwissButton("Choose Source", .quiet)
    private let referenceMenu: AnalysisMenu
    private var controls: [(Field, NSView, NSTextField)] = []
    private var sliders:[Int:ResettingSlider]=[:]
    private var resets:[Int:PaletteAssetIcon]=[:]
    private var presetRows: [(TransformPresetIndexItem, TransformPresetStore.Scope, NSTextField, [PaletteAssetIcon])] = []
    private var curveEditor: TransformCurveEditor?
    private var lockChecks:[SwissCheckbox]=[]
    private var lockPreviews:[NSView]=[]
    private var editingItem: (TransformPresetIndexItem, TransformPresetStore.Scope)?

    private struct Field {
        let key: String
        let title: String
        let value: Double?
        let options: [String]?
        let range: ClosedRange<Double>?
        var isAmount: Bool { key == "$amount" }
        static func amount(_ title:String,_ range:ClosedRange<Double>) -> Field { Field(key:"$amount",title:title,value:nil,options:nil,range:range) }
        static func number(_ key:String,_ title:String,_ value:Double,_ range:ClosedRange<Double>) -> Field { Field(key:key,title:title,value:value,options:nil,range:range) }
        static func choice(_ key:String,_ title:String,_ options:[String]) -> Field { Field(key:key,title:title,value:nil,options:options,range:nil) }
    }

    init(stage: PaletteTransformGraph.Stage, colourCount: Int, store: LibraryStore, referenceOptions:[(String,[XYZ])] = [],inputColours:[ColourDefinition] = [],mergeOptions:[(UUID,String)] = []) {
        self.stage=stage;self.colourCount=colourCount;self.store=store;self.referenceOptions=referenceOptions;self.inputColours=inputColours;self.mergeOptions=mergeOptions
        self.referenceMenu=AnalysisMenu("Reference Palette",["Choose Reference Palette"]+referenceOptions.map(\.0))
        super.init(frame:.zero)
        heading.stringValue=stage.formula?.title ?? "Choose Transform"
        for view in [heading,detail,status,presetsHeading,nameField,scopeMenu,scopeHint,lockHint,mergeLabel,save,importButton,sourceButton,referenceMenu] { addSubview(view) }
        referenceMenu.changed={ [weak self] index in
            guard let self,index>0,self.referenceOptions.indices.contains(index-1) else{return}
            self.stage.settings.references=self.referenceOptions[index-1].1;self.publish()
        }
        nameField.placeholderAttributedString=Design.attributed("Preset Name",.body,colour:Design.quiet)
        styleMetadataInput(nameField)
        nameField.setAccessibilityLabel("Preset Name")
        scopeMenu.changed={ [weak self] _ in self?.needsLayout=true }
        save.target=self;save.action=#selector(savePressed)
        importButton.target=self;importButton.action=#selector(importPressed)
        sourceButton.target=self;sourceButton.action=#selector(sourcePressed)
        buildControls();reloadPresets()
    }
    required init?(coder:NSCoder){fatalError()}
    func escapeInfoRail() -> Bool { false }

    private var fields: [Field] {
        guard let formula=stage.formula else{return []}
        switch formula {
        case .hueRotate:return [.amount("Degrees",0...360)]
        case .lighter,.darker:return [.amount("Strength %",0...100)]
        case .greyscale:return []
        case .lightness,.chroma:return [.amount("Change %",(-100)...100)]
        case .neutralise:return [.amount("Strength %",0...100)]
        case .exposure:return [.amount("Stops",(-10)...10)]
        case .levels:return [.choice("channel","Channel",["Luminance","RGB","Red","Green","Blue"]),.choice("space","Working Space",["linearSRGB","acescg","displayP3","rec2020"]),.number("black","Input Black",0,0...1),.number("gamma","Midpoint Gamma",1,0.01...10),.number("white","Input White",1,0...4),.number("outputWhite","Output White",1,0...4)]
        case .curves:return [.choice("channel","Channel",["Luminance","RGB","Red","Green","Blue"]),.choice("space","Working Space",["linearSRGB","acescg","displayP3","rec2020"]),.number("black","Input Black",0,0...1),.number("white","Input White",1,0...4)]
        case .paletteSpacing:return [.number("low","Low Lightness",0,0...1),.number("high","High Lightness",1,0...1),.number("strength","Strength",1,0...1)]
        case .contrastTarget:return [.number("foreground","Foreground Index",0,0...Double(max(0,colourCount-1))),.number("background","Background Index",1,0...Double(max(0,colourCount-1))),.number("ratio","Target Ratio",4.5,1...21)]
        case .gamutFit:return [.choice("target","Destination",["srgb","displayP3","print"]),.choice("press","Print Condition",[PressProfiles.generic]+PressProfiles.all.map(\.name)),.choice("intent","Rendering Intent",["relative","perceptual","absolute"])]
        case .whiteBalance:return [.choice("sourceWhite","Source White",["A","D50","D55","D65","D75"]),.choice("targetWhite","Target White",["A","D50","D55","D65","D75"])]
        case .referenceMatch:return [.number("strength","Match Strength",1,0...1)]
        case .ascCDL:return [.choice("space","Working RGB",["srgb","displayP3","rec709","rec2020","acescg"]),.choice("style","CDL Style",["Fwd","FwdNoClamp"])]
            + (0..<3).flatMap { channel -> [Field] in
                let name=["Red","Green","Blue"][channel]
                return [.number("slope\(channel)","\(name) Slope",1,0...4),.number("offset\(channel)","\(name) Offset",0,(-2)...2),.number("power\(channel)","\(name) Power",1,0.001...4)]
            } + [.number("saturation","Saturation",1,0...4)]
        case .applyLUT:return [.choice("space","Input/Output RGB",["srgb","displayP3","rec709","rec2020","acescg"])]
        case .spectralRelight:return [.choice("illuminant","Illuminant",["D50","D65","A"])]
        case .merge:return [.choice("blend","Blend Method",["mix","add","subtract","screen","difference"]),.number("opacity","Strength",0.5,0...1)]
        }
    }

    private func buildControls() {
        controls.forEach { $0.1.removeFromSuperview();$0.2.removeFromSuperview() }
        sliders.values.forEach{$0.removeFromSuperview()};resets.values.forEach{$0.removeFromSuperview()}
        sliders=[:];resets=[:]
        controls=[];curveEditor?.removeFromSuperview();curveEditor=nil
        mergeMenu?.removeFromSuperview();mergeMenu=nil
        mergeLabel.isHidden=stage.formula != .merge
        lockChecks.forEach{$0.removeFromSuperview()};lockChecks=[]
        lockPreviews.forEach{$0.removeFromSuperview()};lockPreviews=[]
        for (index,field) in fields.enumerated() {
            let label=Design.text(field.title,.caption)
            let control:NSView
            if let options=field.options {
                let labels=field.key == "sourceWhite" || field.key == "targetWhite" ? options.map(Self.whiteLabel)
                    : field.key == "blend" ? options.map(Self.blendLabel):options
                let menu=AnalysisMenu(field.title,labels)
                let chosen=stage.settings.choice(field.key,options[0])
                menu.selectItem(withTitle:field.key == "blend" ? Self.blendLabel(chosen):Self.whiteLabel(chosen))
                menu.changed={ [weak self] selected in
                    guard let self,options.indices.contains(selected) else{return}
                    self.stage.settings.choices[field.key]=options[selected]
                    if self.stage.formula == .spectralRelight && field.key == "illuminant" {
                        self.stage.settings.references=self.onChooseSpectra?(options[selected],self.colourCount) ?? []
                    }
                    self.publish()
                }
                control=menu
            } else {
                let entry=SwissBlockTextField(frame:.zero)
                styleMetadataInput(entry)
                entry.stringValue=String(format:"%.3f",field.isAmount ? stage.amount : stage.settings.number(field.key,field.value ?? 0))
                entry.tag=index;entry.target=self;entry.action=#selector(fieldChanged(_:))
                entry.setAccessibilityLabel(field.title)
                control=entry
                if let range=field.range {
                    let value=field.isAmount ? stage.amount:stage.settings.number(field.key,field.value ?? 0)
                    let slider=ResettingSlider(value:value,minValue:range.lowerBound,maxValue:range.upperBound,target:self,action:#selector(sliderChanged(_:)))
                    slider.resting=field.isAmount ? (stage.formula?.defaultAmount ?? 0):(field.value ?? 0)
                    slider.tag=index;slider.isContinuous=true
                    slider.setAccessibilityLabel(field.title)
                    slider.toolTip="Drag to change \(field.title). Double-click to reset."
                    let reset=PaletteAssetIcon(frame:.zero)
                    reset.symbol="arrow.counterclockwise";reset.tag=index;reset.setAccessibilityLabel("Reset \(field.title)")
                    reset.toolTip="Reset \(field.title)";reset.run={ [weak self] in self?.resetField(index) }
                    addSubview(slider);addSubview(reset);sliders[index]=slider;resets[index]=reset
                }
            }
            addSubview(label);addSubview(control)
            controls.append((field,control,label))
        }
        if stage.formula == .curves {
            let editor=TransformCurveEditor(points:stage.settings.curve,histogramValues:inputColours.map{$0.master.y})
            editor.onChange={ [weak self] points in self?.stage.settings.curve=points;self?.publish() }
            addSubview(editor);curveEditor=editor
        }
        if stage.formula == .paletteSpacing {
            for index in 0..<min(64,colourCount) {
                let box=SwissCheckbox("Keep Colour \(index+1) Fixed")
                box.state=stage.settings.lockedIndices.contains(index) ? .on:.off
                box.tag=index;box.target=self;box.action=#selector(lockChanged(_:))
                addSubview(box);lockChecks.append(box)
                let preview=NSView(frame:.zero)
                preview.wantsLayer=true;preview.layer?.backgroundColor=(inputColours.indices.contains(index) ? inputColours[index].master.display:Design.card).cgColor
                preview.layer?.borderColor=Design.rule.cgColor;preview.layer?.borderWidth=1;preview.layer?.cornerRadius=3
                addSubview(preview);lockPreviews.append(preview)
            }
        }
        if stage.formula == .merge {
            let menu=AnalysisMenu("Source Branch",["Choose Branch"]+mergeOptions.map(\.1))
            if let selected=mergeOptions.firstIndex(where:{$0.0==stage.mergeSourceBranchID}) {menu.selectItem(at:selected+1)}
            menu.changed={ [weak self] index in
                guard let self else{return}
                self.stage.mergeSourceBranchID=index>0 && self.mergeOptions.indices.contains(index-1) ? self.mergeOptions[index-1].0:nil
                self.publish()
            }
            addSubview(menu);mergeMenu=menu
        }
        lockHint.isHidden=lockChecks.isEmpty
        switch stage.formula {
        case .referenceMatch:sourceButton.isHidden=true;referenceMenu.isHidden=false
        case .spectralRelight:sourceButton.title="Use Linked Measurements";sourceButton.isHidden=false
        case .applyLUT:sourceButton.title="Choose LUT / CLF File";sourceButton.isHidden=false
        default:sourceButton.isHidden=true;referenceMenu.isHidden=true
        }
        if stage.formula != .referenceMatch {referenceMenu.isHidden=true}
        status.stringValue=PaletteTransformEngine.availability(stage,colourCount:colourCount) ?? "Changes update the immediate palette and its dependent branches."
        needsLayout=true
    }
    private static func whiteLabel(_ value:String)->String {
        switch value {
        case "A":return "A · Tungsten Light (2856 K)"
        case "D50":return "D50 · Daylight (5000 K)"
        case "D55":return "D55 · Daylight (5500 K)"
        case "D65":return "D65 · Daylight (6500 K)"
        case "D75":return "D75 · Daylight (7500 K)"
        default:return value
        }
    }
    private static func blendLabel(_ value:String)->String {
        switch value {
        case "mix":return "Mix · Linear Light"
        case "add":return "Add · Linear Light"
        case "subtract":return "Subtractive · CMY Approximation"
        case "screen":return "Screen · Linear Light"
        case "difference":return "Difference · Linear Light"
        default:return value
        }
    }
    @objc private func fieldChanged(_ sender:NSTextField) {
        guard controls.indices.contains(sender.tag) else{return}
        let field=controls[sender.tag].0
        guard let value=Double(sender.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)),value.isFinite else {NSSound.beep();return}
        let bounded=field.range.map{min($0.upperBound,max($0.lowerBound,value))} ?? value
        setField(index:sender.tag,value:bounded)
    }
    @objc private func sliderChanged(_ sender:ResettingSlider) {setField(index:sender.tag,value:sender.doubleValue)}
    private func resetField(_ index:Int) {
        guard controls.indices.contains(index) else{return}
        let field=controls[index].0
        setField(index:index,value:field.isAmount ? (stage.formula?.defaultAmount ?? 0):(field.value ?? 0))
    }
    private func setField(index:Int,value:Double) {
        guard controls.indices.contains(index) else{return}
        let field=controls[index].0
        let bounded=field.range.map{min($0.upperBound,max($0.lowerBound,value))} ?? value
        if field.isAmount {stage.amount=bounded} else {stage.settings.numbers[field.key]=bounded}
        (controls[index].1 as? NSTextField)?.stringValue=String(format:"%.3f",bounded)
        sliders[index]?.doubleValue=bounded
        publish()
    }
    private func publish() {
        status.stringValue=PaletteTransformEngine.availability(stage,colourCount:colourCount) ?? "Changes update the immediate palette and its dependent branches."
        onUpdate?(stage)
    }
    @objc private func lockChanged(_ sender:SwissCheckbox) {
        if sender.state == .on {if !stage.settings.lockedIndices.contains(sender.tag){stage.settings.lockedIndices.append(sender.tag)}}
        else {stage.settings.lockedIndices.removeAll{$0==sender.tag}}
        stage.settings.lockedIndices.sort();publish()
    }

    override func layout() {
        super.layout()
        let width=max(220,bounds.width-32),x:CGFloat=16
        heading.frame=NSRect(x:x,y:20,width:width,height:28)
        detail.frame=NSRect(x:x,y:54,width:width,height:38)
        var y:CGFloat=108
        if let mergeMenu {
            mergeLabel.frame=NSRect(x:x,y:y,width:width,height:18)
            mergeMenu.frame=NSRect(x:x,y:y+22,width:width,height:30)
            y+=64
        }
        for (index,row) in controls.enumerated() {
            let (field,control,label)=row
            label.frame=NSRect(x:x,y:y,width:width,height:18)
            if field.options != nil {
                control.frame=NSRect(x:x,y:y+22,width:width,height:30)
                y+=64
            } else {
                sliders[index]?.frame=NSRect(x:x,y:y+24,width:width,height:24)
                control.frame=NSRect(x:x,y:y+54,width:max(90,width-38),height:30)
                resets[index]?.frame=NSRect(x:x+width-30,y:y+54,width:30,height:30)
                y+=96
            }
        }
        if let curveEditor {curveEditor.frame=NSRect(x:x,y:y,width:min(width,300),height:250);y+=266}
        if !lockChecks.isEmpty {
            lockHint.frame=NSRect(x:x,y:y,width:width,height:36);y+=42
            for (index,box) in lockChecks.enumerated() {
                box.frame=NSRect(x:x,y:y+CGFloat(index)*32,width:max(100,width-32),height:28)
                lockPreviews[index].frame=NSRect(x:x+width-24,y:y+CGFloat(index)*32+5,width:20,height:20)
            }
            y+=CGFloat(lockChecks.count)*32+12
        }
        if !referenceMenu.isHidden {referenceMenu.frame=NSRect(x:x,y:y,width:min(width,280),height:32);y+=48}
        if !sourceButton.isHidden {sourceButton.frame=NSRect(x:x,y:y,width:min(width,260),height:32);y+=48}
        status.frame=NSRect(x:x,y:y+8,width:width,height:42);y+=66
        presetsHeading.frame=NSRect(x:x,y:y,width:width,height:22);y+=34
        nameField.frame=NSRect(x:x,y:y,width:width,height:30);y+=40
        scopeMenu.frame=NSRect(x:x,y:y,width:width,height:30);y+=38
        scopeHint.frame=NSRect(x:x,y:y,width:width,height:48);y+=56
        save.frame=NSRect(x:x,y:y,width:136,height:30)
        importButton.frame=NSRect(x:x+144,y:y,width:140,height:30);y+=52
        for (_,_,label,actions) in presetRows {
            label.frame=NSRect(x:x,y:y+4,width:max(80,width-116),height:22)
            for (index,action) in actions.enumerated() {action.frame=NSRect(x:x+width-108+CGFloat(index)*28,y:y,width:24,height:28)}
            y+=42
        }
        contentBottom=y+16
    }

    private var selectedScope: TransformPresetStore.Scope { scopeMenu.indexOfSelectedItem == 1 ? .both(store) : .application }
    private func reloadPresets() {
        for (_,_,label,icons) in presetRows { label.removeFromSuperview();icons.forEach{$0.removeFromSuperview()} }
        presetRows=[]
        guard let formula=stage.formula else{return}
        do {
            let workspace=try TransformPresetStore.list(.application,kind:.transform,type:formula)
            let catalogue=try TransformPresetStore.list(.catalogue(store),kind:.transform,type:formula)
            let shared=Set(workspace.map(\.id)).intersection(catalogue.map(\.id))
            let rows:[(TransformPresetIndexItem,TransformPresetStore.Scope)]=workspace.map{($0,shared.contains($0.id) ? .both(store):.application)}
                + catalogue.filter{!shared.contains($0.id)}.map{($0,.catalogue(store))}
            for (item,scope) in rows {
                    let scopeName:String
                    switch scope {case .application:scopeName="Workspace";case .catalogue:scopeName="Catalogue";case .both:scopeName="Workspace + Catalogue"}
                    let label=Design.text("\(item.name) · \(scopeName)",.body)
                    let definitions:[(String,String,(()->Void))]=[
                        ("arrow.down.to.line","Apply \(item.name)",{[weak self] in self?.load(item,scope:scope)}),
                        ("pencil","Rename \(item.name)",{[weak self] in self?.beginRename(item,scope:scope)}),
                        ("square.and.arrow.up","Export \(item.name)",{[weak self] in self?.export(item,scope:scope)}),
                        ("trash","Remove \(item.name)",{[weak self] in self?.remove(item,scope:scope)})
                    ]
                    let icons=definitions.map { symbol,title,action -> PaletteAssetIcon in
                        let icon=PaletteAssetIcon(frame:.zero);icon.symbol=symbol;icon.setAccessibilityLabel(title);icon.toolTip=title;icon.run=action
                        addSubview(icon);return icon
                    }
                    addSubview(label);presetRows.append((item,scope,label,icons))
            }
        } catch {onNotice?(error.localizedDescription)}
        needsLayout=true;superview?.needsLayout=true
    }
    private func load(_ item:TransformPresetIndexItem,scope:TransformPresetStore.Scope) {
        do {
            let document=try TransformPresetStore.transform(item,scope:scope)
            guard document.transformType == stage.formula else {throw failure("This preset belongs to another transform.")}
            stage.amount=document.amount;stage.settings=document.settings
            if stage.formula == .spectralRelight {
                stage.settings.references=onChooseSpectra?(stage.settings.choice("illuminant","D50"),colourCount) ?? []
            }
            buildControls();publish()
        } catch {onNotice?(error.localizedDescription)}
    }
    private func beginRename(_ item:TransformPresetIndexItem,scope:TransformPresetStore.Scope) {
        editingItem=(item,scope)
        nameField.stringValue=item.name
        save.title="Rename Preset"
        window?.makeFirstResponder(nameField)
    }
    @objc private func savePressed() {
        let name=nameField.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,let formula=stage.formula else {NSSound.beep();return}
        do {
            if let (item,scope)=editingItem {try TransformPresetStore.rename(item,to:name,scope:scope)}
            else {
                var savedSettings=stage.settings
                if formula == .spectralRelight {savedSettings.references=[]}
                _ = try TransformPresetStore.save(ColtraDocument(transformType:formula,name:name,amount:stage.amount,settings:savedSettings),scope:selectedScope)
            }
            editingItem=nil;save.title="Save Preset";nameField.stringValue=""
            reloadPresets();onNotice?("Saved \(name)")
        } catch {onNotice?(error.localizedDescription)}
    }
    @objc private func importPressed() {
        let panel=NSOpenPanel();panel.title="Import Transform Preset";panel.canChooseFiles=true;panel.canChooseDirectories=false
        panel.allowedContentTypes=[UTType(filenameExtension:"coltra")].compactMap{$0}
        guard panel.runModal()==(.OK),let url=panel.url else{return}
        do {
            let item=try TransformPresetStore.importFile(url,scope:selectedScope)
            guard item.transformType==stage.formula else {onNotice?("Imported for \(item.transformType?.title ?? "another transform"); open its node to use it.");return}
            reloadPresets();onNotice?("Imported \(item.name)")
        } catch {onNotice?(error.localizedDescription)}
    }
    private func export(_ item:TransformPresetIndexItem,scope:TransformPresetStore.Scope) {
        let panel=NSSavePanel();panel.title="Export Transform Preset";panel.nameFieldStringValue=item.name+".coltra"
        guard panel.runModal()==(.OK),let url=panel.url else{return}
        do {try TransformPresetStore.exportedData(item,scope:scope).write(to:url,options:.atomic);onNotice?("Exported \(item.name)")}
        catch {onNotice?(error.localizedDescription)}
    }
    private func remove(_ item:TransformPresetIndexItem,scope:TransformPresetStore.Scope) {
        do {try TransformPresetStore.remove(item,scope:scope);reloadPresets();onNotice?("Removed \(item.name)")}
        catch {onNotice?(error.localizedDescription)}
    }
    @objc private func sourcePressed() {
        switch stage.formula {
        case .spectralRelight:
            let illuminant=stage.settings.choice("illuminant","D50")
            guard let references=onChooseSpectra?(illuminant,colourCount),references.count==colourCount else {onNotice?("Link measured reflectances for all \(colourCount) colours before relighting.");return}
            stage.settings.references=references;publish()
        case .applyLUT:
            let panel=NSOpenPanel();panel.title="Choose LUT or CLF";panel.canChooseFiles=true;panel.canChooseDirectories=false
            panel.allowedContentTypes=["cube","clf"].compactMap{UTType(filenameExtension:$0)}
            guard panel.runModal()==(.OK),let url=panel.url else{return}
            do {
                let data=try Data(contentsOf:url)
                _ = try PaletteLUT.read(data,name:url.lastPathComponent)
                stage.settings.sourceName=url.lastPathComponent;stage.settings.sourceDigest=Sharing.sha256(data);stage.settings.sourceData=data
                publish()
            } catch {onNotice?(error.localizedDescription)}
        default:break
        }
    }
}

/// Drag an intermediate point. Endpoints stay fixed; the interpolation remains deterministic.
private final class TransformCurveEditor:NSView {
    override var isFlipped:Bool{true}
    var onChange:(([TransformPoint])->Void)?
    private var points:[TransformPoint]
    private let histogramValues:[Double]
    private var active:Int?
    init(points:[TransformPoint],histogramValues:[Double]){self.points=points;self.histogramValues=histogramValues;super.init(frame:.zero);setAccessibilityLabel("Tone Curve Over The Palette Colour Histogram")}
    required init?(coder:NSCoder){fatalError()}
    private var plot:NSRect {bounds.insetBy(dx:16,dy:16)}
    override func draw(_ dirtyRect:NSRect) {
        Design.card.setFill();NSBezierPath(rect:bounds).fill()
        let r=plot
        Design.rule.setStroke();let edge=NSBezierPath(rect:r);edge.lineWidth=1;edge.stroke()
        if !histogramValues.isEmpty {
            let bins=64
            var density=[Double](repeating:0,count:bins)
            for sample in histogramValues where sample.isFinite {
                let centre=min(1,max(0,sample))*Double(bins-1)
                for i in 0..<bins {
                    let distance=(Double(i)-centre)/1.6
                    density[i]+=exp(-0.5*distance*distance)
                }
            }
            let peak=max(1e-9,density.max() ?? 0)
            Design.ink.withAlphaComponent(0.16).setFill()
            for i in 0..<bins {
                let height=r.height*CGFloat(density[i]/peak)*0.48
                NSRect(x:r.minX+CGFloat(i)*r.width/CGFloat(bins),y:r.maxY-height,width:r.width/CGFloat(bins)+0.25,height:height).fill()
            }
        }
        for fraction in [0.25,0.5,0.75] {
            let grid=NSBezierPath();grid.move(to:NSPoint(x:r.minX+r.width*fraction,y:r.minY));grid.line(to:NSPoint(x:r.minX+r.width*fraction,y:r.maxY))
            grid.move(to:NSPoint(x:r.minX,y:r.minY+r.height*fraction));grid.line(to:NSPoint(x:r.maxX,y:r.minY+r.height*fraction))
            Design.rule.withAlphaComponent(0.5).setStroke();grid.lineWidth=0.5;grid.stroke()
        }
        let ordered=([TransformPoint(x:0,y:0)]+points+[TransformPoint(x:1,y:1)]).sorted{$0.x<$1.x}
        let line=NSBezierPath()
        for step in 0...128 {
            let x=Double(step)/128
            let y=PaletteTransformEngine.curveValue(x,ordered)
            let screen=NSPoint(x:r.minX+CGFloat(x)*r.width,y:r.maxY-CGFloat(y)*r.height)
            if step==0 {line.move(to:screen)} else {line.line(to:screen)}
        }
        Design.ink.setStroke();line.lineWidth=2;line.stroke()
        for point in points {
            let rect=NSRect(x:r.minX+CGFloat(point.x)*r.width-5,y:r.maxY-CGFloat(point.y)*r.height-5,width:10,height:10)
            Design.card.setFill();NSBezierPath(ovalIn:rect).fill();Design.ink.setStroke();NSBezierPath(ovalIn:rect).stroke()
        }
    }
    override func mouseDown(with event:NSEvent) {
        let location=convert(event.locationInWindow,from:nil),r=plot
        let target=TransformPoint(x:min(1,max(0,Double((location.x-r.minX)/r.width))),y:min(1,max(0,Double((r.maxY-location.y)/r.height))))
        let nearest=points.enumerated().min{abs($0.element.x-target.x)+abs($0.element.y-target.y)<abs($1.element.x-target.x)+abs($1.element.y-target.y)}
        if let nearest,abs(nearest.element.x-target.x)<0.08,abs(nearest.element.y-target.y)<0.08 {active=nearest.offset}
        else if points.count<12 {points.append(target);active=points.count-1;onChange?(points);needsDisplay=true}
    }
    override func mouseDragged(with event:NSEvent) {
        guard let active else{return}
        let location=convert(event.locationInWindow,from:nil),r=plot
        points[active]=TransformPoint(x:min(0.999,max(0.001,Double((location.x-r.minX)/r.width))),y:min(1,max(0,Double((r.maxY-location.y)/r.height))))
        onChange?(points);needsDisplay=true
    }
    override func mouseUp(with event:NSEvent){active=nil}
}
