import AppKit

private enum ImagePaletteSampleMode {case point,area}
private struct ImagePaletteSwatch {
    let id:UUID
    var colour:ColourDefinition
    var share:Double
    var target:CGPoint
    var baseColour:ColourDefinition
    var baseTarget:CGPoint
    var generatedIndex:Int?
    var sampleMode:ImagePaletteSampleMode
    var moved=false
}
private struct ImagePaletteMarker {
    let id:UUID
    let colour:ColourDefinition
    let point:CGPoint
    let removed:Bool
}

/// Image references and recipes stay separate from the exported full-precision palette.
final class DesignerPaletteEditor:NSObject {
    private let library:LibraryController
    private var recipe=ImagePaletteRecipe()
    private var source:CGImage?
    private var graded:CGImage?
    private var activeSwatches:[ImagePaletteSwatch]=[]
    private var removedSwatches:[ImagePaletteSwatch]=[]
    private var selectedSwatchID:UUID?
    private var reordered=false
    private var result:ImagePaletteResult {
        ImagePaletteResult(colours:activeSwatches.map(\.colour),shares:activeSwatches.map(\.share),
                           targets:activeSwatches.map(\.target))
    }
    private var generation=0
    private var pending:DispatchWorkItem?
    private let canvas=ImagePaletteViewport()
    private let bar=DesignerPaletteBar()
    var onImageAvailabilityChanged:((Bool)->Void)?
    var hasImage:Bool {source != nil}
    let inspector=ImagePaletteInspectorPane()
    private static let recipePathsKey="designer.imagePalette.savedRecipePaths"

