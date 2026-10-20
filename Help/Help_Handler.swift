import AppKit
import WebKit

/// One local help catalogue, shared by header controls, the app help index and the Help menu.
/// Read surfaces use the incumbent Swiss typography and rules; diagrams explain actual UI actions.
final class Help_Handler: NSObject {
    struct Page {
        let id: String, title: String, file: String, sections: [String]
    }
    static let shared = Help_Handler()
    static let supportEmail = "support@colorgain.com"
    static var supportURL: URL { URL(string: "mailto:" + supportEmail)! }
    static let pages: [Page] = [
        .init(id:"index",title:"Overview",file:"Help_Index",sections:[]),
        .init(id:"catalogues",title:"Library",file:"Help_Library",sections:["catalogues","favourites","folders","my-palettes"]),
        .init(id:"palette-page",title:"Palette Page",file:"Help_Palette_Page",sections:["start","ownership","navigation","reading","presets","workflow","target","rendering","tolerance","delta-view","analysis","organise","footer","layouts","routine","troubleshooting","glossary","references"]),
        .init(id:"halo",title:"Halo",file:"Help_Halo",sections:["purpose","opening","navigation","palette-actions","colour-actions","destinations","confirmation","settings"]),
        .init(id:"icc-profiles",title:"ICC Profiles",file:"Help_ICC_Profiles",sections:[]),
        .init(id:"histograms",title:"Histograms",file:"Help_Histograms",sections:[]),
        .init(id:"bloom",title:"Delta Bloom",file:"Help_Delta_Bloom",sections:[]),
        .init(id:"inspector",title:"Inspector",file:"Help_Inspector",sections:[]),
        .init(id:"image-source",title:"Image Source",file:"Help_Image_Source",sections:[]),
        .init(id:"image-target",title:"Image Destination",file:"Help_Image_Destination",sections:[])
    ]
    static func page(_ id:String) -> Page? { pages.first{$0.id == id} }
    static func resource(_ page:Page) -> URL? {
        Bundle.main.url(forResource:page.file,withExtension:"html",subdirectory:"HelpResources")
            ?? Bundle.main.url(forResource:page.file,withExtension:"html",subdirectory:"Resources")
            ?? Bundle.main.url(forResource:page.file,withExtension:"html")
    }
    private var reader: Help_Reader?
    func open(_ id:String = "index", section:String? = nil) {
        guard let page=Self.page(id) else {return}
        if reader == nil {reader=Help_Reader()}
        reader?.open(page,section:section.flatMap{page.sections.contains($0) ? $0:nil})
    }
    func menu() -> NSMenu {
        let menu=NSMenu(title:"Help")
        let index=NSMenuItem(title:"Colorgain Help",action:#selector(showIndex),keyEquivalent:"?")
        index.target=self;menu.addItem(index);menu.addItem(.separator())
        for page in Self.pages where page.id != "index" {
            let item=NSMenuItem(title:page.title,action:#selector(showPage(_:)),keyEquivalent:"")
            item.target=self;item.representedObject=page.id;menu.addItem(item)
        }
        menu.addItem(.separator())
        let contact=NSMenuItem(title:"Contact Support…",action:#selector(contactSupport),keyEquivalent:"")
        contact.target=self;menu.addItem(contact)
        let copy=NSMenuItem(title:"Copy Support Email",action:#selector(copySupportEmail),keyEquivalent:"")
        copy.target=self;menu.addItem(copy)
        return menu
    }
    @objc fileprivate func contactSupport(){
        if !NSWorkspace.shared.open(Self.supportURL) {
            let alert=NSAlert();alert.messageText="Contact Support"
            alert.informativeText="Email \(Self.supportEmail). No email app could be opened."
            alert.addButton(withTitle:"Copy Email Address");alert.addButton(withTitle:"Close")
            if alert.runModal() == .alertFirstButtonReturn {copySupportEmail()}
        }
    }
    @objc private func copySupportEmail(){NSPasteboard.general.clearContents();NSPasteboard.general.setString(Self.supportEmail,forType:.string)}
    @objc private func showIndex(){open()}
    @objc private func showPage(_ sender:NSMenuItem){if let id=sender.representedObject as? String{open(id)}}
}

/// Header geometry is shared so panel and section help marks occupy one vertical plane.
final class Help_HexButton: NSButton {
    static let trailingInset:CGFloat=20
    static let slot:CGFloat=28
    /// Helvetica Neue header ink sits a point below the geometric centre of its line box.
    static let opticalOffset:CGFloat=1
    var pageID="catalogues",sectionID:String?
    private var hovered=false
    init(page:String,section:String?=nil,title:String) {
        pageID=page;sectionID=section
        super.init(frame:.zero)
        isBordered=false;target=self;action=#selector(openHelp)
        toolTip="Help: "+title;setAccessibilityLabel("Help: "+title)
        watchTheme(self)
    }
    required init?(coder:NSCoder){fatalError()}
    static func frame(width:CGFloat,height:CGFloat)->NSRect {
        NSRect(x:width-trailingInset-slot/2,y:(height-slot)/2+opticalOffset,width:slot,height:slot)
    }
    @objc private func openHelp(){Help_Handler.shared.open(pageID,section:sectionID)}
    override func acceptsFirstMouse(for event:NSEvent?)->Bool{true}
    override func resetCursorRects(){addCursorRect(bounds,cursor:.pointingHand)}
    override func updateTrackingAreas(){super.updateTrackingAreas();trackingAreas.forEach(removeTrackingArea);addTrackingArea(NSTrackingArea(rect:.zero,options:[.inVisibleRect,.mouseEnteredAndExited,.activeAlways],owner:self))}
    override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
    override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
    override func draw(_ dirtyRect:NSRect){
        let active=hovered || isHighlighted
        let ground=active ? Design.orange:Design.card
        let colour=contrastRatio("#666666",hexOf(ground) ?? "#FFFFFF") >= 4.5 ? Design.hex("#666666"):ThemedButton.readable(on:ground)
        let path=NSBezierPath(),radius:CGFloat=9
        for i in 0..<6 {
            let angle=CGFloat(i)*CGFloat.pi/3+CGFloat.pi/6
            let point=NSPoint(x:bounds.midX+cos(angle)*radius,y:bounds.midY+sin(angle)*radius)
            if i == 0{path.move(to:point)}else{path.line(to:point)}
        }
        path.close()
        if active {Design.orange.setFill();path.fill()}
        colour.setStroke();path.lineWidth=1.25;path.stroke()
        let text=Design.attributed("?",.body,colour:colour)
        text.draw(at:NSPoint(x:bounds.midX-text.size().width/2,y:bounds.midY-text.size().height/2))
        if window?.firstResponder === self {NSBezierPath(rect:bounds.insetBy(dx:2,dy:2)).stroke()}
    }
}

private final class Help_Window:NSWindow {
    override func performKeyEquivalent(with event:NSEvent)->Bool {
        if event.modifierFlags.intersection([.command,.control,.option,.shift]) == .command,event.charactersIgnoringModifiers == "w" {performClose(nil);return true}
        return super.performKeyEquivalent(with:event)
    }
    override func cancelOperation(_ sender:Any?){performClose(sender)}
}

private final class Help_Reader: NSWindowController, WKNavigationDelegate {
    private let web=WKWebView(frame:.zero)
    private var section:String?
    init(){
        let window=Help_Window(contentRect:NSRect(x:0,y:0,width:940,height:720),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        window.title="Colorgain Help";window.minSize=NSSize(width:600,height:440);window.isReleasedWhenClosed=false
        super.init(window:window);web.navigationDelegate=self;window.contentView=web;window.center()
    }
    required init?(coder:NSCoder){fatalError()}
    func open(_ page:Help_Handler.Page,section:String?){
        self.section=section;window?.title="Colorgain Help — "+page.title
        let content=Help_Handler.resource(page).flatMap{try? String(contentsOf:$0,encoding:.utf8)} ?? "<h1>Help Unavailable</h1><p>This bundled help page could not be loaded. Please reinstall the app.</p>"
        let index=Help_Handler.pages.map{"<a href=\"help://\($0.id)\" \($0.id == page.id ? "aria-current=\"page\"":"")>\($0.title)</a>"}.joined()
        let ground=hexOf(Design.card) ?? "#FFFFFF",ink=hexOf(Design.ink) ?? "#161616",rule=hexOf(Design.rule) ?? "#CFCDC7"
        let css="""
        *{box-sizing:border-box}html{scroll-behavior:auto}::-webkit-scrollbar{width:16px}::-webkit-scrollbar-thumb{background:#F4BE00;border:5px solid \(ground)}body{margin:0;background:\(ground);color:\(ink);font:15px/1.65 'Helvetica Neue',Helvetica,Arial,sans-serif}a{color:inherit;text-underline-offset:4px}a:focus-visible{outline:2px solid currentColor;outline-offset:4px}nav{position:fixed;inset:0 auto 0 0;width:200px;padding:28px 20px;border-right:1px solid \(rule);overflow:auto}nav strong{display:block;font-size:20px;margin-bottom:24px}nav a{display:block;margin:0 0 12px}nav [aria-current]{font-weight:500}main{margin-left:200px;padding:32px 40px 70vh;max-width:960px}h1{font-size:36px;font-weight:300;line-height:1.2;margin:0 0 20px}h2{font-size:24px;font-weight:400;margin:44px 0 14px;padding-top:20px;border-top:2px solid currentColor;scroll-margin-top:24px}h3{font-size:17px;font-weight:500}p{margin:0 0 18px}.contents a{display:inline-block;margin:0 18px 8px 0}.diagram{border:1px solid \(rule);padding:20px;margin:24px 0}.diagram strong{display:block}.diagram .row{display:flex;justify-content:space-between;gap:16px;padding:8px 0;border-bottom:1px solid \(rule)}.diagram .indent{padding-left:24px}.diagram .indent2{padding-left:48px}.flow{display:flex;flex-wrap:wrap;align-items:center;gap:12px}.flow span{padding:8px 12px;border:1px solid currentColor}figcaption{font-size:13px;margin-top:12px}code{font-family:inherit;font-weight:500}ul{padding-left:20px}svg{max-width:100%;height:auto;stroke:currentColor;fill:none} @media(max-width:700px){nav{position:static;width:auto;border-right:0;border-bottom:1px solid \(rule)}nav a{display:inline-block;margin-right:16px}main{margin-left:0;padding:24px 24px 70vh}}
        """
        let contentsCSS="""
        .page-contents{position:fixed;left:200px;top:0;bottom:0;width:190px;padding:32px 16px;border-right:1px solid \(rule);overflow:auto}.page-contents strong{display:block;margin-bottom:16px;font-weight:500}.page-contents a{display:block;padding:6px 8px;margin:0 0 4px;border-left:3px solid transparent;text-decoration:none;font-size:13px;line-height:1.45}.page-contents a[aria-current="location"]{border-left-color:#F4BE00;background:color-mix(in srgb,\(ink) 6%,\(ground));font-weight:500}body.has-contents main{margin-left:390px;max-width:1180px;padding-left:28px;padding-right:28px}table{width:100%;border-collapse:collapse;margin:20px 0}th,td{text-align:left;vertical-align:top;padding:10px 8px;border-bottom:1px solid \(rule)}th{font-weight:500}.note{border-left:3px solid #F4BE00;padding:12px 16px;margin:24px 0;background:color-mix(in srgb,\(ink) 3%,\(ground))}section{scroll-margin-top:24px}h2:focus{outline:none}.steps li{margin-bottom:12px}@media(max-width:760px){.page-contents{position:sticky;top:0;left:auto;width:auto;max-height:28vh;background:\(ground);border-right:0;border-bottom:1px solid \(rule);padding:12px 20px;z-index:2}.page-contents a{display:inline-block;margin-right:8px}body.has-contents main{margin-left:0;padding:24px 24px 70vh}}
        """
        let contentsScript="""
        <script>
        (()=>{
          const headings=[...document.querySelectorAll('main h2')];
          if(!headings.length)return;
          const aside=document.createElement('aside');aside.className='page-contents';aside.setAttribute('aria-label','Contents for this page');
          const title=document.createElement('strong');title.textContent='On This Page';aside.append(title);
          const links=headings.map((heading,index)=>{
            if(!heading.id)heading.id='section-'+index;
            const link=document.createElement('a');link.href='#'+heading.id;link.textContent=heading.textContent;aside.append(link);
            link.addEventListener('click',event=>{event.preventDefault();heading.scrollIntoView({block:'start'});heading.tabIndex=-1;heading.focus({preventScroll:true});update();});return link;
          });
          document.body.insertBefore(aside,document.querySelector('main'));document.body.classList.add('has-contents');
          function update(){let active=0;headings.forEach((heading,index)=>{if(heading.getBoundingClientRect().top<=100)active=index;});links.forEach((link,index)=>{if(index===active)link.setAttribute('aria-current','location');else link.removeAttribute('aria-current');});}
          let pending=false;window.addEventListener('scroll',()=>{if(!pending){pending=true;requestAnimationFrame(()=>{update();pending=false;});}},{passive:true});window.addEventListener('resize',update);update();
        })();
        </script>
        """
        web.loadHTMLString("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>\(page.title)</title><style>\(css)\(contentsCSS)</style></head><body><nav aria-label=\"Help topics\"><strong>Colorgain Help</strong>\(index)</nav><main>\(content)</main>\(contentsScript)</body></html>",baseURL:nil)
        showWindow(nil);window?.makeKeyAndOrderFront(nil)
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){
        if let section {let quoted=String(data:try! JSONEncoder().encode(section),encoding:.utf8)!;webView.evaluateJavaScript("document.getElementById(\(quoted))?.scrollIntoView()",completionHandler:nil)}
    }
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
        guard let url=action.request.url else{decisionHandler(.cancel);return}
        if url.scheme == "help",let id=url.host {Help_Handler.shared.open(id,section:url.fragment);decisionHandler(.cancel)}
        else if url.scheme == "about" {decisionHandler(.allow)}
        else if action.navigationType == .linkActivated,url == Help_Handler.supportURL {
            Help_Handler.shared.contactSupport();decisionHandler(.cancel)
        }
        else {if action.navigationType == .linkActivated,url.scheme == "https" {NSWorkspace.shared.open(url)};decisionHandler(.cancel)}
    }
}
