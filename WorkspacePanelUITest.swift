import AppKit

/// Opt-in, session-only fixture. Never creates catalogue or .coldata records.
enum WorkspacePanelUITest {
    static func load(into rails:[WorkspaceRail]) {
        for (index,rail) in rails.enumerated() {
            for letter in ["A","B","C","D","E"] {
                let id="ui-test-rail\(index+1)-\(letter)"
                guard !rail.panels.contains(where:{$0.panelID == id}) else{continue}
                rail.add(WorkspacePanel(id:id,title:"Rail\(index+1) Panel \(letter)",content:NSView(),height:220))
            }
        }
    }
}
