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
    } catch {check(false,"palette asset handler: "+error.localizedDescription)}
}
