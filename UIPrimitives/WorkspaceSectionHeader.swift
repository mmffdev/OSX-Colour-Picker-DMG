import AppKit

/// Flat, full-width sub-panel header for Library and Import. The outer panel alone owns the gradient.
/// A preference key opts into persisted disclosure; transient sections omit it.
final class WorkspaceSectionHeader:ClickCursorButton {
    static let height:CGFloat=WorkspacePanel.headerHeight
    private let preferenceKey:String?
    private let help:Help_HexButton?
    private let actionButton=ClickCursorButton()
    var trailingControl:NSView? {didSet{oldValue?.removeFromSuperview();if let trailingControl{addSubview(trailingControl)};needsLayout=true}}
    private var headerAction:(()->Void)?
    var onContext:((NSPoint,NSView)->Void)?
    var changed:(()->Void)?
    var expanded:Bool {get{state == .on} set{state=newValue ? .on:.off;needsDisplay=true}}
    func restoreLayoutPreference(){guard let preferenceKey else{return};expanded = !AppPreferences.shared.bool(forKey:preferenceKey);changed?()}
    override var isFlipped:Bool {true}
    init(_ title:String,key:String?=nil,helpPage:String?=nil,helpSection:String?=nil){
        preferenceKey=key
        if let page=helpPage ?? (key == nil ? nil:"catalogues") {
            let anchor=helpSection ?? (key?.contains("Catalogues") == true ? "catalogues":key?.contains("Favs") == true ? "favourites":key?.contains("Folders") == true ? "folders":"my-palettes")
            help=Help_HexButton(page:page,section:anchor,title:title)
        } else {help=nil}
        super.init(frame:.zero)
        self.title=title;isBordered=false;setButtonType(.onOff)
        expanded=key.map{!AppPreferences.shared.bool(forKey:$0)} ?? true
        target=self;action=#selector(toggled);setAccessibilityLabel(title+" section")
        actionButton.isBordered=false;actionButton.imagePosition = .imageOnly
        actionButton.target=self;actionButton.action=#selector(runHeaderAction);actionButton.isHidden=true
        addSubview(actionButton)
        if let help {addSubview(help);setAccessibilityCustomActions([NSAccessibilityCustomAction(name:"Help: "+title,handler:{ [weak self] in guard let help=self?.help else{return false};help.performClick(nil);return true })])}
    }
    required init?(coder:NSCoder){fatalError()}
    override func mouseDown(with event:NSEvent){
        let point=convert(event.locationInWindow,from:nil)
        if let help,help.frame.contains(point){help.performClick(nil);return}
        if let control=trailingControl,control.frame.contains(point){control.mouseDown(with:event);return}
        if !actionButton.isHidden,actionButton.frame.contains(point){actionButton.performClick(nil);return}
        super.mouseDown(with:event)
    }
    override func rightMouseDown(with event:NSEvent){
        if let onContext {onContext(convert(event.locationInWindow,from:nil),self)}
        else {super.rightMouseDown(with:event)}
    }
    @objc private func toggled(){if let preferenceKey{AppPreferences.shared.set(!expanded,forKey:preferenceKey)};changed?()}
    func setAction(symbol:String,title:String,run:@escaping()->Void){
        headerAction=run;actionButton.image=NSImage(systemSymbolName:symbol,accessibilityDescription:title)
        actionButton.setAccessibilityLabel(title);actionButton.toolTip=title;actionButton.isHidden=false;needsLayout=true
    }
    @objc private func runHeaderAction(){headerAction?()}
    override func layout(){
        super.layout();help?.frame=Help_HexButton.frame(width:bounds.width,height:bounds.height)
        actionButton.frame=NSRect(x:bounds.width-(help == nil ? 32:60),y:(bounds.height-24)/2+Help_HexButton.opticalOffset,width:24,height:24);actionButton.contentTintColor=Design.ink
        trailingControl?.frame=NSRect(x:max(150,bounds.width-188),y:0,width:min(152,max(0,bounds.width-178)),height:bounds.height)
    }
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    override func draw(_ dirtyRect:NSRect){
        fill(bounds,Design.card)
        if isHighlighted {fill(bounds,Design.mist)}
        WorkspaceHeaderChevron.draw(expanded ? .down:.right,
                                    at:NSPoint(x:18,y:bounds.midY),colour:Design.ink)
        let trailing=trailingControl?.frame.minX ?? (actionButton.isHidden ? bounds.width-(help == nil ? 20:44):actionButton.frame.minX)
        Design.attributed(title,.bodyStrong).draw(x:30,baseline:bounds.midY+5,width:max(0,trailing-38))
        hairline(x:0,y:0,width:bounds.width,Design.rule)
        hairline(x:0,y:bounds.height-1,width:bounds.width,Design.rule)
    }
}
