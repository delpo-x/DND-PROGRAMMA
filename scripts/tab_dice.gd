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
	result_lbl.text = "I dadi rotolano..."
	roll_btn.disabled = true
	tray.roll(_build_spec())


func preset_demo() -> void:
	counts = {20: 1, 8: 1, 6: 2}
	mod = 3
	_update_controls()
	roll_now()


func _on_finished(results: Array) -> void:
	roll_btn.disabled = false
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
	if pending_info.adv != "none" and dice.size() >= 2:
		var a: Dictionary = dice[0]
		var b: Dictionary = dice[dice.size() - 1]
		var keep_first: bool = a.v >= b.v if pending_info.adv == "adv" else a.v <= b.v
		if keep_first:
			b.drop = true
		else:
			a.drop = true
	var entry: Dictionary = app.state.master_roll(pending_info.who, pending_info.kind, dice, int(pending_info.mod),
		pending_info.adv, pending_info.reason, pending_info.secret, pending_info.formula)
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