    init(library:LibraryController,actionbar:DesignerRegion,viewport:DesignerRegion){
        self.library=library
        super.init()
        canvas.frame=viewport.bounds;canvas.autoresizingMask=[.width,.height]
        viewport.addSubview(canvas)
        bar.frame=actionbar.bounds;bar.autoresizingMask=[.width,.height]
        actionbar.addSubview(bar)
        canvas.onImport={[weak self] in self?.importImage()}
        canvas.onChooseImage={[weak self] url,name in self?.useExistingImage(url,name:name)}
        canvas.onConfirmChange={[weak self] in self?.confirmChangeImage()}
        canvas.onSample={[weak self] point,mode in self?.addSample(at:point,mode:mode)}
        canvas.onMoveTarget={[weak self] index,point in self?.moveTarget(at:index,to:point)}
        canvas.onResetTargets={[weak self] in self?.resetTargets()}
        canvas.onRemoveSwatch={[weak self] id in self?.removeSwatch(id)}
        canvas.onRestoreSwatch={[weak self] id in self?.restoreSwatch(id)}
        canvas.onReorderSwatch={[weak self] id,index in self?.reorderSwatch(id,to:index)}
        canvas.onSelectSwatch={[weak self] id in self?.selectedSwatchID=id;self?.refresh()}
        bar.onSaveRecipe={[weak self] in self?.saveRecipe()}
        bar.onExport={[weak self] in self?.exportPalette()}
        inspector.onChange={[weak self] updated in
            guard let self else{return}
            var previous=self.recipe
            previous.paletteName=updated.paletteName
            self.recipe=updated
            if previous == updated {self.refresh()} else {self.schedule()}
        }
        inspector.onSave={[weak self] destination in self?.exportPalette(to:destination)}
        inspector.onRecipePick={[weak self] index in self?.pickRecipe(index)}
        migrateEarlierRecipes()
        inspector.setSavedRecipes(savedRecipes.map(\.name))
        inspector.setDestinations(destinations())
        refresh()
    }
    private var savedRecipes:[ImagePaletteRecipeIndexItem] {ImagePaletteRecipeStore.list()}
    private func migrateEarlierRecipes() {
        let paths=AppPreferences.shared.object(forKey:Self.recipePathsKey) as? [String] ?? []
        guard !paths.isEmpty else{return}
        let remaining=paths.filter{path in
            let url=URL(fileURLWithPath:path)
            guard FileManager.default.fileExists(atPath:url.path) else{return false}
            return (try? ImagePaletteRecipeStore.importFile(url)) == nil
        }
        AppPreferences.shared.set(remaining,forKey:Self.recipePathsKey)
    }
    private func destinations()->[ImagePaletteDestination] {
        var values=[ImagePaletteDestination(label:"My Library",project:nil,bucket:nil)]
        for project in library.library.orderedProjects where !project.isLocked {
            var found=false
            func visit(_ node:SchemaNode,_ path:String) {
                let next=path.isEmpty ? node.name:path+" / "+node.name
                if SchemaTrial.role(of:node) == .palettes {
                    values.append(ImagePaletteDestination(label:project.name+" / "+next,project:project.id,bucket:node.id))
                    found=true
                }
                for child in node.children {visit(child,next)}
            }
            for child in SchemaTrial.schema(for:project.id).children {visit(child,"")}
            if !found {values.append(ImagePaletteDestination(label:project.name,project:project.id,bucket:nil))}
        }
        return values
    }
    private func refresh() {
        if source == nil {canvas.locations=imageLocations()}
        canvas.source=source;canvas.graded=graded;canvas.region=recipe.region
        canvas.result=result
        canvas.activeSwatches=activeSwatches;canvas.removedSwatches=removedSwatches
        canvas.markers=activeSwatches.map{ImagePaletteMarker(id:$0.id,colour:$0.colour,point:$0.target,removed:false)}
            + removedSwatches.map{ImagePaletteMarker(id:$0.id,colour:$0.colour,point:$0.target,removed:true)}
        canvas.selectedSwatchID=selectedSwatchID
        canvas.hasMovedTargets=(activeSwatches+removedSwatches).contains(where:\.moved)
        inspector.update(recipe,hasOutput:!result.colours.isEmpty,hasImage:source != nil)
        bar.canExport = !result.colours.isEmpty
        bar.hasImage = source != nil
    }
    private func confirmChangeImage(){
        pending?.cancel();generation += 1
        recipe=ImagePaletteRecipe()
        source=nil;graded=nil;activeSwatches=[];removedSwatches=[];selectedSwatchID=nil;reordered=false
        bar.message="Choose another image"
        refresh()
        onImageAvailabilityChanged?(false)
    }
    private func imageLocations()->[ImagePaletteSourceChooser.Location] {
        let store=library.store
        let globalIndex=store.assetsHome.map{GlobalAssets(home:$0).index.standardizedFileURL}
        let catalogueName=store.url.deletingPathExtension().lastPathComponent
        var groups:[String:[String:[ImagePaletteSourceChooser.ImageRecord]]]=[:]
        var names:[String:String]=["library":"My Library","catalogue":catalogueName]
        for project in library.library.orderedProjects {names[project.id.uuidString]=project.name}
        let fm=FileManager.default
        for (asset,index) in WorkspaceImport.records(store:store) where asset.type == "Photographs" || asset.type == "Images" {
            guard let url=try? asset.url(in:index.deletingLastPathComponent()),fm.fileExists(atPath:url.path) else{continue}
            let key:String
            let title:String
            if index.standardizedFileURL == globalIndex {key="library";title="My Library"}
            else if let member=asset.member {key=member.uuidString;title=library.library.project(member)?.name ?? catalogueName}
            else {key="catalogue";title=catalogueName}
            names[key]=title
            groups[key,default:[:]][asset.type,default:[]].append(.init(url:url,name:asset.name))
        }
        let preferred=["catalogue"]+library.library.orderedProjects.map{ $0.id.uuidString }+["library"]
        let ordered=preferred+groups.keys.filter{!preferred.contains($0)}.sorted()
        var locations:[ImagePaletteSourceChooser.Location]=[]
        for key in ordered {
            for kind in ["Photographs","Images"] {
                let records=groups[key]?[kind] ?? []
                locations.append(.init(id:key+"/"+kind,section:names[key] ?? catalogueName,title:kind,records:records.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}))
            }
        }
        return locations
    }
    private func useExistingImage(_ url:URL,name:String) {
        let store=library.store
        bar.message="Reading image…"
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            let image=ImagePaletteExtractor.decode(url)
            DispatchQueue.main.async { [weak self] in
                guard let self else{return}
                guard self.library.store === store else{self.bar.message="The workspace changed. Choose the image again.";return}
                guard let image else{self.bar.message="macOS cannot decode this image";return}
                self.recipe.sourcePath=url.standardizedFileURL.path
                self.recipe.sourceName=name
                if self.recipe.paletteName == "Image Palette" {self.recipe.paletteName=url.deletingPathExtension().lastPathComponent}
                self.source=image;self.schedule();self.onImageAvailabilityChanged?(true)
            }
        }
    }
    /// Dropped images stay in this editing session; no Library record or source link is created.
    func useDroppedImage(_ payload:DesignerImageDrop.Payload) {
        pending?.cancel();generation += 1
        let request=generation,store=library.store,name=payload.name
        bar.message="Reading dropped image…"
        let finish:(CGImage?)->Void={ [weak self] image in
            DispatchQueue.main.async { [weak self] in
                guard let self,self.generation == request else{return}
                guard self.library.store === store else{self.bar.message="The workspace changed. Drop the image again.";return}
                guard let image else{self.bar.message="macOS cannot decode this image";return}
                self.recipe=ImagePaletteRecipe()
                self.recipe.sourceName=name
                self.recipe.paletteName=name
                self.source=image;self.graded=nil
                self.activeSwatches=[];self.removedSwatches=[];self.selectedSwatchID=nil;self.reordered=false
                self.schedule();self.onImageAvailabilityChanged?(true)
            }
        }
        switch payload {
        case .file(let url):
            DispatchQueue.global(qos:.userInitiated).async {
                let scoped=url.startAccessingSecurityScopedResource()
                defer {if scoped {url.stopAccessingSecurityScopedResource()}}
                finish(ImagePaletteExtractor.decode(url))
            }
        case .imageData(let data):
            DispatchQueue.global(qos:.userInitiated).async {finish(ImagePaletteExtractor.decode(data))}
        case .remote(let url):
            var request=URLRequest(url:url);request.timeoutInterval=20
            let session=URLSession(configuration:.ephemeral)
            session.dataTask(with:request) {data,response,_ in
                defer {session.finishTasksAndInvalidate()}
                let withinLimit=data.map{$0.count <= 40_000_000} ?? false
                let succeeded=(response as? HTTPURLResponse).map{(200..<300).contains($0.statusCode)} ?? false
                finish(withinLimit && succeeded ? data.flatMap{ImagePaletteExtractor.decode($0)}:nil)
            }.resume()
        }
    }
    private func schedule() {
        pending?.cancel();generation += 1
        let request=generation,current=recipe
        guard let source else {refresh();return}
        bar.message="Processing…";refresh()
        let work=DispatchWorkItem { [weak self] in
            let graded=ImagePaletteExtractor.grade(source,recipe:current)
            let extracted=graded.map{ImagePaletteExtractor.extract($0,recipe:current)} ?? ImagePaletteResult(colours:[],shares:[])
            let ordered=Self.hueOrdered(extracted)
            DispatchQueue.main.async { [weak self] in
                guard let self,self.generation == request else{return}
                self.graded=graded;self.reconcile(ordered,graded:graded)
                self.bar.message=self.activeSwatches.isEmpty ? "No colours found":""
                self.refresh()
            }
        }
        pending=work
        DispatchQueue.global(qos:.userInitiated).asyncAfter(deadline:.now()+0.12,execute:work)
    }
    /// Keep the preview and export sequence identical. Chromatic hues lead; neutrals follow by lightness.
    static func hueOrdered(_ result:ImagePaletteResult)->ImagePaletteResult {
        let indices=result.colours.indices.sorted { lhs,rhs in
            func key(_ index:Int)->(Int,CGFloat,CGFloat,Int) {
                let rgb=result.colours[index].master.display.usingColorSpace(.deviceRGB) ?? result.colours[index].master.display
                let saturation=rgb.saturationComponent,brightness=rgb.brightnessComponent
                return (saturation < 0.08 ? 1:0,saturation < 0.08 ? brightness:rgb.hueComponent,brightness,index)
            }
            let a=key(lhs),b=key(rhs)
            if a.0 != b.0{return a.0 < b.0}
            if a.1 != b.1{return a.1 < b.1}
            if a.2 != b.2{return a.2 < b.2}
            return a.3 < b.3
        }
        return ImagePaletteResult(colours:indices.map{result.colours[$0]},
                                  shares:indices.map{result.shares.indices.contains($0) ? result.shares[$0]:0},
                                  targets:indices.map{result.targets.indices.contains($0) ? result.targets[$0]:.zero})
    }
    private func reconcile(_ extracted:ImagePaletteResult,graded:CGImage?) {
        let old=(activeSwatches+removedSwatches).compactMap{item -> (Int,ImagePaletteSwatch)? in
            guard let index=item.generatedIndex else{return nil};return (index,item)
        }
        var updated:[Int:ImagePaletteSwatch]=[:]
        for index in extracted.colours.indices {
            let colour=extracted.colours[index]
            let target=extracted.targets.indices.contains(index) ? extracted.targets[index]:.zero
            let share=extracted.shares.indices.contains(index) ? extracted.shares[index]:0
            var item=old.first(where:{$0.0 == index})?.1 ?? ImagePaletteSwatch(
                id:UUID(),colour:colour,share:share,target:target,baseColour:colour,
                baseTarget:target,generatedIndex:index,sampleMode:.point)
            item.baseColour=colour;item.baseTarget=target;item.share=share
            if item.moved,let graded {
                item.colour=ImagePaletteExtractor.sampleColour(graded,at:item.target,area:false) ?? colour
            } else {item.colour=colour;item.target=target}
            updated[index]=item
        }
        let previousActive=activeSwatches.compactMap{item -> ImagePaletteSwatch? in
            guard let index=item.generatedIndex else{return resampleManual(item,in:graded)}
            return updated.removeValue(forKey:index)
        }
        let previousRemoved=removedSwatches.compactMap{item -> ImagePaletteSwatch? in
            guard let index=item.generatedIndex else{return resampleManual(item,in:graded)}
            return updated.removeValue(forKey:index)
        }
        let additions=updated.keys.sorted().compactMap{updated[$0]}
        activeSwatches=reordered ? previousActive+additions : (previousActive+additions).sorted{
            ($0.generatedIndex ?? Int.max)<($1.generatedIndex ?? Int.max)
        }
        removedSwatches=previousRemoved
    }
    private func resampleManual(_ item:ImagePaletteSwatch,in image:CGImage?)->ImagePaletteSwatch {
        var value=item
        if let image {value.colour=ImagePaletteExtractor.sampleColour(image,at:item.target,area:item.sampleMode == .area) ?? item.colour}
        return value
    }
    private func addSample(at point:CGPoint,mode:ImagePaletteSampleMode) {
        guard let graded,let colour=ImagePaletteExtractor.sampleColour(graded,at:point,area:mode == .area) else{return}
        activeSwatches.append(ImagePaletteSwatch(id:UUID(),colour:colour,share:0,target:point,
                                                 baseColour:colour,baseTarget:point,generatedIndex:nil,sampleMode:mode))
        selectedSwatchID=activeSwatches.last?.id
        bar.message="Sample added to palette";refresh()
    }
    private func moveTarget(at index:Int,to point:CGPoint) {
        guard activeSwatches.indices.contains(index),let graded,
              let colour=ImagePaletteExtractor.sampleColour(graded,at:point,area:false) else{return}
        activeSwatches[index].target=point;activeSwatches[index].colour=colour
        selectedSwatchID=activeSwatches[index].id
        activeSwatches[index].moved=true
        canvas.activeSwatches=activeSwatches
        canvas.markers=activeSwatches.map{ImagePaletteMarker(id:$0.id,colour:$0.colour,point:$0.target,removed:false)}
            + removedSwatches.map{ImagePaletteMarker(id:$0.id,colour:$0.colour,point:$0.target,removed:true)}
        canvas.selectedSwatchID=selectedSwatchID
        canvas.hasMovedTargets=true
        bar.message="Sample target moved"
    }
    private func resetTargets() {
        guard let graded else{return}
        func reset(_ list:inout [ImagePaletteSwatch]) {
            for index in list.indices {
                list[index].target=list[index].baseTarget
                list[index].colour=list[index].generatedIndex == nil
                    ? (ImagePaletteExtractor.sampleColour(graded,at:list[index].baseTarget,area:list[index].sampleMode == .area) ?? list[index].baseColour)
                    : list[index].baseColour
                list[index].moved=false
            }
        }
        reset(&activeSwatches);reset(&removedSwatches)
        bar.message="Targets reset to RailInfo settings";refresh()
    }
    private func removeSwatch(_ id:UUID) {
        guard let index=activeSwatches.firstIndex(where:{$0.id == id}) else{return}
        selectedSwatchID=id
        removedSwatches.append(activeSwatches.remove(at:index));refresh()
    }
    private func restoreSwatch(_ id:UUID) {
        guard let index=removedSwatches.firstIndex(where:{$0.id == id}) else{return}
        selectedSwatchID=id
        activeSwatches.append(removedSwatches.remove(at:index));refresh()
    }
    private func reorderSwatch(_ id:UUID,to destination:Int) {
        guard let index=activeSwatches.firstIndex(where:{$0.id == id}) else{return}
        let item=activeSwatches.remove(at:index)
        activeSwatches.insert(item,at:max(0,min(activeSwatches.count,destination)))
        reordered=true;refresh()
    }
    private func importImage() {
        let picker=NSOpenPanel();picker.title="Choose Image Reference"
        picker.message="Choose JPG/JPEG, PNG, GIF, TIFF, HEIC/HEIF, ProRAW DNG or supported camera RAW. GIF uses its first frame. The original stays where it is."
        picker.canChooseFiles=true;picker.canChooseDirectories=false;picker.allowsMultipleSelection=false
        picker.begin { [weak self] response in
            guard response == .OK,let url=picker.url,let self else{return}
            do {try FolderAccess.authorize(url)} catch {self.bar.message=error.localizedDescription;return}
            let store=self.library.store
            self.bar.message="Reading image…"
            DispatchQueue.global(qos:.userInitiated).async { [weak self] in
                let loaded=Result { () throws -> CGImage in
                    guard let image=ImagePaletteExtractor.decode(url) else {throw failure("macOS cannot decode this image")}
                    _ = try WorkspaceImport.addImages([url],destination:.library,kind:"Photographs",transfer:.reference,store:store)
                    return image
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else{return}
                    guard self.library.store === store else {self.bar.message="The workspace changed. Import the image again.";return}
                    switch loaded {
                    case .failure(let error):self.bar.message=error.localizedDescription
                    case .success(let image):
                        self.library.reload()
                        self.recipe.sourcePath=url.standardizedFileURL.path
                        self.recipe.sourceName=url.lastPathComponent
                        if self.recipe.paletteName == "Image Palette" {self.recipe.paletteName=url.deletingPathExtension().lastPathComponent}
                        self.source=image;self.schedule();self.onImageAvailabilityChanged?(true)
                    }
                }
            }
        }
    }
    private func exportPalette() {
        inspector.setDestinations(destinations())
        exportPalette(to:inspector.selectedDestination)
    }
    private func exportPalette(to destination:ImagePaletteDestination) {
        guard !result.colours.isEmpty else{return}
        recipe.paletteName=inspector.enteredPaletteName
        let name=recipe.paletteName.trimmingCharacters(in:.whitespacesAndNewlines)
        let colours=result.colours
        var made:UUID?
        let saved=library.apply("Export Image Palette") { lib in
            if let project=destination.project,lib.project(project)?.isLocked != false {return}
            let previous=lib.activeSwatchID
            let id=lib.createSwatch(named:name.isEmpty ? "Image Palette":name,hexes:[],custom:true)
            let keys=colours.compactMap{lib.addColour($0)}
            lib.add(keys,toSwatch:id)
            if let project=destination.project {
                lib.move(id,to:project,index:0)
                if let index=lib.swatches.firstIndex(where:{$0.id == id}) {lib.swatches[index].bucketID=destination.bucket}
            }
            // A fresh export leads both the destination bin and the independent Palettes list.
            lib.placeInList([id]+lib.listedPalettes.map(\.id).filter{$0 != id})
            lib.activeSwatchID=previous
            made=id
        }
        if saved,made != nil {bar.message="Exported palette to \(destination.label)"}
        else {bar.message="Could not export palette to \(destination.label)"}
    }
    private func saveRecipe() {
        guard let host=canvas.window?.contentView ?? inspector.window?.contentView else{return}
        let modal=SwissFocusModal(title:"Save Image Palette Recipe",message:"Save the grading and extraction settings for use with any image. The source image and palette name are not included.")
        let name=modal.field("Recipe Name",value:inspector.enteredPaletteName)
        modal.button("Cancel"){[weak modal] in modal?.dismissOverlay()}
        modal.button("Save Recipe",primary:true){[weak self,weak modal] in
            guard let self else{return}
            do {
                _=try ImagePaletteRecipeStore.save(name:name.stringValue,settings:ImagePaletteSettings(self.recipe))
                self.inspector.setSavedRecipes(self.savedRecipes.map(\.name))
                self.bar.message="Recipe saved in workspace"
                modal?.dismissOverlay()
            } catch {self.bar.message=error.localizedDescription}
        }
        modal.present(over:host)
    }
    private func pickRecipe(_ index:Int) {
        let items=savedRecipes
        guard index > 0 else{return}
        if index == items.count+1 {openRecipe();return}
        guard items.indices.contains(index-1) else{return}
        loadRecipe(items[index-1])
    }
    private func openRecipe() {
        let picker=NSOpenPanel();picker.title="Import Image Palette Recipe"
        picker.canChooseFiles=true;picker.canChooseDirectories=false
        picker.begin { [weak self] response in
            guard response == .OK,let url=picker.url,let self else{return}
            do {
                let item=try ImagePaletteRecipeStore.importFile(url)
                self.inspector.setSavedRecipes(self.savedRecipes.map(\.name))
                self.loadRecipe(item)
            } catch {self.bar.message=error.localizedDescription}
        }
    }
    private func loadRecipe(_ item:ImagePaletteRecipeIndexItem) {
        do {
            try ImagePaletteRecipeStore.load(item).apply(to:&recipe)
            bar.message="Recipe applied · \(item.name)"
            schedule()
        } catch {bar.message=error.localizedDescription}
    }
}

