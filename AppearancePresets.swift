import AppKit

/// Only the selected preset is stored in .coldata; the five choices are fixed.
enum AppearancePresets {
    struct Preset { let id: String; let name: String; let hex: String }
    static let all = [
        Preset(id:"white",name:"White",hex:"#FFFFFF"),
        Preset(id:"cream",name:"Cream",hex:"#F8F7F5"),
        Preset(id:"grey",name:"50% Grey",hex:"#808080"),
        Preset(id:"charcoal",name:"Charcoal",hex:"#242424"),
        Preset(id:"black",name:"Black",hex:"#000000")
    ]
    static func index(for id: String?) -> Int { all.firstIndex { $0.id == id } ?? 1 }
    static func next(after index: Int) -> Int { (index+1)%all.count }
    static var selectedIndex: Int { index(for:AppPreferences.shared.string(forKey:"theme.preset")) }
    static var selected: Preset { all[selectedIndex] }
    static func select(_ index: Int) {
        guard all.indices.contains(index) else { return }
        AppPreferences.shared.set(all[index].id,forKey:"theme.preset")
        NotificationCenter.default.post(name:.themeDidChange,object:nil)
    }
    static func cycle() { select(next(after:selectedIndex)) }
}

final class AppearancePresetControl: NSView {
    private var buttons: [Swatch] = []
    private final class Swatch: NSButton {
        var colour: NSColor = .white
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            let box = bounds.insetBy(dx:3,dy:4)
            colour.setFill(); box.fill()
            Design.rule.setStroke(); NSBezierPath(rect:box.insetBy(dx:0.5,dy:0.5)).stroke()
            if state == .on {
                Design.houseYellow.setStroke()
                let ring = NSBezierPath(rect:box.insetBy(dx:-2,dy:-2)); ring.lineWidth=2;ring.stroke()
            }
            if isHighlighted { Design.ink.withAlphaComponent(0.15).setFill();box.fill() }
        }
        override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    }
    override init(frame:NSRect) {
        super.init(frame:frame)
        for (i,preset) in AppearancePresets.all.enumerated() {
            let button=Swatch();button.title="";button.isBordered=false;button.setButtonType(.toggle)
            button.colour=Design.hex(preset.hex);button.tag=i;button.target=self;button.action=#selector(choose(_:))
            button.toolTip=preset.name+" · L To Cycle";button.setAccessibilityLabel(preset.name)
            addSubview(button);buttons.append(button)
        }
        NotificationCenter.default.addObserver(self,selector:#selector(refresh),name:.themeDidChange,object:nil)
        refresh()
    }
    required init?(coder:NSCoder){fatalError()}
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func choose(_ sender:NSButton){AppearancePresets.select(sender.tag)}
    @objc private func refresh(){for (i,button) in buttons.enumerated(){button.state=i == AppearancePresets.selectedIndex ? .on:.off;button.needsDisplay=true}}
    override func layout(){super.layout();for (i,button) in buttons.enumerated(){button.frame=NSRect(x:CGFloat(i)*28,y:0,width:28,height:28)}}
}
