extends Node
## --self-test <file.json>: drives the app like a master and a player would
## (3D dice roll, local web page, WebSocket player, visibility rules,
## initiative) and writes the results as JSON, then quits.

var app
var steps: Array = []


func _step(name: String, ok: bool, detail: String) -> void:
	steps.append({"step": name, "passed": ok, "detail": detail})
	print("[self-test] %s: %s - %s" % [name, "OK" if ok else "FALLITO", detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func run(a, path: String) -> void:
	app = a
	await _frames(10)
	var st: GameState = app.state
	# ---- hud
	var tab_names: Array = []
	for i in app.tabs.get_tab_count():
		tab_names.append(app.tabs.get_tab_title(i))
	var hud_ok: bool = tab_names.size() == 9 and app.top_net.text.begins_with("http://") and app.tab_dice.roll_btn.text == "LANCIA"
	_step("hud", hud_ok, "schede: %s; indirizzo: %s; pulsante %s" % [", ".join(tab_names), app.top_net.text, app.tab_dice.roll_btn.text])
	# ---- dice roll (move + act)
	app.tab_dice.counts = {20: 1, 6: 2, 100: 1}
	app.tab_dice.mod = 2
	app.tab_dice.roll_now()
	var t0 := Time.get_ticks_msec()
	var entry: Dictionary = {}
	while app.tab_dice.tray.rolling and Time.get_ticks_msec() - t0 < 12000:
		await get_tree().process_frame
	await _frames(2)
	entry = app.tab_dice.last_entry
	var trav: float = app.tab_dice.tray.travelled
	_step("move", trav > 2.0, "i dadi 3D hanno percorso fino a %.1f unità sul tavolo in %.1f s" % [trav, (Time.get_ticks_msec() - t0) / 1000.0])
	var act_ok := false
	var detail := "nessun tiro registrato"
	if not entry.is_empty():
		var sum := int(entry.mod)
		var ranges_ok := true
		for d in entry.dice:
			sum += int(d.v)
			if int(d.v) < 1 or int(d.v) > int(d.s):
				ranges_ok = false
		act_ok = ranges_ok and sum == int(entry.total) and entry.dice.size() == 4
		detail = "%s -> %s = %d" % [entry.formula, str(entry.dice.map(func(d): return d.v)), int(entry.total)]
	_step("act", act_ok, detail)
	# ---- web page served
	var page := await _http_get("/giocatore")
	_step("web_page", page.begins_with("HTTP/1.1 200") and page.contains("LANCIA"), "GET /giocatore -> %s (%d byte)" % [page.get_slice("\r\n", 0), page.length()])
	var page2 := await _http_get("/dice3d.js")
	_step("dice_script", page2.begins_with("HTTP/1.1 200") and page2.contains("DiceTray"), "GET /dice3d.js -> %s" % page2.get_slice("\r\n", 0))
	# ---- player over WebSocket
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % app.net.ws_port())
	var msgs: Array = []
	if await _ws_wait_open(ws):
		ws.send_text(JSON.stringify({"t": "hello", "token": "selftest-token-1", "role": "player"}))
		await _ws_collect(ws, msgs, 20)
		var aria: Dictionary = st.characters()[0]
		ws.send_text(JSON.stringify({"t": "claim", "char_id": aria.id}))
		await _ws_collect(ws, msgs, 20)
	var last_state := _last_state(msgs)
	var welcome_ok := false
	for m in msgs:
		if m.get("t") == "welcome" and m.get("chars", []).size() >= 2:
			welcome_ok = true
	_step("websocket", welcome_ok and last_state.get("me") is Dictionary, "messaggi ricevuti: %d, personaggio: %s" % [msgs.size(), (last_state.get("me") if last_state.get("me") is Dictionary else {}).get("name", "-")])
	# ---- visibility rules
	var vis_ok := true
	var why: Array = []
	for m in last_state.get("monsters", []):
		if m.has("hp") or m.has("ac") or m.has("init_mod") or m.has("notes"):
			vis_ok = false
			why.append("statistiche mostro visibili")
		if str(m.name).begins_with("Capo"):
			vis_ok = false
			why.append("mostro nascosto visibile")
	for q in last_state.get("quests", []):
		for c in q.checks:
			if c.has("dc"):
				vis_ok = false
				why.append("CD visibile")
		if q.checks.size() != 1:
			vis_ok = false
			why.append("prova nascosta visibile")
	app.tab_dice.set_secret(true)
	app.tab_dice.counts = {20: 1}
	app.tab_dice.mod = 0
	app.tab_dice.roll_now()
	t0 = Time.get_ticks_msec()
	while app.tab_dice.tray.rolling and Time.get_ticks_msec() - t0 < 12000:
		await get_tree().process_frame
	app.tab_dice.set_secret(false)
	msgs.clear()
	await _ws_collect(ws, msgs, 15)
	last_state = _last_state(msgs)
	var lg: Array = last_state.get("log", [])
	if lg.is_empty() or not bool(lg[0].get("secret", false)) or lg[0].has("dice") or lg[0].get("text", "") != "Il master ha tirato in segreto":
		vis_ok = false
		why.append("tiro segreto non mascherato")
	for m in msgs:
		if m.get("t") == "roll" and m.e.get("secret", false):
			vis_ok = false
			why.append("animazione di un tiro segreto inviata")
	_step("visibility", vis_ok, "ok: niente CA/PF dei mostri, niente CD, tiri segreti mascherati" if vis_ok else ", ".join(why))
	# ---- request with hidden DC + automatic outcome
	var q: Dictionary = st.data.quests[0]
	var chk: Dictionary = q.checks[0]
	st.request_check(q.id, chk.id)
	msgs.clear()
	await _ws_collect(ws, msgs, 15)
	var req := {}
	for m in msgs:
		if m.get("t") == "request":
			req = m.r
	var req_ok: bool = not req.is_empty() and not req.has("dc")
	ws.send_text(JSON.stringify({"t": "roll", "dice": [{"s": 20, "v": 19, "drop": false}], "mod": 2, "kind": "Prova",
		"reason": "Sopravvivenza", "adv": "none", "request_id": req.get("id", ""), "formula": "1d20 + 2"}))
	msgs.clear()
	await _ws_collect(ws, msgs, 15)
	var outcome := ""
	for m in msgs:
		if m.get("t") == "roll":
			outcome = str(m.e.get("outcome", ""))
	req_ok = req_ok and outcome == "success" and chk.result == "success"
	_step("request_dc", req_ok, "richiesta arrivata senza CD; tiro 19+2 contro CD %d -> %s; prova della missione: %s" % [int(chk.dc), outcome, chk.result])
	# ---- duplicate + initiative
	var gob: Dictionary = st.monsters()[0]
	st.duplicate_monster(gob.id, 1)
	var names: Array = st.monsters().map(func(m): return m.name)
	var dup_ok := names.has("Goblin 1") and names.has("Goblin 2")
	_step("duplicate", dup_ok, "bestiario: %s" % ", ".join(names))
	var refs: Array = []
	for c in st.characters():
		refs.append(c.id)
	for m in st.monsters():
		refs.append(m.id)
	st.combat_start(refs)
	st.roll_monster_initiative()
	for c in st.ini().combatants:
		if c.type == "pc":
			st.set_score(c.id, 12)
	var n: int = st.ini().combatants.size()
	for i in n + 1:
		st.next_turn()
	var sorted_ok := true
	var prev := 999
	for c in st.ini().combatants:
		if int(c.score) > prev:
			sorted_ok = false
		prev = int(c.score)
	msgs.clear()
	await _ws_collect(ws, msgs, 15)
	last_state = _last_state(msgs)
	var order: Array = last_state.get("init", {}).get("order", [])
	var hidden_scores := true
	for o in order:
		if o.has("score") and not o.get("me", false):
			hidden_scores = false
	var ini_ok: bool = sorted_ok and int(st.ini().round) == 2 and hidden_scores and order.size() == n - 1
	_step("initiative", ini_ok, "%d combattenti, round %d, ordine giocatore: %s" % [n, int(st.ini().round), ", ".join(order.map(func(o): return o.name))])
	# ---- QR
	var qr := QR.encode(app.net.base_url() + "/giocatore")
	_step("qr", qr.size >= 21 and qr.size <= 57, "QR versione %d (%dx%d moduli)" % [qr.version, qr.size, qr.size])
	ws.close()
	var out := {"version": 1, "steps": steps}
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	await _frames(2)
	get_tree().quit()


func _last_state(msgs: Array) -> Dictionary:
	var s := {}
	for m in msgs:
		if m.get("t") == "state":
			s = m.s
	return s


func _http_get(path: String) -> String:
	var tcp := StreamPeerTCP.new()
	tcp.connect_to_host("127.0.0.1", app.net.http_port)
	var buf := PackedByteArray()
	var sent := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		tcp.poll()
		var st := tcp.get_status()
		if st == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				tcp.put_data(("GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" % path).to_utf8_buffer())
				sent = true
			var n := tcp.get_available_bytes()
			if n > 0:
				var r := tcp.get_partial_data(n)
				buf.append_array(r[1])
		elif st == StreamPeerTCP.STATUS_NONE or st == StreamPeerTCP.STATUS_ERROR:
			if sent:
				break
		await get_tree().process_frame
		var txt := buf.get_string_from_utf8()
		var hdr_end := txt.find("\r\n\r\n")
		if hdr_end > 0:
			var re := RegEx.new()
			re.compile("Content-Length: (\\d+)")
			var mm := re.search(txt)
			if mm and buf.size() >= hdr_end + 4 + int(mm.get_string(1)):
				break
	tcp.disconnect_from_host()
	return buf.get_string_from_utf8()


func _ws_wait_open(ws: WebSocketPeer) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		ws.poll()
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
		await get_tree().process_frame
	return false


func _ws_collect(ws: WebSocketPeer, into: Array, frames: int) -> void:
	for i in frames:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if m is Dictionary:
				into.append(m)
		await get_tree().process_frame