private final class DesignerPaletteBar:NSView {
    var onSaveRecipe:(()->Void)?,onExport:(()->Void)?
    var canExport=false {didSet{exportButton.isEnabled=canExport}}
    var hasImage=false {didSet{recipeButton.isEnabled=hasImage;needsLayout=true}}
    var message="Import an image to begin" {didSet{status.stringValue=message}}
    private let status=Design.text("Import an image to begin",.caption,colour:Design.quiet)
    private let recipeButton=SwissButton("Save Recipe",.quiet)
    private let exportButton=SwissButton("Export Palette",.primary)
    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame)
        for view in [status,recipeButton,exportButton] {addSubview(view)}
        recipeButton.target=self;recipeButton.action=#selector(recipePressed)
        recipeButton.isEnabled=false
        exportButton.target=self;exportButton.action=#selector(exportPressed);exportButton.isEnabled=false
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func recipePressed(){onSaveRecipe?()}
    @objc private func exportPressed(){onExport?()}
    override func draw(_ dirtyRect:NSRect){
        Design.card.setFill();bounds.fill()
    }
    override func layout(){
        super.layout()
        let top=(bounds.height-32)/2
        recipeButton.frame=NSRect(x:16,y:top,width:112,height:32)
        exportButton.frame=NSRect(x:136,y:top,width:136,height:32)
        status.isHidden=bounds.width < 540
        status.frame=NSRect(x:288,y:(bounds.height-18)/2,width:max(0,bounds.width-304),height:18)
    }
}

private final class ImagePaletteViewport:NSView {
    var onImport:(()->Void)? {didSet{comparison.onImport=onImport}}
    var onChooseImage:((URL,String)->Void)? {didSet{comparison.onChooseImage=onChooseImage}}
    var onConfirmChange:(()->Void)? {didSet{comparison.onConfirmChange=onConfirmChange}}
    var onSample:((CGPoint,ImagePaletteSampleMode)->Void)? {didSet{comparison.onSample=onSample}}
    var onMoveTarget:((Int,CGPoint)->Void)? {didSet{comparison.onMoveTarget=onMoveTarget}}
    var onResetTargets:(()->Void)? {didSet{comparison.onResetTargets=onResetTargets}}
    var onRemoveSwatch:((UUID)->Void)? {didSet{swatches.onRemove=onRemoveSwatch;comparison.onRemoveSwatch=onRemoveSwatch}}
    var onRestoreSwatch:((UUID)->Void)? {didSet{swatches.onRestore=onRestoreSwatch;comparison.onRestoreSwatch=onRestoreSwatch}}
    var onReorderSwatch:((UUID,Int)->Void)? {didSet{swatches.onReorder=onReorderSwatch}}
    var onSelectSwatch:((UUID)->Void)? {didSet{comparison.onSelectSwatch=onSelectSwatch;swatches.onSelect=onSelectSwatch}}
    var locations:[ImagePaletteSourceChooser.Location]=[] {didSet{comparison.locations=locations}}
    var source:CGImage? {didSet{comparison.source=source}}
    var graded:CGImage? {didSet{comparison.graded=graded}}
    var region=ImagePaletteRecipe.Region.full {didSet{comparison.region=region}}
    var activeSwatches:[ImagePaletteSwatch]=[] {didSet{swatches.active=activeSwatches}}
    var removedSwatches:[ImagePaletteSwatch]=[] {didSet{swatches.removed=removedSwatches;needsLayout=true}}
    var markers:[ImagePaletteMarker]=[] {didSet{comparison.markers=markers}}
    var selectedSwatchID:UUID? {didSet{comparison.selectedSwatchID=selectedSwatchID;swatches.selectedSwatchID=selectedSwatchID}}
    var hasMovedTargets=false {didSet{comparison.hasMovedTargets=hasMovedTargets}}
    var result=ImagePaletteResult(colours:[],shares:[]) {didSet{
        revealPalette=oldValue.colours.isEmpty && !result.colours.isEmpty
        needsLayout=true
    }}
    private let comparison=ImagePaletteComparison()
    private let swatches=ImagePaletteSwatches()
    private var revealPalette=false
    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame)
        swatches.wantsLayer=true
        addSubview(comparison);addSubview(swatches)
    }
    required init?(coder:NSCoder){fatalError()}
    override func layout(){
        super.layout()
        let hasColours = !activeSwatches.isEmpty || !removedSwatches.isEmpty
        let paletteHeight:CGFloat=hasColours ? min(swatches.contentHeight(for:bounds.width)+1,
                                                    max(180,bounds.height*0.45)):0
        comparison.frame=NSRect(x:0,y:0,width:bounds.width,height:max(0,bounds.height-paletteHeight))
        swatches.frame=NSRect(x:0,y:comparison.frame.maxY,width:bounds.width,height:paletteHeight)
        swatches.isHidden = !hasColours
        if hasColours,revealPalette {
            revealPalette=false
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let rise=CABasicAnimation(keyPath:"transform.translation.y")
                rise.fromValue=paletteHeight;rise.toValue=0;rise.duration=0.28
                rise.timingFunction=CAMediaTimingFunction(name:.easeOut)
                swatches.layer?.add(rise,forKey:"ExtractedPaletteRise")
            }
        }
        swatches.needsLayout=true
    }
}

