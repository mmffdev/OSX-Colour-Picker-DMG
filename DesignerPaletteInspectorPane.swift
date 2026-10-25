import AppKit

struct ImagePaletteDestination {
    let label:String
    let project:UUID?
    let bucket:UUID?
}

/// One scrollable RailInfo journey: saved settings, grade, extraction, then output.
final class ImagePaletteInspectorPane:NSView,WorkspaceScrollableContent,InfoRailContent {
    override var isFlipped:Bool {true}
    var minimumContentHeight:CGFloat {contentBottom}
    var panelContentPadding:CGFloat {16}
    func escapeInfoRail()->Bool {false}
    var onChange:((ImagePaletteRecipe)->Void)?
    var onSave:((ImagePaletteDestination)->Void)?,onRecipePick:((Int)->Void)?
    private(set) var recipe=ImagePaletteRecipe()
    var enteredPaletteName:String {nameField.stringValue}
    var selectedDestination:ImagePaletteDestination {destinations.indices.contains(destinationMenu.indexOfSelectedItem) ? destinations[destinationMenu.indexOfSelectedItem]:destinations[0]}
    private var contentBottom:CGFloat=1350
    private var hasImage=false
    private var destinations=[ImagePaletteDestination(label:"My Library",project:nil,bucket:nil)]

    private let resetAll=PaletteAssetIcon(frame:.zero)
    private let recipeLabel=Design.text("Saved Recipes",.bodyStrong)
    private let recipeMenu=AnalysisMenu("Saved Recipes",["Import Recipe…"])
    private let gradeHeading=Design.text("Image Grade",.bodyStrong)
    private let extractHeading=Design.text("Extract Colours",.bodyStrong)
    private let methodLabel=Design.text("Extraction Method",.caption)
    private let methodMenu=AnalysisMenu("Extraction Method",ImagePaletteRecipe.Method.allCases.map(\.rawValue))
    private let regionLabel=Design.text("Sample Region",.caption)
    private let regionMenu=AnalysisMenu("Sample Region",ImagePaletteRecipe.Region.allCases.map(\.rawValue))
    private let outputHeading=Design.text("Palette Output",.bodyStrong)
    private let nameLabel=Design.text("Palette Name",.caption)
    private let nameField=SwissBlockTextField(frame:.zero)
    private let destinationLabel=Design.text("Export To",.caption)
    private let destinationMenu=AnalysisMenu("Export Palette To",["My Library"])
    private let exportButton=SwissButton("Export Palette",.primary)

    private struct Control {
        let key:String,resting:Double
        let label:NSTextField,slider:ImagePaletteSlider,value:NSTextField,reset:PaletteAssetIcon
    }
    private var gradeControls=[Control](),extractControls=[Control]()
    private let gradeFields:[(String,String,ClosedRange<Double>,Double)]=[
        ("exposure","Exposure · Stops",(-4)...4,0),
        ("contrast","Contrast",0.2...2.5,1),
        ("saturation","Saturation",0...2.5,1),
        ("highlights","Highlights",0...2,1),
        ("shadows","Shadows",(-1)...1,0),
        ("warmth","Temperature",(-2)...2,0),
        ("tint","Tint",(-2)...2,0)
    ]
    private let extractFields:[(String,String,ClosedRange<Double>,Double)]=[
        ("minimumColours","Minimum Colours",1...32,5),
        ("maximumColours","Maximum Colours",2...32,12),
        ("targetColours","Target Colours",1...32,8),
        ("sampleSide","Sample Detail",128...1024,480),
        ("minimumDifference","Minimum ΔE",0...40,8),
        ("minimumShare","Minimum Area %",0...5,0.1)
    ]
    override init(frame:NSRect){
        super.init(frame:frame)
        for view in [resetAll,recipeLabel,recipeMenu,
                     gradeHeading,extractHeading,methodLabel,methodMenu,regionLabel,regionMenu,
                     outputHeading,nameLabel,nameField,destinationLabel,destinationMenu,exportButton] as [NSView] {addSubview(view)}
        resetAll.symbol="arrow.counterclockwise"
        resetAll.setAccessibilityLabel("Reset All Image Palette Settings")
        resetAll.toolTip="Reset all grading and extraction settings"
        resetAll.run={[weak self] in self?.resetAllSettings()}
        exportButton.target=self;exportButton.action=#selector(exportPressed);exportButton.isEnabled=false
        recipeMenu.changed={[weak self] index in self?.onRecipePick?(index)}
        methodMenu.changed={[weak self] index in
            guard let self,ImagePaletteRecipe.Method.allCases.indices.contains(index) else{return}
            self.recipe.method=ImagePaletteRecipe.Method.allCases[index];self.publish()
        }
        regionMenu.changed={[weak self] index in
            guard let self,ImagePaletteRecipe.Region.allCases.indices.contains(index) else{return}
            self.recipe.region=ImagePaletteRecipe.Region.allCases[index];self.publish()
        }
        styleMetadataInput(nameField);nameField.setAccessibilityLabel("Palette Name")
        nameField.target=self;nameField.action=#selector(nameChanged)
        for (index,field) in gradeFields.enumerated(){gradeControls.append(makeControl(field,tag:index))}
        for (index,field) in extractFields.enumerated(){extractControls.append(makeControl(field,tag:index+gradeFields.count))}
    }
    required init?(coder:NSCoder){fatalError()}

