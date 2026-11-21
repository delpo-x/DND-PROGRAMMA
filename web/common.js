/* Codice comune alle pagine Giocatore e Schermo condiviso. */
(function (global) {
  'use strict';
  var ABILITIES = [['FOR', 'Forza'], ['DES', 'Destrezza'], ['COS', 'Costituzione'], ['INT', 'Intelligenza'], ['SAG', 'Saggezza'], ['CAR', 'Carisma']];
  var SKILLS = [
    ['acrobazia', 'Acrobazia', 'DES'], ['addestrare', 'Addestrare Animali', 'SAG'], ['arcano', 'Arcano', 'INT'],
    ['atletica', 'Atletica', 'FOR'], ['furtivita', 'Furtività', 'DES'], ['indagare', 'Indagare', 'INT'],
    ['inganno', 'Inganno', 'CAR'], ['intimidire', 'Intimidire', 'CAR'], ['intrattenere', 'Intrattenere', 'CAR'],
    ['intuizione', 'Intuizione', 'SAG'], ['medicina', 'Medicina', 'SAG'], ['natura', 'Natura', 'INT'],
    ['percezione', 'Percezione', 'SAG'], ['persuasione', 'Persuasione', 'CAR'], ['rapidita', 'Rapidità di Mano', 'DES'],
    ['religione', 'Religione', 'INT'], ['sopravvivenza', 'Sopravvivenza', 'SAG'], ['storia', 'Storia', 'INT']
  ];
  function abName(id) { for (var i = 0; i < ABILITIES.length; i++) if (ABILITIES[i][0] === id) return ABILITIES[i][1]; return id; }
  function skill(id) { for (var i = 0; i < SKILLS.length; i++) if (SKILLS[i][0] === id) return SKILLS[i]; return null; }
  function abMod(score) { return Math.floor((Number(score || 10) - 10) / 2); }
  function fmtMod(m) { m = Number(m) || 0; return (m >= 0 ? '+' : '') + m; }
  function skillMod(ch, id) {
    var s = skill(id); if (!s || !ch) return 0;
    var lv = Number((ch.skills || {})[id] || 0);
    return abMod((ch.ab || {})[s[2]]) + prof(ch) * Math.min(2, Math.max(0, lv));
  }
  // proficiency bonus of the sheet: 2 only when missing (0 is a valid value)
  function prof(ch) { return (ch.prof === undefined || ch.prof === null || ch.prof === '') ? 2 : (Number(ch.prof) || 0); }
  function saveMod(ch, ab) {
    if (!ch) return 0;
    return abMod((ch.ab || {})[ab]) + ((ch.saves || []).indexOf(ab) >= 0 ? prof(ch) : 0);
  }
  function initMod(ch) { return ch ? abMod((ch.ab || {}).DES) + Number(ch.init_bonus || 0) : 0; }

  function esc(s) {
    return String(s === undefined || s === null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function $(id) { return document.getElementById(id); }

  function store(key, val) {
    try { if (val === undefined) return localStorage.getItem(key); localStorage.setItem(key, val); } catch (e) {
      global.__mem = global.__mem || {}; if (val === undefined) return global.__mem[key] || null; global.__mem[key] = val;
    }
    return null;
  }

  // Collegamento WebSocket al tablet del master, con riconnessione automatica.
  function Link(role, onMessage, onStatus) {
    this.role = role; this.onMessage = onMessage; this.onStatus = onStatus || function () {};
    this.ws = null; this.timer = 0; this.tokenKey = role === 'screen' ? 'dnd_tavolo_screen' : (role === 'spectator' ? 'dnd_tavolo_spect' : 'dnd_tavolo_token');
    this.lastRx = Date.now(); this.hiddenAt = 0;
    var self = this;
    // iPhone: with the screen locked or the app in the background Safari stops
    // the page, and on return the WebSocket often still looks open but is dead
    // (what is sent is lost without errors). After a pause it is replaced.
    document.addEventListener('visibilitychange', function () {
      if (document.hidden) { self.hiddenAt = Date.now(); return; }
      if (self.hiddenAt && Date.now() - self.hiddenAt > 4000) self.connect(); else self.ensure();
      self.hiddenAt = 0;
    });
    window.addEventListener('pageshow', function (ev) { if (ev.persisted) self.connect(); else self.ensure(); });
    window.addEventListener('online', function () { self.connect(); });
    // the master answers every ping: no message for 40 s = dead connection
    setInterval(function () {
      if (document.hidden) return;
      if (self.ws && self.ws.readyState === 1 && Date.now() - self.lastRx > 40000) { self.connect(); return; }
      self.send({ t: 'ping' });
    }, 15000);
    this.connect();
  }
  Link.prototype.url = function () {
    var port = Number(location.port || 80) + 1;
    return 'ws://' + location.hostname + ':' + port + '/';
  };
  Link.prototype.ensure = function () {
    if (!this.ws || this.ws.readyState > 1) this.connect();
  };
  Link.prototype.connect = function () {
    var self = this;
    clearTimeout(this.timer);
    try { if (this.ws) { this.ws.onclose = null; this.ws.close(); } } catch (e) { }
    this.onStatus('connecting');
    var ws;
    try { ws = new WebSocket(this.url()); } catch (e) { this.timer = setTimeout(function () { self.connect(); }, 2000); return; }
    this.ws = ws;
    ws.onopen = function () {
      self.lastRx = Date.now();
      self.onStatus('open');
      ws.send(JSON.stringify({ t: 'hello', role: self.role, token: store(self.tokenKey) || '' }));
    };
    ws.onmessage = function (ev) {
      self.lastRx = Date.now();
      var m; try { m = JSON.parse(ev.data); } catch (e) { return; }
      if (m.t === 'welcome' && m.token) store(self.tokenKey, m.token);
      self.onMessage(m);
    };
    ws.onclose = function () {
      self.onStatus('closed');
      self.timer = setTimeout(function () { self.connect(); }, 1500);
    };
    ws.onerror = function () { try { ws.close(); } catch (e) { } };
  };
  Link.prototype.send = function (obj) {
    if (this.ws && this.ws.readyState === 1) { this.ws.send(JSON.stringify(obj)); return true; }
    return false;
  };

  // Suono e vibrazione per le notifiche (il suono parte dopo il primo tocco).
  var audio = null;
  function unlockAudio() {
    if (!audio) { try { var AC = window.AudioContext || window.webkitAudioContext; if (AC) audio = new AC(); } catch (e) { audio = null; } }
    if (!audio) return;
    try { if (audio.state !== 'running') audio.resume(); } catch (e) { }
    // iOS: a silent sample started inside the tap unlocks the context.
    try { var b = audio.createBuffer(1, 1, 22050), s = audio.createBufferSource(); s.buffer = b; s.connect(audio.destination); s.start(0); } catch (e) { }
  }
  // iPhone: let sound play even with the ring/silent switch on (Safari 17+).
  try { if (navigator.audioSession) navigator.audioSession.type = 'playback'; } catch (e) { }
  document.addEventListener('touchstart', unlockAudio, { passive: true });
  document.addEventListener('touchend', unlockAudio, { passive: true });
  document.addEventListener('click', unlockAudio);
  function beep(freq, dur) {
    if (!audio) return;
    try {
      if (audio.state !== 'running') audio.resume();
      var o = audio.createOscillator(), g = audio.createGain();
      o.frequency.value = freq || 660; o.type = 'triangle';
      g.gain.setValueAtTime(0.0001, audio.currentTime);
      g.gain.exponentialRampToValueAtTime(0.25, audio.currentTime + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, audio.currentTime + (dur || 0.35));
      o.connect(g); g.connect(audio.destination); o.start(); o.stop(audio.currentTime + (dur || 0.35) + 0.05);
    } catch (e) { }
  }
  function buzz(pattern) { try { if (navigator.vibrate) navigator.vibrate(pattern); } catch (e) { } }

  // Testo di una voce del registro pubblico.
  function rollLine(e) {
    if (e.secret) return '<span class="who">Master</span> <span class="dim">' + esc(e.text || 'Il master ha tirato in segreto') + '</span>';
    var dice = (e.dice || []).map(function (d) {
      var cls = d.drop ? 'die drop' : (d.s === 20 && d.v === 20 ? 'die nat20' : (d.s === 20 && d.v === 1 ? 'die nat1' : 'die'));
      return '<span class="' + cls + '" title="d' + d.s + '">' + d.v + '</span>';
    }).join('');
    var out = '<span class="who">' + esc(e.who) + '</span> ';
    if (e.reason) out += '<span class="reason">' + esc(e.reason) + '</span> ';
    else out += '<span class="reason">' + esc(e.kind) + '</span> ';
    out += '<span class="formula">' + esc(e.formula || '') + (e.mod_hidden ? ' <span class="dim">(mod. nascosto)</span>' : '') + '</span> ';
    out += dice + ' <b class="total">= ' + e.total + '</b>';
    if (e.manual) out += ' <span class="realdice">dadi veri</span>';
    if (e.outcome === 'success') out += ' <span class="ok">RIUSCITA</span>';
    if (e.outcome === 'fail') out += ' <span class="ko">FALLITA</span>';
    if (e.nat === 20) out += ' <span class="nat20t">20 naturale!</span>';
    if (e.nat === 1) out += ' <span class="nat1t">1 naturale</span>';
    return out;
  }

  function statusClass(s) {
    return { 'Illeso': 'st-ok', 'Ferito': 'st-hurt', 'Gravemente ferito': 'st-bad', 'A terra': 'st-down' }[s] || '';
  }

  // Effetti a tutto schermo: lampo per critico / fallimento, scossa di un elemento,
  // banner animato per il cambio di turno. Gli elementi vengono creati al primo uso.
  function fxEl(id) {
    var el = document.getElementById(id);
    if (!el) { el = document.createElement('div'); el.id = id; document.body.appendChild(el); }
    return el;
  }
  function restart(el, cls) { el.classList.remove(cls); void el.offsetWidth; el.classList.add(cls); }
  function flash(kind, shakeEl) {
    var el = fxEl('fx');
    el.className = ''; void el.offsetWidth; el.className = kind;
    if (shakeEl) restart(shakeEl, 'shake');
  }
  function turnBanner(title, sub, img) {
    var el = fxEl('turnFx');
    el.innerHTML = (img ? '<img src="/img/' + esc(img) + '.jpg" alt="">' : '') + '<div><small>' + esc(sub || '') + '</small>' + esc(title) + '</div>';
    restart(el, 'show');
  }
  // Ritratto piccolo per le liste (vuoto se non c'e' un'immagine).
  function avatar(img) { return img ? '<img class="av" src="/img/' + esc(img) + '.jpg" alt="" loading="lazy">' : ''; }

  global.T = {
    ABILITIES: ABILITIES, SKILLS: SKILLS, abName: abName, skill: skill, abMod: abMod, fmtMod: fmtMod,
    skillMod: skillMod, saveMod: saveMod, initMod: initMod, esc: esc, $: $, store: store, Link: Link,
    beep: beep, buzz: buzz, rollLine: rollLine, statusClass: statusClass, flash: flash, turnBanner: turnBanner, avatar: avatar
  };
})(window);