/// The tab row overlaps the VP-actionbar's last pixel; this foreground rule owns that seam.
private final class ImagePaletteTopSeam:NSView {
    override var isFlipped:Bool {true}
    override func hitTest(_ point:NSPoint)->NSView? {nil}
    override func draw(_ dirtyRect:NSRect){fill(bounds,Design.rule)}
}

private final class ImagePaletteComparison:NSView {
    var onImport:(()->Void)? {didSet{chooser.onImport=onImport}}
    var onChooseImage:((URL,String)->Void)? {didSet{chooser.onChooseImage=onChooseImage}}
    var onConfirmChange:(()->Void)?
    var onSample:((CGPoint,ImagePaletteSampleMode)->Void)?
    var onMoveTarget:((Int,CGPoint)->Void)?
    var onResetTargets:(()->Void)?
    var onRemoveSwatch:((UUID)->Void)?,onRestoreSwatch:((UUID)->Void)?,onSelectSwatch:((UUID)->Void)?
    var locations:[ImagePaletteSourceChooser.Location]=[] {didSet{chooser.locations=locations}}
    var source:CGImage? {didSet{
        chooser.isHidden=source != nil
        if source == nil {
            changeArmed=false
            if oldValue != nil {chooser.clearSelection()}
        }
        changeButton.isHidden=source == nil
        changeWarning.isHidden=source == nil || !changeArmed
        needsLayout=true;needsDisplay=true
    }}
    var graded:CGImage? {didSet{
        if graded == nil {adjustedExpanded=false}
        widthButton.isHidden=graded == nil
        needsLayout=true;needsDisplay=true
    }}
    var markers:[ImagePaletteMarker]=[] {didSet{needsDisplay=true;window?.invalidateCursorRects(for:self)}}
    var selectedSwatchID:UUID? {didSet{needsDisplay=true}}
    var hasMovedTargets=false {didSet{resetButton.isHidden = !hasMovedTargets || graded == nil;needsLayout=true}}
    var region=ImagePaletteRecipe.Region.full {didSet{adjustedTab.title="Adjusted · \(region.rawValue)";needsDisplay=true}}
    private let chooser=ImagePaletteSourceChooser()
    private let originalTab=WorkspacePageTabHeader(frame:.zero)
    private let adjustedTab=WorkspacePageTabHeader(frame:.zero)
    private let tabHeight=WorkspaceTabContour.height+1
    private let changeButton=WorkspaceImportActionButton(frame:.zero)
    private let resetButton=WorkspaceImportActionButton(frame:.zero)
    private let widthButton=PaletteAssetIcon(frame:.zero)
    private let tools=ImagePaletteToolStack(frame:.zero)
    private let topSeam=ImagePaletteTopSeam(frame:.zero)
    private let changeWarning=Design.text("This clears the current grade and extraction settings.",.caption,colour:Design.quiet)
    private var changeArmed=false {didSet{
        changeButton.title=changeArmed ? "Confirm":"Change Image"
        changeWarning.isHidden = !changeArmed || source == nil
        needsLayout=true
    }}
    private var sampleMode:ImagePaletteSampleMode? {didSet{
        tools.selected=sampleMode
        window?.invalidateCursorRects(for:self)
    }}
    private var showsTargets=true {didSet{tools.showsTargets=showsTargets;needsDisplay=true;window?.invalidateCursorRects(for:self)}}
    private var draggedTarget:UUID?,dragPreview:CGPoint?
    private var adjustedExpanded=false {didSet{
        originalTab.isHidden=adjustedExpanded
        adjustedTab.showsLeadingBorder = !adjustedExpanded
        widthButton.symbol=adjustedExpanded ? PanelExpansionSymbol.contract:PanelExpansionSymbol.expand
        let label=adjustedExpanded ? "Show Original and Adjusted Side by Side":"Show Adjusted Image Full Width"
        widthButton.toolTip=label;widthButton.setAccessibilityLabel(label)
        needsLayout=true;needsDisplay=true
    }}
    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame)
        originalTab.title="Original Reference";originalTab.symbol="photo"
        adjustedTab.title="Adjusted · Full Image";adjustedTab.symbol="slider.horizontal.3"
        originalTab.stripeColour=Design.rule;adjustedTab.stripeColour=Design.rule
        adjustedTab.showsLeadingBorder=true
        for view in [originalTab,adjustedTab,chooser] {addSubview(view)}
        changeButton.symbol="arrow.triangle.2.circlepath"
        changeButton.title="Change Image"
        changeButton.setAccessibilityLabel("Change Image")
        changeButton.target=self;changeButton.action=#selector(changePressed)
        changeButton.isHidden=true;changeWarning.isHidden=true
        addSubview(changeButton);addSubview(changeWarning)
        resetButton.symbol="arrow.counterclockwise";resetButton.title="Reset"
        resetButton.setAccessibilityLabel("Reset Sample Targets")
        resetButton.toolTip="Restore calculated sample targets from the current RailInfo settings"
        resetButton.target=self;resetButton.action=#selector(resetPressed)
        resetButton.isHidden=true;addSubview(resetButton)
        widthButton.symbol=PanelExpansionSymbol.expand;widthButton.matchesHeaderGlyph=true
        widthButton.outlinedSquare=true
        widthButton.toolTip="Show Adjusted Image Full Width"
        widthButton.setAccessibilityLabel("Show Adjusted Image Full Width")
        widthButton.run={ [weak self] in self?.adjustedExpanded.toggle() }
        widthButton.isHidden=true
        addSubview(widthButton)
        tools.onPoint={[weak self] in self?.sampleMode = self?.sampleMode == .point ? nil:.point}
        tools.onArea={[weak self] in self?.sampleMode = self?.sampleMode == .area ? nil:.area}
        tools.onTargets={[weak self] in self?.showsTargets.toggle()}
        addSubview(tools)
        addSubview(topSeam,positioned:.above,relativeTo:nil)
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func changePressed(){
        if changeArmed {onConfirmChange?()}
        else {changeArmed=true}
    }
    @objc private func resetPressed(){onResetTargets?()}
    override func layout(){
        super.layout()
        let width=max(0,bounds.width/2)
        // The tab has no top border and must meet the actionbar directly.
        let original=NSRect(x:0,y:0,width:width,height:bounds.height)
        let adjusted=adjustedPage()
        originalTab.frame=NSRect(x:original.minX,y:original.minY,width:original.width,height:tabHeight)
        adjustedTab.frame=NSRect(x:adjusted.minX,y:adjusted.minY,width:adjusted.width,height:tabHeight)
        let body=previewBody(original)
        chooser.frame=body.insetBy(dx:40,dy:40)
        chooser.isHidden=adjustedExpanded || source != nil || chooser.frame.width < 220 || chooser.frame.height < 130
        let picture=previewImageArea(body),painted=source.map{imageRect($0,in:picture)} ?? picture
        let stackHeight:CGFloat=changeArmed ? 60:38
        let top=max(picture.maxY,min(body.maxY-stackHeight-8,(painted.maxY+body.maxY-stackHeight)/2))
        changeButton.frame=NSRect(x:body.midX-88,y:top,width:176,height:38)
        changeWarning.frame=NSRect(x:body.minX+12,y:top+42,width:max(0,body.width-24),height:18)
        changeWarning.alignment = .center
        changeButton.isHidden=adjustedExpanded || source == nil || body.height < 150
        changeWarning.isHidden=adjustedExpanded || !changeArmed || source == nil
        let adjustedBody=previewBody(adjusted)
        let adjustedArea=previewImageArea(adjustedBody)
        let adjustedPicture=graded.map{imageRect($0,in:adjustedArea)} ?? .zero
        let resetTop=max(adjustedArea.maxY,
                         min(adjustedBody.maxY-46,(adjustedPicture.maxY+adjustedBody.maxY-38)/2))
        resetButton.frame=NSRect(x:adjustedBody.midX-88,y:resetTop,width:176,height:38)
        resetButton.isHidden = !hasMovedTargets || graded == nil
        tools.frame=NSRect(x:min(adjustedBody.maxX-48,adjustedPicture.maxX+12),
                           y:adjustedPicture.minY,width:36,height:108)
        tools.isHidden=graded == nil || adjustedPicture.isEmpty
        widthButton.frame=NSRect(x:adjustedBody.minX+12,y:adjustedBody.minY+12,width:32,height:32)
        topSeam.frame=NSRect(x:0,y:0,width:bounds.width,height:1)
    }
    override func draw(_ dirtyRect:NSRect){
        Design.paper.setFill();bounds.fill()
        let width=max(0,bounds.width/2)
        let original=NSRect(x:0,y:0,width:width,height:bounds.height)
        if !adjustedExpanded {drawPreview(source,at:previewBody(original))}
        let adjusted=adjustedPage()
        let adjustedBody=previewBody(adjusted)
        drawPreview(graded,at:adjustedBody)
        if let graded,showsTargets {drawTargets(on:graded,in:adjustedBody)}
        Design.rule.setStroke()
        let border=NSBezierPath()
        border.move(to:NSPoint(x:bounds.width-0.5,y:0))
        border.line(to:NSPoint(x:bounds.width-0.5,y:bounds.height))
        if !adjustedExpanded {
            border.move(to:NSPoint(x:width+0.5,y:tabHeight-1))
            border.line(to:NSPoint(x:width+0.5,y:bounds.height))
        }
        border.lineWidth=1;border.stroke()
    }
    private func adjustedPage()->NSRect {
        let left=adjustedExpanded ? 0:bounds.width/2
        return NSRect(x:left,y:0,width:max(0,bounds.width-left),height:bounds.height)
    }
    private func previewBody(_ page:NSRect)->NSRect {
        NSRect(x:page.minX,y:page.minY+tabHeight-1,width:page.width,
               height:max(0,page.height-tabHeight+1))
    }
    private func previewImageArea(_ frame:NSRect)->NSRect {
        NSRect(x:frame.minX+12,y:frame.minY+12,width:max(0,frame.width-24),height:max(0,frame.height-110))
    }
    private func imageRect(_ image:CGImage,in area:NSRect)->NSRect {
        guard area.width > 0,area.height > 0 else{return .zero}
        let width=CGFloat(image.width),height=CGFloat(image.height)
        let ratio=min(area.width/width,area.height/height)
        return NSRect(x:area.midX-width*ratio/2,y:area.midY-height*ratio/2,width:width*ratio,height:height*ratio)
    }
    private func drawPreview(_ image:CGImage?,at frame:NSRect){
        guard frame.width > 0,frame.height > 0 else{return}
        Design.card.setFill();frame.fill()
        let area=previewImageArea(frame)
        if let image,area.width > 0,area.height > 0 {
            NSImage(cgImage:image,size:NSSize(width:CGFloat(image.width),height:CGFloat(image.height))).draw(in:imageRect(image,in:area))
        }
    }
    private func drawTargets(on image:CGImage,in frame:NSRect){
        let picture=imageRect(image,in:previewImageArea(frame))
        guard picture.width>0,picture.height>0 else{return}
        for marker in markers {
            let point=marker.id == draggedTarget ? (dragPreview ?? marker.point):marker.point
            guard point.x>=0 && point.x<=1 && point.y>=0 && point.y<=1 else{continue}
            let square=markerRect(point,in:picture)
            if marker.id == selectedSwatchID {
                ColourTargetBarberPole.draw(in:square.insetBy(dx:-6,dy:-6),radius:2,thickness:3)
            }
            (marker.removed ? Design.hex("#D52B29"):Design.houseYellow).setStroke()
            let border=NSBezierPath(rect:square);border.lineWidth=2;border.stroke()
        }
    }
    private func markerRect(_ point:CGPoint,in picture:NSRect)->NSRect {
        let size=min(34,max(18,picture.width*0.045))
        return NSRect(x:picture.minX+point.x*picture.width-size/2,
                      y:picture.minY+point.y*picture.height-size/2,width:size,height:size)
    }
    private func marker(at position:NSPoint,in picture:NSRect)->ImagePaletteMarker? {
        markers.reversed().first { marker in
            markerRect(marker.point,in:picture).insetBy(dx:-4,dy:-4).contains(position)
        }
    }
    private func adjustedPicture()->NSRect? {
        guard let graded else{return nil}
        let picture=imageRect(graded,in:previewImageArea(previewBody(adjustedPage())))
        return picture.isEmpty ? nil:picture
    }
    private func point(in picture:NSRect,from event:NSEvent)->CGPoint {
        let position=convert(event.locationInWindow,from:nil)
        return CGPoint(x:max(0,min(1,(position.x-picture.minX)/picture.width)),
                       y:max(0,min(1,(position.y-picture.minY)/picture.height)))
    }
    override func mouseDown(with event:NSEvent){
        guard let picture=adjustedPicture() else{super.mouseDown(with:event);return}
        let position=convert(event.locationInWindow,from:nil)
        guard picture.contains(position) else{super.mouseDown(with:event);return}
        if let sampleMode {
            onSample?(point(in:picture,from:event),sampleMode)
            self.sampleMode=nil
            return
        }
        guard showsTargets else{return}
        guard let selected=marker(at:position,in:picture) else{return}
        onSelectSwatch?(selected.id)
        draggedTarget=selected.removed ? nil:selected.id
    }
    override func mouseDragged(with event:NSEvent){
        guard let id=draggedTarget,let picture=adjustedPicture(),
              let index=markers.firstIndex(where:{$0.id == id && !$0.removed})
        else{super.mouseDragged(with:event);return}
        let position=point(in:picture,from:event)
        dragPreview=position
        onMoveTarget?(index,position)
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent){
        if let id=draggedTarget,let point=dragPreview,
           let index=markers.firstIndex(where:{$0.id == id && !$0.removed}) {
            onMoveTarget?(index,point)
        }
        draggedTarget=nil;dragPreview=nil;needsDisplay=true
    }
    override func rightMouseDown(with event:NSEvent){
        guard showsTargets,let picture=adjustedPicture() else{super.rightMouseDown(with:event);return}
        let position=convert(event.locationInWindow,from:nil)
        guard let marker=marker(at:position,in:picture) else{super.rightMouseDown(with:event);return}
        onSelectSwatch?(marker.id)
        let menu=NSMenu(title:"Sample Target")
        let remove=NSMenuItem(title:"Remove from Palette",action:#selector(removeMarker(_:)),keyEquivalent:"")
        remove.target=self;remove.representedObject=marker.id.uuidString;remove.isEnabled = !marker.removed
        menu.addItem(remove)
        let restore=NSMenuItem(title:"Add to Palette",action:#selector(restoreMarker(_:)),keyEquivalent:"")
        restore.target=self;restore.representedObject=marker.id.uuidString;restore.isEnabled=marker.removed
        menu.addItem(restore)
        menu.addItem(.separator())
        let title=NSMenuItem(title:"Colour Details",action:nil,keyEquivalent:"")
        title.isEnabled=false;menu.addItem(title)
        if let hex=hexOf(marker.colour.master.display) {
            for format in Prefs.houseCardRows {
                let value=format.text(hex,lowercase:Prefs.lowercaseHex)
                let item=NSMenuItem(title:"\(format.label)  \(value)",action:#selector(copyDetail(_:)),keyEquivalent:"")
                item.target=self;item.representedObject=value;menu.addItem(item)
            }
        }
        let estimatedHeight=CGFloat(menu.items.count)*24
        let anchor=NSPoint(x:position.x > bounds.maxX-260 ? max(bounds.minX+4,position.x-245):position.x+12,
                           y:position.y < bounds.minY+estimatedHeight ? position.y+12:position.y-estimatedHeight)
        menu.popUp(positioning:nil,at:anchor,in:self)
    }
    @objc private func removeMarker(_ sender:NSMenuItem){
        guard let value=sender.representedObject as? String,let id=UUID(uuidString:value) else{return}
        onRemoveSwatch?(id)
    }
    @objc private func restoreMarker(_ sender:NSMenuItem){
        guard let value=sender.representedObject as? String,let id=UUID(uuidString:value) else{return}
        onRestoreSwatch?(id)
    }
    @objc private func copyDetail(_ sender:NSMenuItem){
        if let value=sender.representedObject as? String {copyToClipboard(value)}
    }
    override func resetCursorRects(){
        super.resetCursorRects()
        guard let picture=adjustedPicture() else{return}
        if sampleMode != nil {addCursorRect(picture,cursor:Self.dropperCursor)}
        else if showsTargets {
            for marker in markers {
                addCursorRect(markerRect(marker.point,in:picture),cursor:marker.removed ? .arrow:.openHand)
            }
        }
    }
    private static let dropperCursor:NSCursor = {
        let image=NSImage(size:NSSize(width:28,height:28))
        image.lockFocus()
        let symbol=NSImage(systemSymbolName:"eyedropper",accessibilityDescription:nil)
        NSColor.black.setFill();NSBezierPath(roundedRect:NSRect(x:2,y:2,width:24,height:24),xRadius:4,yRadius:4).fill()
        symbol?.withSymbolConfiguration(.init(pointSize:18,weight:.medium))?.draw(in:NSRect(x:5,y:5,width:18,height:18))
        image.unlockFocus()
        return NSCursor(image:image,hotSpot:NSPoint(x:5,y:22))
    }()
}

private final class ImagePaletteToolStack:NSView {
    var onPoint:(()->Void)?,onArea:(()->Void)?,onTargets:(()->Void)?
    var selected:ImagePaletteSampleMode? {didSet{refresh()}}
    var showsTargets=true {didSet{refresh()}}
    private let point=PaletteAssetIcon(frame:.zero),area=PaletteAssetIcon(frame:.zero),targets=PaletteAssetIcon(frame:.zero)
    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame)
        let options:[(PaletteAssetIcon,String,String,()->Void)]=[
            (point,"eyedropper","Sample Pixel and Add Swatch",{ [weak self] in self?.onPoint?() }),
            (area,"square.dashed","Average Area and Add Swatch",{ [weak self] in self?.onArea?() }),
            (targets,"viewfinder","Show or Hide Sample Targets",{ [weak self] in self?.onTargets?() })
        ]
        for (button,symbol,label,action) in options {
            button.symbol=symbol;button.matchesHeaderGlyph=true;button.outlinedSquare=true
            button.run=action
            button.toolTip=label;button.setAccessibilityLabel(label);addSubview(button)
        }
        refresh()
    }
    required init?(coder:NSCoder){fatalError()}
    private func refresh(){
        point.selectedSquare=selected == .point
        area.selectedSquare=selected == .area
        targets.selectedSquare = !showsTargets
    }
    override func layout(){
        super.layout()
        point.frame=NSRect(x:2,y:2,width:32,height:32)
        area.frame=NSRect(x:2,y:38,width:32,height:32)
        targets.frame=NSRect(x:2,y:74,width:32,height:32)
    }
}

