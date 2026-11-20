// End-to-end: a "phone" connects over WebSocket, uploads a PDF sheet over HTTP,
// and must receive its new character. Usage: node app/tests/import_upload.js <sheet.pdf>
const fs = require('fs');
const pdf = fs.readFileSync(process.argv[2]);
const ws = new WebSocket('ws://127.0.0.1:8081');
let token = '', done = false;
const fail = (m) => { console.log('FAIL', m); process.exit(1); };
setTimeout(() => fail('timeout'), 20000);
ws.onopen = () => ws.send(JSON.stringify({ t: 'hello', role: 'player', token: '' }));
ws.onmessage = async (ev) => {
  const m = JSON.parse(ev.data);
  if (m.t === 'welcome' && !token) {
    token = m.token;
    const r = await fetch('http://127.0.0.1:8080/importa-scheda?token=' + token + '&player=Test', { method: 'POST', body: pdf });
    const j = await r.json();
    console.log('upload:', JSON.stringify(j));
    if (!j.ok) fail('upload refused');
  } else if (m.t === 'welcome' && m.char_id) {
    console.log('welcome char_id', m.char_id);
  } else if (m.t === 'state' && m.s.me && !done) {
    done = true;
    const me = m.s.me;
    console.log('me:', me.name, '|', me.race, me.cls, 'liv', me.level, 'PF', me.hp_max, 'CA', me.ac, 'INT', me.ab.INT, 'player', me.player, 'attacchi', me.attacks.length);
    process.exit(me.name.startsWith('Aelyra') && me.ac === 13 ? 0 : 1);
  }
};
