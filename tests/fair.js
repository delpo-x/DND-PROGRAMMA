const fs=require('fs'),vm=require('vm');
const ctx={Math,console,performance:{now:()=>Date.now()}};ctx.window=ctx;vm.createContext(ctx);
vm.runInContext(fs.readFileSync('app/web/dice3d.js','utf8'),ctx);
const c={};const N=4000;for(let i=0;i<N;i++){const r=ctx.DiceMath.simulateForTest(['d20']);c[r.values[0]]=(c[r.values[0]]||0)+1;}
let chi=0;for(let v=1;v<=20;v++){const e=N/20;chi+=((c[v]||0)-e)**2/e;}
console.log(JSON.stringify(c),'chi2',chi.toFixed(1),'(19 gdl, soglia 5% = 30.1)');
