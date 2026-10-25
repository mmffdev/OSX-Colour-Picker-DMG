import AppKit

/// Technical facts are selectable text and resize with the viewport, including
/// long copyright notices and multilingual coverage lists.
private final class FontFactsView:NSView {
    private struct Row {let label:NSTextField;let value:NSTextField}
    private struct Group {let heading:NSTextField;let rows:[Row]}
    private let previewHeading=FontFactsView.field("Character Preview",size:15,strong:true)
    private let preview=FontFactsView.field("",size:30,strong:false)
    private var groups:[Group]=[]
    override var isFlipped:Bool {true}
    override init(frame:NSRect){super.init(frame:frame);addSubview(previewHeading);addSubview(preview)}
    required init?(coder:NSCoder){fatalError()}
    private static func field(_ value:String,size:CGFloat,strong:Bool)->NSTextField {
        let field=NSTextField(labelWithString:value)
        field.font=strong ? Design.Text.header.font():Design.Text.body.font()
        if size == 30 {field.font=NSFont.systemFont(ofSize:size)}
        field.textColor=Design.ink
        field.isSelectable=true;field.lineBreakMode = .byWordWrapping
        field.usesSingleLineMode=false;field.maximumNumberOfLines=0
        return field
    }
    func configure(_ facts:FontFaceFacts?) {
        for group in groups {
            group.heading.removeFromSuperview()
            for row in group.rows {row.label.removeFromSuperview();row.value.removeFromSuperview()}
        }
        groups=[]
        preview.stringValue=facts?.preview ?? "No character preview available"
        preview.font=facts?.previewFont.withSize(30) ?? Design.Text.body.font()
        for section in facts?.sections ?? [] {
            let heading=Self.field(section.title,size:15,strong:true);addSubview(heading)
            let rows=(section.rows.isEmpty ? [("","Not reported by this font")]:section.rows).map { label,value -> Row in
                let labelField=Self.field(label,size:13,strong:true)
                let valueField=Self.field(value,size:13,strong:false)
                if !label.isEmpty {addSubview(labelField)}
                addSubview(valueField)
                return Row(label:labelField,value:valueField)
            }
            groups.append(Group(heading:heading,rows:rows))
        }
        needsLayout=true
    }
    private func textHeight(_ field:NSTextField,width:CGFloat)->CGFloat {
        let attributes:[NSAttributedString.Key:Any]=[.font:field.font ?? Design.Text.body.font()]
        return max(20,ceil((field.stringValue as NSString).boundingRect(with:NSSize(width:max(1,width),height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attributes).height)+3)
    }
    private func place(_ group:Group,x:CGFloat,y:CGFloat,width:CGFloat)->CGFloat {
        var cursor=y
        group.heading.frame=NSRect(x:x,y:cursor,width:width,height:24);cursor += 36
        for row in group.rows {
            if !row.label.stringValue.isEmpty {
                row.label.frame=NSRect(x:x,y:cursor,width:width,height:20);cursor += 22
            }
            let h=textHeight(row.value,width:width)
            row.value.frame=NSRect(x:x,y:cursor,width:width,height:h);cursor += h+12
        }
        return cursor+20
    }
    @discardableResult private func arrange(width:CGFloat,apply:Bool)->CGFloat {
        let content=min(1120,max(0,width)),gap:CGFloat=32
        let previewWidth=max(1,content)
        let previewHeight=textHeight(preview,width:previewWidth)
        if apply {
            previewHeading.frame=NSRect(x:0,y:0,width:content,height:24)
            preview.frame=NSRect(x:0,y:32,width:previewWidth,height:previewHeight)
        }
        let start=32+previewHeight+48
        guard !groups.isEmpty else{return start}
        if content < 720 {
            var y=start
            for group in groups {
                if apply {y=place(group,x:0,y:y,width:content)}
                else {y += groupHeight(group,width:content)}
            }
            return y
        }
        let column=(content-gap)/2
        var left=start,right=start
        for (index,group) in groups.enumerated() {
            if index == 0 || index == 2 {
                if apply {left=place(group,x:0,y:left,width:column)}
                else {left += groupHeight(group,width:column)}
            } else {
                if apply {right=place(group,x:column+gap,y:right,width:column)}
                else {right += groupHeight(group,width:column)}
            }
        }
        return max(left,right)
    }
    private func groupHeight(_ group:Group,width:CGFloat)->CGFloat {
        36 + group.rows.reduce(CGFloat(20)){sum,row in sum+(row.label.stringValue.isEmpty ? 0:22)+textHeight(row.value,width:width)+12}
    }
    func contentHeight(forWidth width:CGFloat)->CGFloat {arrange(width:width,apply:false)}
    override func layout(){super.layout();_ = arrange(width:bounds.width,apply:true)}
}

private final class FontInfoDocument:NSView {override var isFlipped:Bool {true}}

/// The same read-only facts shown below the specimen, sized for RailInfo.
final class FontInfoPane:NSView, WorkspaceScrollableContent, InfoRailContent {
    private let scroll=NSScrollView(frame:.zero)
    private let document=FontInfoDocument(frame:.zero)
    private let name=Design.text("",.heading)
    private let facts=FontFactsView(frame:.zero)
    var minimumContentHeight:CGFloat {320}
    var panelContentPadding:CGFloat {16}
    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame)
        scroll.drawsBackground=false;scroll.borderType = .noBorder
        scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true
        document.addSubview(name);document.addSubview(facts)
        scroll.documentView=document;addSubview(scroll)
    }
    required init?(coder:NSCoder){fatalError()}
    func escapeInfoRail()->Bool {false}
    func configure(_ entry:FontLibraryEntry){
        name.stringValue=entry.info.family
        let face=entry.info.faces.first?.postScriptName
            ?? (NSFontManager.shared.availableMembers(ofFontFamily:entry.info.family)?.first?.first as? String)
            ?? entry.info.family
        facts.configure(FontFaceFacts.read(postScriptName:face,family:entry.info.family,sourceURL:entry.fileURL))
        needsLayout=true
    }
    override func layout(){
        super.layout()
        scroll.frame=bounds
        let width=max(100,scroll.contentSize.width),inner=max(80,width-32)
        let factsHeight=facts.contentHeight(forWidth:inner)
        document.frame=NSRect(x:0,y:0,width:width,height:max(bounds.height,64+factsHeight+16))
        name.frame=NSRect(x:16,y:16,width:inner,height:30)
        facts.frame=NSRect(x:16,y:64,width:inner,height:factsHeight)
    }
}

