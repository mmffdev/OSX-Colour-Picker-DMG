import Foundation

func runPaletteAssetTests(check:(Bool,String)->Void){
    let fm=FileManager.default
    let folder=fm.temporaryDirectory.appendingPathComponent("PaletteAssetTests-"+UUID().uuidString)
    do {
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? fm.removeItem(at:folder)}
        let date=Date(timeIntervalSince1970:1_700_000_000)
        var lib=Library()
        let id=lib.createSwatch(named:"Portable Review",hexes:["#123456","#FEDCBA"],at:date)
        lib.setName("Exact Name",of:"#123456",in:id,at:date)
        PaletteAssetHandler.setRating(4,on:id,in:&lib,at:date)
        PaletteAssetHandler.setFlag(.orange,on:id,in:&lib,at:date)
        let original=lib.swatch(id)!
        let asset=PaletteAssetHandler.document(original,in:lib,member:nil,file:"Portable Review")
        var metadata=AssetMetadata(title:"Test Colour System",description:"A portable print palette",creator:"Colorgain",printProcess:"Offset lithography",keywords:["Brand", "Primary"])
        metadata.tidy()
        var metadataAsset=asset;metadataAsset.palette.metadata=metadata;metadataAsset.palette.tags=["Brand","Primary"]
        let metadataRoundTrip=try PaletteAssetHandler.read(PaletteAssetHandler.data(metadataAsset))
        check(metadataRoundTrip.palette.metadata == metadata && metadataRoundTrip.palette.tagList == ["Brand","Primary"],"asset metadata and Lightroom-style keywords travel inside the native palette file")
        let url=folder.appendingPathComponent("Portable Review.colpal")
        try PaletteAssetHandler.store(asset,at:url)
        let loaded=try PaletteAssetHandler.read(url)
        check(loaded == asset,"palette handler round-trips the complete metadata and colour records")
        check(loaded.palette.review?.rating == 4 && loaded.palette.review?.flag == .orange,"ratings and flags live in the portable .colpal")
        var old=original;old.review=nil
        let legacy=try PaletteAssetHandler.read(PaletteAssetHandler.data(PaletteAssetHandler.document(old,in:lib,member:nil,file:"Legacy")))
        check(legacy.palette.review == nil,"older palette files load without invented ratings or flags")
        var invalid=asset;invalid.version=999
        check((try? PaletteAssetHandler.data(invalid)) == nil,"unsupported palette versions cannot be saved over valid assets")
        invalid=asset;invalid.palette.review?.rating=6
        check((try? PaletteAssetHandler.data(invalid)) == nil,"invalid stored palette ratings are refused")
        let incoming=PaletteImport.read(try PaletteAssetHandler.data(asset),fallback:"Fallback")
        var imported=Library();let result=imported.merge(incoming,into:nil,at:date)
        check(result.palettesMade == 1 && imported.swatches.first?.review == original.review && imported.swatches.first?.entries == original.entries,"native palette imports retain review metadata and whole swatches")
        check(imported.colours == lib.colours,"native palette imports retain exact master colour records")
        let one=lib.createProject(named:"One",at:date),two=lib.createProject(named:"Two",at:date)
        let copy=lib.copyPalette(id,to:one,withNotes:true,at:date)!
        _=lib.copyPalette(copy,to:two,withNotes:true,at:date)
        check(lib.swatch(copy)?.review == original.review && PaletteAssetHandler.presentation(lib.swatch(id)!,in:lib).useCount == 2,"palette copies retain review metadata and count distinct projects through copy lineage")
        var remote=lib
        PaletteAssetHandler.setRating(2,on:id,in:&remote,at:date.addingTimeInterval(10))
        PaletteAssetHandler.setFlag(nil,on:id,in:&lib,at:date.addingTimeInterval(20))
        let merged=mergeLibraries(local:lib,remote:remote).swatch(id)!
        check(merged.review?.rating == 2 && merged.review?.flag == nil,"sync merges rating and flag independently and preserves flag clearing")
        check(PaletteAssetHandler.Filter(rating:4).matches(original) && !PaletteAssetHandler.Filter(rating:0).matches(original),"palette rating filters match exact whole ratings")
        check(PaletteAssetHandler.Filter(rating:0,flag:"").matches(old),"unrated and unflagged filters include legacy palettes")
        check(PaletteAssetHandler.Filter(flag:PaletteReview.Flag.orange.rawValue).matches(original) && !PaletteAssetHandler.Filter(flag:PaletteReview.Flag.green.rawValue).matches(original),"palette flag filters match the selected flag")
        var multiple=PaletteAssetHandler.Filter();multiple.selectedFlags=[PaletteReview.Flag.orange.rawValue,PaletteReview.Flag.green.rawValue]
        check(multiple.matches(original) && !multiple.matches(old),"multi-flag filtering matches any selected colour and excludes unflagged palettes")
        multiple.selectedFlags.insert("")
        check(multiple.matches(original) && multiple.matches(old),"multi-flag filtering can include unflagged palettes alongside colours")
        multiple.selectedFlags=[]
        check(multiple.flag == nil && multiple.matches(old),"clearing multi-flag selections restores all flags")
        let filtered=PaletteAssetHandler.filtered([old,original],by:.init(rating:4,flag:PaletteReview.Flag.orange.rawValue),in:lib)
        check(filtered.map(\.id) == [original.id],"palette rating and flag filters combine without changing assets")
        let bounds=NSRect(x:0,y:0,width:800,height:600),size=NSSize(width:200,height:250)
        let low=SwissDropdown.MenuPanel.placement(anchor:NSRect(x:100,y:20,width:80,height:28),size:size,within:bounds)
        let high=SwissDropdown.MenuPanel.placement(anchor:NSRect(x:100,y:540,width:80,height:28),size:size,within:bounds)
        check(low.origin.y == 52 && low.height == 250 && high.origin.y == 286,"dropdown placement flips upward near the lower edge and downward near the upper edge")
        let clipped=SwissDropdown.MenuPanel.placement(anchor:NSRect(x:760,y:280,width:40,height:28),size:NSSize(width:200,height:900),within:bounds)
        check(clipped.origin.x == 600 && clipped.origin.y >= 0 && clipped.origin.y+clipped.height <= 600,"oversized menus stay within the window and retain a scrollable height")
        let ranked=PaletteAssetHandler.ordered([merged,old],by:.rating,in:lib)
        check(ranked.first?.review?.rating == 2,"palette rating order puts rated assets above unrated assets")
        let catalogue=folder.appendingPathComponent("Mutation Catalogue",isDirectory:true)
        let store=LibraryStore(directory:catalogue,legacyURL:nil,name:"Mutation Catalogue")
        var mutationLibrary=Library()
        let changedID=mutationLibrary.createSwatch(named:"Changing",hexes:["#123456"],at:date)
        let untouchedID=mutationLibrary.createSwatch(named:"Untouched",hexes:["#FEDCBA"],at:date)
        try store.save(mutationLibrary)
        let untouchedFile=CatalogueTree.file(ofPalette:untouchedID,in:catalogue)!
        let untouchedBytes=try Data(contentsOf:untouchedFile)
        let mutated=try store.mutate { value in
            if let index=value.swatches.firstIndex(where:{$0.id == changedID}) {
                value.swatches[index].name="Changed"
                value.swatches[index].nameChangedAt=date.addingTimeInterval(1)
            }
        }
        check(mutated == (try store.load()),"single-palette mutation returns the exact persisted library without a second full read")
        check(try Data(contentsOf:untouchedFile) == untouchedBytes,"single-palette mutation leaves the unrelated asset file unchanged")
        let renamedFile=CatalogueTree.file(ofPalette:changedID,in:catalogue)!
        let renamedLink=CatalogueTree.catalogue(in:catalogue)?.libraryAssets.first{$0.id == changedID}
        check(renamedFile.lastPathComponent == "Changed.colpal" && renamedLink?.name == "Changed" && renamedLink?.file.hasSuffix("Changed.colpal") == true,
              "single-palette rename moves its file and updates the catalogue link")
        let catalogueBytes=try Data(contentsOf:store.url)
        let reviewed=try store.mutate { value in
            PaletteAssetHandler.setRating(4,on:changedID,in:&value,at:date.addingTimeInterval(2))
        }
        let persistedReview=try store.load().swatch(changedID)?.review?.rating
        let persistedIndex=try Data(contentsOf:store.url)
        check(reviewed.swatch(changedID)?.review?.rating == 4 && persistedReview == 4 && persistedIndex == catalogueBytes,
              "review-only mutation persists its palette without rewriting the catalogue index")
        let noOp=try store.mutate { _ in }
        check(noOp == reviewed,"no-op mutation preserves the loaded library without rewriting it")
        let changedFile=CatalogueTree.file(ofPalette:changedID,in:catalogue)!
        var externallyEdited=try PaletteAssetHandler.read(changedFile)
        externallyEdited.palette.review?.flag = .red
        externallyEdited.palette.review?.flagChangedAt = date.addingTimeInterval(3)
        try PaletteAssetHandler.store(externallyEdited,at:changedFile)
        check(try store.load().swatch(changedID)?.review?.flag == .red,
              "a changed external palette invalidates the warm library snapshot")
        let conflictRejected=(try? store.mutate { value in
            value.swatches[value.swatches.firstIndex(where:{$0.id == changedID})!].name="Should Not Save"
            var external=try PaletteAssetHandler.read(untouchedFile)
            external.palette.review=PaletteReview(rating:1)
            try PaletteAssetHandler.store(external,at:untouchedFile)
        }) == nil
        let conflictReloaded=try store.load()
        check(conflictRejected && conflictReloaded.swatch(untouchedID)?.review?.rating == 1,
              "a concurrent asset edit blocks a stale palette rename without losing the external change")
        var futureIndex=try JSONSerialization.jsonObject(with:Data(contentsOf:store.url)) as! [String:Any]
        futureIndex["futureCatalogueField"]="Retain"
        try JSONSerialization.data(withJSONObject:futureIndex).write(to:store.url,options:.atomic)
        _ = try store.load()
        _ = try store.mutate { value in
            value.swatches[value.swatches.firstIndex(where:{$0.id == changedID})!].name="Final Name"
        }
        let retainedIndex=try JSONSerialization.jsonObject(with:Data(contentsOf:store.url)) as! [String:Any]
        check(retainedIndex["futureCatalogueField"] as? String == "Retain" && CatalogueTree.file(ofPalette:changedID,in:catalogue)?.lastPathComponent == "Final Name.colpal",
              "fast palette renaming retains future catalogue fields and settles the new filename")
        let noteKey="file:"+folder.appendingPathComponent("Preview.png").path
        let note=AssetNote(name:"Preview",description:"Keep this note")
        try AssetNotes.save(note,for:noteKey)
        let noteFile=folder.appendingPathComponent("Preview.png.colcar")
        check(AssetNotes.record(noteKey) == note,"file note sidecars remain readable after saving")
        let oversized=Data(repeating:0x7B,count:2*1024*1024+1)
        try oversized.write(to:noteFile)
        let rejected=(try? AssetNotes.save(note,for:noteKey)) == nil
        let preserved=try Data(contentsOf:noteFile) == oversized
        check(rejected && preserved,
              "an oversized external sidecar cannot be silently overwritten")
        if ProcessInfo.processInfo.environment["COLORGAIN_BENCHMARK"] == "1" {
            let requested=ProcessInfo.processInfo.environment["COLORGAIN_BENCHMARK_COUNTS"]?
                .split(separator:",").compactMap{Int($0.trimmingCharacters(in:.whitespaces))}
                .filter{(1...10_000).contains($0)}
            let counts=requested.flatMap{$0.isEmpty ? nil:$0} ?? [100,1000]
            for count in counts {
                let root=folder.appendingPathComponent("Benchmark-\(count)",isDirectory:true)
                let benchmarkStore=LibraryStore(directory:root,legacyURL:nil,name:"Benchmark")
                var value=Library()
                var first:UUID?
                for index in 0..<count {
                    let id=value.createSwatch(named:"Palette \(index)",hexes:[String(format:"#%06X",index+1)],at:date)
                    if first == nil{first=id}
                }
                try benchmarkStore.save(value)
                let coldStarted=Date()
                _ = try benchmarkStore.load()
                print(String(format:"PERF catalogue load, %d palettes: %.3f s",count,Date().timeIntervalSince(coldStarted)))
                let started=Date()
                _ = try benchmarkStore.mutate { candidate in
                    if let first,let index=candidate.swatches.firstIndex(where:{$0.id == first}) {
                        candidate.swatches[index].name="Renamed Palette"
                        candidate.swatches[index].nameChangedAt=date.addingTimeInterval(1)
                    }
                }
                print(String(format:"PERF single-palette edit, %d palettes: %.3f s",count,Date().timeIntervalSince(started)))
                let reviewStarted=Date()
                _ = try benchmarkStore.mutate { candidate in
                    if let first {PaletteAssetHandler.setRating(4,on:first,in:&candidate,at:date.addingTimeInterval(2))}
                }
                print(String(format:"PERF single-palette review, %d palettes: %.3f s",count,Date().timeIntervalSince(reviewStarted)))
            }
        }
    } catch {check(false,"palette asset handler: "+error.localizedDescription)}
}