private final class ImagePaletteSourceChooser:NSView {
    private final class CardCanvas:NSView {override var isFlipped:Bool {true}}
    struct ImageRecord {let url:URL;let name:String}
    struct Location {let id:String;let section:String;let title:String;let records:[ImageRecord]}
    var onImport:(()->Void)?
    var onChooseImage:((URL,String)->Void)?
    var locations:[Location]=[] {didSet{
        if let selectedID,
           !locations.contains(where:{$0.id == selectedID || String($0.id.prefix{ $0 != "/" }) == selectedID}) {
            self.selectedID=nil
        }
        navigation.locations=locations;navigation.selectedID=selectedID
        showSelection()
    }}
    private var selectedID:String?
    private let diskButton=WorkspaceImportActionButton(frame:.zero)
    private let sourceHeading=Design.text("Source Directories",.bodyStrong)
    private let navigation=ImagePaletteLocationList()
    private let navigationScroll=FittedScrollView()
    private let grid=CardCanvas(frame:.zero)
    private let gridScroll=FittedScrollView()
    private let title=Design.text("Choose an Image",.bodyStrong)
    private let emptyLabel=Design.text("",.body)
    private var cards:[ImagePaletteImageCard]=[]
    private var folderButtons:[WorkspaceImportActionButton]=[]
    private var cardByPath:[String:ImagePaletteImageCard]=[:]
    private let thumbnails=NSCache<NSString,NSImage>()
    private var pending=Set<String>(),failed=Set<String>()
    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame)
        diskButton.title="Import from Disk";diskButton.symbol="square.and.arrow.down"
        diskButton.setAccessibilityLabel("Import Image from Disk")
        diskButton.target=self;diskButton.action=#selector(importPressed)
        navigation.onSelect={ [weak self] id in
            self?.selectedID=id;self?.navigation.selectedID=id;self?.showSelection()
        }
        for scroll in [navigationScroll,gridScroll] {
            scroll.drawsBackground=false;scroll.hasVerticalScroller=false;scroll.autohidesScrollers=false
            scroll.verticalScrollElasticity = .none
            QuietScroller.install(in:scroll)
        }
        navigationScroll.documentView=navigation
        grid.addSubview(emptyLabel)
        gridScroll.documentView=grid
        thumbnails.countLimit=128
        for view in [sourceHeading,diskButton,navigationScroll,title,gridScroll] {addSubview(view)}
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func importPressed(){onImport?()}
    func clearSelection(){selectedID=nil;navigation.selectedID=nil;showSelection()}
    private func showSelection(){
        let location=locations.first{$0.id == selectedID}
        let children=location == nil ? locations.filter{String($0.id.prefix{ $0 != "/" }) == selectedID}:[]
        title.stringValue=location.map{"\($0.section) · \($0.title)"}
            ?? children.first?.section ?? "Choose an Image"
        cards.forEach{$0.removeFromSuperview()}
        folderButtons.forEach{$0.removeFromSuperview()}
        cards=[];folderButtons=[];cardByPath=[:]
        for child in children {
            let button=WorkspaceImportActionButton(frame:.zero)
            button.symbol=child.title == "Photographs" ? "camera":"photo"
            button.title="\(child.title) · \(child.records.count)"
            button.identifier=NSUserInterfaceItemIdentifier(child.id)
            button.setAccessibilityLabel("Open \(child.title) in \(child.section)")
            button.target=self;button.action=#selector(openFolder(_:))
            grid.addSubview(button);folderButtons.append(button)
        }
        for record in location?.records ?? [] {
            let card=ImagePaletteImageCard(name:record.name)
            card.onUse={ [weak self] in self?.onChooseImage?(record.url,record.name) }
            card.image=thumbnail(record.url.path)
            grid.addSubview(card);cards.append(card);cardByPath[record.url.path]=card
        }
        emptyLabel.stringValue=location == nil ? "Import an image from disk or choose a location." : location?.records.isEmpty == true ? "No \(location!.title.lowercased()) in this location." : ""
        emptyLabel.isHidden = !cards.isEmpty || !folderButtons.isEmpty
        resizeGrid()
        gridScroll.contentView.scroll(to:.zero)
        gridScroll.reflectScrolledClipView(gridScroll.contentView)
        needsDisplay=true
    }
    @objc private func openFolder(_ sender:NSButton){
        guard let id=sender.identifier?.rawValue else{return}
        selectedID=id;navigation.selectedID=id;showSelection()
    }
    private func thumbnail(_ path:String)->NSImage? {
        if let image=thumbnails.object(forKey:path as NSString){return image}
        guard !pending.contains(path),!failed.contains(path) else{return nil}
        pending.insert(path)
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let image=ImagePaletteExtractor.decode(URL(fileURLWithPath:path),maximumSide:360)
                .map{NSImage(cgImage:$0,size:NSSize(width:$0.width,height:$0.height))}
            DispatchQueue.main.async { [weak self] in
                guard let self else{return}
                self.pending.remove(path)
                if let image {self.thumbnails.setObject(image,forKey:path as NSString);self.cardByPath[path]?.image=image}
                else {self.failed.insert(path)}
            }
        }
        return nil
    }
    private func resizeGrid(){
        let naturalHeight=cardLayout(for:max(1,gridScroll.bounds.width)).height
        let overflow=naturalHeight > gridScroll.bounds.height+0.5
        if gridScroll.hasVerticalScroller != overflow {gridScroll.hasVerticalScroller=overflow;gridScroll.tile()}
        let width=max(1,gridScroll.contentSize.width)
        let measure=cardLayout(for:width)
        let size=NSSize(width:width,height:max(gridScroll.contentSize.height,measure.height))
        if grid.frame.size != size {grid.setFrameSize(size)}
        emptyLabel.frame=NSRect(x:12,y:12,width:max(0,width-24),height:32)
        for (index,button) in folderButtons.enumerated() {
            button.frame=NSRect(x:12,y:12+CGFloat(index)*50,width:min(320,max(0,width-24)),height:38)
        }
        for (index,card) in cards.enumerated() {
            let column=index % measure.columns,row=index / measure.columns
            card.frame=NSRect(x:12+CGFloat(column)*(measure.cardWidth+12),y:12+CGFloat(row)*286,
                              width:measure.cardWidth,height:274)
        }
    }
    private func cardLayout(for width:CGFloat)->(columns:Int,cardWidth:CGFloat,height:CGFloat){
        let usable=max(1,width-24)
        let columns=max(1,Int((usable+12)/252))
        let cardWidth=max(1,(usable-CGFloat(columns-1)*12)/CGFloat(columns))
        let rows=(cards.count+columns-1)/columns
        let height=folderButtons.isEmpty ? (rows == 0 ? 56:CGFloat(rows)*286+12)
            : CGFloat(folderButtons.count)*50+12
        return (columns,cardWidth,height)
    }
    override func layout(){
        super.layout()
        let gap:CGFloat=12
        let navWidth=min(300,max(220,bounds.width*0.31))
        let rightX=navWidth+gap
        let rightWidth=max(0,bounds.width-rightX)
        let buttonWidth=min(260,max(0,navWidth-24))
        diskButton.frame=NSRect(x:(navWidth-buttonWidth)/2,y:max(0,bounds.height-50),width:buttonWidth,height:38)
        sourceHeading.frame=NSRect(x:16,y:14,width:max(0,navWidth-32),height:24)
        navigationScroll.frame=NSRect(x:6,y:46,width:max(0,navWidth-12),height:max(0,bounds.height-108))
        let navOverflow=navigation.contentHeight > navigationScroll.bounds.height+0.5
        if navigationScroll.hasVerticalScroller != navOverflow {navigationScroll.hasVerticalScroller=navOverflow;navigationScroll.tile()}
        navigation.resize(to:navigationScroll.contentSize.width)
        title.frame=NSRect(x:rightX+12,y:12,width:max(0,rightWidth-24),height:24)
        gridScroll.frame=NSRect(x:rightX+1,y:48,width:max(0,rightWidth-2),height:max(0,bounds.height-49))
        gridScroll.tile();resizeGrid()
    }
    override func draw(_ dirtyRect:NSRect){
        Design.card.setFill();bounds.fill()
        let navWidth=min(300,max(220,bounds.width*0.31)),gap:CGFloat=12
        Design.rule.setStroke()
        NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)).stroke()
        NSBezierPath(rect:NSRect(x:navWidth+gap+0.5,y:0.5,width:max(0,bounds.width-navWidth-gap-1),height:max(0,bounds.height-1))).stroke()
    }
}