/// The family browser keeps the shared dropdown surface while exposing families, faces and favourites.
private final class FontFamilyDropdown: NSView, Overlay {
    private enum Item { case heading, family(String), face(String,String) }
    private let trigger=DropdownButton(frame:.zero)
    private var panel:SwissDropdown.MenuPanel?
    private var families:[String]=[]
    private var expanded:Set<String>=[]
    private var items:[Item]=[]
    private let favouriteKey="FontLibrary.FavouriteFamilies"
    var selectedFamily="Helvetica Neue" {didSet{trigger.title=selectedFamily;trigger.needsDisplay=true}}
    var onSelection:((String,String?)->Void)?
    var overlayWindows:[NSWindow]{panel.map{[$0]} ?? []}
    var dismissOnOutsideClick:Bool{true}
    override var isFlipped:Bool{true}
    override init(frame:NSRect){
        super.init(frame:frame)
        trigger.title=selectedFamily;trigger.setAccessibilityLabel("Font Family")
        trigger.target=self;trigger.action=#selector(open);addSubview(trigger)
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){super.layout();trigger.frame=bounds}
    func configure(families:[String],selected:String){
        self.families=Array(Set(families+[selected])).sorted{$0.localizedStandardCompare($1) == .orderedAscending}
        selectedFamily=selected
    }
    func dismissOverlay(){
        if let panel {panel.parent?.removeChildWindow(panel);panel.orderOut(nil)}
        panel=nil;Overlays.closed(self)
    }
    func handleOverlayEscape()->Bool{dismissOverlay();return true}
    private func faces(of family:String)->[FontAssetInfo.Face]{
        (NSFontManager.shared.availableMembers(ofFontFamily:family) ?? []).compactMap { row in
            guard row.count >= 2,let post=row[0] as? String,let name=row[1] as? String else{return nil}
            return .init(name:name,postScriptName:post)
        }
    }
    @objc private func open(){if panel != nil{dismissOverlay();return};show()}
    private func show(){
        guard let owner=window else{return}
        let favourites=AppPreferences.shared.stringArray(forKey:favouriteKey) ?? []
        let saved=Set(favourites),featured=favourites.filter{families.contains($0)}
        items=[];var titles:[String]=[]
        func add(_ item:Item,_ title:String){items.append(item);titles.append(title)}
        if !featured.isEmpty {
            add(.heading,SwissDropdown.MenuPanel.heading("Favourites"))
            for family in featured {add(.family(family),family);if expanded.contains(family){for face in faces(of:family){add(.face(family,face.name),"    "+face.name)}}}
            add(.heading,SwissDropdown.MenuPanel.divider)
        }
        add(.heading,SwissDropdown.MenuPanel.heading("Font Families"))
        for family in families where !saved.contains(family) {
            add(.family(family),family)
            if expanded.contains(family){for face in faces(of:family){add(.face(family,face.name),"    "+face.name)}}
        }
        let menu=SwissDropdown.MenuPanel(items:titles,chosen:selectedFamily,width:min(520,max(360,bounds.width)),chosenIndex:nil){[weak self] index in
            guard let self,self.items.indices.contains(index) else{return}
            switch self.items[index] {
            case .heading:break
            case .family(let family):self.selectedFamily=family;self.onSelection?(family,nil);self.dismissOverlay()
            case .face(let family,let face):self.selectedFamily=family;self.onSelection?(family,face);self.dismissOverlay()
            }
        }
        var fonts:[Int:NSFont]=[:]
        for (index,item) in items.enumerated() {
            switch item {
            case .heading:break
            case .family(let family):
                fonts[index]=NSFontManager.shared.font(withFamily:family,traits:[],weight:5,size:TextSize.body)
                let expanded=expanded.contains(family)
                menu.setActions(for:index,symbols:[(saved.contains(family) ? "star.fill":"star",saved.contains(family) ? "Remove Favourite":"Add Favourite"),(expanded ? "chevron.down":"chevron.right",expanded ? "Collapse Styles":"Expand Styles")]){[weak self] action in
                    guard let self else{return}
                    if action == 0 {
                        var set=AppPreferences.shared.stringArray(forKey:self.favouriteKey) ?? []
                        if let at=set.firstIndex(of:family){set.remove(at:at)}else{set.append(family)}
                        AppPreferences.shared.set(set,forKey:self.favouriteKey)
                    } else if expanded {self.expanded.remove(family)}else{self.expanded.insert(family)}
                    self.dismissOverlay();self.show()
                }
            case .face(let family,let face):
                let post=faces(of:family).first{$0.name == face}?.postScriptName ?? family
                fonts[index]=NSFont(name:post,size:TextSize.body)
            }
        }
        menu.setFontPreviews(fonts)
        let anchor=owner.convertToScreen(trigger.convert(trigger.bounds,to:nil))
        menu.place(anchoredTo:anchor,within:owner)
        owner.addChildWindow(menu,ordered:.above);panel=menu;menu.makeKeyAndOrderFront(nil);Overlays.opened(self)
    }
}