    private func makeControl(_ field:(String,String,ClosedRange<Double>,Double),tag:Int)->Control {
        let label=Design.text(field.1,.caption)
        let slider=ImagePaletteSlider(value:value(for:field.0),minValue:field.2.lowerBound,maxValue:field.2.upperBound,target:self,action:#selector(sliderChanged(_:)))
        slider.cell=ImagePaletteSliderCell()
        // NSSlider forwards its target/action through the cell; replacing the
        // default cell clears that wiring even though the thumb still moves.
        slider.target=self;slider.action=#selector(sliderChanged(_:))
        slider.minValue=field.2.lowerBound;slider.maxValue=field.2.upperBound;slider.doubleValue=value(for:field.0)
        slider.resting=field.3;slider.tag=tag;slider.isContinuous=true
        slider.setAccessibilityLabel(field.1);slider.toolTip="Double-click to reset \(field.1)"
        let value=Design.text(formatted(field.0,value(for:field.0)),.bodyStrong)
        let reset=PaletteAssetIcon(frame:.zero);reset.symbol="arrow.counterclockwise"
        reset.setAccessibilityLabel("Reset \(field.1)");reset.toolTip="Reset \(field.1)"
        reset.run={[weak self] in self?.reset(tag)}
        for view in [label,slider,value,reset] as [NSView] {addSubview(view)}
        return Control(key:field.0,resting:field.3,label:label,slider:slider,value:value,reset:reset)
    }
    func update(_ recipe:ImagePaletteRecipe,hasOutput:Bool,hasImage:Bool) {
        self.recipe=recipe
        self.hasImage=hasImage
        if window?.firstResponder !== nameField.currentEditor() {nameField.stringValue=recipe.paletteName}
        methodMenu.selectItem(at:ImagePaletteRecipe.Method.allCases.firstIndex(of:recipe.method) ?? 0)
        regionMenu.selectItem(at:ImagePaletteRecipe.Region.allCases.firstIndex(of:recipe.region) ?? 0)
        for control in gradeControls+extractControls {
            let number=value(for:control.key)
            control.slider.doubleValue=number
            control.value.stringValue=formatted(control.key,number)
        }
        for control in gradeControls+extractControls {
            for view in [control.label,control.slider,control.value,control.reset] as [NSView] {view.alphaValue=hasImage ? 1:0.45}
            control.slider.isEnabled=hasImage;control.reset.isEnabled=hasImage
        }
        for menu in [recipeMenu,methodMenu,regionMenu,destinationMenu] {menu.isEnabled=hasImage;menu.alphaValue=hasImage ? 1:0.45}
        for view in [methodLabel,regionLabel,nameLabel,destinationLabel] {view.alphaValue=hasImage ? 1:0.45}
        resetAll.isEnabled=hasImage;resetAll.alphaValue=hasImage ? 1:0.45
        nameField.isEnabled=hasImage;nameField.alphaValue=hasImage ? 1:0.45
        exportButton.isEnabled=hasImage && hasOutput
    }
    func setDestinations(_ values:[ImagePaletteDestination]) {
        let selected=destinationMenu.indexOfSelectedItem
        destinations=values
        destinationMenu.options(values.map(\.label),selected:min(selected,values.count-1))
    }
    func setSavedRecipes(_ names:[String]) {
        recipeMenu.options(["Choose Recipe"]+names+["Import Recipe…"])
    }
    @objc private func exportPressed(){
        guard destinations.indices.contains(destinationMenu.indexOfSelectedItem) else{return}
        onSave?(destinations[destinationMenu.indexOfSelectedItem])
    }
    @objc private func nameChanged(){recipe.paletteName=nameField.stringValue;publish()}
    @objc private func sliderChanged(_ slider:ResettingSlider){
        let all=gradeControls+extractControls
        guard all.indices.contains(slider.tag) else{return}
        set(all[slider.tag].key,slider.doubleValue)
        for row in all {
            let number=value(for:row.key)
            row.slider.doubleValue=number;row.value.stringValue=formatted(row.key,number)
        }
        publish()
    }
    private func reset(_ index:Int){
        let all=gradeControls+extractControls
        guard all.indices.contains(index) else{return}
        all[index].slider.doubleValue=all[index].resting
        sliderChanged(all[index].slider)
    }
    private func resetAllSettings(){
        let old=recipe
        recipe=ImagePaletteRecipe()
        recipe.sourcePath=old.sourcePath;recipe.sourceName=old.sourceName;recipe.paletteName=nameField.stringValue
        update(recipe,hasOutput:exportButton.isEnabled,hasImage:hasImage);publish()
    }
    private func publish(){onChange?(recipe)}
    private func set(_ key:String,_ value:Double){
        switch key {
        case "exposure":recipe.exposure=value
        case "contrast":recipe.contrast=value
        case "saturation":recipe.saturation=value
        case "highlights":recipe.highlights=value
        case "shadows":recipe.shadows=value
        case "warmth":recipe.warmth=value
        case "tint":recipe.tint=value
        case "minimumColours":recipe.minimumColours=Int(value.rounded())
        case "maximumColours":recipe.maximumColours=Int(value.rounded())
        case "targetColours":recipe.targetColours=Int(value.rounded())
        case "sampleSide":recipe.sampleSide=Int(value.rounded())
        case "minimumDifference":recipe.minimumDifference=value
        case "minimumShare":recipe.minimumShare=value/100
        default:break
        }
        recipe.maximumColours=max(2,recipe.maximumColours)
        recipe.minimumColours=min(recipe.minimumColours,recipe.maximumColours)
        recipe.targetColours=max(recipe.minimumColours,min(recipe.maximumColours,recipe.targetColours))
    }
    private func value(for key:String)->Double {
        switch key {
        case "exposure":return recipe.exposure
        case "contrast":return recipe.contrast
        case "saturation":return recipe.saturation
        case "highlights":return recipe.highlights
        case "shadows":return recipe.shadows
        case "warmth":return recipe.warmth
        case "tint":return recipe.tint
        case "minimumColours":return Double(recipe.minimumColours)
        case "maximumColours":return Double(recipe.maximumColours)
        case "targetColours":return Double(recipe.targetColours)
        case "sampleSide":return Double(recipe.sampleSide)
        case "minimumDifference":return recipe.minimumDifference
        case "minimumShare":return recipe.minimumShare*100
        default:return 0
        }
    }
    private func formatted(_ key:String,_ value:Double)->String {
        if ["minimumColours","maximumColours","targetColours","sampleSide"].contains(key){return String(Int(value.rounded()))}
        return String(format:"%.2f",value)
    }
    override func layout(){
        super.layout()
        let width=max(250,bounds.width),inset:CGFloat=16,controlWidth=width-2*inset
        resetAll.frame=NSRect(x:width-inset-28,y:16,width:28,height:28)
        var y:CGFloat=16
        func heading(_ view:NSView){view.frame=NSRect(x:inset,y:y,width:controlWidth,height:24);y+=32}
        func divider(){rules.append(y+12);y+=32}
        rules=[]
        recipeLabel.frame=NSRect(x:inset,y:y,width:controlWidth-36,height:24);y+=32
        recipeMenu.frame=NSRect(x:inset,y:y,width:controlWidth,height:32);y+=36
        divider();heading(gradeHeading)
        func rows(_ list:[Control]) {
            for control in list {
                control.label.frame=NSRect(x:inset,y:y,width:controlWidth-72,height:18)
                control.value.frame=NSRect(x:width-inset-62,y:y,width:62,height:18)
                control.value.alignment = .right
                control.slider.frame=NSRect(x:inset,y:y+18,width:controlWidth-36,height:20)
                control.reset.frame=NSRect(x:width-inset-28,y:y+17,width:24,height:24)
                y+=48
            }
        }
        rows(gradeControls)
        divider();heading(extractHeading)
        methodLabel.frame=NSRect(x:inset,y:y,width:controlWidth,height:18);y+=22
        methodMenu.frame=NSRect(x:inset,y:y,width:controlWidth,height:32);y+=44
        regionLabel.frame=NSRect(x:inset,y:y,width:controlWidth,height:18);y+=22
        regionMenu.frame=NSRect(x:inset,y:y,width:controlWidth,height:32);y+=48
        rows(extractControls)
        divider();heading(outputHeading)
        nameLabel.frame=NSRect(x:inset,y:y,width:controlWidth,height:18);y+=22
        nameField.frame=NSRect(x:inset,y:y,width:controlWidth,height:32);y+=44
        destinationLabel.frame=NSRect(x:inset,y:y,width:controlWidth,height:18);y+=22
        destinationMenu.frame=NSRect(x:inset,y:y,width:controlWidth,height:32);y+=48
        exportButton.frame=NSRect(x:inset,y:y,width:170,height:32);y+=48
        contentBottom=y+16
        if frame.height < contentBottom {setFrameSize(NSSize(width:frame.width,height:contentBottom))}
        needsDisplay=true
    }
    private var rules=[CGFloat]()
    override func draw(_ dirtyRect:NSRect){
        super.draw(dirtyRect)
        for y in rules {hairline(x:16,y:y,width:max(0,bounds.width-32),Design.rule)}
    }
}

/// Flat, high-contrast ink slider for both light and dark workspace themes.
final class ImagePaletteSliderCell:NSSliderCell {
    override func drawBar(inside rect:NSRect,flipped:Bool) {
        let track=NSRect(x:rect.minX,y:rect.midY-2,width:rect.width,height:4)
        Design.mix(Design.card,Design.ink,0.58).withAlphaComponent(isEnabled ? 1:0.45).setFill()
        NSBezierPath(roundedRect:track,xRadius:2,yRadius:2).fill()
        let resting=(controlView as? ImagePaletteSlider)?.resting ?? doubleValue
        let span=max(0.0001,maxValue-minValue)
        let start=max(0,min(1,(resting-minValue)/span))
        let end=max(0,min(1,(doubleValue-minValue)/span))
        if abs(end-start) > 0.0001 {
            let delta=NSRect(x:track.minX+track.width*min(start,end),y:track.minY,width:track.width*abs(end-start),height:track.height)
            Design.houseYellow.withAlphaComponent(isEnabled ? 1:0.45).setFill()
            NSBezierPath(roundedRect:delta,xRadius:2,yRadius:2).fill()
        }
    }
    override func drawKnob(_ knobRect:NSRect) {
        let slider=controlView as? ImagePaletteSlider
        let changed=abs(doubleValue-(slider?.resting ?? doubleValue)) > 0.0001
        let active=slider?.knobHovered == true || slider?.knobDragging == true
        let centre=NSPoint(x:knobRect.midX,y:knobRect.midY)
        let outer=NSBezierPath(ovalIn:NSRect(x:centre.x-8,y:centre.y-8,width:16,height:16))
        (changed ? Design.houseYellow:Design.card).setFill();outer.fill()
        WorkspaceBranchTree.accent.setStroke();outer.lineWidth=1;outer.stroke()
        let inner=NSBezierPath(ovalIn:NSRect(x:centre.x-4.5,y:centre.y-4.5,width:9,height:9))
        (active ? WorkspaceBranchTree.accent:Design.card).setFill();inner.fill()
        WorkspaceBranchTree.accent.setStroke();inner.lineWidth=1;inner.stroke()
    }
}

final class ImagePaletteSlider:ResettingSlider {
    private(set) var knobHovered=false
    private(set) var knobDragging=false
    private var hoverArea:NSTrackingArea?
    override func updateTrackingAreas(){
        super.updateTrackingAreas()
        if let hoverArea {removeTrackingArea(hoverArea)}
        let area=NSTrackingArea(rect:.zero,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self)
        addTrackingArea(area);hoverArea=area
    }
    private func updateKnobHover(_ event:NSEvent){
        let point=convert(event.locationInWindow,from:nil)
        let hovered=(cell as? NSSliderCell)?.knobRect(flipped:isFlipped).insetBy(dx:-4,dy:-4).contains(point) == true
        if hovered != knobHovered {knobHovered=hovered;needsDisplay=true}
    }
    override func mouseEntered(with event:NSEvent){updateKnobHover(event)}
    override func mouseMoved(with event:NSEvent){updateKnobHover(event)}
    override func mouseExited(with event:NSEvent){knobHovered=false;needsDisplay=true}
    override func mouseDown(with event:NSEvent){
        knobDragging=true;needsDisplay=true
        super.mouseDown(with:event)
        knobDragging=false
        updateKnobHover(event)
        needsDisplay=true
    }
}
