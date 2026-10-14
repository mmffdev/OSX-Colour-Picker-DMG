import AppKit
import UniformTypeIdentifiers

/// Both the PrePress controls and palette header consume the same .coldata profile list.
final class PrintProfileSelector:NSView,Overlay {
    var dismissOnOutsideClick:Bool{true}
    func handleOverlayEscape()->Bool{dismissOverlay();return true}
    func containsOverlayEvent(_ event:NSEvent)->Bool{
        if event.window === dropped{return true}
        return event.window === window && bounds.contains(convert(event.locationInWindow,from:nil))
    }
    var opensUpward=false { didSet { button.opensUpward=opensUpward;button.needsDisplay=true } }
    var preferredControlWidth:CGFloat { ceil(Design.attributed(button.title,.body).size().width)+48 }
    let compact:Bool
    private let button=PrintProfileValueButton()
    private var dropped:SwissDropdown.MenuPanel?
    private var document=SavedPrintProfiles.Document()
    var overlayWindows:[NSWindow]{dropped.map{[$0]} ?? []}
    init(compact:Bool=false){self.compact=compact;super.init(frame:.zero);button.compact=compact;button.target=self;button.action=#selector(open);addSubview(button);NotificationCenter.default.addObserver(self,selector:#selector(reload),name:.printProfilesChanged,object:nil);reload()}
    required init?(coder:NSCoder){fatalError()}
    deinit{NotificationCenter.default.removeObserver(self)}
    override var isFlipped:Bool{true}
    @objc func reload(){do{document=try SavedPrintProfiles.load();button.title=document.profiles.first{$0.id==document.selected}?.name ?? "Current Settings"}catch{button.title="Profiles Unavailable"};button.setAccessibilityLabel("Print Profile: "+button.title);needsDisplay=true;superview?.needsLayout=true}
    override func layout(){super.layout();button.frame=NSRect(x:0,y:compact ? 0:18,width:bounds.width,height:compact ? bounds.height:38)}
    override func draw(_ dirtyRect:NSRect){if !compact{Design.attributed("Saved Print Profile",.caption,colour:Design.quiet).draw(x:0,baseline:11,width:bounds.width)}}
    func dismissOverlay(){if let dropped{dropped.parent?.removeChildWindow(dropped);dropped.orderOut(nil)};dropped=nil;Overlays.closed(self)}
    @objc private func open(){
        if dropped != nil {dismissOverlay();return}
        guard let window else{return};do{document=try SavedPrintProfiles.load()}catch{NSApp.presentError(error);return};dismissOverlay()
        let actions=["Save Profile…","Edit Profile…","Duplicate Profile","Remove Profile…","Import Profile…","Export Profile…"]
        let labels=actions+["#Saved Profiles","Current Settings"]+document.profiles.map{$0.name}
        let profiles=document.profiles,chosen=profiles.first{$0.id==document.selected}?.name ?? "Current Settings"
        let panel=SwissDropdown.MenuPanel(items:labels,chosen:chosen,width:max(260,bounds.width)){[weak self] i in
            guard let self else{return};self.dismissOverlay()
            do{switch i{
            case 0:self.editor(nil,settings:self.document.current)
            case 1:if let p=self.selected{self.editor(p,settings:p.settings)}
            case 2:if let id=self.document.selected{try SavedPrintProfiles.duplicate(id)}
            case 3:if let p=self.selected{self.confirmRemoval(p)}
            case 4:self.importFile()
            case 5:self.exportFile()
            case 7:try SavedPrintProfiles.setCurrent(self.document.current)
            default:if i>=8,profiles.indices.contains(i-8){try SavedPrintProfiles.select(profiles[i-8].id)}
            }}catch{NSApp.presentError(error)};self.reload()
        }
        panel.configure(disabled:document.selected == nil ? [1,2,3,6]:[6])
        let screen=window.convertToScreen(convert(button.frame,to:nil));if opensUpward { panel.place(above:NSPoint(x:screen.maxX-panel.frame.width,y:screen.maxY+4)) } else { panel.place(below:NSPoint(x:screen.minX,y:screen.minY-4)) };window.addChildWindow(panel,ordered:.above);dropped=panel;Overlays.opened(self)
    }
    private var selected:SavedPrintProfile?{document.profiles.first{$0.id==document.selected}}
    private func editor(_ original:SavedPrintProfile?,settings:PrintProfileSettings){
        let modal=SwissFocusModal(title:original == nil ? "Save Print Profile":"Edit Print Profile",message:"Keep these printing settings together for use across your palettes.")
        let name=modal.field("Profile Name",value:original?.name ?? "Print Profile"),description=modal.field("Description",value:original?.description ?? "")
        let form=PrintProfileForm(settings:settings);modal.content(form,height:224)
        modal.button("Cancel"){[weak modal] in modal?.dismissOverlay()}
        modal.button("Save Profile",primary:true){[weak modal] in
            do{var p=original ?? SavedPrintProfile(name:"",description:"",settings:form.settings);p.name=name.stringValue;p.description=description.stringValue;p.settings=form.settings;try SavedPrintProfiles.save(p);modal?.dismissOverlay()}catch{NSApp.presentError(error)}
        };modal.present(over:self)
    }
    private func confirmRemoval(_ p:SavedPrintProfile){
        let modal=SwissFocusModal(title:"Remove Print Profile",message:"Remove “"+p.name+"” from your saved profiles. The current printing settings remain available as Current Settings.")
        let slider=SwissSlide();slider.words="Slide To Remove Profile";modal.content(slider,height:SwissSlide.height)
        slider.onArmed={ [weak modal] armed in guard armed else{return};do{try SavedPrintProfiles.remove(p.id);modal?.dismissOverlay()}catch{NSApp.presentError(error)} }
        modal.button("Keep Profile"){[weak modal] in modal?.dismissOverlay()};modal.present(over:self)
    }
    private var fileType:UTType{UTType(filenameExtension:"colpro") ?? UTType(exportedAs:"com.mmffdev.colorgain.print-profile",conformingTo:.json)}
    private func importFile(){let panel=NSOpenPanel();panel.allowedContentTypes=[fileType];panel.allowsMultipleSelection=false;panel.begin{reply in guard reply == .OK,let url=panel.url else{return};do{let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0;guard size<=65536 else{throw failure("Choose a .colpro profile under 64 KB.")};try SavedPrintProfiles.importProfile(Data(contentsOf:url))}catch{NSApp.presentError(error)}}}
    private func exportFile(){let p=selected ?? SavedPrintProfile(name:"Current Print Settings",description:"",settings:document.current);let panel=NSSavePanel();panel.allowedContentTypes=[fileType];panel.nameFieldStringValue=filesystemName(p.name)+".colpro";panel.begin{reply in guard reply == .OK,let url=panel.url else{return};do{try SavedPrintProfiles.export(p).write(to:url,options:.atomic)}catch{NSApp.presentError(error)}}}
}
private final class PrintProfileValueButton:NSButton {
    var compact=false
    var opensUpward=false
    override init(frame:NSRect){super.init(frame:frame);isBordered=false;alignment = .left}
    required init?(coder:NSCoder){fatalError()}
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        let hover=window.map{bounds.contains(convert($0.mouseLocationOutsideOfEventStream,from:nil))} ?? false
        DropdownSkin.draw(in:bounds,hover:hover || isHighlighted,up:opensUpward)
        Design.attributed(title,.body,colour:Design.ink).draw(x:8,baseline:bounds.midY+4,width:max(0,bounds.width-44))
    }
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self))}
    override func mouseEntered(with event:NSEvent){needsDisplay=true}
    override func mouseExited(with event:NSEvent){needsDisplay=true}
}
private final class PrintProfileForm:NSView {
    var settings:PrintProfileSettings
    private var menus:[SwissDropdown]=[]
    init(settings:PrintProfileSettings){self.settings=settings;super.init(frame:.zero)
        func menu(_ label:String,_ value:String,_ options:[String],change:@escaping(String)->Void){let m=SwissDropdown(label,value:value,options:options,allowsOwn:false,width:448);m.onChange=change;menus.append(m);addSubview(m)}
        menu("Printing Condition",settings.press,PressProfiles.all.map{$0.name}){[weak self] in self?.settings.press=$0}
        menu("Rendering Intent",settings.intent.name,RenderingIntent.allCases.map{$0.name}){[weak self] name in self?.settings.intent=RenderingIntent.allCases.first{$0.name==name} ?? .relative}
        menu("Black Point Compensation",settings.blackPoint ? "On":"Off",["Off","On"]){[weak self] in self?.settings.blackPoint=$0=="On"}
        let values=Array(Set(PrePressPage.tolerances+[settings.tolerance])).sorted()
        menu("ΔE00 Tolerance",PrePressPage.toleranceName(settings.tolerance),values.map(PrePressPage.toleranceName)){[weak self] name in self?.settings.tolerance=values.first{PrePressPage.toleranceName($0)==name} ?? 2}
    }
    required init?(coder:NSCoder){fatalError()}
    override var isFlipped:Bool{true}
    override func layout(){super.layout();for(i,m)in menus.enumerated(){for c in m.constraints where c.firstAttribute == .width{c.constant=bounds.width};m.frame=NSRect(x:0,y:CGFloat(i)*56,width:bounds.width,height:56)}}
}
