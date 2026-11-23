extends HBoxContainer
## Master dice: 3D tray with physics, dice selection, modifier,
## advantage / disadvantage, public / secret switch and the big LANCIA button.

signal roll_done(entry: Dictionary)

var app
var tray: DiceTray
var tray_holder: Control
var badges: Control
var result_lbl: Label
var crit_lbl: Label
var flash: ColorRect
var who_opt: OptionButton
var who_ids: Array = [""]
var kind_opt: OptionButton
var reason_edit: LineEdit
var formula_lbl: Label
var mod_lbl: Label
var dice_btns: Dictionary = {}
var adv_btns: Dictionary = {}
var secret_btn: Button
var roll_btn: Button
var counts: Dictionary = {}
var mod := 0
var adv := "none"
var secret := false
var manual := false  # true = the master types in the values of real dice
var manual_btn: Button
var pick_box: VBoxContainer
var pick_steps: Array = []
var pick_vals: Array = []
var logical: Array = []
var pending_info: Dictionary = {}
var last_entry: Dictionary = {}


func setup(a) -> void:
	app = a
	add_theme_constant_override("separation", 12)
	# ---- tray
	tray_holder = Control.new()
	tray_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tray_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tray_holder.clip_contents = true
	add_child(tray_holder)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	tray_holder.add_child(svc)
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_2X
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	tray = DiceTray.new()
	sv.add_child(tray)
	tray.finished.connect(_on_finished)
	badges = Control.new()
	badges.set_anchors_preset(Control.PRESET_FULL_RECT)
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray_holder.add_child(badges)
	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(1, 0.8, 0.3, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray_holder.add_child(flash)
	crit_lbl = UI.lbl("", 64, UI.GOLD)
	crit_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	crit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crit_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crit_lbl.add_theme_constant_override("outline_size", 14)
	crit_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	crit_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray_holder.add_child(crit_lbl)
	var res_panel := UI.card(UI.vbox(), Color(0, 0, 0, 0.6), 10)
	res_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	res_panel.offset_top = -86
	res_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray_holder.add_child(res_panel)
	result_lbl = UI.lbl("Scegli i dadi e premi LANCIA", 26, UI.TEXT)
	UI.engrave(result_lbl)
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	res_panel.get_child(0).add_child(result_lbl)
	# ---- controls
	var col := UI.vbox([], 10)
	var sc := UI.scroll(col)
	sc.custom_minimum_size = Vector2(420, 0)
	sc.size_flags_horizontal = Control.SIZE_FILL
	add_child(sc)
	secret_btn = UI.color_btn("", UI.GREEN, _toggle_secret, 64)
	secret_btn.add_theme_font_size_override("font_size", 26)
	UI.engrave(secret_btn)
	col.add_child(secret_btn)
	manual_btn = UI.color_btn("", UI.PANEL2, _toggle_manual, 52)
	manual_btn.add_theme_font_size_override("font_size", 20)
	col.add_child(manual_btn)
	who_opt = UI.option(["Master"], 0, func(_i): _auto_mod())
	kind_opt = UI.option(Rules.KINDS, 0, func(_i): _auto_mod())
	col.add_child(UI.hbox([UI.lbl("Chi tira", 20, UI.DIM), UI.expand(who_opt)]))
	col.add_child(UI.hbox([UI.lbl("Tipo", 20, UI.DIM), UI.expand(kind_opt)]))
	reason_edit = UI.edit("", "Motivo (es. Attacco alla guardia)")
	col.add_child(reason_edit)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for s in Rules.DIE_SIDES:
		var b := UI.btn("d%d" % s, _add_die.bind(s), 64, 90)
		b.add_theme_font_size_override("font_size", 22)
		dice_btns[s] = b
		grid.add_child(b)
	grid.add_child(UI.color_btn("Azzera", Color(0.35, 0.25, 0.2), _clear_dice, 64))
	col.add_child(grid)
	formula_lbl = UI.lbl("", 26, UI.GOLD)
	formula_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(formula_lbl)
	mod_lbl = UI.lbl("+0", 28)
	mod_lbl.custom_minimum_size = Vector2(80, 0)
	mod_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(UI.hbox([UI.lbl("Modificatore", 20, UI.DIM), UI.spacer(),
		UI.btn("-", func(): _set_mod(mod - 1), 56, 64), mod_lbl, UI.btn("+", func(): _set_mod(mod + 1), 56, 64)]))
	var adv_row := UI.hbox([], 6)
	for pair in [["dis", "Svantaggio"], ["none", "Normale"], ["adv", "Vantaggio"]]:
		var b := UI.btn(pair[1], _set_adv.bind(pair[0]), 56)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		adv_btns[pair[0]] = b
		adv_row.add_child(b)
	col.add_child(adv_row)
	roll_btn = UI.color_btn("LANCIA", Color(0.55, 0.1, 0.1), roll_now, 96)
	UI.engrave(roll_btn)
	roll_btn.add_theme_font_size_override("font_size", 40)
	col.add_child(roll_btn)
	_update_controls()


func refresh() -> void:
	var cur: String = who_ids[who_opt.selected] if who_opt.selected >= 0 and who_opt.selected < who_ids.size() else ""
	who_opt.clear()
	who_ids = [""]
	who_opt.add_item("Master")
	for m in app.state.monsters():
		who_ids.append(m.id)
		who_opt.add_item("%s (%s)" % [m.name, m.kind])
	for c in app.state.characters():
		who_ids.append(c.id)
		who_opt.add_item("%s (personaggio)" % c.name)
	var idx := who_ids.find(cur)
	who_opt.select(maxi(0, idx))


func _auto_mod() -> void:
	var id: String = who_ids[who_opt.selected] if who_opt.selected < who_ids.size() else ""
	if id != "" and Rules.KINDS[kind_opt.selected] == "Iniziativa":
		var e: Dictionary = app.state.find_entity(id)
		_set_mod(app.state.entity_init_mod(e))
		counts = {20: 1}
		_update_controls()


func _toggle_secret() -> void:
	secret = not secret
	_update_controls()


func _add_die(s: int) -> void:
	counts[s] = int(counts.get(s, 0)) + 1
	_update_controls()


func _clear_dice() -> void:
	counts.clear()
	mod = 0
	adv = "none"
	_update_controls()


func _set_mod(v: int) -> void:
	mod = clampi(v, -30, 30)
	_update_controls()


func _set_adv(a: String) -> void:
	adv = a
	_update_controls()


func _toggle_manual() -> void:
	manual = not manual
	result_lbl.text = "Tira i dadi veri, poi premi INSERISCI TIRO" if manual else "Scegli i dadi e premi LANCIA"
	_update_controls()


func set_secret(v: bool) -> void:
	secret = v
	_update_controls()


func _update_controls() -> void:
	secret_btn.text = "TIRO SEGRETO" if secret else "TIRO PUBBLICO"
	var col := Color(0.34, 0.14, 0.42) if secret else Color(0.16, 0.38, 0.23)
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = secret_btn.get_theme_stylebox(st).duplicate()
		sb.bg_color = col if st == "normal" else (col.lightened(0.1) if st == "hover" else col.darkened(0.2))
		sb.border_color = col.lerp(UI.GOLD, 0.45)
		secret_btn.add_theme_stylebox_override(st, sb)
	for s in dice_btns:
		var n := int(counts.get(s, 0))
		dice_btns[s].text = ("%dd%d" % [n, s]) if n > 0 else "d%d" % s
	for k in adv_btns:
		adv_btns[k].button_pressed = (k == adv)
	mod_lbl.text = Rules.fmt_mod(mod)
	formula_lbl.text = formula_text()
	manual_btn.text = "DADI VERI: inserisci a mano" if manual else "Dadi dell'app (tocca per i dadi veri)"
	var mcol := Color(0.55, 0.42, 0.12) if manual else UI.PANEL2
	for st in ["normal", "hover", "pressed"]:
		var msb: StyleBoxFlat = manual_btn.get_theme_stylebox(st).duplicate()
		msb.bg_color = mcol if st == "normal" else (mcol.lightened(0.1) if st == "hover" else mcol.darkened(0.2))
		manual_btn.add_theme_stylebox_override(st, msb)
	roll_btn.text = "INSERISCI TIRO" if manual else "LANCIA"


func formula_text() -> String:
	var c := counts.duplicate()
	if c.is_empty():
		c = {20: 1}
	if adv != "none" and not c.has(20):
		c[20] = 1
	var parts: Array = []
	for s in [20, 12, 10, 8, 6, 4, 100]:
		if c.has(s):
			var p := "%dd%d" % [c[s], s]
			if s == 20 and adv == "adv":
				p += " con vantaggio"
			elif s == 20 and adv == "dis":
				p += " con svantaggio"
			parts.append(p)
	var t := " + ".join(parts)
	if mod > 0:
		t += " + %d" % mod
	elif mod < 0:
		t += " - %d" % -mod
	return t


## Builds the physical dice list and the logical dice that map onto it.
func _build_spec() -> Array:
	var c := counts.duplicate()
	if c.is_empty():
		c = {20: 1}
	if adv != "none" and not c.has(20):
		c[20] = 1
	var spec: Array = []
	logical = []
	for s in [20, 12, 10, 8, 6, 4, 100]:
		for k in int(c.get(s, 0)):
			if s == 100:
				logical.append({"s": 100, "p": [spec.size(), spec.size() + 1]})
				spec.append({"type": "d100t"})
				spec.append({"type": "d100u"})
			else:
				logical.append({"s": s, "p": [spec.size()]})
				spec.append({"type": "d%d" % s})
	if adv != "none":
		logical.append({"s": 20, "p": [spec.size()], "pair": 0})
		spec.append({"type": "d20"})
	return spec


func roll_now() -> void:
	if tray.rolling:
		return
	var who: String = who_ids[who_opt.selected] if who_opt.selected >= 0 and who_opt.selected < who_ids.size() else ""
	pending_info = {"who": who, "kind": Rules.KINDS[kind_opt.selected], "reason": reason_edit.text,
		"secret": secret, "mod": mod, "adv": adv, "formula": formula_text()}
	UI.clear(badges)
	crit_lbl.text = ""
	if manual:
		# the button stays enabled: the picker modal already blocks it, and if the
		# modal is closed some other way the master can simply press it again
		_build_spec()
		result_lbl.text = "Inserisci i numeri usciti sui dadi..."
		_ask_values()
		return
	roll_btn.disabled = true
	result_lbl.text = "I dadi rotolano..."
	tray.roll(_build_spec())


func preset_demo() -> void:
	counts = {20: 1, 8: 1, 6: 2}
	mod = 3
	_update_controls()
	roll_now()


func _on_finished(results: Array) -> void:
	var dice: Array = []
	for l in logical:
		var v := 0
		if l.s == 100:
			v = int(results[l.p[0]].value) + int(results[l.p[1]].value)
			if v == 0:
				v = 100
		else:
			v = int(results[l.p[0]].value)
		dice.append({"s": l.s, "v": v, "drop": false})
	_complete(dice, results, false)


## Applies advantage / disadvantage, records the roll and shows it.
## real = values typed in from the dice on the table.
func _complete(dice: Array, results: Array, real: bool) -> void:
	roll_btn.disabled = false
	if pending_info.adv != "none" and dice.size() >= 2:
		var a: Dictionary = dice[0]
		var b: Dictionary = dice[dice.size() - 1]
		var keep_first: bool = a.v >= b.v if pending_info.adv == "adv" else a.v <= b.v
		if keep_first:
			b.drop = true
		else:
			a.drop = true
	# advantage / disadvantage count for one roll only
	adv = "none"
	_update_controls()
	var entry: Dictionary = app.state.master_roll(pending_info.who, pending_info.kind, dice, int(pending_info.mod),
		pending_info.adv, pending_info.reason, pending_info.secret, pending_info.formula, real)
	last_entry = entry
	_show_result(entry, results)
	roll_done.emit(entry)


func _show_result(entry: Dictionary, results: Array) -> void:
	var parts: Array = []
	for d in entry.dice:
		var t := "d%d: %d" % [d.s, d.v]
		if d.drop:
			t = "(%s scartato)" % t
		parts.append(t)
	var txt := "  ".join(parts)
	if int(entry.mod) != 0:
		txt += "   mod %s" % Rules.fmt_mod(entry.mod)
	txt += "   =   TOTALE %d" % int(entry.total)
	if entry.secret:
		txt += "   (segreto)"
	if bool(entry.get("manual", false)):
		txt += "   (dadi veri)"
	result_lbl.text = txt
	var pos := tray.die_screen_positions()
	for i in mini(pos.size(), results.size()):
		var b := UI.lbl(str(results[i].value), 24, Color.WHITE)
		b.add_theme_constant_override("outline_size", 8)
		b.add_theme_color_override("font_outline_color", Color.BLACK)
		b.position = pos[i] - Vector2(12, 18)
		badges.add_child(b)
	if int(entry.nat) == 20:
		Sfx.play(self, "crit", 0.9)
		_crit("20 NATURALE!", UI.GOLD, Color(1, 0.85, 0.3, 0.45))
	elif int(entry.nat) == 1:
		Sfx.play(self, "fumble", 0.9)
		_crit("1 NATURALE...", Color(1, 0.3, 0.25), Color(0.8, 0.05, 0.05, 0.45))


func _crit(text: String, col: Color, flash_col: Color) -> void:
	crit_lbl.text = text
	crit_lbl.add_theme_color_override("font_color", col)
	crit_lbl.pivot_offset = crit_lbl.size / 2
	crit_lbl.scale = Vector2(0.3, 0.3)
	crit_lbl.modulate.a = 1.0
	flash.color = flash_col
	var tw := create_tween().set_parallel(true)
	tw.tween_property(crit_lbl, "scale", Vector2(1, 1), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "color:a", 0.0, 0.9)
	# shake the camera a little
	var sh := create_tween()
	for dx in [0.35, -0.3, 0.22, -0.14, 0.06, 0.0]:
		sh.tween_property(tray.cam, "h_offset", dx, 0.05)
	tw.chain().tween_interval(1.8)
	tw.chain().tween_property(crit_lbl, "modulate:a", 0.0, 0.6)


# ------------------------------------------------------------- real dice
## Asks the value of each die of `logical`, one tap per die. The d100 is
## entered as on the table: tens die (00-90), then units die (0-9); 00 + 0 = 100.
func _ask_values() -> void:
	pick_steps = []
	for i in logical.size():
		var s := int(logical[i].s)
		if s == 100:
			pick_steps.append({"die": i, "s": 100, "part": "tens"})
			pick_steps.append({"die": i, "s": 100, "part": "units"})
		else:
			pick_steps.append({"die": i, "s": s, "part": ""})
	pick_vals = []
	pick_box = UI.vbox([], 10)
	pick_box.custom_minimum_size = Vector2(0, 440)
	_render_pick()
	var why: String = str(pending_info.reason).strip_edges()
	app.show_modal("Dadi veri: %s" % (why if why != "" else str(pending_info.formula)), pick_box, [
		["Indietro", _pick_back],
		["Annulla", _pick_cancel],
	], 820)


func _pick_values() -> Array:
	var vals: Array = []
	for l in logical:
		vals.append(-1)
	for k in pick_vals.size():
		var st: Dictionary = pick_steps[k]
		var v := int(pick_vals[k])
		if st.part == "units":
			var t := int(vals[st.die]) + v
			vals[st.die] = 100 if t == 0 else t
		else:
			vals[st.die] = v
	return vals


func _render_pick() -> void:
	if pick_box == null or not is_instance_valid(pick_box) or pick_vals.size() >= pick_steps.size():
		return
	UI.clear(pick_box)
	var vals := _pick_values()
	var st: Dictionary = pick_steps[pick_vals.size()]
	var chips: Array = []
	for i in logical.size():
		var v := int(vals[i])
		var txt := "?" if v < 0 else str(v)
		if i == int(st.die) and v >= 0:
			txt = ("00" if v == 0 else str(v)) + " + ?"
		chips.append(("[d%d: %s]" if i == int(st.die) else "d%d: %s") % [int(logical[i].s), txt])
	pick_box.add_child(UI.wrap_lbl("   ".join(chips), 22, UI.TEXT))
	var q := "Che numero è uscito sul d%d?" % int(st.s)
	var opts: Array = []
	if st.part == "tens":
		q = "d100: dado delle decine"
		for v in range(0, 100, 10):
			opts.append(v)
	elif st.part == "units":
		q = "d100: dado delle unità"
		for v in range(0, 10):
			opts.append(v)
	else:
		if pending_info.adv != "none" and int(st.s) == 20:
			var how := "vantaggio" if pending_info.adv == "adv" else "svantaggio"
			if logical[int(st.die)].has("pair"):
				q = "Secondo d20 (%s)" % how
			else:
				q = "Primo d20 (%s)" % how
		for v in range(1, int(st.s) + 1):
			opts.append(v)
	pick_box.add_child(UI.lbl(q, 24, UI.GOLD))
	var g := GridContainer.new()
	g.columns = 5 if int(st.s) in [10, 20, 100] else (3 if int(st.s) == 6 else 4)
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	for v in opts:
		var label := "00" if st.part == "tens" and int(v) == 0 else str(v)
		var b: Button
		if int(st.s) == 20 and int(v) == 20:
			b = UI.color_btn(label, Color(0.5, 0.38, 0.08), _pick.bind(int(v)), 66)
		elif int(st.s) == 20 and int(v) == 1:
			b = UI.color_btn(label, Color(0.45, 0.12, 0.1), _pick.bind(int(v)), 66)
		else:
			b = UI.btn(label, _pick.bind(int(v)), 66)
		b.add_theme_font_size_override("font_size", 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(b)
	pick_box.add_child(g)


func _pick(v: int) -> void:
	pick_vals.append(v)
	if pick_vals.size() < pick_steps.size():
		_render_pick.call_deferred()
		return
	var vals := _pick_values()
	app.close_modal()
	var dice: Array = []
	for i in logical.size():
		dice.append({"s": int(logical[i].s), "v": clampi(int(vals[i]), 1, int(logical[i].s)), "drop": false})
	_complete(dice, [], true)


func _pick_back() -> void:
	if pick_vals.size() > 0:
		pick_vals.pop_back()
		_render_pick.call_deferred()


func _pick_cancel() -> void:
	app.close_modal()
	roll_btn.disabled = false
	result_lbl.text = "Tiro annullato"
