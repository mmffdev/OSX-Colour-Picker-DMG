"""Rebuild the ten document-icon proposals. Requires Pillow and rsvg-convert."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import subprocess, json, html, zipfile
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
INK = '#343C42'
TYPES = [
 ('colproject','Project','core'), ('colpalette','Palette','core'),
 ('colswatch','Swatch','core'), ('colhistory','History','core'),
 ('colcatalogue','Catalogue','core'), ('coldata','Data','core'),
 ('colweb','Screen & Web','purpose'), ('colprint','Print','purpose'),
 ('colphoto','Photography','purpose'), ('colvideo','Video','purpose'),
 ('colcine','Cinema & VFX','purpose'), ('col3d','3D & Games','purpose'),
 ('colsyncproject','Sync project','sync'), ('colsynccatalogue','Sync catalogue','sync')]
STYLES = [
 dict(id='01-instrument', name='Instrument', desc='Quiet paper · precise line symbols', page='#F0F1EE', fold='#D5D9D6', ink='#343C42', accent='#788D81', mode='line'),
 dict(id='02-graphite', name='Graphite', desc='Dark document · luminous line symbols', page='#343A3D', fold='#565F63', ink='#E1E6E5', accent='#A1B8B3', mode='dark'),
 dict(id='03-technical', name='Technical', desc='Drafting frame · square-ended geometry', page='#EDF2F4', fold='#CED9DF', ink='#375569', accent='#7393A6', mode='technical'),
 dict(id='04-recess', name='Recess', desc='Inset instrument panel · soft grey field', page='#F3F2EE', fold='#DADBD6', ink='#3F474B', accent='#8C9888', mode='inset'),
 dict(id='05-silhouette', name='Silhouette', desc='Solid marks · strongest compact presence', page='#ECEFED', fold='#CDD3D0', ink='#35433F', accent='#809B91', mode='solid'),
 dict(id='06-header', name='Header', desc='Dark upper register · open paper below', page='#F0F0EC', fold='#CDD2CE', ink='#3E4643', accent='#879D93', mode='header'),
 dict(id='07-seal', name='Seal', desc='Circular field · centred identifying mark', page='#F0F0EF', fold='#D7D8D6', ink='#46505B', accent='#8997A9', mode='circle'),
 dict(id='08-etched', name='Etched', desc='Flat ivory · open outlines and restrained detail', page='#F8F5ED', fold='#E6E0D3', ink='#5B5549', accent='#A0957A', mode='etched'),
 dict(id='09-margin', name='Margin', desc='Vertical register · generous central symbol', page='#EEF0F0', fold='#D0D7D9', ink='#3E4C54', accent='#7B929E', mode='margin'),
 dict(id='10-plaque', name='Plaque', desc='Dark symbol plate · light paper surround', page='#F0F1ED', fold='#D3D8D1', ink='#39413D', accent='#92A087', mode='plaque')]

def rect(x,y,w,h,fill='none',r=0,stroke=None,sw=None):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"'+(f' stroke="{stroke}"' if stroke else '')+(f' stroke-width="{sw}"' if sw else '')+'/>'
def path(d,fill='none',stroke=None,sw=None):
    return f'<path d="{d}" fill="{fill}"'+(f' stroke="{stroke}"' if stroke else '')+(f' stroke-width="{sw}"' if sw else '')+'/>'
def circle(x,y,r,fill='none',stroke=None,sw=None):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}"'+(f' stroke="{stroke}"' if stroke else '')+(f' stroke-width="{sw}"' if sw else '')+'/>'

def glyph(key, ink, paper, accent, solid=False):
    p=lambda d: path(d,stroke=ink)
    r=lambda x,y,w,h,rr=1: rect(x,y,w,h,ink if solid else 'none',rr,ink)
    c=lambda x,y,rr: circle(x,y,rr,stroke=ink)
    if key=='colproject':
        return path('M19 28V25Q19 23 21 23H28L31 27H43Q45 27 45 29V42Q45 44 43 44H21Q19 44 19 42Z',ink if solid else 'none',ink)+p('M20 30H44')
    if key=='colpalette':
        return ''.join(rect(x,28,7,12,col,1,ink,1.1) for x,col in zip([19,28.5,38],['#899EAE','#95A38B','#B1A185']))
    if key=='colswatch':
        return rect(23,25,18,18,accent,2,ink)+ (p('M27 39H31') if not solid else '')
    if key=='colhistory':
        return c(32,34,12)+p('M32 26V34L38 38')
    if key=='colcatalogue':
        return ''.join(r(x,24,6,21,0.7) for x in [20,29,38])+''.join(path(f'M{x+2} 28H{x+4}',stroke=paper if solid else ink,sw=1.3) for x in [20,29,38])
    if key=='coldata':
        return path('M19 35H27L29 39H35L37 35H45V43Q45 45 43 45H21Q19 45 19 43Z',ink if solid else 'none',ink)+rect(24,24,16,5,accent,1)+rect(24,31,16,2,ink,0.5)
    if key=='colweb':
        return r(19,24,26,21,2)+path('M20 30H44',stroke=paper if solid else ink)+''.join(circle(x,27,0.7,paper if solid else ink) for x in [23,26,29])+(path('M26 34L23 37L26 40M38 34L41 37L38 40',stroke=paper if solid else ink,sw=1.4))
    if key=='colprint':
        return r(19,30,26,11,2)+p('M24 30V23H40V30')+rect(24,36,16,10,paper,0.5,ink)+circle(41,34,1,accent)+path('M28 40H36M28 43H35',stroke=ink,sw=1.1)
    if key=='colphoto':
        return path('M20 28H26L28 24H36L38 28H44Q46 28 46 30V42Q46 44 44 44H20Q18 44 18 42V30Q18 28 20 28Z',ink if solid else 'none',ink)+circle(32,35,6,paper if solid else 'none',paper if solid else ink)+circle(42,31,0.9,accent)
    if key=='colvideo':
        return r(18,25,28,19,2)+path('M29 30L37 34.5L29 39Z',paper if solid else ink)
    if key=='colcine':
        s=r(21,22,22,25,1)+path('M26 23V46M38 23V46',stroke=paper if solid else ink,sw=1.3)
        return s+''.join(rect(x,y,2,2,paper if solid else ink,0.2) for x in [22.5,39.5] for y in [25,31,37,43])+path('M27 34.5H37',stroke=paper if solid else ink,sw=1.3)
    if key=='col3d':
        return path('M32 21L45 28.5V41L32 48L19 41V28.5Z',ink if solid else 'none',ink)+path('M19 28.5L32 36L45 28.5M32 36V48M32 21V35',stroke=paper if solid else ink,sw=1.7)
    # A single composite sync emblem: opposing arcs enclosing the payload.
    s=p('M20 30A13 13 0 0 1 42 25M44 39A13 13 0 0 1 22 44')+path('M37 24L44 23L43 30Z',ink)+path('M27 45L20 46L21 39Z',ink)
    if key=='colsyncproject':
        return s+path('M25 31H30L32 33H39V39H25Z',accent,ink,1.5)
    return s+''.join(rect(x,30,3,10,accent,0.4,ink,1) for x in [26,31,36])

def small_glyph(key,n,ink,paper,accent):
    # Two separately drawn optical masters, in their own pixel grids.
    if n==16:
        p=lambda d: path(d,stroke=ink,sw=1)
        if key=='colproject': return path('M4 6H7L8 7H12V11H4Z',ink)
        if key=='colpalette': return ''.join(rect(x,7,2,3,c) for x,c in [(4,ink),(7,accent),(10,ink)])
        if key=='colswatch': return rect(5,6,6,6,ink,1)+rect(6,7,4,4,accent)
        if key=='colhistory': return circle(8,8.5,3.5,ink)+path('M8 6V8.5L10 10',stroke=paper,sw=1)
        if key=='colcatalogue': return ''.join(rect(x,5,2,7,ink) for x in [4,7,10])+path('M4 7H6M7 7H9M10 7H12',stroke=paper,sw=1)
        if key=='coldata': return path('M4 9H6V10H10V9H12V12H4Z',ink)+rect(5,5,6,1,ink)+rect(5,7,6,1,ink)
        if key=='colweb': return rect(4,5,8,7,ink,0.5)+rect(5,7,6,4,paper)+rect(5,6,2,0.6,paper)
        if key=='colprint': return rect(5,5,6,2,ink)+rect(4,7,8,4,ink,0.5)+rect(6,9,4,3,paper,0,ink,1)
        if key=='colphoto': return path('M4 7H6L7 5H10L11 7H12V12H4Z',ink)+circle(8,9,2,paper)+circle(8,9,1,ink)
        if key=='colvideo': return rect(4,6,8,6,ink,0.5)+path('M7 7L10 9L7 11Z',paper)
        if key=='colcine': return rect(5,5,6,7,ink)+rect(7,6,2,5,paper)+''.join(rect(x,y,1,1,paper) for x in [5,10] for y in [6,8,10])
        if key=='col3d': return path('M8 5L12 7V11L8 13L4 11V7Z',ink)+path('M4.5 7.5L8 9.5L11.5 7.5M8 9.5V12',stroke=paper,sw=0.8)
        s=path('M4 7Q5 4 10 5V4L13 6L10 8V6Q6 5 5 7Z',ink)+path('M12 10Q11 13 6 12V13L3 11L6 9V11Q10 12 11 10Z',ink)
        return s+(path('M6 7.5H8L9 8.5H10V10H6Z',ink) if key=='colsyncproject' else path('M6 7.5V10M8 7.5V10M10 7.5V10',stroke=ink,sw=1))
    # 32 px: lighter than 16 px, larger counters and omitted decorative detail.
    p=lambda d: path(d,stroke=ink,sw=1.5)
    r=lambda x,y,w,h: rect(x,y,w,h,'none',1,ink,1.5)
    if key=='colproject': return path('M9 13V11H14L16 13H23V22H9Z',ink)+path('M10 15H22',stroke=paper,sw=1)
    if key=='colpalette': return ''.join(rect(x,14,4,6,c,0.6) for x,c in [(9,ink),(14,accent),(19,ink)])
    if key=='colswatch': return rect(11,12,10,10,accent,1,ink,1.5)
    if key=='colhistory': return circle(16,17,6,'none',ink,1.5)+p('M16 13V17L19 19')
    if key=='colcatalogue': return ''.join(rect(x,11,3,12,ink,0.5) for x in [10,15,20])+path('M10 14H13M15 14H18M20 14H23',stroke=paper,sw=1)
    if key=='coldata': return path('M9 17H13L14 19H18L19 17H23V23H9Z',ink)+rect(11,11,10,2,accent)+rect(11,14,10,1.5,ink)
    if key=='colweb': return r(9,11,14,12)+p('M10 14.5H22')+path('M12 12.5H15',stroke=ink,sw=1)
    if key=='colprint': return r(9,14,14,7)+p('M12 14V10H20V14')+rect(12,18,8,6,paper,0,ink,1.5)
    if key=='colphoto': return path('M9 14H12L13 11H19L20 14H23V23H9Z',ink)+circle(16,18,3.5,paper)+circle(16,18,2,ink)
    if key=='colvideo': return r(9,12,14,10)+path('M14 14L19 17L14 20Z',ink)
    if key=='colcine': return r(11,10,10,14)+path('M14 11V23M18 11V23M14 17H18',stroke=ink,sw=1)+''.join(rect(x,y,1,1,ink) for x in [12,19] for y in [12,15,18,21])
    if key=='col3d': return p('M16 10L23 14V21L16 25L9 21V14ZM9 14L16 18L23 14M16 18V25')
    s=p('M10 14Q13 7 22 12M22 21Q19 27 10 23')+path('M19 10L24 11L22 16Z',ink)+path('M13 25L8 24L10 19Z',ink)
    return s+(path('M12 15H15L17 17H20V21H12Z',accent,ink,1) if key=='colsyncproject' else ''.join(rect(x,15,2,6,ink) for x in [12,15,18]))

def svg(key, group, st, n=64):
    page,fold,ink,accent=[st[k] for k in ['page','fold','ink','accent']]
    mode=st['mode']; is_small=n<64
    edge='#8E999A' if mode=='dark' else '#959D9B'
    if is_small:
        scale=n/16
        s=f'<g transform="scale({scale})">'+path('M3 1.5H10L13.5 5V14Q13.5 14.5 13 14.5H3Q2.5 14.5 2.5 14V2Q2.5 1.5 3 1.5Z',page,edge,0.7)+path('M10 1.5V5H13.5',fold,edge,0.6)
        if mode=='header': s+=path('M3 2H9.5V4H3Z',ink)
        if mode=='margin': s+=rect(3,5,0.8,7,accent)
        if mode in ['inset','circle','plaque']:
            f=ink if mode=='plaque' else fold
            s+=circle(8,8.5,4.4,f) if mode=='circle' else rect(3.5,4.7,9,8,f,1)
        s+='</g>'
        gi=page if mode=='plaque' else ink
        s+=small_glyph(key,n,gi,ink if mode=='plaque' else page,accent)
        s+=f'<g transform="scale({scale})">'
        if group=='core': s+=rect(4,13,5,0.7,accent)
        elif group=='purpose': s+=rect(4,12.8,5,0.55,accent)+rect(4,13.7,5,0.55,accent)
        else: s+=''.join(rect(x,13.3,1,0.7,accent) for x in [4,6,8])
        s+='</g>'
    else:
        s=path('M13 3H40L54 17V57Q54 61 50 61H14Q10 61 10 57V7Q10 3 13 3Z',page,edge,0.7)
        s+=path('M40 3V14Q40 17 43 17H54',fold,edge,0.7)
        if mode=='technical': s+=path('M15 17V12H20M44 49H49V44',stroke=accent,sw=1)
        if mode=='header': s+=path('M13 4H39V13H11V7Q11 4 13 4Z',ink)+rect(15,8,12,1,accent)
        if mode=='margin': s+=rect(11,19,3,31,accent,1)
        if mode=='inset': s+=rect(15,19,34,31,fold,3)+path('M18 20H46',stroke='#FFFFFF',sw=0.8)
        if mode=='circle': s+=circle(32,34,18,fold)
        if mode=='plaque': s+=rect(15,19,34,31,ink,2)
        gi=page if mode=='plaque' else ink
        sw=1.5 if mode=='etched' else 2 if mode=='technical' else 2.2
        cap='square' if mode in ['technical','etched'] else 'round'
        s+=f'<g stroke-width="{sw}" stroke-linejoin="round" stroke-linecap="{cap}">'+glyph(key,gi,ink if mode=='plaque' else page,accent,mode=='solid')+'</g>'
        if group=='core': s+=rect(19,53,18,1.6,accent,0.6)
        elif group=='purpose': s+=rect(19,52,18,1.2,accent,0.5)+rect(19,55,18,1.2,accent,0.5)
        else: s+=''.join(rect(x,53,4,1.6,accent,0.5) for x in [19,26,33])
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{n}" height="{n}" viewBox="0 0 {n} {n}"><title>{key} — {st["name"]}</title>{s}</svg>'

def font(n,bold=False): return ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial'+(' Bold' if bold else '')+'.ttf',n)
def txt(draw,xy,t,size=16,fill='#343C42',bold=False): draw.text(xy,t,font=font(size,bold),fill=fill)
def render(job):
    src,dst,size=job
    subprocess.run(['rsvg-convert','-w',str(size),'-h',str(size),'-o',str(dst),str(src)],check=True)

def make_sheet(st):
    # Exact device pixels: each size is shown at 1:1 on both backgrounds.
    width=3920
    sheet=Image.new('RGB',(width,4068),'#ECEEEB'); d=ImageDraw.Draw(sheet)
    txt(d,(40,25),f'{st["id"][:2]}  /  {st["name"]}',34,bold=True)
    txt(d,(40,70),st['desc']+'  •  14 related document types',20)
    y=116
    for size in [16,32,128,512]:
        rowh=size+54
        for bg,label in [('#F4F4F1','LIGHT'),('#202427','DARK')]:
            h=rowh*2+42
            d.rectangle((0,y,width,y+h),fill=bg)
            fg='#DCE0DF' if label=='DARK' else '#454D4C'
            txt(d,(24,y+9),f'{size} px  /  {label}',18,fg,True)
            for i,(key,name,group) in enumerate(TYPES):
                x=20+(i%7)*556; yy=y+40+(i//7)*rowh
                im=Image.open(ROOT/st['id']/'png'/key/f'{key}_{size}.png').convert('RGBA')
                sheet.paste(im,(x+(536-size)//2,yy),im)
                tw=d.textbbox((0,0),'.'+key,font=font(16))[2]
                txt(d,(x+(536-tw)//2,yy+size+8),'.'+key,16,fg)
            y+=h
    sheet=sheet.crop((0,0,width,y))
    sheet.save(ROOT/st['id']/'contact-sheet.png')
    # Readable presentation board, 128px and pixel-size rows.
    board=Image.new('RGB',(1560,980),'#ECEEEB'); d=ImageDraw.Draw(board)
    txt(d,(32,22),f'{st["id"][:2]}  /  {st["name"]}',30,bold=True)
    txt(d,(32,62),st['desc'],18)
    for panel,bg in enumerate(['#F4F4F1','#202427']):
        yy=102+panel*434; d.rectangle((0,yy,1560,yy+434),fill=bg)
        fg='#DCE0DF' if panel else '#454D4C'
        for i,(key,name,group) in enumerate(TYPES):
            x=14+(i%7)*220; y=yy+16+(i//7)*204
            im=Image.open(ROOT/st['id']/'png'/key/f'{key}_128.png').convert('RGBA'); board.paste(im,(x+44,y),im)
            txt(d,(x+12,y+129),name,16,fg)
            for sz,dx in [(16,66),(32,103)]:
                im=Image.open(ROOT/st['id']/'png'/key/f'{key}_{sz}.png').convert('RGBA'); board.paste(im,(x+dx,y+155+(32-sz)//2),im)
    board.save(ROOT/st['id']/'preview.png')

def main():
    jobs=[]
    for st in STYLES:
        dest=ROOT/st['id']; (dest/'svg').mkdir(parents=True,exist_ok=True)
        for key,name,group in TYPES:
            for optical in [64,16,32]:
                suffix='' if optical==64 else f'.{optical}'
                (dest/'svg'/f'{key}{suffix}.svg').write_text(svg(key,group,st,optical))
            pd=dest/'png'/key; pd.mkdir(parents=True,exist_ok=True)
            for logical in [16,32,64,128,256,512,1024]:
                src=dest/'svg'/f'{key}{"."+str(logical) if logical<64 else ""}.svg'
                for density in [1,2]:
                    dst=pd/f'{key}_{logical}{"@2x" if density==2 else ""}.png'
                    jobs.append((src,dst,logical*density))
    with ThreadPoolExecutor(max_workers=6) as pool: list(pool.map(render,jobs))
    for st in STYLES: make_sheet(st)
    overview=Image.new('RGB',(1960,1600),'#ECEEEB'); d=ImageDraw.Draw(overview)
    txt(d,(24,18),'DOCUMENT ICONS / TEN COORDINATED FAMILIES',30,bold=True)
    txt(d,(24,59),'6 core  /  6 purposes  /  2 sync    •    Each row is a complete family',18)
    for i,(key,name,group) in enumerate(TYPES):
        x=235+i*122
        txt(d,(x,105),name,12)
    for row,st in enumerate(STYLES):
        y=135+row*144; bg='#F4F4F1' if row%2==0 else '#E4E7E4'
        d.rectangle((0,y,1960,y+143),fill=bg)
        txt(d,(24,y+42),st['id'][:2],20,st['ink'] if st['mode']!='dark' else INK,True)
        txt(d,(65,y+43),st['name'],20,bold=True)
        for i,(key,name,group) in enumerate(TYPES):
            im=Image.open(ROOT/st['id']/'png'/key/f'{key}_128.png').convert('RGBA').resize((104,104),Image.Resampling.LANCZOS)
            overview.paste(im,(230+i*122,y+14),im)
        for x in [954,1686]: d.line((x,y+20,x,y+120),fill='#C5CBC7',width=1)
    overview.save(ROOT/'overview.png')
    (ROOT/'manifest.json').write_text(json.dumps({'families':STYLES,'types':TYPES,'logical_sizes':[16,32,64,128,256,512,1024],'densities':[1,2]},indent=2))
    cards=''.join(f'<section id="{s["id"]}"><h2>{s["id"][:2]} / {s["name"]}</h2><p>{s["desc"]}</p><a href="{s["id"]}/contact-sheet.png">Full contact sheet: 16, 32, 128 and 512 px</a><img src="{s["id"]}/preview.png" alt="{s["name"]}: all fourteen document icons on light and dark backgrounds"></section>' for s in STYLES)
    (ROOT/'index.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Document icon families</title><style>body{margin:0;background:#eceeeb;color:#343c42;font:16px system-ui}main{max-width:1560px;margin:auto;padding:32px}h1{font-size:32px}h2{margin-bottom:8px}p{line-height:1.6}img{display:block;width:100%;height:auto;margin:22px 0 50px}a{color:#375569}nav{display:flex;flex-wrap:wrap;gap:18px}section{padding-top:24px;border-top:1px solid #c5cbc7}</style><main><h1>Ten coordinated document-icon families</h1><p>Fourteen file types per family. Each numbered proposal is a complete set. The small rows use dedicated 16 and 32 px optical drawings. No product name, app badge or third-party marks are included.</p><nav>'+''.join(f'<a href="#{s["id"]}">{s["id"][:2]} {s["name"]}</a>' for s in STYLES)+'</nav><img src="overview.png" alt="All 140 icons, organised into ten family rows">'+cards+'</main></html>')
    print(f'Generated {len(jobs)} PNGs, 420 SVGs, ten contact sheets, ten preview boards and an overview.')

if __name__=='__main__': main()