private final class ImagePaletteImageCard:NSView {
    var image:NSImage? {didSet{preview.image=image}}
    var onUse:(()->Void)?
    private let preview=NSImageView(frame:.zero)
    private let nameLabel:NSTextField
    private let useButton=WorkspaceImportActionButton(frame:.zero)
    override var isFlipped:Bool {true}
    init(name:String){
        nameLabel=Design.text(name,.bodyStrong)
        super.init(frame:.zero)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.toolTip=name
        preview.imageScaling = .scaleProportionallyUpOrDown
        useButton.symbol="arrow.up.right";useButton.title="Use Image"
        useButton.setAccessibilityLabel("Use Image: \(name)")
        useButton.target=self;useButton.action=#selector(usePressed)
        [preview,nameLabel,useButton].forEach(addSubview)
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func usePressed(){onUse?()}
    override func layout(){
        super.layout()
        preview.frame=NSRect(x:12,y:12,width:max(0,bounds.width-24),height:174)
        nameLabel.frame=NSRect(x:12,y:195,width:max(0,bounds.width-24),height:24)
        useButton.frame=NSRect(x:12,y:226,width:max(0,bounds.width-24),height:38)
    }
    override func draw(_ dirtyRect:NSRect){
        Design.card.setFill();bounds.fill()
        Design.rule.setStroke()
        NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)).stroke()
        NSBezierPath(rect:preview.frame.insetBy(dx:0.5,dy:0.5)).stroke()
    }
}

