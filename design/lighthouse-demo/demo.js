import * as THREE from './vendor/three.module.js';
const TAU=Math.PI*2, reduced=matchMedia('(prefers-reduced-motion: reduce)');
let seed=83;const random=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296};
const material=(color,opts={})=>new THREE.MeshStandardMaterial({color,roughness:.88,flatShading:true,...opts});
const slate=[0x454e60,0x576174,0x65717b,0x384655],grass=[0xb4c960,0xc8d56a,0x9eb95b,0xd4db7a,0x85a760];
const cream=material(0xf5efdc),iron=material(0x33434c),coral=material(0xe56f5d),sand=material(0xd8cda4);
const mesh=(geo,mat,parent,x=0,y=0,z=0)=>{const m=new THREE.Mesh(geo,mat);m.position.set(x,y,z);m.castShadow=true;m.receiveShadow=true;parent.add(m);return m};
function cylinder(parent,r0,r1,h,mat,y=0,n=12){return mesh(new THREE.CylinderGeometry(r1,r0,h,n),mat,parent,0,y+h/2,0)}
function line(parent,points,color,opacity=1){const l=new THREE.Line(new THREE.BufferGeometry().setFromPoints(points.map(p=>new THREE.Vector3(...p))),new THREE.LineBasicMaterial({color,transparent:true,opacity,depthWrite:false}));parent.add(l);return l}
function rock(parent,x,z,size,height,y=0){const n=6, rings=[[],[],[]],positions=[];for(let i=0;i<n;i++){const a=i/n*TAU,r=.85+random()*.25;rings[0].push([Math.cos(a)*size*r,0,Math.sin(a)*size*r*.85]);rings[1].push([Math.cos(a+.16)*size*r*.9,height*.48,Math.sin(a+.16)*size*r*.8]);rings[2].push([Math.cos(a)*size*r*.43,height,Math.sin(a)*size*r*.43])}for(let k=0;k<2;k++)for(let i=0;i<n;i++){const j=(i+1)%n;positions.push(...rings[k][i],...rings[k+1][i],...rings[k][j],...rings[k][j],...rings[k+1][i],...rings[k+1][j])}for(let i=0;i<n;i++)positions.push(...rings[2][i],0,height,0,...rings[2][(i+1)%n]);const geo=new THREE.BufferGeometry();geo.setAttribute('position',new THREE.Float32BufferAttribute(positions,3));geo.computeVertexNormals();const r=mesh(geo,material(slate[Math.floor(random()*slate.length)],{side:THREE.DoubleSide}),parent,x,y,z);return r}
function turf(parent){const n=18,outer=[],inner=[];for(let i=0;i<n;i++){const a=i/n*TAU,r=2.35+random()*.48;outer.push([Math.cos(a)*r,.58+random()*.3,Math.sin(a)*r]);inner.push([Math.cos(a)*r*.6,1.01+random()*.09,Math.sin(a)*r*.6])}const positions=[],colors=[];const tri=(a,b,c,color)=>{const co=new THREE.Color(color);for(const v of [a,b,c]){positions.push(...v);colors.push(co.r,co.g,co.b)}};for(let i=0;i<n;i++){const j=(i+1)%n,b=[outer[i][0]*1.04,-.5,outer[i][2]*1.04],bj=[outer[j][0]*1.04,-.5,outer[j][2]*1.04];tri(outer[i],outer[j],inner[i],grass[i%5]);tri(outer[j],inner[j],inner[i],grass[(i+2)%5]);tri(inner[i],inner[j],[0,1.06,0],grass[(i+1)%5]);tri(outer[i],b,outer[j],slate[i%4]);tri(b,bj,outer[j],slate[(i+1)%4]);}const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute(positions,3));g.setAttribute('color',new THREE.Float32BufferAttribute(colors,3));g.computeVertexNormals();mesh(g,material(0xffffff,{vertexColors:true,side:THREE.DoubleSide}),parent);return outer}
function spiralTexture(){const c=document.createElement('canvas');c.width=1024;c.height=2048;const x=c.getContext('2d');x.fillStyle='#f5efdc';x.fillRect(0,0,c.width,c.height);x.fillStyle='#e56f5d';for(let i=-5;i<6;i++){const y=i*1024;x.beginPath();x.moveTo(0,y);x.lineTo(1024,y-1024);x.lineTo(1024,y-610);x.lineTo(0,y+414);x.closePath();x.fill()}const t=new THREE.CanvasTexture(c);t.colorSpace=THREE.SRGBColorSpace;t.wrapS=THREE.RepeatWrapping;return t}
const spiralMap=spiralTexture();
function windowOn(parent,r,y,angle,door=false){const holder=new THREE.Group();holder.position.set(Math.sin(angle)*r,y,Math.cos(angle)*r);holder.rotation.y=angle;parent.add(holder);const w=door?.29:.17,h=door?.56:.33;mesh(new THREE.BoxGeometry(w+.07,h+.06,.045),cream,holder,0,h/2,0);mesh(new THREE.BoxGeometry(w,h,.052),material(door?0x624c3e:0x253e4b),holder,0,h/2,.025);if(!door){mesh(new THREE.BoxGeometry(.022,h,.015),iron,holder,0,h/2,.055);mesh(new THREE.BoxGeometry(w+.1,.035,.09),cream,holder,0,-.015,.02)}}
function sceneFor(id,twisting){seed=83;const host=document.getElementById(id),scene=new THREE.Scene(),renderer=new THREE.WebGLRenderer({antialias:true,alpha:true});renderer.setPixelRatio(Math.min(devicePixelRatio,2));renderer.setClearColor(0xeaf0f3,0);renderer.shadowMap.enabled=true;renderer.shadowMap.type=THREE.PCFSoftShadowMap;renderer.outputColorSpace=THREE.SRGBColorSpace;renderer.toneMapping=THREE.ACESFilmicToneMapping;renderer.toneMappingExposure=1.22;host.append(renderer.domElement);
const camera=new THREE.PerspectiveCamera(32,1,.1,100);camera.position.set(19,11.6,26);camera.lookAt(0,11.6,0); // Horizontal optical axis: verticals remain parallel (two-point perspective).
scene.add(new THREE.HemisphereLight(0xf4fbff,0x728995,2.3));const sun=new THREE.DirectionalLight(0xfff0d1,3.3);sun.position.set(-6,15,7);sun.castShadow=true;sun.shadow.mapSize.set(2048,2048);Object.assign(sun.shadow.camera,{left:-8,right:8,top:12,bottom:-8,near:.1,far:45});sun.shadow.normalBias=.045;sun.shadow.bias=-.0001;sun.shadow.radius=3;scene.add(sun);
const ground=mesh(new THREE.PlaneGeometry(200,200),new THREE.ShadowMaterial({opacity:.12}),scene,0,-2.27,0);ground.rotation.x=-Math.PI/2;ground.castShadow=false;
const root=new THREE.Group();scene.add(root);const island=new THREE.Group();root.add(island);mesh(new THREE.BoxGeometry(8.6,.15,8.6),sand,island,0,-2.15,0);
for(let i=0;i<32;i++){const a=random()*TAU,r=2.8+random()*1.2;rock(island,Math.cos(a)*r,Math.sin(a)*r,.16+random()*.37,.18+random()*.55,-2.02)}
// A quiet web of refracted light on the visible seabed.
for(let i=0;i<21;i++){const pts=[];const z=-4.15+i*.41;for(let j=0;j<=32;j++){const x=-4.2+j*.262;pts.push([x,-2.062,z+.1*Math.sin(j*.95+i)])}line(island,pts,0xbef0d4,.24)}
const seaMaterial=new THREE.MeshPhysicalMaterial({color:0x1599a7,transparent:true,opacity:.48,roughness:.2,metalness:0,side:THREE.DoubleSide,depthWrite:false});
const walls=[];for(let i=0;i<4;i++){const g=new THREE.PlaneGeometry(8.6,2.1,50,1);const m=mesh(g,seaMaterial,island);m.castShadow=false;m.receiveShadow=false;m.position.y=-1.05;if(i<2){m.position.z=i?4.3:-4.3;m.rotation.y=i?0:Math.PI}else{m.position.x=i===2?4.3:-4.3;m.rotation.y=i===2?Math.PI/2:-Math.PI/2}m.material=seaMaterial.clone();m.material.color.setHex(i===2?0x08728d:0x169ea9);m.renderOrder=3;walls.push(m)}
const waterGeo=new THREE.PlaneGeometry(8.6,8.6,44,44);waterGeo.rotateX(-Math.PI/2);const water=mesh(waterGeo,new THREE.MeshPhongMaterial({color:0x188e9f,transparent:true,opacity:.62,shininess:85,specular:0xa7ede1,side:THREE.DoubleSide,depthWrite:false}),island);water.castShadow=false;water.receiveShadow=true;water.renderOrder=2;
const outline=[];for(let side=0;side<4;side++)for(let j=0;j<65;j++){const q=-4.3+j/64*8.6;outline.push(side===0?[q,0,-4.3]:side===1?[4.3,0,q]:side===2?[-q,0,4.3]:[-4.3,0,-q])}outline.push(outline[0].slice());const edge=line(island,outline,0xe6ffff,.85);edge.renderOrder=5;
const shore=turf(island);
function shoreRadius(a){const f=((a/TAU)%1+1)%1*shore.length,i=Math.floor(f),u=f-i,p=shore[i],q=shore[(i+1)%shore.length];return Math.hypot(p[0],p[2])*(1-u)+Math.hypot(q[0],q[2])*u}
// Large rear outcrops and smaller shore rocks frame the tower without hiding its doorway.
[[-1.45,-.95,.65,1.8],[-1.95,-.1,.53,1.05],[1.4,-1.15,.7,1.55],[2,-.45,.48,1.15],[-2.1,1.03,.57,.95],[1.9,1.25,.62,.9],[-.8,-1.8,.6,1.4],[.3,-2,.45,1.05]].forEach(([x,z,r,h])=>{rock(island,x,z,r,h,.35);const cap=mesh(new THREE.ConeGeometry(r*.46,.035,6),material(grass[Math.floor(random()*5)]),island,x,.35+h+.01,z);cap.rotation.y=.3});
for(let i=0;i<18;i++){const a=random()*TAU,r=1.4+random()*1.35;rock(island,Math.cos(a)*r,Math.sin(a)*r,.10+random()*.18,.16+random()*.24,.67)}
// Narrow sandy path curves from the doorway down to the water.
const pathPts=[[.2,.99,.7],[.45,.99,1.2],[.18,.91,1.65],[.65,.77,2.13],[.95,.55,2.57]],pv=[];for(let i=0;i<pathPts.length-1;i++){const a=pathPts[i],b=pathPts[i+1],w=.14;pv.push(a[0]-w,a[1]+.03,a[2],a[0]+w,a[1]+.03,a[2],b[0]-w,b[1]+.03,b[2],a[0]+w,a[1]+.03,a[2],b[0]+w,b[1]+.03,b[2],b[0]-w,b[1]+.03,b[2])}const pg=new THREE.BufferGeometry();pg.setAttribute('position',new THREE.Float32BufferAttribute(pv,3));pg.computeVertexNormals();mesh(pg,material(0xe1d39a,{side:THREE.DoubleSide}),island);
for(let i=0;i<60;i++){const a=random()*TAU,r=1.05+random()*1.55,x=Math.cos(a)*r,z=Math.sin(a)*r;const g=new THREE.BufferGeometry();g.setAttribute('position',new THREE.Float32BufferAttribute([x,.94,z,x+.04,.94,z,x-.02,1.07+random()*.16,z+.02],3));g.computeVertexNormals();mesh(g,material(grass[i%5],{side:THREE.DoubleSide}),island)}
const ripples=[];for(let k=0;k<3;k++){const pts=Array.from({length:145},()=>[0,0,0]);const l=line(island,pts,0xeaffed,.5);l.renderOrder=5;ripples.push(l)}
const foam=[];for(let k=0;k<12;k++){const pts=Array.from({length:12},()=>[0,0,0]);const l=line(island,pts,0xf5ffef,.68);l.renderOrder=5;foam.push(l)}
const stages=[island];const towerBase=1.01,sh=1.34;
for(let i=0;i<4;i++){const group=new THREE.Group();group.position.y=towerBase+i*sh;root.add(group);stages.push(group);const r0=.83-i*.105,r1=.83-(i+1)*.105;let mat=i%2?coral:cream;const geo=new THREE.CylinderGeometry(r1,r0,sh,12,32);if(twisting){const uv=geo.attributes.uv;for(let j=0;j<uv.count;j++)uv.setY(j,(uv.getY(j)+i)/4);mat=material(0xffffff,{map:spiralMap})}mesh(geo,mat,group,0,sh/2,0);windowOn(group,(r0+r1)/2+.017,.43,Math.PI/6,i===0);if(i===0)windowOn(group,r0-.02,.54,-Math.PI/3);}
const gallery=new THREE.Group();gallery.position.y=towerBase+4*sh;root.add(gallery);stages.push(gallery);cylinder(gallery,.42,.69,.23,cream);cylinder(gallery,.76,.76,.11,iron,.23);cylinder(gallery,.7,.7,.035,iron,.75);cylinder(gallery,.7,.7,.026,iron,.53); // Replace solid railing bands with open torus rails.
for(let i=gallery.children.length-1;i>=2;i--){gallery.remove(gallery.children[i])}
for(const y of [.43,.72]){const rail=mesh(new THREE.TorusGeometry(.71,.022,4,12),iron,gallery,0,y,0);rail.rotation.x=Math.PI/2}
for(let i=0;i<12;i++){const a=i/12*TAU;mesh(new THREE.CylinderGeometry(.018,.018,.4,5),iron,gallery,Math.sin(a)*.71,.53,Math.cos(a)*.71)}
const lamp=new THREE.Group();lamp.position.y=towerBase+4*sh+.34;root.add(lamp);stages.push(lamp);const glass=material(0xffd580,{transparent:true,opacity:.47,roughness:.16,emissive:0xffb944,emissiveIntensity:.2,depthWrite:false});cylinder(lamp,.43,.43,.79,glass);cylinder(lamp,.46,.46,.065,iron,.79);for(let i=0;i<8;i++){const a=i/8*TAU;mesh(new THREE.CylinderGeometry(.018,.018,.79,5),iron,lamp,Math.sin(a)*.435,.395,Math.cos(a)*.435)}
cylinder(lamp,.62,.05,.48,coral,.85,8);cylinder(lamp,.075,.035,.2,iron,1.32,8);const bulb=mesh(new THREE.SphereGeometry(.145,12,8),material(0xffeaa1,{emissive:0xffbd45,emissiveIntensity:2}),lamp,0,.41,0);const light=new THREE.PointLight(0xffb94e,2,3);light.position.set(0,.4,0);lamp.add(light);
const haloCanvas=document.createElement('canvas');haloCanvas.width=128;haloCanvas.height=128;const hc=haloCanvas.getContext('2d'),hg=hc.createRadialGradient(64,64,2,64,64,64);hg.addColorStop(0,'rgba(255,217,121,.55)');hg.addColorStop(.3,'rgba(255,217,121,.13)');hg.addColorStop(1,'rgba(255,217,121,0)');hc.fillStyle=hg;hc.fillRect(0,0,128,128);const halo=new THREE.Sprite(new THREE.SpriteMaterial({map:new THREE.CanvasTexture(haloCanvas),transparent:true,depthWrite:false}));halo.position.y=.41;halo.scale.set(2.2,2.2,1);lamp.add(halo);
// Smoke lives in world space at each construction joint, never in the rotating tower group.
// Overlapping lobes begin as a continuous horizontal cloud ring, then separate into uneven puffs.
const puffGeometry=new THREE.SphereGeometry(1,10,7);
const smokeRings=Array.from({length:6},(_,index)=>{
    const joint=new THREE.Group();joint.position.y=stages[index+1].position.y+.035;root.add(joint);
    const puffs=Array.from({length:20},(_,j)=>{
        const group=new THREE.Group();joint.add(group);
        const mat=new THREE.MeshStandardMaterial({color:0xf7f3e8,roughness:1,transparent:true,opacity:0,depthWrite:false});
        const size=.21+random()*.14;
        for(let k=0;k<3;k++){
            const cloud=new THREE.Mesh(puffGeometry,mat);
            cloud.position.set(k===0?0:(k===1?-.075:.08),k===0?0:.035,k===0?0:(random()-.5)*.11);
            cloud.scale.setScalar(k===0?1:.65+random()*.2);group.add(cloud);
        }
        return {group,mat,size,angle:j/20*TAU+(random()-.5)*.06,spread:.83+random()*.35,lift:random()*.18};
    });
    joint.visible=false;return {joint,puffs,radius:index<4?.83-index*.105:.67};
});
function animateSmoke(now){
    smokeRings.forEach((ring,index)=>{
        const burst=bursts[index+1],age=burst?(now*1000-burst.start)/burst.duration:2;
        ring.joint.visible=!reduced.matches&&age>=0&&age<1;
        if(!ring.joint.visible)return;
        const expansion=1-Math.pow(1-age,2),appear=Math.min(1,age/.07);
        ring.puffs.forEach((p,j)=>{
            const radius=ring.radius+.06+expansion*1.3*p.spread;
            const angle=p.angle+Math.sin(j*2.1)*age*.07;
            p.group.position.set(Math.sin(angle)*radius,.025+age*p.lift+Math.sin(age*Math.PI)*.085,Math.cos(angle)*radius);
            const evaporation=1-Math.pow(Math.max(0,(age-.58)/.42),1.3);
            const size=p.size*(.82+expansion*.65)*evaporation;
            p.group.scale.set(size,size*(.78+age*.35),size);
            p.mat.opacity=.86*appear*Math.pow(1-age,1.15);
        });
    });
}
function resize(){const w=host.clientWidth,h=host.clientHeight;renderer.setSize(w,h,false);camera.aspect=w/h;camera.updateProjectionMatrix();camera.projectionMatrix.elements[9]=-1.01;camera.projectionMatrixInverse.copy(camera.projectionMatrix).invert()};new ResizeObserver(resize).observe(host);resize();
function wave(x,z,t){return .045*Math.sin(x*2.3+z*.9+t*1.4)+.025*Math.sin(z*3.1-x*.8-t*1.1)}
function render(t,values){const time=reduced.matches?0:t;const wp=waterGeo.attributes.position;for(let i=0;i<wp.count;i++)wp.setY(i,wave(wp.getX(i),wp.getZ(i),time));wp.needsUpdate=true;waterGeo.computeVertexNormals();for(const wall of walls){const p=wall.geometry.attributes.position;for(let i=0;i<51;i++){const v=new THREE.Vector3(p.getX(i),1.05,0).applyMatrix4(wall.matrix);p.setY(i,1.05+wave(v.x,v.z,time))}p.needsUpdate=true;}
const ep=edge.geometry.attributes.position;outline.forEach((p,i)=>ep.setXYZ(i,p[0],wave(p[0],p[2],time)+.012,p[2]));ep.needsUpdate=true;
for(let k=0;k<3;k++){const phase=(time*.13+k/3)%1,l=ripples[k],p=l.geometry.attributes.position;for(let j=0;j<p.count;j++){const a=j/(p.count-1)*TAU,r=shoreRadius(a)+.12+phase*1.12,x=Math.cos(a)*r,z=Math.sin(a)*r;p.setXYZ(j,x,wave(x,z,time)+.055,z)}p.needsUpdate=true;l.material.opacity=Math.sin(phase*Math.PI)*.42;}
foam.forEach((l,k)=>{const p=l.geometry.attributes.position;for(let j=0;j<p.count;j++){const a=k/12*TAU+j/11*.22,r=shoreRadius(a)+.12+.04*Math.sin(time*1.5+k),x=Math.cos(a)*r,z=Math.sin(a)*r;p.setXYZ(j,x,wave(x,z,time)+.07,z)}p.needsUpdate=true;l.material.opacity=.4+.2*Math.sin(time+k)});
stages.forEach((g,i)=>{const v=values[i];g.visible=v>.001;if(i===0)return;g.scale.y=Math.max(.001,v);g.scale.x=g.scale.z=1+Math.max(0,v-1)*-.16;if(twisting)g.rotation.y=(1-v)*-Math.PI*1.35;});animateSmoke(t);halo.material.opacity=.65+.12*Math.sin(time*1.7);renderer.render(scene,camera)}return {render};}
const names=['The island','The doorway','The first band','Above the rocks','The upper tower','The gallery','The light comes on'];
let level=6,values=Array(7).fill(1),moves=Array(7).fill(null),bursts=Array(7).fill(null),playing=false,replayElapsed=0,lastFrame=performance.now(),slow=false;
const steps=document.getElementById('steps');names.forEach((name,i)=>{const b=document.createElement('button');b.className='step';b.textContent=i+1;b.title=name;b.setAttribute('aria-label',`Stage ${i+1}: ${name}`);b.onclick=()=>go(i);steps.append(b)});
function update(){document.getElementById('count').textContent=`0${level+1} / 07`;document.getElementById('stage').textContent=names[level];document.getElementById('prev').disabled=level===0;document.getElementById('next').disabled=level===6;[...steps.children].forEach((b,i)=>{b.className=`step ${i<=level?'done':''} ${i===level?'active':''}`;b.setAttribute('aria-current',i===level?'step':'false')});document.getElementById('replay').textContent=playing?'■ Stop replay':'↻ Replay build'}
function go(n,auto=false){
    if(!auto)playing=false;
    level=Math.max(0,Math.min(6,n));const now=performance.now(),speed=slow?2:1;
    for(let i=1;i<7;i++){
        const target=i<=level?1:0;
        if(moves[i]?.to===target)continue;
        if(Math.abs(values[i]-target)>.001||moves[i]){
            const rising=target>values[i];
            // On retreat, release the ring at the instant the section finishes collapsing.
            // Reversing direction replaces this scheduled burst with the new movement.
            bursts[i]={start:now+(rising?0:600*speed),duration:1400*speed};
            moves[i]={from:values[i],to:target,start:now+(rising?120*speed:0),duration:(rising?1250:600)*speed};
        }
    }
    update();
}
document.getElementById('prev').onclick=()=>go(level-1);document.getElementById('next').onclick=()=>go(level+1);document.getElementById('slow').onchange=e=>slow=e.target.checked;document.getElementById('replay').onclick=()=>{if(playing){playing=false;update();return}values=values.map((_,i)=>i===0?1:0);moves.fill(null);bursts.fill(null);level=0;playing=true;replayElapsed=0;update()};document.addEventListener('keydown',e=>{if(['INPUT','TEXTAREA','SELECT'].includes(e.target.tagName))return;if(e.key==='ArrowRight'){e.preventDefault();go(level+1)}if(e.key==='ArrowLeft'){e.preventDefault();go(level-1)}});
// A damped spring deliberately crosses the destination twice: rise, overshoot, compression, small rebound, settle.
function spring(t){if(t>=1)return 1;return 1-Math.exp(-7*t)*(Math.cos(13*t)+.18*Math.sin(13*t))}
try{const scenes=[sceneFor('straight',false),sceneFor('spiral',true)];update();function frame(now){const delta=Math.min(100,now-lastFrame);lastFrame=now;if(playing){replayElapsed+=delta/(slow?2:1);const target=Math.min(6,Math.floor(replayElapsed/1450));if(target>level)go(target,true);if(level===6&&replayElapsed>1450*7){playing=false;update()}}for(let i=1;i<7;i++){const m=moves[i];if(!m)continue;const t=reduced.matches?1:Math.max(0,Math.min(1,(now-m.start)/m.duration)),e=m.to>m.from?spring(t):t*t*(3-2*t);values[i]=m.from+(m.to-m.from)*e;if(t>=1){values[i]=m.to;moves[i]=null}}if(!document.hidden)scenes.forEach(s=>s.render(now/1000,values));requestAnimationFrame(frame)}requestAnimationFrame(frame)}catch(error){document.getElementById('error').hidden=false;document.getElementById('error').textContent='The 3D preview could not start. Please open this page in a browser with WebGL enabled.';console.error(error)}
