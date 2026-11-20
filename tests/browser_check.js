// End-to-end browser check (needs the master app serving on 127.0.0.1:8080):
// node tests/browser_check.js <chrome.exe> <outdir>
// Opens the player page in headless Chrome, rolls, waits for the dice to stop,
// reads the result and saves screenshots.
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const chrome = process.argv[2];
const outdir = process.argv[3];
const port = 9333;
const prof = fs.mkdtempSync(path.join(os.tmpdir(), 'dndcdp-'));
const proc = spawn(chrome, ['--headless=new', '--disable-gpu', '--remote-debugging-port=' + port, '--user-data-dir=' + prof, '--window-size=520,900', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

async function cdp(wsUrl) {
  const ws = new WebSocket(wsUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let id = 0; const pending = {};
  ws.onmessage = (ev) => { const m = JSON.parse(ev.data); if (m.id && pending[m.id]) { pending[m.id](m); delete pending[m.id]; } };
  const send = (method, params = {}) => new Promise(res => { const i = ++id; pending[i] = res; ws.send(JSON.stringify({ id: i, method, params })); });
  return { send, close: () => ws.close() };
}

async function page(url, w, h) {
  const r = await fetch(`http://127.0.0.1:${port}/json/new?${encodeURIComponent(url)}`, { method: 'PUT' });
  const t = await r.json();
  const c = await cdp(t.webSocketDebuggerUrl);
  await c.send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: w < 700 });
  await c.send('Runtime.enable');
  return c;
}
const c_bring = async (c) => c.send('Page.bringToFront');
const evalJs = async (c, expr) => (await c.send('Runtime.evaluate', { expression: expr, returnByValue: true })).result.result.value;
const shot = async (c, file) => { const r = await c.send('Page.captureScreenshot', { format: 'png' }); fs.writeFileSync(file, Buffer.from(r.result.data, 'base64')); };

(async () => {
  let ok = true;
  try {
    for (let i = 0; i < 30; i++) { try { await fetch(`http://127.0.0.1:${port}/json/version`); break; } catch (e) { await sleep(300); } }
    const screen = await page('http://127.0.0.1:8080/schermo', 1600, 900);
    const p = await page('http://127.0.0.1:8080/giocatore?char=c1&roll=1', 400, 860);
    let res = '';
    for (let i = 0; i < 40; i++) {
      await sleep(500);
      res = await evalJs(p, "document.getElementById('result').innerText");
      if (res && res.indexOf('=') >= 0) break;
    }
    console.log('giocatore, risultato del tiro:', JSON.stringify(res));
    if (!res || res.indexOf('=') < 0) ok = false;
    await sleep(800);
    await shot(p, path.join(outdir, 'p_roll.png'));
    const log = await evalJs(p, "document.getElementById('logBox').innerText.slice(0,200)");
    console.log('registro giocatore:', JSON.stringify(log));
    await sleep(3500);
    console.log('schermo: stato connessione', await evalJs(screen, "document.getElementById('conn').className"), 'giocatore:', await evalJs(p, "document.getElementById('conn').className"));
    await c_bring(screen);
    await sleep(1500);
    console.log('schermo in primo piano: stato connessione', await evalJs(screen, "document.getElementById('conn').className"));
    const last = await evalJs(screen, "document.getElementById('lastRoll').innerText");
    console.log('schermo condiviso, ultimo tiro:', JSON.stringify(last));
    if (!last || last.indexOf('Aria') < 0) ok = false;
    await shot(screen, path.join(outdir, 'screen.png'));
    await evalJs(p, "document.querySelector('#tabs button[data-tab=sheet]').click()");
    await sleep(500);
    await shot(p, path.join(outdir, 'p_sheet.png'));
    const w = await evalJs(p, 'document.documentElement.scrollWidth');
    console.log('larghezza pagina a 400px:', w);
    if (w > 400) ok = false;
  } catch (e) { console.log('ERRORE', e); ok = false; }
  proc.kill();
  console.log(ok ? 'OK' : 'FALLITO');
  process.exit(ok ? 0 : 1);
})();