private final class ImagePaletteLocationList:NSView,NSOutlineViewDataSource,NSOutlineViewDelegate {
    private final class Node:NSObject {
        let title:String,id:String?,symbol:String,appearanceKey:String?
        let isRoot:Bool
        var count:Int
        var children:[Node]=[]
        init(_ title:String,id:String?,count:Int,symbol:String,appearanceKey:String?=nil,isRoot:Bool=false){
            self.title=title;self.id=id;self.count=count;self.symbol=symbol
            self.appearanceKey=appearanceKey;self.isRoot=isRoot
        }
    }
    var locations:[ImagePaletteSourceChooser.Location]=[] {didSet{rebuild()}}
    var selectedID:String? {didSet{selectCurrent()}}
    var onSelect:((String)->Void)?
    private let tree=WorkspaceBranchTree()
    private var roots:[Node]=[]
    private var updating=false
    var contentHeight:CGFloat {max(1,CGFloat(tree.numberOfRows)*(tree.rowHeight+WorkspaceBranchTree.rowSpacing))}
    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame)
        let column=NSTableColumn(identifier:NSUserInterfaceItemIdentifier("Image Palette Sources"))
        tree.addTableColumn(column);tree.outlineTableColumn=column;tree.headerView=nil
        tree.rowHeight=34;tree.indentationPerLevel=0
        tree.intercellSpacing=NSSize(width:0,height:WorkspaceBranchTree.rowSpacing)
        tree.backgroundColor=Design.card;tree.appearance=Theme.appearance;tree.style = .plain
        tree.leadingDisclosure=true;tree.showsConnectors=true;tree.expandsOnSelection=false
        tree.selectedBarberPole=true
        tree.rootConnectorBreak={item in (item as? Node)?.title == "My Library"}
        tree.rowColour={item in
            guard let node=item as? Node else{return nil}
            let assigned=node.appearanceKey.flatMap(WorkspaceNodeAppearance.colour)
            return node.isRoot ? assigned ?? WorkspaceBranchTree.tint(3):assigned
        }
        tree.rowInk={item in
            guard let node=item as? Node else{return nil}
            return node.appearanceKey.flatMap(WorkspaceNodeAppearance.ink) ?? (node.isRoot ? .white:Design.ink)
        }
        tree.rowBorder={item in (item as? Node)?.appearanceKey.flatMap(WorkspaceNodeAppearance.borderColour)}
        tree.rowClear={item in
            guard let node=item as? Node else{return false}
            return !node.isRoot && node.appearanceKey.flatMap(WorkspaceNodeAppearance.colour) == nil
        }
        tree.dataSource=self;tree.delegate=self;tree.focusRingType = .none
        tree.setAccessibilityLabel("Image Palette Sources")
        addSubview(tree);tree.installConnectors(in:self)
    }
    required init?(coder:NSCoder){fatalError()}
    private func rebuild(){
        var groups:[String:Node]=[:]
        roots=[]
        for location in locations {
            let owner=String(location.id.prefix{ $0 != "/" })
            let group:Node
            if let existing=groups[owner] {group=existing}
            else {
                let appearanceKey:String? = owner == "library" ? "catalogue":UUID(uuidString:owner).map{String(describing:StudioFrame.Place.project($0))}
                group=Node(location.section,id:owner,count:0,symbol:"folder",appearanceKey:appearanceKey,isRoot:true)
                groups[owner]=group;roots.append(group)
            }
            group.count += location.records.count
            let childKey=owner == "library" ? (location.title == "Photographs" ? "mylibrary-photography":"mylibrary-images"):nil
            group.children.append(Node(location.title,id:location.id,count:location.records.count,
                                       symbol:location.title == "Photographs" ? "camera":"photo",appearanceKey:childKey))
        }
        updating=true;tree.reloadData()
        for root in roots {tree.expandItem(root)}
        updating=false;selectCurrent();resize(to:bounds.width)
    }
    private func selectCurrent(){
        guard !updating else{return}
        guard let selectedID else {
            if tree.selectedRow >= 0 {updating=true;tree.deselectAll(nil);updating=false}
            tree.refreshSurfaces()
            return
        }
        for row in 0..<tree.numberOfRows {
            guard let node=tree.item(atRow:row) as? Node,node.id == selectedID else{continue}
            if tree.selectedRow != row {updating=true;tree.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);updating=false}
            break
        }
        tree.refreshSurfaces()
    }
    func resize(to width:CGFloat){
        let size=NSSize(width:max(1,width),height:contentHeight)
        if frame.size != size {setFrameSize(size)}
        tree.frame=bounds;tree.tableColumns.first?.width=tree.bounds.width
        tree.layoutConnectors();tree.refreshSurfaces()
    }
    override func layout(){super.layout();tree.frame=bounds;tree.layoutConnectors()}
    func outlineView(_ outlineView:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int {
        (item as? Node)?.children.count ?? roots.count
    }
    func outlineView(_ outlineView:NSOutlineView,child index:Int,ofItem item:Any?)->Any {
        (item as? Node)?.children[index] ?? roots[index]
    }
    func outlineView(_ outlineView:NSOutlineView,isItemExpandable item:Any)->Bool {
        !(item as! Node).children.isEmpty
    }
    func outlineView(_ outlineView:NSOutlineView,rowViewForItem item:Any)->NSTableRowView? {
        let row=WorkspaceBranchTree.Row();row.accordion=tree;return row
    }
    func outlineView(_ outlineView:NSOutlineView,viewFor tableColumn:NSTableColumn?,item:Any)->NSView? {
        let node=item as! Node
        let cell=WorkspaceBranchTree.Cell(frame:NSRect(x:0,y:0,width:tree.bounds.width,height:34))
        cell.leadingDisclosure=true;cell.symbol=node.symbol
        cell.star.isHidden=true
        cell.countLabel.stringValue=node.count == 0 ? "(0)":String(node.count)
        cell.countLabel.isHidden=false
        let label=NSTextField(labelWithString:node.title)
        label.font=Design.Text.body.font();label.lineBreakMode = .byTruncatingTail
        cell.addSubview(label);cell.textField=label;cell.toolTip=node.title
        return cell
    }
    func outlineView(_ outlineView:NSOutlineView,shouldSelectItem item:Any)->Bool {
        (item as? Node)?.id != nil
    }
    func outlineViewSelectionDidChange(_ notification:Notification){
        guard !updating,tree.selectedRow >= 0,
              let id=(tree.item(atRow:tree.selectedRow) as? Node)?.id else{return}
        onSelect?(id);tree.refreshSurfaces()
    }
    func outlineViewItemDidExpand(_ notification:Notification){tree.refreshSurfaces();resize(to:bounds.width)}
    func outlineViewItemDidCollapse(_ notification:Notification){tree.refreshSurfaces();resize(to:bounds.width)}
}

