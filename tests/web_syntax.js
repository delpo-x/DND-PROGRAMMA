// Compiles the inline scripts of the phone and screen pages and the shared
// .js files, so a syntax error cannot reach the players unnoticed.
// node tests/web_syntax.js
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const web = path.join(__dirname, '..', 'web');
let bad = 0;
for (const f of fs.readdirSync(web)) {
  const p = path.join(web, f);
  let parts = [];
  if (f.endsWith('.html')) {
    const html = fs.readFileSync(p, 'utf8');
    const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;
    let m;
    while ((m = re.exec(html))) parts.push(m[1]);
  } else if (f.endsWith('.js')) {
    parts.push(fs.readFileSync(p, 'utf8'));
  }
  parts.forEach((code, i) => {
    try {
      new vm.Script(code, { filename: f + (parts.length > 1 ? '#' + (i + 1) : '') });
    } catch (e) {
      bad++;
      console.log('FAIL ' + f + ': ' + e.message);
    }
  });
  if (parts.length && !bad) console.log('ok   ' + f);
}
console.log('web syntax: ' + (bad ? bad + ' FAIL' : 'OK'));
process.exit(bad ? 1 : 0);