private final class FontSpecimenCanvas: NSView, NSTextViewDelegate {
    var onTextChange: (() -> Void)?
    private let editor = NSTextView(frame: .zero)
    var text: String {
        get { editor.string }
        set { if editor.string != newValue { editor.string = newValue }; needsDisplay = true }
    }
    var family = "Helvetica Neue" { didSet { updateEditor() } }
    var faces: [FontAssetInfo.Face] = [] { didSet { updateEditor() } }
    var chosenFace = 0 { didSet { updateEditor() } }
    var familyMode = false { didSet { updateEditor() } }
    var size: CGFloat = 32 { didSet { updateEditor() } }
    var weight = 5 { didSet { updateEditor() } }
    var bold = false { didSet { updateEditor() } }
    var italic = false { didSet { updateEditor() } }
    var ink = NSColor.black { didSet { updateEditor() } }
    var paper = NSColor.white { didSet { needsDisplay = true } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        editor.drawsBackground = false
        editor.isRichText = false
        editor.isEditable = true
        editor.isSelectable = true
        editor.textContainerInset = NSSize(width: 24, height: 24)
        editor.textContainer?.widthTracksTextView = true
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width, .height]
        editor.delegate = self
        editor.setAccessibilityLabel("Font specimen; click to edit")
        addSubview(editor)
        text = "The quick brown fox jumps over the lazy dog."
        updateEditor()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); editor.frame = bounds }
    func textDidChange(_ notification: Notification) { onTextChange?(); needsDisplay = true }
    private func previewFont(for face: FontAssetInfo.Face) -> NSFont {
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        let altered = bold || italic || weight != 5
        return (altered ? NSFontManager.shared.font(withFamily: family, traits: traits, weight: weight, size: size) : nil)
            ?? NSFont(name: face.postScriptName, size: size)
            ?? NSFontManager.shared.font(withFamily: family, traits: traits, weight: weight, size: size)
            ?? NSFont.systemFont(ofSize: size)
    }
    private func specimenAttributes(for face: FontAssetInfo.Face) -> [NSAttributedString.Key:Any] {
        let font=previewFont(for:face)
        let traits=NSFontManager.shared.traits(of:font)
        var attributes:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:ink]
        // Families without a matching face still need a visible Bold/Italic preview.
        if bold && !traits.contains(.boldFontMask) {attributes[.strokeWidth] = -3.0}
        if italic && !traits.contains(.italicFontMask) {attributes[.obliqueness] = 0.22}
        return attributes
    }
    private func updateEditor() {
        let face = faces.indices.contains(chosenFace) ? faces[chosenFace] : .init(name: "Regular", postScriptName: family)
        let attributes=specimenAttributes(for:face)
        editor.font = attributes[.font] as? NSFont
        editor.textColor = ink
        editor.insertionPointColor = ink
        editor.typingAttributes = attributes
        if !editor.string.isEmpty {editor.textStorage?.setAttributes(attributes,range:NSRange(location:0,length:(editor.string as NSString).length))}
        editor.isHidden = familyMode
        needsDisplay = true
    }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        paper.setFill();bounds.fill()
        Design.rule.setStroke();NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)).stroke()
        if !familyMode {
            let face=faces.indices.contains(chosenFace) ? faces[chosenFace] : .init(name:"Regular",postScriptName:family)
            let font=previewFont(for:face)
            let characters=text.unicodeScalars.filter{!CharacterSet.whitespacesAndNewlines.contains($0)}
            if family == "Apple Braille",!characters.isEmpty,characters.allSatisfy({!font.coveredCharacterSet.contains($0)}) {
                Design.attributed("This face has no glyphs for those words. Available glyphs:",.caption,colour:ink).draw(x:24,baseline:32)
                NSAttributedString(string:"⠞⠓⠑ ⠟⠥⠊⠉⠅ ⠃⠗⠕⠺⠝ ⠋⠕⠭",attributes:specimenAttributes(for:face))
                    .draw(with:NSRect(x:24,y:48,width:max(1,bounds.width-48),height:80),options:[.usesLineFragmentOrigin,.truncatesLastVisibleLine])
            }
            return
        }
        let examples=Array(faces.prefix(12).enumerated())
        let lines=examples.isEmpty ? [(0,FontAssetInfo.Face(name:"Regular",postScriptName:family))] : examples
        var y:CGFloat=24
        for (_,face) in lines {
            let attributes=specimenAttributes(for:face)
            if familyMode {
                Design.attributed(face.name,.caption,colour:ink.withAlphaComponent(0.7)).draw(x:24,baseline:y+12)
                y += 18
            }
            let paragraph=NSAttributedString(string:text,attributes:attributes)
            let height=ceil(paragraph.boundingRect(with:NSSize(width:max(1,bounds.width-48),height:.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading]).height)
            paragraph.draw(with:NSRect(x:24,y:y,width:max(1,bounds.width-48),height:min(height+6,bounds.height-y-16)),options:[.usesLineFragmentOrigin,.truncatesLastVisibleLine])
            y += max(size+18,min(height+16,150))
            if y > bounds.maxY-30 {break}
        }
    }
}

