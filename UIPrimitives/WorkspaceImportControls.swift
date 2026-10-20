import AppKit
import UniformTypeIdentifiers
import ImageIO

final class WorkspaceImportControlsView:NSView {
    override var isFlipped:Bool {true}
}

final class WorkspaceImportMethodButton:ClickCursorButton {
    var chosen=false {didSet{needsDisplay=true}}
    var symbol="" {didSet{needsDisplay=true}}
    override var isFlipped:Bool {true}
    override init(frame:NSRect){super.init(frame:frame);isBordered=false;setButtonType(.momentaryPushIn)}
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ dirtyRect:NSRect){
        let background=chosen ? Design.houseYellow:Design.mist
        let foreground=chosen ? NSColor.black:Design.ink
        background.setFill();bounds.fill()
        Design.rule.setStroke();NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)).stroke()
        fill(NSRect(x:28,y:0,width:1,height:bounds.height),Design.rule)
        RowMark.image(symbol,colour:foreground).draw(in:NSRect(x:6,y:(bounds.height-16)/2,width:16,height:16),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        Design.attributed(title,.bodyStrong,colour:foreground).draw(x:33,baseline:bounds.midY+5,width:max(0,bounds.width-36))
    }
}

final class WorkspaceImportActionButton:ClickCursorButton {
    var symbol="square.and.arrow.down" {didSet{needsDisplay=true}}
    override var isFlipped:Bool {true}
    override init(frame:NSRect){super.init(frame:frame);isBordered=false;setButtonType(.momentaryPushIn)}
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ dirtyRect:NSRect){
        (isEnabled ? Design.card:Design.mist).setFill();bounds.fill()
        Design.rule.setStroke();NSBezierPath(rect:bounds.insetBy(dx:0.5,dy:0.5)).stroke()
        fill(NSRect(x:42,y:0,width:1,height:bounds.height),Design.rule)
        let ink=isEnabled ? Design.ink:Design.quiet
        RowMark.image(symbol,colour:ink).draw(in:NSRect(x:13,y:(bounds.height-18)/2,width:18,height:18),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
        Design.attributed(title,.bodyStrong,colour:ink).draw(x:54,baseline:bounds.midY+5,width:max(0,bounds.width-62))
    }
}
