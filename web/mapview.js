// Battle map for the phone and the shared screen: the map picture, its square
// grid and the pieces. One finger drags the map (or your own piece, which
// snaps to a square like on a checkers board), two fingers zoom.
(function (global) {
  'use strict';

  function MapView(canvas, opts) {
    this.c = canvas;
    this.ctx = canvas.getContext('2d');
    this.opts = opts || {};
    this.map = null;
    this.img = null;
    this.url = '';
    this.zoom = 1; this.pan = { x: 0, y: 0 };
    this.fitNext = true;
    this.avatars = {};
    this.pointers = {};
    this.drag = null;       // {ref, x, y} own piece being moved
    this.pending = null;    // {ref, x, y} move sent, waiting for the master
    var self = this;
    canvas.style.touchAction = 'none';
    canvas.addEventListener('pointerdown', function (e) { self._down(e); });
    canvas.addEventListener('pointermove', function (e) { self._move(e); });
    canvas.addEventListener('pointerup', function (e) { self._up(e); });
    canvas.addEventListener('pointercancel', function (e) { self._up(e); });
    canvas.addEventListener('wheel', function (e) {
      e.preventDefault();
      var r = canvas.getBoundingClientRect();
      self.zoomBy(e.deltaY < 0 ? 1.12 : 1 / 1.12, e.clientX - r.left, e.clientY - r.top);
    }, { passive: false });
    window.addEventListener('resize', function () { self.resize(); });
  }

  MapView.prototype.set = function (map) {
    var self = this;
    if (!map) { this.map = null; this.draw(); return; }
    var newMap = !this.map || this.map.id !== map.id;
    this.map = map;
    if (this.pending) {
      // the master answered: drop the optimistic position
      var t = this._tok(this.pending.ref);
      if (!t || (t.x === this.pending.x && t.y === this.pending.y) || Date.now() - this.pending.t > 3000) this.pending = null;
    }
    if (newMap) this.fitNext = true;
    if (map.url !== this.url) {
      this.url = map.url;
      var im = new Image();
      im.onload = function () { if (self.url === map.url) { self.img = im; if (self.fitNext) self.fit(); self.draw(); } };
      im.src = map.url + '?v=' + encodeURIComponent(map.id);
      this.img = null;
    }
    if (this.fitNext && this.img) this.fit();
    this.draw();
  };

  MapView.prototype._tok = function (ref) {
    var ts = (this.map && this.map.tokens) || [];
    for (var i = 0; i < ts.length; i++) if (ts[i].ref === ref) return ts[i];
    return null;
  };

  MapView.prototype.resize = function () {
    var r = this.c.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    if (r.width < 2) return;
    var w = Math.round(r.width * dpr), h = Math.round(r.height * dpr);
    if (this.c.width !== w || this.c.height !== h) { this.c.width = w; this.c.height = h; }
    if (this.fitNext) this.fit();
    this.draw();
  };

  MapView.prototype.fit = function () {
    var m = this.map, r = this.c.getBoundingClientRect();
    if (!m || r.width < 2) return;
    this.fitNext = false;
    this.zoom = Math.min(r.width / m.w, r.height / m.h);
    this.pan = { x: (r.width - m.w * this.zoom) / 2, y: (r.height - m.h * this.zoom) / 2 };
    this.draw();
  };

  // Shows the own piece in the middle, close enough to tap squares.
  MapView.prototype.focusMe = function () {
    var m = this.map, r = this.c.getBoundingClientRect(), me = null;
    if (!m) return;
    (m.tokens || []).forEach(function (t) { if (t.me) me = t; });
    if (!me) { this.fit(); return; }
    this.zoom = Math.max(this.zoom, 56 / m.cell);
    var p = this._center(me.x, me.y);
    this.pan.x += r.width / 2 - p.x; this.pan.y += r.height / 2 - p.y;
    this.draw();
  };

  MapView.prototype.zoomBy = function (f, x, y) {
    var r = this.c.getBoundingClientRect();
    if (x === undefined) { x = r.width / 2; y = r.height / 2; }
    var nz = Math.max(0.03, Math.min(8, this.zoom * f));
    this.pan.x = x - (x - this.pan.x) * (nz / this.zoom);
    this.pan.y = y - (y - this.pan.y) * (nz / this.zoom);
    this.zoom = nz;
    this.draw();
  };

  MapView.prototype._center = function (x, y) {
    var m = this.map;
    return { x: this.pan.x + (m.ox + (x + 0.5) * m.cell) * this.zoom, y: this.pan.y + (m.oy + (y + 0.5) * m.cell) * this.zoom };
  };

  MapView.prototype._square = function (px, py) {
    var m = this.map;
    return { x: Math.floor(((px - this.pan.x) / this.zoom - m.ox) / m.cell), y: Math.floor(((py - this.pan.y) / this.zoom - m.oy) / m.cell) };
  };

  MapView.prototype._pos = function (e) {
    var r = this.c.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  };

  MapView.prototype._down = function (e) {
    if (!this.map) return;
    this.c.setPointerCapture(e.pointerId);
    var p = this._pos(e);
    this.pointers[e.pointerId] = p;
    var ids = Object.keys(this.pointers);
    if (ids.length === 1 && this.opts.onMove) {
      // a touch on the own piece starts moving it
      var ts = this.map.tokens || [], r = this.map.cell * this.zoom * 0.5;
      for (var i = 0; i < ts.length; i++) {
        if (!ts[i].me) continue;
        var c = this._center(ts[i].x, ts[i].y);
        if (Math.hypot(c.x - p.x, c.y - p.y) <= Math.max(r, 22)) { this.drag = { ref: ts[i].ref, x: p.x, y: p.y }; break; }
      }
    }
    if (ids.length === 2) this.drag = null;
    this.draw();
  };

  MapView.prototype._move = function (e) {
    if (!this.pointers[e.pointerId]) return;
    var p = this._pos(e), old = this.pointers[e.pointerId];
    var ids = Object.keys(this.pointers);
    if (ids.length === 2) {
      var other = this.pointers[ids[0] == e.pointerId ? ids[1] : ids[0]];
      var d0 = Math.hypot(old.x - other.x, old.y - other.y), d1 = Math.hypot(p.x - other.x, p.y - other.y);
      if (d0 > 10) this.zoomBy(d1 / d0, (p.x + other.x) / 2, (p.y + other.y) / 2);
      this.pan.x += (p.x - old.x) / 2; this.pan.y += (p.y - old.y) / 2;
    } else if (this.drag) {
      this.drag.x = p.x; this.drag.y = p.y;
    } else {
      this.pan.x += p.x - old.x; this.pan.y += p.y - old.y;
    }
    this.pointers[e.pointerId] = p;
    this.draw();
  };

  MapView.prototype._up = function (e) {
    if (!this.pointers[e.pointerId]) return;
    var p = this._pos(e);
    delete this.pointers[e.pointerId];
    if (this.drag) {
      var sq = this._square(p.x, p.y), m = this.map, t = this._tok(this.drag.ref);
      this.drag = null;
      if (t && (sq.x !== t.x || sq.y !== t.y) && sq.x >= 0 && sq.y >= 0 && sq.x < m.cols && sq.y < m.rows) {
        var busy = (m.tokens || []).some(function (o) { return o.x === sq.x && o.y === sq.y; });
        if (busy) { if (this.opts.onBusy) this.opts.onBusy(); }
        else { this.pending = { ref: t.ref, x: sq.x, y: sq.y, t: Date.now() }; this.opts.onMove(sq.x, sq.y); }
      }
    }
    this.draw();
  };

  MapView.prototype._avatar = function (key) {
    if (!key) return null;
    var a = this.avatars[key], self = this;
    if (!a) {
      a = this.avatars[key] = new Image();
      a.onload = function () { self.draw(); };
      a.src = '/img/' + key + '.jpg';
    }
    return a.complete && a.naturalWidth ? a : null;
  };

  MapView.prototype.draw = function () {
    var ctx = this.ctx, dpr = window.devicePixelRatio || 1, W = this.c.width / dpr, H = this.c.height / dpr, m = this.map;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = '#120c08';
    ctx.fillRect(0, 0, W, H);
    if (!m) return;
    var z = this.zoom, c = m.cell * z, ox = this.pan.x + m.ox * z, oy = this.pan.y + m.oy * z;
    if (this.img) ctx.drawImage(this.img, this.pan.x, this.pan.y, m.w * z, m.h * z);
    else { ctx.fillStyle = '#b3a48e'; ctx.font = '16px sans-serif'; ctx.fillText('Carico la mappa...', 16, 28); }
    if (m.grid) {
      ctx.strokeStyle = 'rgba(0,0,0,0.45)'; ctx.lineWidth = 1;
      ctx.beginPath();
      for (var i = 0; i <= m.cols; i++) { ctx.moveTo(ox + i * c, oy); ctx.lineTo(ox + i * c, oy + m.rows * c); }
      for (var j = 0; j <= m.rows; j++) { ctx.moveTo(ox, oy + j * c); ctx.lineTo(ox + m.cols * c, oy + j * c); }
      ctx.stroke();
    }
    var self = this, ts = (m.tokens || []).slice();
    // pieces: the own one is drawn last (on top)
    ts.sort(function (a, b) { return (a.me ? 1 : 0) - (b.me ? 1 : 0); });
    ts.forEach(function (t) {
      var x = t.x, y = t.y;
      if (self.pending && self.pending.ref === t.ref) { x = self.pending.x; y = self.pending.y; }
      var p = self._center(x, y);
      if (self.drag && self.drag.ref === t.ref) {
        var sq = self._square(self.drag.x, self.drag.y);
        if (sq.x >= 0 && sq.y >= 0 && sq.x < m.cols && sq.y < m.rows) {
          ctx.fillStyle = 'rgba(255,215,80,0.35)';
          ctx.fillRect(ox + sq.x * c, oy + sq.y * c, c, c);
        }
        // lifted above the finger so it stays visible
        p = { x: self.drag.x, y: self.drag.y - Math.max(0, 30 - c * 0.3) };
      }
      self._piece(t, p.x, p.y, Math.max(6, c * 0.42));
    });
  };

  MapView.prototype._piece = function (t, x, y, r) {
    var ctx = this.ctx, pc = t.kind === 'pc', down = t.status === 'A terra' || t.status === 'Morto' || t.status === 'Sconfitto';
    ctx.fillStyle = 'rgba(0,0,0,0.45)';
    ctx.beginPath(); ctx.arc(x + r * 0.08, y + r * 0.12, r, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = down ? '#4a4a4a' : (pc ? '#2e5fc4' : '#b3271e');
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
    var av = r >= 12 ? this._avatar(t.img) : null;
    if (av) {
      ctx.save(); ctx.beginPath(); ctx.arc(x, y, r * 0.9, 0, Math.PI * 2); ctx.clip();
      ctx.drawImage(av, x - r * 0.9, y - r * 0.9, r * 1.8, r * 1.8);
      if (down) { ctx.fillStyle = 'rgba(0,0,0,0.5)'; ctx.fillRect(x - r, y - r, 2 * r, 2 * r); }
      ctx.restore();
    } else {
      ctx.fillStyle = '#fff';
      ctx.font = 'bold ' + Math.max(8, Math.round(r * 0.8)) + 'px sans-serif';
      ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(initials(t.name), x, y + 1);
    }
    ctx.lineWidth = Math.max(2, r * 0.1);
    ctx.strokeStyle = pc ? '#f0cd6a' : '#3a0c08';
    ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.stroke();
    if (t.cur) { ctx.lineWidth = Math.max(2.5, r * 0.13); ctx.strokeStyle = '#ffd84a'; ctx.beginPath(); ctx.arc(x, y, r * 1.2, 0, Math.PI * 2); ctx.stroke(); }
    if (t.me) { ctx.lineWidth = 2; ctx.strokeStyle = '#fff'; ctx.setLineDash([4, 3]); ctx.beginPath(); ctx.arc(x, y, r * 1.36, 0, Math.PI * 2); ctx.stroke(); ctx.setLineDash([]); }
    if (down) {
      ctx.strokeStyle = '#e02020'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(x - r * 0.6, y - r * 0.6); ctx.lineTo(x + r * 0.6, y + r * 0.6);
      ctx.moveTo(x - r * 0.6, y + r * 0.6); ctx.lineTo(x + r * 0.6, y - r * 0.6); ctx.stroke();
    }
  };

  function initials(n) {
    var p = String(n || '?').trim().split(/\s+/);
    var s = p[0].charAt(0).toUpperCase(), last = p[p.length - 1];
    if (p.length > 1) s += /^\d+$/.test(last) ? last : last.charAt(0).toUpperCase();
    else s += p[0].charAt(1) || '';
    return s;
  }

  global.MapView = MapView;
})(window);