/// A font detail page hosted by StudioPage, with a family comparison and editable specimen.
final class FontSpecimenPage: NSView, PageSection {
    var onResize: (() -> Void)?
    var onBack: (() -> Void)?
    var onSave: ((FontAssetInfo) -> Void)?
    var onImport: (() -> Void)?
    var onAddCollection: (() -> Void)?
    private let title=Design.text("Font",.heading)
    private let family=FontFamilyDropdown(frame:.zero)
    private let face=AnalysisMenu("Face",[])
    private let mode=AnalysisMenu("Specimen View",["Single Face","Family"])
    private let weight=ImagePaletteSlider(value:5,minValue:0,maxValue:15,target:nil,action:nil)
    private let size=ImagePaletteSlider(value:32,minValue:12,maxValue:120,target:nil,action:nil)
    private let bold=SwissCheckbox("Bold")
    private let italic=SwissCheckbox("Italic")
    private let ink = NSColorWell(), paper = NSColorWell()
    private let samples=AnalysisMenu("Sample Text Preset",[])
    private let tags=NSTextField(),keywords=NSTextField(),notes=NSTextField()
    private let familyLabel=Design.text("Font Family",.caption,colour:Design.quiet)
    private let faceLabel=Design.text("Face",.caption,colour:Design.quiet)
    private let weightLabel=Design.text("Weight",.caption,colour:Design.quiet)
    private let sizeLabel=Design.text("Size",.caption,colour:Design.quiet)
    private let weightValue=Design.text("5",.bodyStrong)
    private let sizeValue=Design.text("32 pt",.bodyStrong)
    private let weightReset=PaletteAssetIcon(frame:.zero)
    private let sizeReset=PaletteAssetIcon(frame:.zero)
    private let inkLabel=Design.text("Ink",.caption,colour:Design.quiet)
    private let paperLabel=Design.text("Paper",.caption,colour:Design.quiet)
    private let wordsLabel=Design.text("Click In The Canvas To Edit",.caption,colour:Design.quiet)
    private let tagsLabel=Design.text("Tags",.caption,colour:Design.quiet)
    private let keywordsLabel=Design.text("Keywords",.caption,colour:Design.quiet)
    private let notesLabel=Design.text("Notes",.caption,colour:Design.quiet)
    private let canvas=FontSpecimenCanvas()
    private let factsView=FontFactsView(frame:.zero)
    private var info=FontAssetInfo(family:"Helvetica Neue",faces:[])
    private var sourceURL:URL?
    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame)
        for view in [title,family,face,mode,weight,size,bold,italic,ink,paper,samples,tags,keywords,notes,canvas,factsView,familyLabel,faceLabel,weightLabel,sizeLabel,weightValue,sizeValue,weightReset,sizeReset,inkLabel,paperLabel,wordsLabel,tagsLabel,keywordsLabel,notesLabel] as [NSView] {addSubview(view)}
        for popup in [face,samples] {popup.changed={ [weak self] _ in self?.changed(popup) }}
        family.onSelection={ [weak self] _,style in
            guard let self else{return}
            self.populateFaces()
            if let style {self.face.selectItem(withTitle:style)}
            self.updatePreview();self.updateFacts()
        }
        family.configure(families:NSFontManager.shared.availableFontFamilies,selected:"Helvetica Neue")
        samples.addItems(withTitles:["My Words","The quick brown fox","Sphinx of black quartz","Alphabet & numerals","Colour proof"])
        mode.selectItem(at:0);mode.changed={ [weak self] _ in self?.updatePreview() }
        for (slider,resting,range,label) in [(weight,5.0,0.0...15.0,"Weight"),(size,32.0,12.0...120.0,"Size")] {
            slider.cell=ImagePaletteSliderCell()
            slider.target=self;slider.action=#selector(changed);slider.resting=resting;slider.isContinuous=true
            slider.minValue=range.lowerBound;slider.maxValue=range.upperBound;slider.doubleValue=resting
            slider.setAccessibilityLabel(label);slider.toolTip="Double-click to reset \(label)"
        }
        weightReset.symbol="arrow.counterclockwise";sizeReset.symbol="arrow.counterclockwise"
        weightReset.setAccessibilityLabel("Reset Weight");sizeReset.setAccessibilityLabel("Reset Size")
        weightReset.run={ [weak self] in self?.weight.doubleValue=5;self?.updatePreview() }
        sizeReset.run={ [weak self] in self?.size.doubleValue=32;self?.updatePreview() }
        for button in [bold,italic] {button.target=self;button.action=#selector(changed)}
        for well in [ink,paper] {well.target=self;well.action=#selector(changed)}
        tags.placeholderString="Comma-separated tags"
        keywords.placeholderString="Search keywords"
        notes.placeholderString="Notes about this font"
        for field in [tags,keywords,notes] {
            styleMetadataInput(field)
            field.drawsBackground=false;field.backgroundColor = .clear
            field.layer?.borderWidth=0
            field.target=self;field.action=#selector(changed)
        }
        ink.color = .black; paper.color = .white
    }
    required init?(coder:NSCoder){fatalError()}
    func configure(_ value:FontAssetInfo, sourceURL:URL?=nil, collectionEnabled:Bool=true){
        info=value;title.stringValue=value.family
        self.sourceURL=sourceURL
        let selectedFamily=value.previewFamily ?? value.family
        family.configure(families:NSFontManager.shared.availableFontFamilies,selected:selectedFamily)
        populateFaces()
        if let previewFace=value.previewFace {face.selectItem(withTitle:previewFace)}
        mode.selectItem(at:value.previewFamilyMode == true ? 1:0)
        weight.doubleValue=Double(value.previewWeight ?? 5)
        bold.state=value.previewBold == true ? .on:.off
        italic.state=value.previewItalic == true ? .on:.off
        canvas.text=value.specimen
        ink.color=Design.hex(value.ink);paper.color=Design.hex(value.paper)
        size.doubleValue=value.size;tags.stringValue=value.tags.joined(separator:", ")
        keywords.stringValue=(value.metadata?.keywords ?? []).joined(separator:", ")
        notes.stringValue=value.metadata?.description ?? ""
        updatePreview()
        updateFacts()
    }
    private func populateFaces(){
        let selected=face.titleOfSelectedItem
        let selectedFamily=family.selectedFamily
        let members=NSFontManager.shared.availableMembers(ofFontFamily:selectedFamily) ?? []
        let installed=members.compactMap{row -> FontAssetInfo.Face? in
            guard row.count >= 2,let post=row[0] as? String,let style=row[1] as? String else{return nil}
            return .init(name:style,postScriptName:post)
        }
        let faces=selectedFamily == info.family && !info.faces.isEmpty ? info.faces : installed
        canvas.faces=faces;face.removeAllItems();face.addItems(withTitles:faces.map(\.name))
        if let selected {face.selectItem(withTitle:selected)}
        if face.indexOfSelectedItem < 0 && !faces.isEmpty {face.selectItem(at:0)}
    }
    @objc private func changed(_ sender:Any?){
        if sender as AnyObject? === face {updateFacts()}
        if sender as AnyObject? === samples {
            switch samples.indexOfSelectedItem {
            case 1:canvas.text="The quick brown fox jumps over the lazy dog."
            case 2:canvas.text="Sphinx of black quartz, judge my vow."
            case 3:canvas.text="ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789"
            case 4:canvas.text="Colour is a language. Shape it with type."
            default:break
            }
        }
        updatePreview()
    }
    private func updateFacts(){
        let selected=canvas.faces.indices.contains(face.indexOfSelectedItem) ? canvas.faces[face.indexOfSelectedItem] : nil
        let postScriptName=selected?.postScriptName ?? family.selectedFamily
        let original=family.selectedFamily == info.family
        factsView.configure(FontFaceFacts.read(postScriptName:postScriptName,family:family.selectedFamily,sourceURL:original ? sourceURL:nil))
        onResize?()
    }
    private func updatePreview(){
        canvas.family=family.selectedFamily
        canvas.chosenFace=max(0,face.indexOfSelectedItem);canvas.familyMode=mode.indexOfSelectedItem == 1
        canvas.size=CGFloat(size.doubleValue);canvas.weight=Int(weight.doubleValue)
        weightValue.stringValue="\(Int(weight.doubleValue.rounded()))"
        sizeValue.stringValue="\(Int(size.doubleValue.rounded())) pt"
        canvas.bold=bold.state == .on;canvas.italic=italic.state == .on
        canvas.ink=ink.color;canvas.paper=paper.color
    }
    func saveDetails(){
        var changed=info
        changed.specimen=canvas.text;changed.size=size.doubleValue
        changed.ink=hex(ink.color);changed.paper=hex(paper.color)
        changed.previewFamily=family.selectedFamily
        changed.previewFace=face.titleOfSelectedItem
        changed.previewWeight=Int(weight.doubleValue)
        changed.previewBold=bold.state == .on
        changed.previewItalic=italic.state == .on
        changed.previewFamilyMode=mode.indexOfSelectedItem == 1
        changed.tags=Library.cleanTags(tags.stringValue.split(separator:",").map(String.init))
        var metadata=changed.metadata ?? AssetMetadata()
        metadata.keywords=Library.cleanTags(keywords.stringValue.split(separator:",").map(String.init))
        metadata.description=notes.stringValue
        changed.metadata=metadata
        onSave?(changed)
    }
    private func hex(_ colour:NSColor)->String {
        let rgb=colour.usingColorSpace(.deviceRGB) ?? colour
        return String(format:"#%02X%02X%02X",Int((rgb.redComponent*255).rounded()),Int((rgb.greenComponent*255).rounded()),Int((rgb.blueComponent*255).rounded()))
    }
    func reload(){}
    func height(forWidth width:CGFloat)->CGFloat {
        900+factsView.contentHeight(forWidth:min(1120,max(0,width-48)))+24
    }
    override func layout(){
        super.layout()
        let available=min(1120,max(0,bounds.width-48)),left:CGFloat=24,top:CGFloat=16
        let half=max(140,(available-24)/2),second=left+half+24
        title.frame=NSRect(x:left,y:24+top,width:available,height:30)
        familyLabel.frame=NSRect(x:left,y:80+top,width:half,height:16)
        faceLabel.frame=NSRect(x:second,y:80+top,width:half,height:16)
        family.frame=NSRect(x:left,y:100+top,width:half,height:32)
        face.frame=NSRect(x:second,y:100+top,width:half,height:32)
        mode.frame=NSRect(x:left,y:156+top,width:min(252,available),height:32)
        weightLabel.frame=NSRect(x:left,y:209+top,width:half,height:16)
        sizeLabel.frame=NSRect(x:second,y:209+top,width:half,height:16)
        weightValue.frame=NSRect(x:left+half-68,y:207+top,width:44,height:20)
        sizeValue.frame=NSRect(x:second+half-74,y:207+top,width:50,height:20)
        weight.frame=NSRect(x:left,y:229+top,width:half-36,height:28)
        size.frame=NSRect(x:second,y:229+top,width:half-36,height:28)
        weightReset.frame=NSRect(x:left+half-28,y:229+top,width:28,height:28)
        sizeReset.frame=NSRect(x:second+half-28,y:229+top,width:28,height:28)
        bold.frame=NSRect(x:left,y:278+top,width:90,height:28)
        italic.frame=NSRect(x:left+104,y:278+top,width:90,height:28)
        inkLabel.frame=NSRect(x:second,y:269+top,width:48,height:16)
        paperLabel.frame=NSRect(x:second+64,y:269+top,width:54,height:16)
        ink.frame=NSRect(x:second,y:286+top,width:42,height:28)
        paper.frame=NSRect(x:second+64,y:286+top,width:42,height:28)
        wordsLabel.frame=NSRect(x:left+264,y:366+top,width:max(100,available-264),height:16)
        samples.frame=NSRect(x:left,y:358+top,width:min(248,available),height:32)
        canvas.frame=NSRect(x:left,y:414+top,width:available,height:300)
        tagsLabel.frame=NSRect(x:left,y:740+top,width:half,height:16)
        keywordsLabel.frame=NSRect(x:second,y:740+top,width:half,height:16)
        tags.frame=NSRect(x:left,y:758+top,width:half,height:32)
        keywords.frame=NSRect(x:second,y:758+top,width:half,height:32)
        notesLabel.frame=NSRect(x:left,y:803+top,width:available,height:16)
        notes.frame=NSRect(x:left,y:822+top,width:available,height:32)
        factsView.frame=NSRect(x:left,y:884+top,width:available,height:factsView.contentHeight(forWidth:available))
    }
    override func draw(_ dirtyRect:NSRect){
        super.draw(dirtyRect)
        Design.rule.setFill()
        for field in [tags,keywords,notes] {
            let line=field.frame
            NSRect(x:line.minX,y:line.maxY-1,width:line.width,height:1).fill()
        }
    }
}
