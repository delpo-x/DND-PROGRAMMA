const fs=require('fs'),vm=require('vm');
const ctx={Math,console,performance:{now:()=>Date.now()}};ctx.window=ctx;vm.createContext(ctx);
vm.runInContext(fs.readFileSync('app/web/dice3d.js','utf8'),ctx);
let tot=0,mx=0,nf=0;for(let i=0;i<40;i++){const r=ctx.DiceMath.simulateForTest(['d20','d20','d6','d6','d8','d12','d4','d10']);const s=r.frames/60;tot+=s;mx=Math.max(mx,s);}
console.log('8 dadi: media',(tot/40).toFixed(2),'s max',mx.toFixed(2));
tot=0;mx=0;for(let i=0;i<60;i++){const r=ctx.DiceMath.simulateForTest(['d20','d6','d6']);const s=r.frames/60;tot+=s;mx=Math.max(mx,s);}
console.log('3 dadi: media',(tot/60).toFixed(2),'s max',mx.toFixed(2));
