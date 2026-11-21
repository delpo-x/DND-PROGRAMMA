extends SceneTree
# Checks the master's real-dice entry, typed numbers not yet confirmed and the
# death-save row, with the whole app loaded.

var ok := true


func _check(name: String, cond: bool, detail = "") -> void:
	print("%s %s %s" % ["ok  " if cond else "FAIL", name, str(detail)])
	ok = ok and cond


func _init() -> void:
	var app = load("res://main.tscn").instantiate()
	app.state.persist = false
	root.add_child(app)
	for i in 10:
		await process_frame
	var st: GameState = app.state
	st.new_campaign("Test dadi veri")
	var a: Dictionary = st.add_character("Aria", "")
	var dice = app.tab_dice
	# real dice with advantage: 7 then 15 -> keeps 15
	dice.counts = {}
	dice.mod = 2
	dice._toggle_manual()
	_check("button text in real-dice mode", dice.roll_btn.text == "INSERISCI TIRO", dice.roll_btn.text)
	dice._set_adv("adv")
	dice.roll_now()
	await process_frame
	_check("picker asks two d20", dice.pick_steps.size() == 2, dice.pick_steps)
	dice._pick(7)
	await process_frame
	dice._pick(15)
	await process_frame
	var e: Dictionary = dice.last_entry
	_check("advantage keeps 15, total 17", int(e.get("total", 0)) == 17 and bool(e.get("manual", false)), e.get("dice", []))
	_check("advantage off after the roll", dice.adv == "none")
	_check("button usable again", not dice.roll_btn.disabled)
	# d100: tens 00 + units 0 = 100, with Indietro in between
	dice.counts = {100: 1}
	dice.mod = 0
	dice.roll_now()
	await process_frame
	dice._pick(30)
	dice._pick_back()
	await process_frame
	dice._pick(0)
	await process_frame
	dice._pick(0)
	await process_frame
	_check("d100 00 + 0 = 100", int(dice.last_entry.get("total", 0)) == 100, dice.last_entry.get("dice", []))
	# cancel leaves the button usable
	dice.roll_now()
	await process_frame
	dice._pick_cancel()
	_check("cancel: no roll, button usable", int(dice.last_entry.total) == 100 and not dice.roll_btn.disabled)
	# a number typed without Enter is used
	var sb := SpinBox.new()
	sb.max_value = 999
	root.add_child(sb)
	sb.get_line_edit().text = "12"
	_check("typed number used without Enter", UI.spin_value(sb) == 12)
	# spectator: public view of the shared screen, read only, not listed for the master
	var ws := WebSocketPeer.new()
	ws.connect_to_url("ws://127.0.0.1:%d" % app.net.ws_port())
	var msgs: Array = []
	var t0 := Time.get_ticks_msec()
	while ws.get_ready_state() != WebSocketPeer.STATE_OPEN and Time.get_ticks_msec() - t0 < 5000:
		ws.poll()
		await process_frame
	ws.send_text(JSON.stringify({"t": "hello", "token": "spectator-test-1", "role": "spectator"}))
	await _collect(ws, msgs, 20)
	var view: Dictionary = {}
	for m in msgs:
		if m.get("t") == "state":
			view = m.s
	_check("spectator gets the shared-screen view", view.has("init") and view.has("log") and not view.has("me") and not view.has("requests"), view.keys())
	var listed := false
	for c in app.net.client_list():
		listed = true
	_check("spectator not listed for the master", not listed)
	var log_before: int = st.data.log.size()
	var hp_before := int(a.hp)
	for bad in [{"t": "roll", "dice": [{"s": 20, "v": 20, "drop": false}], "mod": 0, "kind": "Libero"},
			{"t": "hp", "d": 5}, {"t": "claim", "char_id": a.id}, {"t": "create_char", "name": "Intruso"}]:
		ws.send_text(JSON.stringify(bad))
	await _collect(ws, msgs, 20)
	_check("spectator can't act", st.data.log.size() == log_before and int(a.hp) == hp_before and st.characters().size() == 1)
	st.master_roll("", "Libero", [{"s": 20, "v": 11, "drop": false}], 0, "none", "prova pubblica", false, "1d20")
	var got_roll := false
	msgs.clear()
	await _collect(ws, msgs, 20)
	for m in msgs:
		if m.get("t") == "roll" and int(m.e.total) == 11:
			got_roll = true
	_check("spectator sees public rolls", got_roll)
	ws.close()
	# death-save row: no roll buttons once dead
	st.change_hp(a.id, -10)
	st.set_death(a.id, 0, 3)
	var row: Control = app.tab_players._death_row(a)
	var texts: Array = []
	for c in row.find_children("*", "Button", true, false):
		texts.append(c.text)
	_check("dead: only Azzera", texts == ["Azzera"], texts)
	print("master new test: ", "OK" if ok else "FAIL")
	row.free()
	sb.free()
	app.queue_free()
	for i in 3:
		await process_frame
	quit(0 if ok else 1)


func _collect(ws: WebSocketPeer, into: Array, frames: int) -> void:
	for i in frames:
		ws.poll()
		while ws.get_available_packet_count() > 0:
			var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if m is Dictionary:
				into.append(m)
		await process_frame