private final class ImagePaletteSwatches:NSView {
    var active:[ImagePaletteSwatch]=[] {didSet{document.active=active;needsLayout=true}}
    var removed:[ImagePaletteSwatch]=[] {didSet{document.removed=removed;needsLayout=true}}
    var onRemove:((UUID)->Void)? {didSet{document.onRemove=onRemove}}
    var onRestore:((UUID)->Void)? {didSet{document.onRestore=onRestore}}
    var onReorder:((UUID,Int)->Void)? {didSet{document.onReorder=onReorder}}
    var onSelect:((UUID)->Void)? {didSet{document.onSelect=onSelect}}
    var selectedSwatchID:UUID? {didSet{document.selectedSwatchID=selectedSwatchID}}
    private let scroll=FittedScrollView()
    private let document=ImagePaletteSwatchDocument()
    override var isFlipped:Bool {true}
    override init(frame:NSRect){
        super.init(frame:frame)
        scroll.drawsBackground=false;scroll.hasVerticalScroller=false;scroll.autohidesScrollers=false
        scroll.verticalScrollElasticity = .none
        QuietScroller.install(in:scroll)
        scroll.documentView=document
        addSubview(scroll)
    }
    required init?(coder:NSCoder){fatalError()}
    func contentHeight(for width:CGFloat)->CGFloat {
        ImagePaletteSwatchDocument.height(for:width,active:active.count,removed:removed.count)
    }
    override func layout(){
        super.layout()
        scroll.frame=NSRect(x:0,y:1,width:bounds.width,height:max(0,bounds.height-1))
        let overflow=contentHeight(for:bounds.width) > scroll.bounds.height+0.5
        if scroll.hasVerticalScroller != overflow {scroll.hasVerticalScroller=overflow}
        scroll.tile()
        document.resize(to:scroll.contentSize.width)
    }
    override func draw(_ dirtyRect:NSRect){
        Design.card.setFill();bounds.fill()
        Design.rule.setStroke()
        let separator=NSBezierPath();separator.move(to:NSPoint(x:0,y:0.5))
        separator.line(to:NSPoint(x:bounds.width,y:0.5));separator.stroke()
    }
}
private final class ImagePaletteSwatchDocument:NSView {
    var active:[ImagePaletteSwatch]=[] {didSet{updateContent()}}
    var removed:[ImagePaletteSwatch]=[] {didSet{updateContent()}}
    var onRemove:((UUID)->Void)?,onRestore:((UUID)->Void)?,onReorder:((UUID,Int)->Void)?,onSelect:((UUID)->Void)?
    var selectedSwatchID:UUID? {didSet{needsDisplay=true}}
    private var columns=1,cellWidth:CGFloat=160
    private var actionButtons:[NSButton]=[]
    private var draggedID:UUID?,dragDestination:Int?,dragStarted=false
    override var isFlipped:Bool {true}
    static func height(for width:CGFloat,active:Int,removed:Int)->CGFloat {
        let columns=max(1,Int((max(100,width-32)+8)/176))
        func rows(_ count:Int)->Int {max(1,Int(ceil(Double(count)/Double(columns))))}
        let main=24+CGFloat(rows(active))*76
        return max(104,12+main+(removed > 0 ? 32+CGFloat(rows(removed))*76:0)+12)
    }
    private func updateContent(){resize(to:bounds.width);needsDisplay=true}
    func resize(to width:CGFloat){
        let usable=max(100,width-32)
        columns=max(1,Int((usable+8)/176))
        cellWidth=max(64,(usable-CGFloat(columns-1)*8)/CGFloat(columns))
        let height=Self.height(for:width,active:active.count,removed:removed.count)
        if abs(frame.width-width)>0.5 || abs(frame.height-height)>0.5 {setFrameSize(NSSize(width:width,height:height))}
        refreshButtons()
        needsDisplay=true
    }
    private var removedTop:CGFloat {
        12+24+CGFloat(max(1,Int(ceil(Double(active.count)/Double(columns)))))*76+32
    }
    private func tile(_ index:Int,removed:Bool)->NSRect {
        let top:CGFloat=removed ? removedTop:36
        return NSRect(x:16+CGFloat(index%columns)*(cellWidth+8),
                      y:top+CGFloat(index/columns)*76,width:cellWidth,height:68)
    }
    private func refreshButtons(){
        actionButtons.forEach{$0.removeFromSuperview()};actionButtons=[]
        for (isRemoved,items) in [(false,active),(true,removed)] {
            for (index,item) in items.enumerated() {
                let button=NSButton(frame:.zero)
                button.isBordered=false;button.imagePosition = .imageOnly
                let symbol=isRemoved ? "arrow.uturn.backward":"xmark"
                let label=isRemoved ? "Restore Swatch":"Remove Swatch"
                button.image=NSImage(systemSymbolName:symbol,accessibilityDescription:label)
                button.contentTintColor=Design.ink
                button.setAccessibilityLabel(label)
                button.toolTip=label
                button.identifier=NSUserInterfaceItemIdentifier(item.id.uuidString)
                button.target=self;button.action=isRemoved ? #selector(restorePressed(_:)):#selector(removePressed(_:))
                let rect=tile(index,removed:isRemoved)
                button.frame=NSRect(x:rect.maxX-23,y:rect.maxY-22,width:22,height:22)
                addSubview(button);actionButtons.append(button)
            }
        }
    }
    @objc private func removePressed(_ sender:NSButton){
        guard let id=sender.identifier.flatMap({UUID(uuidString:$0.rawValue)}) else{return}
        onRemove?(id)
    }
    @objc private func restorePressed(_ sender:NSButton){
        guard let id=sender.identifier.flatMap({UUID(uuidString:$0.rawValue)}) else{return}
        onRestore?(id)
    }
    private func rgb(_ colour:ColourDefinition)->String {
        let value=colour.master.display.usingColorSpace(.deviceRGB) ?? colour.master.display
        return String(format:"R %d  G %d  B %d",Int((value.redComponent*255).rounded()),
                      Int((value.greenComponent*255).rounded()),Int((value.blueComponent*255).rounded()))
    }
    private func drawSection(_ items:[ImagePaletteSwatch],removed isRemoved:Bool){
        for (index,item) in items.enumerated() {
            let rect=tile(index,removed:isRemoved)
            let swatch=NSRect(x:rect.minX,y:rect.minY,width:rect.width,height:44)
            if item.id == selectedSwatchID {
                ColourTargetBarberPole.draw(in:swatch.insetBy(dx:-4,dy:-4),radius:2,thickness:3)
            }
            item.colour.master.display.setFill();swatch.fill()
            Design.rule.setStroke();NSBezierPath(rect:swatch).stroke()
            let label=rgb(item.colour)
            Design.attributed(label,.caption,colour:Design.ink)
                .draw(in:NSRect(x:rect.minX,y:rect.minY+47,width:max(0,rect.width-28),height:18))
            if !isRemoved,draggedID == item.id {
                (dragDestination == index ? Design.houseYellow:Design.ink).setStroke()
                let outline=NSBezierPath(rect:swatch.insetBy(dx:-2,dy:-2));outline.lineWidth=2;outline.stroke()
            } else if !isRemoved,dragDestination == index,draggedID != nil {
                Design.houseYellow.setStroke()
                let outline=NSBezierPath(rect:swatch.insetBy(dx:-2,dy:-2));outline.lineWidth=2;outline.stroke()
            }
        }
    }
    override func draw(_ dirtyRect:NSRect){
        Design.card.setFill();bounds.fill()
        Design.attributed("Generated Palette",.bodyStrong,colour:Design.ink)
            .draw(in:NSRect(x:16,y:12,width:max(0,bounds.width-32),height:20))
        if active.isEmpty {
            Design.attributed("No swatches in the palette.",.body,colour:Design.quiet)
                .draw(in:NSRect(x:16,y:40,width:max(0,bounds.width-32),height:22))
        } else {drawSection(active,removed:false)}
        if !removed.isEmpty {
            Design.attributed("Removed Swatches",.bodyStrong,colour:Design.ink)
                .draw(in:NSRect(x:16,y:removedTop-28,width:max(0,bounds.width-32),height:20))
            drawSection(removed,removed:true)
        }
    }
    override func mouseDown(with event:NSEvent){
        let point=convert(event.locationInWindow,from:nil)
        draggedID=active.enumerated().first(where:{tile($0.offset,removed:false).contains(point)})?.element.id
        let selected=draggedID ?? removed.enumerated().first(where:{tile($0.offset,removed:true).contains(point)})?.element.id
        if let selected {onSelect?(selected)}
        dragDestination=nil;dragStarted=false
    }
    override func mouseDragged(with event:NSEvent){
        guard draggedID != nil,!active.isEmpty else{return}
        dragStarted=true
        let point=convert(event.locationInWindow,from:nil)
        let nearest=active.indices.min{lhs,rhs in
            abs(tile(lhs,removed:false).midX-point.x)+abs(tile(lhs,removed:false).midY-point.y)
            < abs(tile(rhs,removed:false).midX-point.x)+abs(tile(rhs,removed:false).midY-point.y)
        }
        dragDestination=nearest;needsDisplay=true
    }
    override func mouseUp(with event:NSEvent){
        if dragStarted,let id=draggedID,let destination=dragDestination {onReorder?(id,destination)}
        draggedID=nil;dragDestination=nil;dragStarted=false;needsDisplay=true
    }
}
