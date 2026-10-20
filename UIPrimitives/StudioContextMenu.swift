import AppKit

/// The same action tree drives circular halos and conventional Swiss cascading menus.
final class SwissContextMenu: Overlay {
    private weak var origin: NSView?
    private weak var previous: NSResponder?
    private var panels: [SwissDropdown.MenuPanel] = []
    private var levels: [[HaloAction]] = []
    private var indices: [Int] = []
    private var keyboard: Any?
    var overlayWindows: [NSWindow] { panels }
    func open(_ actions: [HaloAction], at point: NSPoint, in view: NSView) {
        dismissOverlay(); guard let window = view.window, !actions.isEmpty else { return }
        origin = view; previous = window.firstResponder
        let screen = window.convertPoint(toScreen: view.convert(point, to: nil))
        add(actions, at: screen, depth: 0)
        Overlays.opened(self)
        keyboard = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.panels.isEmpty, event.window === self.origin?.window || self.panels.contains(where: { $0 === event.window }) else { return event }
            let depth = self.levels.count - 1
            switch event.keyCode {
            case 125, 126:
                let choices = self.levels[depth]
                guard !choices.isEmpty else { return nil }
                let direction = event.keyCode == 125 ? 1 : -1
                var i = self.indices[depth] < 0 ? (direction == 1 ? -1 : 0) : self.indices[depth]
                for _ in choices { i = (i + direction + choices.count) % choices.count; if !choices[i].disabled { break } }
                self.indices[depth] = i; self.panels[depth].highlight(i); return nil
            case 124: self.expand(self.indices[depth], depth: depth); return nil
            case 123: if depth > 0 { self.trim(after: depth - 1) }; return nil
            case 36, 76: self.choose(self.indices[depth], depth: depth); return nil
            case 53: self.dismissOverlay(); return nil
            default: return event
            }
        }
    }
    private func add(_ actions: [HaloAction], at point: NSPoint, depth: Int) {
        let labels = actions.map { ($0.checked == true ? "✓  " : "") + $0.label }
        let width = min(420, max(230, labels.map { Design.attributed($0, .body).size().width + 32 }.max() ?? 230))
        let dividers = Set(actions.indices.filter { actions[$0].id.hasPrefix("divider-") })
        let panel = SwissDropdown.MenuPanel(items: labels, chosen: "", width: width, literalItems: true, dividerIndexes: dividers) { [weak self] index in self?.choose(index, depth: depth) }
        panel.onPreviewIndex = { [weak self] index in
            guard let self, self.indices.indices.contains(depth) else { return }
            self.indices[depth] = index; self.expand(index, depth: depth)
        }
        panel.configure(disabled: Set(actions.indices.filter { actions[$0].disabled }), submenus: Set(actions.indices.filter { actions[$0].children != nil }))
        panel.setLeadingSymbols(Dictionary(uniqueKeysWithValues:actions.enumerated().compactMap { index,action in
            action.menuSwatch.map { (index,("square.fill",$0)) }
        }))
        panels.append(panel); levels.append(actions); indices.append(-1)
        origin?.window?.addChildWindow(panel, ordered: .above)
        panel.place(below: point); panel.orderFront(nil)
    }
    private func expand(_ index: Int, depth: Int) {
        guard levels.indices.contains(depth), levels[depth].indices.contains(index), !levels[depth][index].disabled else { return }
        let children = levels[depth][index].children?() ?? []
        if panels.count > depth + 1, indices[depth] == index, levels[depth + 1].map({ $0.id }) == children.map({ $0.id }) { return }
        trim(after: depth)
        guard !children.isEmpty else { return }
        var point = panels[depth].trailingPoint(forRow: index)
        let width = min(420, max(230, children.map { Design.attributed($0.label, .body).size().width + 64 }.max() ?? 230))
        if let screen = panels[depth].screen, point.x + width > screen.visibleFrame.maxX { point.x = panels[depth].frame.minX - width + 1 }
        add(children, at: point, depth: depth + 1)
    }
    private func choose(_ index: Int, depth: Int) {
        guard levels.indices.contains(depth), levels[depth].indices.contains(index) else { return }
        let action = levels[depth][index]
        guard !action.disabled else { return }
        indices[depth] = index
        if action.children != nil { expand(index, depth: depth); return }
        let view = origin; dismissOverlay()
        if let edit = action.edit, let view {
            let modal = SwissFocusModal(title: action.label, message: edit.hint)
            let field = modal.field(edit.placeholder, value: edit.value)
            modal.button("Save", primary: true) { [weak modal] in edit.onCommit(field.stringValue); modal?.dismissOverlay() }
            modal.button("Cancel") { [weak modal] in modal?.dismissOverlay() }
            modal.present(over: view); return
        }
        if let run = action.onMenuSelect { run(); return }
        if action.confirmation != nil {
            SwissConfirm.ask(over: view?.window, title: action.label, note: action.description ?? "Slide across to confirm this action.", commit: action.label) { action.onSelect() }
        } else { action.onSelect() }
    }
    private func trim(after depth: Int) {
        while panels.count > depth + 1 {
            let panel = panels.removeLast(); panel.parent?.removeChildWindow(panel); panel.orderOut(nil)
            levels.removeLast(); indices.removeLast()
        }
    }
    func dismissOverlay() {
        for panel in panels { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        panels = []; levels = []; indices = []
        if let keyboard { NSEvent.removeMonitor(keyboard) }; keyboard = nil
        Overlays.closed(self)
        if let window = origin?.window, let previous { window.makeFirstResponder(previous) }
    }
}
