// Headless check of web/dice3d.js physics: node tests/test_dice.js
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const ctx = { Math, console, performance: { now: () => Date.now() } };
ctx.window = ctx;
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'web', 'dice3d.js'), 'utf8'), ctx);
const DM = ctx.DiceMath;
const types = ['d4', 'd6', 'd8', 'd10', 'd12', 'd20', 'd100t', 'd100u'];
const expectFaces = { d4: 4, d6: 6, d8: 8, d10: 10, d12: 12, d20: 20, d100t: 10, d100u: 10 };
let fail = 0;
for (const t of types) {
  const counts = {};
  let notFlat = 0, frames = 0;
  const N = 300;
  for (let i = 0; i < N; i++) {
    const r = DM.simulateForTest([t]);
    if (r.faces[0] !== expectFaces[t]) { console.log('FACCE ERRATE', t, r.faces[0]); fail++; break; }
    if (!r.flat[0]) notFlat++;
    frames += r.frames;
    counts[r.values[0]] = (counts[r.values[0]] || 0) + 1;
  }
  const keys = Object.keys(counts).map(Number).sort((a, b) => a - b);
  console.log(t, 'valori', keys.join(','), 'non in piano', notFlat, 'durata media s', (frames / N / 60).toFixed(2));
  console.log('   distribuzione', keys.map(k => k + ':' + counts[k]).join(' '));
}
const multi = DM.simulateForTest(['d20', 'd20', 'd6', 'd6', 'd8', 'd12', 'd4', 'd10']);
console.log('8 dadi insieme: in piano', multi.flat.join(','), 'durata s', (multi.frames / 60).toFixed(2));
for (let v = 1; v <= 20; v++) if (DM.forceTest('d20', v) !== v) { console.log('forzatura fallita', v); fail++; }
for (let v = 0; v <= 90; v += 10) if (DM.forceTest('d100t', v) !== v) { console.log('forzatura d100 fallita', v); fail++; }
console.log(fail ? 'FALLITO' : 'OK');
