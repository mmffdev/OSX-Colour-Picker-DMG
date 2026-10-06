import AppKit

/// Removing a level with everything in it, from the sidebar or the Schema panel alike: the same words,
/// the same slide to confirm, the same deletion. Nothing here moves anything aside; it all goes.
extension LibraryController {
    // MARK: What a level holds, in words

    /// The palettes, typography palettes and tags of these projects, as "3 palettes, 1 tag", or nil for nothing.
    func holdings(of projects: [UUID]) -> String? {
        let held = projects.flatMap { library.palettes(in: $0) }
        let colours = held.filter { !$0.isTypography }.count, type = held.filter { $0.isTypography }.count
        let tags = library.allTags.filter { tag in projects.contains { library.project(ofTag: tag) == $0 } }.count
        var parts: [String] = []
        if colours > 0 { parts.append(plural(colours, "palette")) }
        if type > 0 { parts.append(plural(type, "typography palette")) }
        if tags > 0 { parts.append(plural(tags, "tag")) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The name of the first locked project among these, which stops the whole act.
    private func locked(among projects: [UUID]) -> String? {
        projects.compactMap { library.project($0) }.first { $0.isLocked }?.name
    }

    private func refuse(locked name: String) {
        flash("\(name) is locked. Unlock it in the sidebar first.")
        NSSound.beep()
    }

    // MARK: The deletion itself, after the slide

    /// These projects and all they hold, gone for good, with their stacks and places. Each goes in its own step, so a lock on one stops only that one.
    private func erase(projects: [UUID], as title: String) {
        for id in projects {
            let ids = library.palettes(in: id).map { $0.id }
            let names = library.allTags.filter { library.project(ofTag: $0) == id }
            apply(title) { lib in
                ids.forEach { lib.deleteSwatch($0) }
                names.forEach { lib.deleteTag($0) }
                lib.deleteProject(id)
            }
            guard library.project(id) == nil else { continue }   // refused: locked
            SchemaTrial.setSchema(nil, for: id)
            SchemaTrial.places.removeValue(forKey: id.uuidString)
        }
    }

    // MARK: Each level, asked for with the slide

    /// A member: the project and everything in it.
    func dump(project id: UUID, over window: NSWindow?, then: (() -> Void)? = nil) {
        guard let p = library.project(id) else { return }
        if let name = locked(among: [id]) { refuse(locked: name); return }
        let home = SchemaTrial.collection(of: id)
        let what = holdings(of: [id]).map { "Its \($0) and every group inside it are deleted, not moved." } ?? "It holds nothing yet, and its groups go with it."
        SlideConfirm.ask(over: window, title: "Remove \(p.name) From \(home.name)", note: what + " This cannot be undone.") { [weak self] in
            self?.erase(projects: [id], as: "Remove \(SchemaTrial.memberName(of: home))")
            then?()
        }
    }

    /// A folder of a collection: its members and everything in them, then the folder.
    func dump(folder: UUID, in collection: UUID, over window: NSWindow?, then: (() -> Void)? = nil) {
        guard let c = SchemaTrial.collections.first(where: { $0.id == collection }), let f = c.folders.first(where: { $0.id == folder }) else { return }
        let members = library.orderedProjects.map { $0.id }.filter { SchemaTrial.folder(of: $0, among: SchemaTrial.collections, places: SchemaTrial.places) == folder }
        if members.isEmpty {
            SchemaTrial.changeCollection(collection) { $0.folders.removeAll { $0.id == folder } }
            then?()
            return
        }
        if let name = locked(among: members) { refuse(locked: name); return }
        let noun = SchemaTrial.plural(SchemaTrial.memberName(of: c)).lowercased()
        let what = "Its \(plural(members.count, SchemaTrial.memberName(of: c).lowercased(), noun))" + (holdings(of: members).map { ", with their \($0)," } ?? "") + " are deleted, not moved."
        SlideConfirm.ask(over: window, title: "Remove \(f.name) From \(c.name)", note: what + " This cannot be undone.") { [weak self] in
            self?.erase(projects: members, as: "Remove \(c.folderName ?? "Folder")")
            SchemaTrial.changeCollection(collection) { $0.folders.removeAll { $0.id == folder } }
            then?()
        }
    }

    /// A collection: every member in it, in any folder, and everything they hold, then the heading. The first collection stays: it is where things land.
    func dump(collection id: UUID, over window: NSWindow?, then: (() -> Void)? = nil) {
        let all = SchemaTrial.collections
        guard let c = all.first(where: { $0.id == id }), id != SchemaTrial.firstCollection else { return }
        let members = library.orderedProjects.map { $0.id }.filter { SchemaTrial.collection(of: $0, among: all, places: SchemaTrial.places).id == id }
        if members.isEmpty {
            SchemaTrial.collections = all.filter { $0.id != id }
            then?()
            return
        }
        if let name = locked(among: members) { refuse(locked: name); return }
        let member = SchemaTrial.memberName(of: c)
        let what = "Its \(plural(members.count, member.lowercased(), SchemaTrial.plural(member).lowercased()))" + (holdings(of: members).map { ", with their \($0)," } ?? "") + " are deleted, not moved."
        SlideConfirm.ask(over: window, title: "Remove The \(c.name) Collection", note: what + " This cannot be undone.") { [weak self] in
            self?.erase(projects: members, as: "Remove Collection")
            SchemaTrial.collections = SchemaTrial.collections.filter { $0.id != id }
            then?()
        }
    }

    /// What one of a project's buckets holds: palette ids, or tag names.
    private func contents(_ role: SchemaRole, of project: UUID) -> (ids: [UUID], names: [String]) {
        let held = library.palettes(in: project)
        switch role {
        case .palettes: return (held.filter { !$0.isTypography }.map { $0.id }, [])
        case .typography: return (held.filter { $0.isTypography }.map { $0.id }, [])
        case .tags: return ([], library.allTags.filter { library.project(ofTag: $0) == project })
        case .information: return ([], [])
        }
    }

    /// Deletes everything in one of a project's buckets, the question having been asked already.
    func erase(role: SchemaRole, of project: UUID) {
        let (ids, names) = contents(role, of: project)
        guard !ids.isEmpty || !names.isEmpty else { return }
        apply("Empty \(role.title)") { lib in
            ids.forEach { lib.deleteSwatch($0) }
            names.forEach { lib.deleteTag($0) }
        }
    }

    /// Everything in one of a project's buckets: its palettes, its typography palettes or its tags.
    func dump(role: SchemaRole, of project: UUID, over window: NSWindow?, then: (() -> Void)? = nil) {
        guard let p = library.project(project) else { return }
        if let name = locked(among: [project]) { refuse(locked: name); return }
        let group = SchemaTrial.schema(for: project).children.first { SchemaTrial.role(of: $0) == role }?.name ?? role.title
        let (ids, names) = contents(role, of: project)
        guard !ids.isEmpty || !names.isEmpty else { return }
        let what: String
        switch role {
        case .palettes: what = "Its \(plural(ids.count, "palette")) are deleted, not moved."
        case .typography: what = "Its \(plural(ids.count, "typography palette")) are deleted, not moved."
        case .tags: what = "Its \(plural(names.count, "tag")) are deleted, and come off every swatch that wears them."
        case .information: return
        }
        SlideConfirm.ask(over: window, title: "Empty \(group) In \(p.name)", note: what + " This cannot be undone.", commit: "Empty") { [weak self] in
            self?.erase(role: role, of: project)
            then?()
        }
    }
}
