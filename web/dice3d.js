/* Dadi 3D con fisica per il browser (telefono, PC, TV).
 * Nessuna libreria esterna: corpi rigidi semplici simulati in JavaScript e
 * disegnati su <canvas> 2D in prospettiva. Funziona su Safari (iPhone) e Chrome.
 *
 * tray.roll([{type:'d20'}, ...])            -> Promise<[{type, value}]>
 * tray.roll(specs, [valori])                 -> come sopra ma mostra i valori dati
 *                                              (usato per ripetere i tiri degli altri)
 * Tipi: d4 d6 d8 d10 d12 d20 d100t (decine 00-90) d100u (unita 0-9)
 */
(function (global) {
  'use strict';
  var PHI = (1 + Math.sqrt(5)) / 2;
  // ---- vettori [x,y,z] (Z verso l'alto) e quaternioni [w,x,y,z]
  function add(a, b) { return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]; }
  function sub(a, b) { return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]; }
  function mul(a, s) { return [a[0] * s, a[1] * s, a[2] * s]; }
  function dot(a, b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }
  function cross(a, b) { return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]; }
  function len(a) { return Math.sqrt(dot(a, a)); }
  function norm(a) { var l = len(a) || 1; return [a[0] / l, a[1] / l, a[2] / l]; }
  function qmul(a, b) {
    return [a[0] * b[0] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
      a[0] * b[1] + a[1] * b[0] + a[2] * b[3] - a[3] * b[2],
      a[0] * b[2] - a[1] * b[3] + a[2] * b[0] + a[3] * b[1],
      a[0] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[0]];
  }
  function qrot(q, v) {
    var u = [q[1], q[2], q[3]];
    var t = mul(cross(u, v), 2);
    return add(add(v, mul(t, q[0])), cross(u, t));
  }
  function qnorm(q) { var l = Math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]) || 1; return [q[0] / l, q[1] / l, q[2] / l, q[3] / l]; }
  function qrand() {
    var u1 = Math.random(), u2 = Math.random(), u3 = Math.random();
    var s1 = Math.sqrt(1 - u1), s2 = Math.sqrt(u1);
    return [s2 * Math.cos(2 * Math.PI * u3), s1 * Math.sin(2 * Math.PI * u2), s1 * Math.cos(2 * Math.PI * u2), s2 * Math.sin(2 * Math.PI * u3)];
  }
  function rnd(a, b) { return a + Math.random() * (b - a); }
  function randInt(n) {
    try {
      var c = global.crypto || global.msCrypto;
      if (c && c.getRandomValues) {
        var buf = new Uint32Array(1), lim = Math.floor(4294967296 / n) * n;
        do { c.getRandomValues(buf); } while (buf[0] >= lim);
        return buf[0] % n;
      }
    } catch (e) { }
    return Math.floor(Math.random() * n);
  }

  // ---- geometria
  function baseVerts(sides) {
    var v = [], x, y, z, a, b;
    if (sides === 4) v = [[1, 1, 1], [1, -1, -1], [-1, 1, -1], [-1, -1, 1]];
    else if (sides === 6) { for (x = -1; x <= 1; x += 2) for (y = -1; y <= 1; y += 2) for (z = -1; z <= 1; z += 2) v.push([x, y, z]); }
    else if (sides === 8) v = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]];
    else if (sides === 10) {
      var ha = 0.105, c36 = Math.cos(Math.PI / 5), h = ha * (1 + c36) / (1 - c36);
      v.push([0, 0, h], [0, 0, -h]);
      for (var i = 0; i < 10; i++) { var g = i * Math.PI / 5; v.push([Math.cos(g), Math.sin(g), i % 2 === 0 ? ha : -ha]); }
    } else if (sides === 12) {
      for (x = -1; x <= 1; x += 2) for (y = -1; y <= 1; y += 2) for (z = -1; z <= 1; z += 2) v.push([x, y, z]);
      var p = PHI, q = 1 / PHI;
      for (a = -1; a <= 1; a += 2) for (b = -1; b <= 1; b += 2) { v.push([0, a * q, b * p]); v.push([a * q, b * p, 0]); v.push([a * p, 0, b * q]); }
    } else {
      for (a = -1; a <= 1; a += 2) for (b = -1; b <= 1; b += 2) { v.push([0, a, b * PHI]); v.push([a, b * PHI, 0]); v.push([a * PHI, 0, b]); }
    }
    var m = 0; v.forEach(function (w) { m = Math.max(m, len(w)); });
    return v.map(function (w) { return mul(w, 1 / m); });
  }

  function findFaces(verts) {
    var res = [], seen = {}, n = verts.length;
    for (var i = 0; i < n; i++) for (var j = i + 1; j < n; j++) for (var k = j + 1; k < n; k++) {
      var nr = cross(sub(verts[j], verts[i]), sub(verts[k], verts[i]));
      if (len(nr) < 1e-6) continue;
      nr = norm(nr);
      var d = dot(nr, verts[i]);
      if (d < 0) { nr = mul(nr, -1); d = -d; }
      if (d < 1e-4) continue;
      var ok = true, on = [];
      for (var m = 0; m < n; m++) {
        var s = dot(nr, verts[m]) - d;
        if (s > 1e-4) { ok = false; break; }
        if (Math.abs(s) < 1e-4) on.push(m);
      }
      if (!ok) continue;
      var key = Math.round(nr[0] * 1000) + ',' + Math.round(nr[1] * 1000) + ',' + Math.round(nr[2] * 1000);
      if (seen[key]) continue;
      seen[key] = true;
      var c = [0, 0, 0];
      on.forEach(function (ix) { c = add(c, verts[ix]); });
      c = mul(c, 1 / on.length);
      var u = norm(sub(verts[on[0]], c)), w = cross(nr, u);
      on.sort(function (A, B) {
        var pa = sub(verts[A], c), pb = sub(verts[B], c);
        return Math.atan2(dot(pa, w), dot(pa, u)) - Math.atan2(dot(pb, w), dot(pb, u));
      });
      res.push({ idx: on, n: nr, c: c });
    }
    return res;
  }

  function assignValues(faces) {
    var N = faces.length, vals = faces.map(function () { return 0; }), low = 1;
    for (var i = 0; i < N; i++) {
      if (vals[i]) continue;
      var best = -1, bd = 2;
      for (var j = 0; j < N; j++) {
        if (j === i || vals[j]) continue;
        var d = dot(faces[i].n, faces[j].n);
        if (d < bd) { bd = d; best = j; }
      }
      vals[i] = low;
      if (best >= 0 && bd < -0.99) vals[best] = N + 1 - low;
      low++;
      while (vals.indexOf(low) >= 0 && low <= N) low++;
    }
    return vals;
  }

  var GEO = {};
  function geometry(sides) {
    if (GEO[sides]) return GEO[sides];
    var verts = baseVerts(sides), faces = findFaces(verts);
    faces.forEach(function (f) {
      var idx = f.idx, up;
      if (idx.length === 3) up = sub(verts[idx[0]], f.c);
      else if (sides === 10) {
        var far = verts[idx[0]];
        idx.forEach(function (ix) { if (len(sub(verts[ix], f.c)) > len(sub(far, f.c))) far = verts[ix]; });
        up = sub(far, f.c);
      } else up = sub(mul(add(verts[idx[0]], verts[idx[1]]), 0.5), f.c);
      f.up = norm(up);
    });
    GEO[sides] = { verts: verts, faces: faces, values: assignValues(faces) };
    return GEO[sides];
  }

  var SIZE = { 4: 1.25, 6: 0.95, 8: 1.05, 10: 1.05, 12: 1.1, 20: 1.15 };
  var FONT = { 4: 0.3, 6: 0.62, 8: 0.42, 10: 0.38, 12: 0.42, 20: 0.32 };
  var COLORS = { d4: '#2e8b57', d6: '#ece4d4', d8: '#3b6fd1', d10: '#8a3fc7', d12: '#d07a1e', d20: '#b3202a', d100t: '#3d3d44', d100u: '#6a6a72' };

  function sidesOf(type) { return type.indexOf('d100') === 0 ? 10 : parseInt(type.slice(1), 10); }

  function labelFor(type, base) {
    if (type === 'd10') return { t: base === 10 ? '0' : String(base), v: base };
    if (type === 'd100t') { var v = (base - 1) * 10; return { t: v === 0 ? '00' : String(v), v: v }; }
    if (type === 'd100u') return { t: String(base - 1), v: base - 1 };
    var t = String(base);
    if ((type === 'd12' || type === 'd20') && (base === 6 || base === 9)) t += '.';
    return { t: t, v: base };
  }

  function hexRgb(h) { var n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }

  function makeDie(type) {
    var sides = sidesOf(type), g = geometry(sides), labels = [], i;
    if (sides === 4) { for (i = 0; i < 4; i++) labels.push(labelFor(type, i + 1)); }
    else { for (i = 0; i < g.faces.length; i++) labels.push(labelFor(type, g.values[i])); }
    return {
      type: type, sides: sides, g: g, R: SIZE[sides], labels: labels, rgb: hexRgb(COLORS[type] || '#888888'),
      ink: type === 'd6' ? '#1a120c' : '#fff1c8', p: [0, 0, 0], q: [1, 0, 0, 0], v: [0, 0, 0], w: [0, 0, 0], floor: false
    };
  }

  // ---- fisica (valori stimati: vedi MECHANICS.md)
  var PHYS = { g: 75, dt: 1 / 120, restFloor: 0.32, restWall: 0.5, mu: 0.45, linDamp: 0.15, angDamp: 0.5, maxSteps: 120 * 6 };

  function upIndex(d) {
    var best = 0, bv = -1e9, i;
    if (d.sides === 4) {
      for (i = 0; i < 4; i++) { var z = qrot(d.q, d.g.verts[i])[2]; if (z > bv) { bv = z; best = i; } }
      return best;
    }
    for (i = 0; i < d.g.faces.length; i++) { var nz = qrot(d.q, d.g.faces[i].n)[2]; if (nz > bv) { bv = nz; best = i; } }
    return best;
  }

  function isFlat(d) {
    var i;
    if (d.sides === 4) {
      for (i = 0; i < d.g.faces.length; i++) if (qrot(d.q, d.g.faces[i].n)[2] < -0.97) return true;
      return false;
    }
    for (i = 0; i < d.g.faces.length; i++) if (qrot(d.q, d.g.faces[i].n)[2] > 0.97) return true;
    return false;
  }

  function contact(d, n, point, rest) {
    var r = sub(point, d.p), I = 0.4 * d.R * d.R, invI = 1 / I;
    var vp = add(d.v, cross(d.w, r));
    var vn = dot(vp, n);
    if (vn < 0) {
      var e = vn < -2 ? rest : 0;
      var rn = cross(r, n);
      var j = -(1 + e) * vn / (1 + invI * dot(rn, rn));
      d.v = add(d.v, mul(n, j));
      d.w = add(d.w, mul(cross(r, mul(n, j)), invI));
      vp = add(d.v, cross(d.w, r));
      var vt = sub(vp, mul(n, dot(vp, n)));
      var vtl = len(vt);
      if (vtl > 1e-4) {
        var t = mul(vt, -1 / vtl);
        var rt = cross(r, t);
        var jt = Math.min(vtl / (1 + invI * dot(rt, rt)), PHYS.mu * j);
        d.v = add(d.v, mul(t, jt));
        d.w = add(d.w, mul(cross(r, mul(t, jt)), invI));
      }
    }
  }

  // Urti registrati durante la simulazione, per i suoni (fotogramma, forza).
  var SIM = null;
  function hit(d, speed) {
    if (!SIM || speed < 1.6) return;
    if (d._lastHit !== undefined && SIM.step - d._lastHit < 10) return;
    d._lastHit = SIM.step;
    SIM.impacts.push({ f: Math.floor(SIM.step / 2), s: speed });
  }

  function collideBounds(d, W, H) {
    var wv = d.g.verts.map(function (v) { return add(d.p, qrot(d.q, mul(v, d.R))); });
    var planes = [[[0, 0, 1], 0, PHYS.restFloor], [[1, 0, 0], -W, PHYS.restWall], [[-1, 0, 0], -W, PHYS.restWall],
      [[0, 1, 0], -H, PHYS.restWall], [[0, -1, 0], -H, PHYS.restWall]];
    planes.forEach(function (pl, pi) {
      var n = pl[0], off = pl[1], maxPen = 0, pts = [];
      wv.forEach(function (p) { var s = dot(p, n) - off; if (s < 0) { pts.push(p); maxPen = Math.max(maxPen, -s); } });
      if (!pts.length) return;
      if (pi === 0) d.floor = true;
      hit(d, -dot(d.v, n));
      pts.forEach(function (p) { contact(d, n, p, pl[2]); });
      d.p = add(d.p, mul(n, maxPen));
      wv = wv.map(function (p) { return add(p, mul(n, maxPen)); });
    });
  }

  function collidePair(a, b) {
    var ra = a.R * 0.66, rb = b.R * 0.66;
    var dlt = sub(b.p, a.p), dist = len(dlt);
    if (dist >= ra + rb || dist < 1e-6) return;
    var n = mul(dlt, 1 / dist), pen = ra + rb - dist;
    a.p = sub(a.p, mul(n, pen / 2)); b.p = add(b.p, mul(n, pen / 2));
    var rv = dot(sub(b.v, a.v), n);
    if (rv < 0) {
      hit(a, -rv);
      var j = -(1 + 0.4) * rv / 2;
      a.v = sub(a.v, mul(n, j)); b.v = add(b.v, mul(n, j));
      a.w = add(a.w, mul(cross(n, [0, 0, 1]), j * 0.3)); b.w = sub(b.w, mul(cross(n, [0, 0, 1]), j * 0.3));
    }
  }

  function integrate(d, dt) {
    var wasFloor = d.floor;
    d.floor = false;
    if (wasFloor && len(d.v) < 0.6 && len(d.w) < 0.9) { d.v = mul(d.v, 0.9); d.w = mul(d.w, 0.9); }
    d.v[2] -= PHYS.g * dt;
    d.p = add(d.p, mul(d.v, dt));
    var wq = [0, d.w[0], d.w[1], d.w[2]];
    var dq = qmul(wq, d.q);
    d.q = qnorm([d.q[0] + 0.5 * dt * dq[0], d.q[1] + 0.5 * dt * dq[1], d.q[2] + 0.5 * dt * dq[2], d.q[3] + 0.5 * dt * dq[3]]);
    d.v = mul(d.v, 1 - PHYS.linDamp * dt);
    d.w = mul(d.w, 1 - PHYS.angDamp * dt);
    if (wasFloor) { d.w = mul(d.w, 0.985); d.v = [d.v[0] * 0.992, d.v[1] * 0.992, d.v[2]]; }
  }

  function throwDice(dice, W, H) {
    var n = dice.length;
    dice.forEach(function (d, i) {
      var lane = (i + 0.5) / n - 0.5;
      d.p = [lane * (W * 1.2) + rnd(-0.5, 0.5), -H + 1.6 + rnd(0, 1), rnd(3, 5.5)];
      d.q = qrand();
      d.v = [rnd(-6, 6) - lane * 6, rnd(9, 15) * Math.min(1.3, H / 6), rnd(0, 4)];
      d.w = mul(norm([rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)]), rnd(14, 24));
    });
  }

  function simulate(dice, W, H) {
    var frames = [], still = 0, nudges = 0, step;
    SIM = { impacts: [], step: 0 };
    dice.forEach(function (d) { d._lastHit = undefined; });
    for (step = 0; step < PHYS.maxSteps; step++) {
      SIM.step = step;
      dice.forEach(function (d) { integrate(d, PHYS.dt); });
      for (var it = 0; it < 2; it++) {
        dice.forEach(function (d) { collideBounds(d, W, H); });
        for (var a = 0; a < dice.length; a++) for (var b = a + 1; b < dice.length; b++) collidePair(dice[a], dice[b]);
      }
      if (step % 2 === 0) frames.push(dice.map(function (d) { return [d.p.slice(), d.q.slice()]; }));
      if (step > 120 * 3.5) dice.forEach(function (d) { d.v = mul(d.v, 0.94); d.w = mul(d.w, 0.94); });
      var allStill = dice.every(function (d) { return len(d.v) < 0.35 && len(d.w) < 0.5; });
      still = allStill ? still + 1 : 0;
      if (still > 24) {
        var ok = true;
        dice.forEach(function (d) {
          if (!isFlat(d)) {
            ok = false;
            d.v = add(d.v, [rnd(-1, 1), rnd(-1, 1), 4]);
            d.w = add(d.w, [rnd(-4, 4), rnd(-4, 4), 0]);
          }
        });
        if (ok || nudges > 5) break;
        nudges++; still = 0;
      }
    }
    // Ultimo fotogramma: dado appoggiato in piano (correzione minima se storto).
    dice.forEach(function (d) { if (!isFlat(d)) snapFlat(d); });
    frames.push(dice.map(function (d) { return [d.p.slice(), d.q.slice()]; }));
    frames.impacts = SIM.impacts;
    SIM = null;
    return frames;
  }

  // Ruota il dado in modo che la faccia piu' vicina sia esattamente in piano.
  function snapFlat(d) {
    var target = d.sides === 4 ? [0, 0, -1] : [0, 0, 1], best = null, bv = -2;
    d.g.faces.forEach(function (f) {
      var n = qrot(d.q, f.n), s = dot(n, target);
      if (s > bv) { bv = s; best = n; }
    });
    var axis = cross(best, target), sl = len(axis);
    if (sl < 1e-6) return;
    var ang = Math.asin(Math.min(1, sl));
    if (dot(best, target) < 0) ang = Math.PI - ang;
    axis = mul(axis, 1 / sl);
    var r = [Math.cos(ang / 2)].concat(mul(axis, Math.sin(ang / 2)));
    d.q = qnorm(qmul(r, d.q));
    var minZ = 1e9;
    d.g.verts.forEach(function (v) { minZ = Math.min(minZ, qrot(d.q, mul(v, d.R))[2]); });
    d.p = [d.p[0], d.p[1], -minZ];
  }

  function forceValue(d, value) {
    var up = upIndex(d), target = -1;
    for (var i = 0; i < d.labels.length; i++) if (d.labels[i].v === value) { target = i; break; }
    if (target < 0 || target === up) return;
    var tmp = d.labels[up]; d.labels[up] = d.labels[target]; d.labels[target] = tmp;
  }

  // ---- disegno
  // Suoni dei dadi (WebAudio). Partono solo dopo il primo tocco sulla pagina.
  var Sfx = (function () {
    var ac = null, bufs = {}, loading = false;
    function ctx() {
      if (!ac) { try { var AC = window.AudioContext || window.webkitAudioContext; if (AC) ac = new AC(); } catch (e) { ac = null; } }
      if (ac && ac.state === 'suspended') { try { ac.resume(); } catch (e) { } }
      return ac;
    }
    function load() {
      if (loading || !ctx()) return;
      loading = true;
      ['tok1', 'tok2', 'tok3', 'crit', 'fumble', 'turn'].forEach(function (n) {
        fetch('/sfx/' + n + '.wav').then(function (r) { return r.arrayBuffer(); })
          .then(function (b) { ac.decodeAudioData(b, function (d) { bufs[n] = d; }, function () { }); })
          .catch(function () { });
      });
    }
    function play(n, gain, rate) {
      var c = ctx();
      if (!c || !bufs[n]) return false;
      try {
        var src = c.createBufferSource(), g = c.createGain();
        src.buffer = bufs[n]; src.playbackRate.value = rate || 1;
        g.gain.value = gain; src.connect(g); g.connect(c.destination); src.start();
      } catch (e) { return false; }
      return true;
    }
    ['touchstart', 'click', 'keydown'].forEach(function (ev) { document.addEventListener(ev, load, { passive: true }); });
    return {
      load: load,
      play: play,
      tok: function (speed) {
        var k = 'tok' + (1 + Math.floor(Math.random() * 3));
        play(k, Math.min(1, 0.15 + speed / 14), 0.9 + Math.random() * 0.25);
      }
    };
  })();
  global.DiceSfx = Sfx;

  function DiceTray(canvas, opts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.opts = opts || {};
    this.dice = [];
    this.frames = null;
    this.start = 0;
    this.results = null;
    this.effect = null;
    this.particles = [];
    this.raf = 0;
    this.hint = this.opts.hint || '';
    var self = this;
    this._resize = function () { self.resize(); };
    window.addEventListener('resize', this._resize);
    this.resize();
  }

  DiceTray.prototype.resize = function () {
    var dpr = Math.min(window.devicePixelRatio || 1, 2);
    var r = this.canvas.getBoundingClientRect();
    var w = Math.max(50, Math.round(r.width * dpr)), h = Math.max(50, Math.round(r.height * dpr));
    if (this.canvas.width !== w || this.canvas.height !== h) { this.canvas.width = w; this.canvas.height = h; }
    // Tavolo piu' piccolo sui telefoni, cosi' i dadi restano grandi.
    this.H = this.opts.tableH || Math.max(5.5, Math.min(8, Math.max(w, h) / (window.devicePixelRatio || 1) / 90));
    this.W = Math.max(4.5, Math.min(16, this.H * (w / h) * 0.92));
    this.draw();
  };

  DiceTray.prototype.camera = function () {
    var cw = this.canvas.width, ch = this.canvas.height, tilt = 0.32, dist = 42;
    var C = [0, -dist * Math.sin(tilt), dist * Math.cos(tilt)];
    var F = norm(sub([0, 0.4, 0], C));
    var Rt = norm(cross(F, [0, 0, 1]));
    var U = cross(Rt, F);
    var f = Math.min(cw / (2 * (this.W + 1.2)), ch / (2 * (this.H + 1.6))) * dist;
    return { C: C, F: F, R: Rt, U: U, f: f, cx: cw / 2, cy: ch / 2 };
  };

  function project(cam, p) {
    var d = sub(p, cam.C), z = dot(d, cam.F);
    return [cam.cx + cam.f * dot(d, cam.R) / z, cam.cy - cam.f * dot(d, cam.U) / z, z];
  }

  DiceTray.prototype.roll = function (specs, forced) {
    var self = this;
    this.resize();
    this.dice = specs.map(function (s) { return makeDie(s.type); });
    throwDice(this.dice, this.W, this.H);
    this.frames = simulate(this.dice, this.W, this.H);
    // Equita' garantita: il valore finale e' estratto con un generatore casuale
    // uniforme; la fisica decide solo come rotola il dado (la faccia in alto
    // riceve quel numero).
    if (!forced) forced = this.dice.map(function (d) { return d.labels[randInt(d.labels.length)].v; });
    var res = this.dice.map(function (d, i) {
      if (forced && forced[i] !== undefined && forced[i] !== null) forceValue(d, forced[i]);
      var up = upIndex(d);
      return { type: d.type, value: d.labels[up].v };
    });
    this.results = null;
    this.effect = null;
    this.particles = [];
    this.start = performance.now();
    this._imp = 0;
    return new Promise(function (resolve) {
      self._done = function () { self.results = res; resolve(res); };
      self._loop();
    });
  };

  DiceTray.prototype.celebrate = function (kind) {
    this.effect = { kind: kind, t0: performance.now() };
    this.particles = [];
    if (kind === 'crit') {
      var cam = this.camera();
      for (var i = 0; i < 90; i++) {
        var a = Math.random() * Math.PI * 2, s = rnd(2, 9) * (this.canvas.width / 600);
        this.particles.push({ x: cam.cx, y: cam.cy, vx: Math.cos(a) * s, vy: Math.sin(a) * s - 2, life: rnd(0.8, 1.6), c: Math.random() < 0.5 ? '#ffd76a' : '#fff3c0' });
      }
    }
    this._loop();
  };

  // Animazione con requestAnimationFrame; un timer di riserva fa finire il tiro
  // anche se il browser sospende i fotogrammi (schermo bloccato, scheda nascosta).
  DiceTray.prototype._loop = function () {
    var self = this;
    if (this.raf) return;
    var schedule = function () {
      var fired = false;
      var run = function () {
        if (fired) return;
        fired = true;
        cancelAnimationFrame(rafId); clearTimeout(tmId);
        self.raf = 0;
        if (self.draw()) self.raf = schedule();
      };
      var rafId = requestAnimationFrame(run);
      var tmId = setTimeout(run, 100);
      return rafId || 1;
    };
    this.raf = schedule();
  };

  DiceTray.prototype.draw = function () {
    var ctx = this.ctx, cw = this.canvas.width, ch = this.canvas.height, cam = this.camera(), self = this;
    var busy = false;
    var fi = 0;
    if (this.frames) {
      fi = Math.floor((performance.now() - this.start) / (1000 / 60));
      if (fi >= this.frames.length - 1) {
        fi = this.frames.length - 1;
        if (this._done) { var cb = this._done; this._done = null; cb(); busy = true; }
      } else busy = true;
      var imp = this.frames.impacts || [];
      while (this._imp < imp.length && imp[this._imp].f <= fi) { Sfx.tok(imp[this._imp].s); this._imp++; }
      var fr = this.frames[fi];
      this.dice.forEach(function (d, i) { d.p = fr[i][0]; d.q = fr[i][1]; });
    }
    // fondo
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = '#1c120c';
    ctx.fillRect(0, 0, cw, ch);
    var W = this.W, H = this.H;
    var corners = [[-W - 0.9, -H - 0.9, 0], [W + 0.9, -H - 0.9, 0], [W + 0.9, H + 0.9, 0], [-W - 0.9, H + 0.9, 0]].map(function (p) { return project(cam, p); });
    poly(ctx, corners); ctx.fillStyle = '#5a3418'; ctx.fill();
    var inner = [[-W, -H, 0], [W, -H, 0], [W, H, 0], [-W, H, 0]].map(function (p) { return project(cam, p); });
    var cc = project(cam, [0, 0, 0]);
    var grad = ctx.createRadialGradient(cc[0], cc[1], 10, cc[0], cc[1], Math.max(cw, ch) * 0.7);
    grad.addColorStop(0, '#2f6b45'); grad.addColorStop(1, '#173a26');
    poly(ctx, inner); ctx.fillStyle = grad; ctx.fill();
    ctx.lineWidth = Math.max(2, cw / 300); ctx.strokeStyle = 'rgba(0,0,0,0.45)'; ctx.stroke();
    if (!this.dice.length && this.hint) {
      ctx.fillStyle = 'rgba(255,240,210,0.55)';
      var fs = Math.round(Math.min(cw, ch) / 14);
      ctx.font = 'bold ' + fs + 'px Georgia, serif';
      // keep the hint inside the felt: shrink until it fits 70% of the width
      var maxW = cw * 0.7;
      while (fs > 10 && ctx.measureText(this.hint).width > maxW) { fs -= 1; ctx.font = 'bold ' + fs + 'px Georgia, serif'; }
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(this.hint, cw / 2, ch / 2);
    }
    // ombre
    this.dice.forEach(function (d) {
      var s = project(cam, [d.p[0], d.p[1], 0]);
      var rad = d.R * cam.f / s[2] * 1.05;
      var a = Math.max(0.08, 0.42 - d.p[2] * 0.04);
      ctx.fillStyle = 'rgba(0,0,0,' + a + ')';
      ctx.beginPath(); ctx.ellipse(s[0] + rad * 0.15, s[1] + rad * 0.12, rad, rad * 0.8, 0, 0, Math.PI * 2); ctx.fill();
    });
    // dadi dal piu' lontano
    var order = this.dice.slice().sort(function (a, b) { return dot(sub(b.p, cam.C), cam.F) - dot(sub(a.p, cam.C), cam.F); });
    order.forEach(function (d) { drawDie(ctx, cam, d); });
    // valori sopra i dadi a fine tiro
    if (this.results) {
      this.dice.forEach(function (d, i) {
        var s = project(cam, [d.p[0], d.p[1], d.p[2] + d.R * 1.5]);
        var r = Math.max(14, d.R * cam.f / s[2] * 0.48);
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.beginPath(); ctx.arc(s[0], s[1], r, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(20,12,8,0.85)'; ctx.fill();
        ctx.lineWidth = 2; ctx.strokeStyle = '#e6c06a'; ctx.stroke();
        ctx.fillStyle = '#fff'; ctx.font = 'bold ' + Math.round(r * 1.05) + 'px Georgia, serif';
        ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
        var lab = self.results[i].value;
        if (d.type === 'd100t' && lab === 0) lab = '00';
        ctx.fillText(String(lab), s[0], s[1] + 1);
      });
    }
    // effetti 20 / 1 naturale
    if (this.effect) {
      var t = (performance.now() - this.effect.t0) / 1000;
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      if (this.effect.kind === 'crit') {
        var g2 = ctx.createRadialGradient(cw / 2, ch / 2, 0, cw / 2, ch / 2, Math.max(cw, ch) * 0.6);
        var al = Math.max(0, 0.55 - t * 0.3);
        g2.addColorStop(0, 'rgba(255,215,100,' + al + ')'); g2.addColorStop(1, 'rgba(255,180,40,0)');
        ctx.fillStyle = g2; ctx.fillRect(0, 0, cw, ch);
        this.particles.forEach(function (p) {
          if (p.life <= 0) return;
          p.x += p.vx; p.y += p.vy; p.vy += 0.12; p.life -= 1 / 60;
          ctx.globalAlpha = Math.max(0, Math.min(1, p.life));
          ctx.fillStyle = p.c; ctx.beginPath(); ctx.arc(p.x, p.y, Math.max(2, cw / 260), 0, Math.PI * 2); ctx.fill();
        });
        ctx.globalAlpha = 1;
      } else {
        var al2 = Math.max(0, 0.6 - t * 0.35);
        var g3 = ctx.createRadialGradient(cw / 2, ch / 2, Math.min(cw, ch) * 0.2, cw / 2, ch / 2, Math.max(cw, ch) * 0.75);
        g3.addColorStop(0, 'rgba(120,0,0,0)'); g3.addColorStop(1, 'rgba(160,0,0,' + al2 + ')');
        ctx.fillStyle = g3; ctx.fillRect(0, 0, cw, ch);
      }
      var title = this.effect.kind === 'crit' ? '20 NATURALE!' : '1 NATURALE...';
      var sc = Math.min(1, t * 3);
      var shake = this.effect.kind === 'fumble' && t < 0.6 ? Math.sin(t * 60) * cw * 0.01 : 0;
      var fs = Math.round(Math.min(cw, ch) / 7 * (0.6 + 0.4 * sc));
      ctx.globalAlpha = t < 2.4 ? 1 : Math.max(0, 1 - (t - 2.4) * 2);
      ctx.font = 'bold ' + fs + 'px Georgia, serif';
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.lineWidth = fs / 8; ctx.strokeStyle = 'rgba(0,0,0,0.85)';
      ctx.strokeText(title, cw / 2 + shake, ch * 0.2);
      ctx.fillStyle = this.effect.kind === 'crit' ? '#ffd76a' : '#ff5a4a';
      ctx.fillText(title, cw / 2 + shake, ch * 0.2);
      ctx.globalAlpha = 1;
      if (t < 3) busy = true; else this.effect = null;
    }
    return busy;
  };

  function poly(ctx, pts) {
    ctx.beginPath(); ctx.moveTo(pts[0][0], pts[0][1]);
    for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
    ctx.closePath();
  }

  var LIGHT = norm([-0.35, -0.55, 0.85]);

  function drawDie(ctx, cam, d) {
    var g = d.g, R = d.R;
    var wv = g.verts.map(function (v) { return add(d.p, qrot(d.q, mul(v, R))); });
    var pv = wv.map(function (p) { return project(cam, p); });
    g.faces.forEach(function (f, fi) {
      var n = qrot(d.q, f.n), c = add(d.p, qrot(d.q, mul(f.c, R)));
      if (dot(n, sub(c, cam.C)) >= 0) return;
      var lit = Math.max(0, dot(n, LIGHT));
      var sh = 0.42 + 0.58 * lit;
      var spec = Math.pow(lit, 12) * 60;
      var col = 'rgb(' + Math.min(255, Math.round(d.rgb[0] * sh + spec)) + ',' + Math.min(255, Math.round(d.rgb[1] * sh + spec)) + ',' + Math.min(255, Math.round(d.rgb[2] * sh + spec)) + ')';
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      poly(ctx, f.idx.map(function (i) { return pv[i]; }));
      ctx.fillStyle = col; ctx.fill();
      ctx.lineJoin = 'round';
      ctx.lineWidth = Math.max(1, cam.f / 900);
      ctx.strokeStyle = 'rgba(0,0,0,0.35)'; ctx.stroke();
      var size = FONT[d.sides] * R * (d.type === 'd100t' ? 0.8 : 1);
      if (d.sides === 4) {
        f.idx.forEach(function (vi) {
          var corner = mul(g.verts[vi], R), cl = mul(f.c, R);
          var pos = add(cl, mul(sub(corner, cl), 0.52));
          text(ctx, cam, d, d.labels[vi].t, pos, f.n, norm(sub(corner, cl)), size);
        });
      } else {
        text(ctx, cam, d, d.labels[fi].t, mul(f.c, R), f.n, f.up, size);
      }
    });
    ctx.setTransform(1, 0, 0, 1, 0, 0);
  }

  // Disegna il numero "incollato" sulla faccia (trasformazione affine locale).
  function text(ctx, cam, d, str, localPos, localN, localUp, size) {
    var n = qrot(d.q, localN), up = qrot(d.q, localUp);
    var right = cross(up, n);
    var c = add(d.p, qrot(d.q, localPos));
    c = add(c, mul(n, 0.01));
    var s = 0.05, PX = 48, k = (size / PX) / s;
    var P0 = project(cam, c), Pr = project(cam, add(c, mul(right, s))), Pu = project(cam, add(c, mul(up, s)));
    ctx.setTransform((Pr[0] - P0[0]) * k, (Pr[1] - P0[1]) * k, -(Pu[0] - P0[0]) * k, -(Pu[1] - P0[1]) * k, P0[0], P0[1]);
    ctx.font = 'bold ' + PX + 'px Georgia, "Times New Roman", serif';
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.lineWidth = 6;
    ctx.strokeStyle = d.type === 'd6' ? 'rgba(255,255,255,0.35)' : 'rgba(0,0,0,0.55)';
    ctx.strokeText(str, 0, 2);
    ctx.fillStyle = d.ink;
    ctx.fillText(str, 0, 2);
  }

  // ---- dadi logici <-> dadi fisici (d100 = decine + unita)
  function physicalFor(logical) {
    var specs = [], map = [];
    logical.forEach(function (l) {
      if (l.s === 100) { map.push([specs.length, specs.length + 1]); specs.push({ type: 'd100t' }); specs.push({ type: 'd100u' }); }
      else { map.push([specs.length]); specs.push({ type: 'd' + l.s }); }
    });
    return { specs: specs, map: map };
  }
  function logicalValues(logical, map, results) {
    return logical.map(function (l, i) {
      if (l.s === 100) { var v = results[map[i][0]].value + results[map[i][1]].value; return v === 0 ? 100 : v; }
      return results[map[i][0]].value;
    });
  }
  function forcedPhysical(logicalDice) {
    var vals = [];
    logicalDice.forEach(function (d) {
      if (d.s === 100) { var v = d.v === 100 ? 0 : d.v; vals.push(Math.floor(v / 10) * 10); vals.push(v % 10); }
      else vals.push(d.v);
    });
    return vals;
  }

  global.DiceTray = DiceTray;
  global.DiceMath = {
    physicalFor: physicalFor, logicalValues: logicalValues, forcedPhysical: forcedPhysical, geometry: geometry,
    simulateForTest: function (types) {
      var dice = types.map(makeDie); throwDice(dice, 9, 8); var fr = simulate(dice, 9, 8);
      return { frames: fr.length, flat: dice.map(isFlat), values: dice.map(function (d) { return d.labels[upIndex(d)].v; }), faces: dice.map(function (d) { return d.g.faces.length; }) };
    },
    forceTest: function (type, value) {
      var d = makeDie(type); throwDice([d], 9, 8); simulate([d], 9, 8); forceValue(d, value); return d.labels[upIndex(d)].v;
    }
  };
})(typeof window !== 'undefined' ? window : this);
