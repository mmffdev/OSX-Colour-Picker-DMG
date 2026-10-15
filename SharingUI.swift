import AppKit
import AVFoundation
import Vision
import UniformTypeIdentifiers
import ImageIO

/// The application preference and macOS grant are separate; camera use never starts at launch.
enum SharingCamera {
    static var allowed: Bool { Prefs.sharingCameraAllowed && AVCaptureDevice.authorizationStatus(for:.video) == .authorized }
    static func enable(_ completion: @escaping (Bool)->Void) {
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: Prefs.sharingCameraAllowed=true; NotificationCenter.default.post(name:.permissionsChanged,object:nil); completion(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for:.video) { yes in DispatchQueue.main.async { Prefs.sharingCameraAllowed=yes; NotificationCenter.default.post(name:.permissionsChanged,object:nil); completion(yes) } }
        default: completion(false); NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
        }
    }
}
final class SharingSettings:NSView,PageSection {
    var onResize:(()->Void)?
    var sectionAnchors:[(String,CGFloat)] { [("QR Generation Settings",SettingsSheet.headerGuide+1)] }
    private let camera=SwissButton("Allow Camera",.secondary)
    init(){super.init(frame:.zero);addSubview(camera);camera.target=self;camera.action=#selector(toggle);reload()}
    required init?(coder:NSCoder){fatalError()}
    override var isFlipped:Bool{true}
    func reload(){camera.title="Allow Camera: " + (SharingCamera.allowed ? "On" : "Off");needsDisplay=true}
    @objc private func toggle(){if Prefs.sharingCameraAllowed {Prefs.sharingCameraAllowed=false;reload()} else {SharingCamera.enable { [weak self] _ in self?.reload() }}}
    func height(forWidth width:CGFloat)->CGFloat{SettingsSheet.baseline(17)}
    override func layout(){super.layout();let x=SettingsSheet.contentColumn(width:bounds.width,window:window?.frame.width ?? Design.App.size.width);camera.frame=NSRect(x:x,y:SettingsSheet.buttonTop(baseline:SettingsSheet.baseline(5)),width:max(180,bounds.width-x),height:32)}
    override func draw(_ dirtyRect:NSRect){
        let x=SettingsSheet.contentColumn(width:bounds.width,window:window?.frame.width ?? Design.App.size.width)
        SettingsSheet.title("Sharing.")
        SettingsSheet.introduction("Colour exchange","Share named XYZ D50 colours, offline.",x:x,width:bounds.width-x)
        SettingsSheet.section(1,"QR Generation Settings",guide:SettingsSheet.headerGuide,contentX:x,width:bounds.width)
        SettingsSheet.paragraph("Use your Mac’s camera to scan a Colorgain QR displayed on a phone or printed on paper. Camera access is optional. QR generation, image import and clipboard import work without it. The camera runs only while the scanner is open; images are processed locally and are not saved.",x:x,firstBaseline:SettingsSheet.baseline(7),width:bounds.width-x,height:168)
    }
}
final class QRImportPage:NSView,PageSection {
    var onResize:(()->Void)?
    var onDocument:((ColourQR.Document)->Void)?
    var sectionAnchors:[(String,CGFloat)]{[("QR Import",SettingsSheet.headerGuide+1)]}
    private let camera=SwissButton("Scan With Camera",.secondary), image=SwissButton("Import Image Or Colour File…",.secondary), clipboard=SwissButton("Import From Clipboard",.secondary), access=SwissButton("Allow Camera",.secondary)
    private var status="Camera access is optional. Choose a saved image, paste a QR image, or hold your phone in front of the camera."
    init(){super.init(frame:.zero);for (i,b) in [camera,image,clipboard,access].enumerated(){b.tag=i;b.target=self;b.action=#selector(act(_:));addSubview(b)}}
    required init?(coder:NSCoder){fatalError()}
    override var isFlipped:Bool{true}
    func reload(){needsLayout=true;needsDisplay=true}
    func height(forWidth width:CGFloat)->CGFloat{SettingsSheet.baseline(22)}
    override func layout(){super.layout();let x=SettingsSheet.contentColumn(width:bounds.width,window:window?.frame.width ?? Design.App.size.width);for (i,b) in [camera,image,clipboard,access].enumerated(){b.frame=NSRect(x:x,y:SettingsSheet.buttonTop(baseline:SettingsSheet.baseline(CGFloat(5+i*2))),width:max(180,bounds.width-x),height:32)};access.title=SharingCamera.allowed ? "Camera Access: On" : "Allow Camera…"}
    override func draw(_ dirtyRect:NSRect){let x=SettingsSheet.contentColumn(width:bounds.width,window:window?.frame.width ?? Design.App.size.width);SettingsSheet.title("Import.");SettingsSheet.introduction("Bring colours home","Scan a Colorgain QR to recover its original colour data.",x:x,width:bounds.width);SettingsSheet.section(1,"QR Import",guide:SettingsSheet.headerGuide,contentX:x,width:bounds.width);SettingsSheet.paragraph(status,x:x,firstBaseline:SettingsSheet.baseline(14),width:bounds.width-x,height:168)}
    private func report(_ text:String){status=text;needsDisplay=true;needsLayout=true}
    private func received(_ d:ColourQR.Document){report("Decoded “"+d.name+"” · \(d.colours.count) colours · XYZ D50. Review before importing.");onDocument?(d)}
    private func decodeImage(_ image:NSImage){var rect=NSRect(origin:.zero,size:image.size);guard let cg=image.cgImage(forProposedRect:&rect,context:nil,hints:nil) else {report("Could not read this image.");return};report("Reading QR…");DispatchQueue.global(qos:.userInitiated).async{[weak self] in let result=Result{try ColourQR.decode(ColourQR.scan(cg))};DispatchQueue.main.async{switch result{case .success(let d):self?.received(d);case .failure(let e):self?.report(e.localizedDescription)}}}}
    @objc private func act(_ sender:NSButton){switch sender.tag{
        case 0:guard SharingCamera.allowed else {report("Enable camera access first, or import an image instead.");return};let modal=SwissFocusModal(title:"Scan A Colour QR",message:"Hold a Colorgain QR in front of the camera. The scanner closes after a valid code is found.");let capture=QRScanner();capture.onCode={ [weak self,weak modal] code in do{let d=try ColourQR.decode(code);modal?.dismissOverlay();self?.received(d)}catch{self?.report(error.localizedDescription)}};modal.content(capture,height:300);modal.button("Close"){[weak modal] in modal?.dismissOverlay()};modal.present(over:self)
        case 1:let panel=NSOpenPanel();panel.allowedContentTypes=[.png,.jpeg,.tiff,UTType(filenameExtension:"colqr") ?? .data];panel.allowsMultipleSelection=false;panel.begin{[weak self] reply in guard reply == .OK,let url=panel.url,let self else{return};do{let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0;guard size<=20*1024*1024 else{throw failure("Choose an image under 20 MB.")};if url.pathExtension.lowercased()=="colqr"{self.received(try ColourQR.document(Handler_File_Manager.shared.read(url)))}else if let source=CGImageSourceCreateWithURL(url as CFURL,nil),let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],let width=properties[kCGImagePropertyPixelWidth] as? Int,let height=properties[kCGImagePropertyPixelHeight] as? Int,width>0,height>0,width<=8192,height<=8192,width*height<=40_000_000,let image=NSImage(contentsOf:url){self.decodeImage(image)}else{throw failure("Could not read this image.")}}catch{self.report(error.localizedDescription)}}
        case 2:if let image=NSImage(pasteboard:.general){decodeImage(image)}else if let text=NSPasteboard.general.string(forType:.string){do{received(try ColourQR.decode(text.trimmingCharacters(in:.whitespacesAndNewlines)))}catch{report(error.localizedDescription)}}else{report("Copy a Colorgain QR image or its encoded text first.")}
        default:SharingCamera.enable{[weak self] yes in self?.report(yes ? "Camera access enabled. Choose Scan With Camera to begin." : "Camera access is off. Image and clipboard import remain available.")}
    }}
}
private final class QRScanner:NSView,AVCaptureVideoDataOutputSampleBufferDelegate {
    var onCode:((String)->Void)?
    private let session=AVCaptureSession(), queue=DispatchQueue(label:"com.colorgain.qr.camera",qos:.userInitiated)
    private var preview:AVCaptureVideoPreviewLayer?
    private let activityLock=NSLock()
    private var activity=false
    private var active:Bool { get {activityLock.lock();defer{activityLock.unlock()};return activity} set{activityLock.lock();activity=newValue;activityLock.unlock()} }
    private var delivered=false
    private var lastScan:Double=0
    override init(frame:NSRect){super.init(frame:frame);wantsLayer=true}
    convenience init(){self.init(frame:.zero)}
    required init?(coder:NSCoder){fatalError()}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();if window == nil{stop();return};guard SharingCamera.allowed else{return};active=true
        let layer=AVCaptureVideoPreviewLayer(session:session);layer.videoGravity = .resizeAspectFill;self.layer?.addSublayer(layer);preview=layer
        queue.async{[weak self] in guard let self,self.active else{return};do{guard let device=AVCaptureDevice.default(for:.video) else{throw failure("No camera is connected.")};let input=try AVCaptureDeviceInput(device:device);self.session.beginConfiguration();self.session.sessionPreset = self.session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high;guard self.session.canAddInput(input) else{self.session.commitConfiguration();throw failure("This camera is unavailable.")};self.session.addInput(input);let output=AVCaptureVideoDataOutput();output.alwaysDiscardsLateVideoFrames=true;output.setSampleBufferDelegate(self,queue:self.queue);guard self.session.canAddOutput(output) else{self.session.commitConfiguration();throw failure("Could not read camera frames.")};self.session.addOutput(output);self.session.commitConfiguration();if self.active{self.session.startRunning()}}catch{DispatchQueue.main.async{[weak self] in self?.showError(error.localizedDescription)}}}
    }
    private func showError(_ text:String){let label=Design.text(text,.body);label.frame=bounds.insetBy(dx:16,dy:16);label.autoresizingMask=[.width,.height];addSubview(label)}
    override func layout(){super.layout();preview?.frame=bounds}
    private func stop(){active=false;queue.async{[session] in if session.isRunning{session.stopRunning()}}}
    deinit{if session.isRunning{session.stopRunning()}}
    func captureOutput(_ output:AVCaptureOutput,didOutput sampleBuffer:CMSampleBuffer,from connection:AVCaptureConnection){guard active,!delivered,SharingCamera.allowed else{if !SharingCamera.allowed{stop()};return};let now=ProcessInfo.processInfo.systemUptime;guard now-lastScan>=0.2,let buffer=CMSampleBufferGetImageBuffer(sampleBuffer) else{return};lastScan=now;let request=VNDetectBarcodesRequest();request.symbologies=[.qr];do{try VNImageRequestHandler(cvPixelBuffer:buffer,options:[:]).perform([request]);if let code=request.results?.compactMap({$0.payloadStringValue}).first(where:{$0.hasPrefix(ColourQR.prefix)}),(try? ColourQR.decode(code)) != nil{delivered=true;session.stopRunning();DispatchQueue.main.async{[weak self] in guard self?.active==true else{return};self?.onCode?(code)}}}catch{}}
}

/// Modal export and reviewed, atomic import share the same versioned document.
enum QRSharing {
    static func show(_ d:ColourQR.Document,over view:NSView){
        let modal=SwissFocusModal(title:d.type == "palette" ? "Share Palette QR" : "Share Swatch QR",message:d.name+" · "+plural(d.colours.count,"colour")+" · XYZ D50 · Scan with Colorgain Import")
        let image: NSImage?
        do{image=try ColourQR.image(ColourQR.text(d))}catch{image=nil;let label=Design.text(error.localizedDescription,.body);label.maximumNumberOfLines=0;modal.content(label,height:84)}
        if let image{let iv=NSImageView();iv.image=image;iv.imageScaling = .scaleProportionallyUpOrDown;modal.content(iv,height:360);modal.button("Copy QR Image"){NSPasteboard.general.clearContents();NSPasteboard.general.writeObjects([image])};modal.button("Save QR Image…"){let p=NSSavePanel();p.allowedContentTypes=[.png];p.nameFieldStringValue=filesystemName(d.name)+" QR.png";p.begin{reply in guard reply == .OK,let url=p.url,let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let data=rep.representation(using:.png,properties:[:]) else{return};do{try data.write(to:url,options:.atomic)}catch{NSApp.presentError(error)}}};modal.button("Share QR…"){let picker=NSSharingServicePicker(items:[image]);picker.show(relativeTo:view.bounds,of:view,preferredEdge:.minY)}}
        modal.button("Save Colour File…"){let p=NSSavePanel();p.allowedContentTypes=[UTType(filenameExtension:"colqr") ?? .data];p.nameFieldStringValue=filesystemName(d.name)+".colqr";p.begin{reply in guard reply == .OK,let url=p.url else{return};do{try Handler_File_Manager.shared.write(ColourQR.data(d),to:url)}catch{NSApp.presentError(error)}}}
        modal.button("Close"){[weak modal] in modal?.dismissOverlay()};modal.present(over:view)
    }
    static func review(_ d:ColourQR.Document,library:LibraryController,over view:NSView){
        let modal=SwissFocusModal(title:"Import Colour QR",message:"“"+d.name+"” · "+plural(d.colours.count,"colour")+" · XYZ D50, 2°")
        let preview=QRColourPreview(colours:d.colours);modal.content(preview,height:168)
        let target=library.library.activeSwatchID.flatMap{library.library.swatch($0)}
        var intoTarget=false
        if let target {
            let reference=QRDestinationReference()
            let destination = AppbridgeListButton("Destination: New Library Palette") {
                intoTarget.toggle(); reference.button?.title = intoTarget ? "Destination: " + target.name : "Destination: New Library Palette"
                reference.button?.setAccessibilityLabel(reference.button?.title ?? "Import Destination")
            }
            reference.button=destination; modal.content(destination,height:32)
        }

        modal.button("Cancel"){[weak modal] in modal?.dismissOverlay()}
        modal.button("Import Colours",primary:true){[weak modal] in
            guard !intoTarget || target.map({library.library.swatch($0.id) != nil}) == true else{library.flash("The selected destination is no longer available.");return}
            library.apply("Import Colour QR"){lib in
                _ = try? ColourQR.insert(d,into:&lib,target:intoTarget ? target?.id : nil)
            }
            modal?.dismissOverlay();library.flash("Imported “"+d.name+"”")
        };modal.present(over:view)
    }
}
private final class QRColourPreview:NSView {
    let colours:[ColourQR.Entry]
    init(colours:[ColourQR.Entry]){self.colours=colours;super.init(frame:.zero)}
    required init?(coder:NSCoder){fatalError()}
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){for(i,c)in colours.enumerated(){let width=bounds.width/CGFloat(colours.count);c.master.display.setFill();NSRect(x:CGFloat(i)*width,y:0,width:width+0.5,height:84).fill()};Design.attributed(colours.map{$0.name}.joined(separator:" · "),.body).draw(x:0,baseline:112,width:bounds.width)}
}

private final class QRDestinationReference { weak var button:NSButton? }
