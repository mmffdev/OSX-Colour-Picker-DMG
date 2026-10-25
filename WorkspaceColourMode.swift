import AppKit

/// One temporary selection session across the editable workspace trees.
final class WorkspaceColourMode {
    enum Channel {case background,text,border}
    struct Target {
        let id:String
        let name:String
        let read:(Channel)->NSColor?
        let write:(Channel,String?)->Void
        /// The visible tree treatment, including legacy/default rows without saved overrides.
        var rendered:((Channel)->NSColor?)? = nil
        func visible(_ channel:Channel)->NSColor? {rendered?(channel) ?? read(channel)}
    }
    private final class Source {
        weak var tree:WorkspaceBranchTree?
        let resolve:(Any)->Target?
        var previous=IndexSet()
        var allowedMultiple=false
        var allowedEmpty=true
        var anchor:Int?
        init(tree:WorkspaceBranchTree,resolve:@escaping(Any)->Target?){self.tree=tree;self.resolve=resolve}
    }
    private var sources:[Source]=[]
    private(set) var isActive=false
    private(set) var selected:[Target]=[]
    var onChange:((Int)->Void)?

    func register(_ tree:WorkspaceBranchTree,resolve:@escaping(Any)->Target?){sources.append(Source(tree:tree,resolve:resolve))}

    func begin(){
        guard !isActive else{return}
        isActive=true;selected=[]
        for source in sources {
            guard let tree=source.tree else{continue}
            source.previous=tree.selectedRowIndexes
            source.allowedMultiple=tree.allowsMultipleSelection
            source.allowedEmpty=tree.allowsEmptySelection
            source.anchor=nil
            tree.allowsMultipleSelection=true;tree.allowsEmptySelection=true
            tree.onColourModeClick={[weak self,weak tree] row,event in
                guard let self,let tree else{return};self.select(row,in:tree,modifiers:event.modifierFlags)
            }
            tree.deselectAll(nil)
        }
        onChange?(0)
    }

    func end(){
        guard isActive else{return}
        // Restore the prior navigation selection before releasing the colour-mode guard.
        for source in sources {
            guard let tree=source.tree else{continue}
            let oldSelection=tree.selectedRowIndexes
            tree.selectRowIndexes(source.previous,byExtendingSelection:false)
            tree.allowsMultipleSelection=source.allowedMultiple
            tree.allowsEmptySelection=source.allowedEmpty
            tree.onColourModeClick=nil
            source.anchor=nil
            tree.refreshColourTargetGeometry(oldSelection)
        }
        isActive=false;selected=[];onChange?(0)
    }

    func choose(_ hex:String?,for channel:Channel){
        guard isActive,!selected.isEmpty else{return}
        for target in selected where target.read(channel).flatMap(hexOf)?.uppercased() != hex?.uppercased(){target.write(channel,hex)}
        // Keep the targets for the other channel. A new plain tree click replaces
        // this selection; swatches never act as a persistent brush on that click.
        onChange?(selected.count)
    }

    func apply(background:String?,text:String?,border:String?){
        guard isActive,!selected.isEmpty else{return}
        for target in selected {
            for (channel,hex) in [(Channel.background,background),(.text,text),(.border,border)] {
                if target.read(channel).flatMap(hexOf)?.uppercased() != hex?.uppercased() {
                    target.write(channel,hex)
                }
            }
        }
        onChange?(selected.count)
    }

    func select(_ item:Any,in tree:WorkspaceBranchTree){
        guard isActive,let source=sources.first(where:{$0.tree === tree}),let target=source.resolve(item) else{return}
        var row=tree.row(forItem:item)
        if row < 0 {row=(0..<tree.numberOfRows).first(where:{index in
            guard let candidate=tree.item(atRow:index) else{return false}
            return source.resolve(candidate)?.id == target.id
        }) ?? -1}
        if row >= 0 {select(row,in:tree,modifiers:[])}
    }

    private func select(_ row:Int,in tree:WorkspaceBranchTree,modifiers:NSEvent.ModifierFlags){
        guard let source=sources.first(where:{$0.tree === tree}),let item=tree.item(atRow:row),source.resolve(item) != nil else{return}
        let previousSelections=sources.map{$0.tree?.selectedRowIndexes ?? IndexSet()}
        let command=modifiers.contains(.command),shift=modifiers.contains(.shift)
        if !command {
            for other in sources where other.tree !== tree {other.tree?.deselectAll(nil)}
        }
        var indexes=tree.selectedRowIndexes
        if shift {
            let anchor=source.anchor ?? indexes.last ?? row
            let range=IndexSet(integersIn:min(anchor,row)...max(anchor,row))
            indexes=command ? indexes.union(range):range
        } else if command {
            if indexes.contains(row){indexes.remove(row)}else{indexes.insert(row)}
            source.anchor=row
        } else {
            indexes=IndexSet(integer:row);source.anchor=row
        }
        // Some rows in a visible range are commands rather than colourable nodes.
        indexes=IndexSet(indexes.filter{index in
            guard let item=tree.item(atRow:index) else{return false}
            return source.resolve(item) != nil
        })
        tree.selectRowIndexes(indexes,byExtendingSelection:false)
        for (index,source) in sources.enumerated() {
            guard let tree=source.tree else{continue}
            tree.refreshColourTargetGeometry(previousSelections[index].union(tree.selectedRowIndexes))
        }
        var unique=Set<String>()
        selected=sources.flatMap{source -> [Target] in
            guard let tree=source.tree else{return []}
            return tree.selectedRowIndexes.compactMap{index in
                guard let item=tree.item(atRow:index),var target=source.resolve(item),unique.insert(target.id).inserted else{return nil}
                target.rendered={[weak tree] channel in tree?.renderedColour(for:item,channel:channel)}
                return target
            }
        }
        onChange?(selected.count)
    }
}
