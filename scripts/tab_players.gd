extends VBoxContainer
## Connected devices and characters: sheets, damage/heal, roll requests.

const SheetEditor := preload("res://scripts/sheet_editor.gd")

var app
var list: VBoxContainer
var amounts: Dictionary = {}


func setup(a) -> void:
	app = a
	add_child(UI.flow([
		UI.color_btn("+ Nuovo personaggio", Color(0.18, 0.42, 0.25), _new_char, 56),
		UI.color_btn("Importa da PDF", Color(0.45, 0.3, 0.1), _import_pdf, 56),
		UI.color_btn("Richiedi un tiro ai giocatori", Color(0.2, 0.36, 0.6), func(): request_dialog([]), 56),
		UI.btn("Collega giocatori (QR)", func(): app.show_qr(), 56),
	]))
	list = UI.vbox([], 8)
	add_child(UI.scroll(list))


func refresh() -> void:
	UI.clear(list)
	var st: GameState = app.state
	# devices
	list.add_child(UI.title("Dispositivi connessi"))
	var clients: Array = app.net.client_list()
	if clients.is_empty():
		list.add_child(UI.wrap_lbl("Nessun telefono collegato. Premi \"Collega giocatori (QR)\" e fai inquadrare il codice.", 20, UI.DIM))
	for c in clients:
		var txt := ""
		if c.role == "screen":
			txt = "Schermo condiviso"
		elif c.char_id == "":
			txt = "Telefono: sta scegliendo il personaggio..."
		else:
			txt = "Telefono: %s" % st.find_entity(c.char_id).get("name", "?")
		var row := UI.hbox([UI.lbl("●", 20, UI.GREEN), UI.lbl(txt, 20), UI.spacer()])
		if c.role == "player" and c.char_id != "":
			var cid: String = c.char_id
			row.add_child(UI.btn("Libera personaggio", func(): app.net.release_char(cid), 48))
		list.add_child(UI.card(row, UI.PANEL, 8))
	# pending requests
	var reqs: Array = st.data.requests
	if reqs.size() > 0:
		list.add_child(UI.title("Richieste di tiro in attesa"))
		for r in reqs:
			var names: Array = []
			for cid in r.chars:
				if not r.done.has(cid):
					names.append(st.find_entity(cid).get("name", "?"))
			var txt := "%s  -  attesa da: %s" % [st.request_label(r), ", ".join(names)]
			if int(r.dc) >= 0:
				txt += "   (CD %d, nascosta)" % int(r.dc)
			var rid: String = r.id
			list.add_child(UI.card(UI.hbox([UI.wrap_lbl(txt, 20), UI.btn("Annulla", func(): st.cancel_request(rid), 48)]), UI.PANEL, 8))
	# characters
	list.add_child(UI.title("Personaggi"))
	var xp_amt := UI.spin(0, 99999, int(amounts.get("_xp", 100)), func(v): amounts["_xp"] = v, 130)
	list.add_child(UI.card(UI.flow([
		UI.btn("Riposo breve", func(): st.rest(false), 48),
		UI.btn("Riposo lungo", func(): app.confirm("Riposo lungo: i personaggi con almeno 1 PF tornano ai PF massimi, recuperano dadi vita e slot e perdono un livello di indebolimento. Chi è a 0 PF non ne beneficia. Procedere?", func(): st.rest(true)), 48),
		UI.lbl("PE da dividere", 18, UI.DIM), xp_amt,
		UI.color_btn("Assegna PE", Color(0.45, 0.33, 0.1), func(): st.award_xp(UI.spin_value(xp_amt), "assegnati dal master"), 48),
		UI.lbl("PE totali del gruppo: %d" % int(st.data.get("xp_total", 0)), 18, UI.DIM),
	]), UI.PANEL, 8))
	if st.characters().is_empty():
		list.add_child(UI.wrap_lbl("Nessun personaggio. Creane uno qui o lascia che i giocatori lo creino dal telefono.", 20, UI.DIM))
	for ch in st.characters():
		var id: String = ch.id
		var online: bool = st.online_chars.has(id)
		var top := UI.hbox([], 12)
		var img_key := Art.key_for(ch, "pc")
		if img_key != "":
			top.add_child(Art.avatar(img_key, 72))
		# online state in words too, not only by colour (WCAG 1.4.1)
		var dot := UI.lbl("● collegato" if online else "○ non collegato", 17, UI.GREEN.lightened(0.25) if online else UI.DIM)
		dot.tooltip_text = "Telefono collegato" if online else "Nessun telefono collegato"
		top.add_child(dot)
		top.add_child(UI.lbl(str(ch.name), 26, Color.WHITE))
		var sub := "%s %s liv. %d  -  %d PE" % [ch.race, ch.cls, int(ch.level), int(ch.get("xp", 0))]
		if str(ch.player) != "":
			sub += "  -  %s" % ch.player
		top.add_child(UI.lbl(sub.strip_edges(), 18, UI.DIM))
		top.add_child(UI.spacer())
		var hp := "PF %d/%d" % [int(ch.hp), int(ch.hp_max)]
		if int(ch.hp_temp) > 0:
			hp += " (+%d temp.)" % int(ch.hp_temp)
		top.add_child(UI.lbl(hp, 24, UI.RED if int(ch.hp) <= 0 else UI.TEXT))
		top.add_child(UI.lbl("CA %d" % int(ch.ac), 24))
		var mods: Array = []
		for a in Rules.ABILITIES:
			mods.append("%s %d (%s)" % [a, int(ch.ab[a]), Rules.fmt_mod(Rules.mod(ch.ab[a]))])
		var info := UI.wrap_lbl("   ".join(mods) + "    Iniz. %s   Perc. passiva %d" % [Rules.fmt_mod(Rules.init_mod(ch)), 10 + Rules.skill_mod(ch, "percezione")], 17, UI.DIM)
		var amt := UI.spin(1, 999, int(amounts.get(id, 5)), func(v): amounts[id] = v, 100)
		UI.named(amt, "Punti ferita da togliere o curare a %s" % str(ch.name))
		var actions := UI.flow([
			UI.btn("Scheda", edit_dialog.bind(id), 48),
			amt,
			CombatUI.damage_btn(app, id, func(): return UI.spin_value(amt), 48),
			UI.color_btn("Cura", Color(0.18, 0.48, 0.25), func(): st.change_hp(id, UI.spin_value(amt)), 48),
			UI.btn("PF temp.", func(): st.give_temp_hp(id, UI.spin_value(amt)), 48),
			UI.btn("Difese", func(): CombatUI.defenses_dialog(app, id), 48),
			UI.btn("Slot", _slots_dialog.bind(id), 48),
			UI.btn("Risorse", _res_dialog.bind(id), 48),
			UI.color_btn("Ispirazione ✦" if bool(ch.get("inspiration", false)) else "Ispirazione",
				Color(0.55, 0.42, 0.1) if bool(ch.get("inspiration", false)) else Color(0.2, 0.2, 0.24),
				func(): st.set_inspiration(id, not bool(ch.get("inspiration", false))), 48),
			UI.btn("Dado vita (%d/%d)" % [int(ch.get("level", 1)) - int(ch.get("hd_used", 0)), int(ch.get("level", 1))],
				func():
					var t := st.spend_hit_die(id)
					app.toast(t if t != "" else "Nessun dado vita da spendere (o PF già al massimo)"), 48),
			UI.btn("Incantesimi", _spells_dialog.bind(id), 48),
			_cond_menu(ch),
			UI.btn("Richiedi tiro", func(): request_dialog([id]), 48),
			UI.btn("Cambia ritratto" if img_key != "" else "Ritratto…", _pick_portrait.bind(id), 48),
			UI.btn("Libera", func(): app.net.release_char(id), 48),
			UI.color_btn("Elimina", Color(0.35, 0.12, 0.1), func(): app.confirm("Eliminare %s?" % ch.name, func(): st.delete_character(id)), 48),
		])
		var rows: Array = [top, info]
		if str(ch.get("conditions", "")).strip_edges() != "":
			rows.append(UI.wrap_lbl("Condizioni: " + str(ch.conditions), 18, Color(0.85, 0.6, 0.95)))
		var sl := _slots_row(ch)
		if sl != null:
			rows.append(sl)
		var rs := _res_rows(ch)
		if rs != null:
			rows.append(rs)
		var spl := _spells_text(ch)
		if spl != "":
			rows.append(UI.wrap_lbl(spl, 17, Color(0.7, 0.78, 0.95)))
		if Rules.defenses_text(ch) != "":
			rows.append(UI.wrap_lbl(Rules.defenses_text(ch), 18, Color(0.95, 0.75, 0.45)))
		if int(ch.hp) <= 0:
			rows.append(_death_row(ch))
		if str(ch.get("portrait", "")) != "":
			actions.add_child(UI.btn("Togli ritratto", func(): st.clear_portrait(id), 48))
		rows.append(actions)
		list.add_child(UI.card(UI.vbox(rows, 6), UI.PANEL, 12))


## Picture for a character from a file on this computer (JPG, PNG, WebP).
func _pick_portrait(id: String) -> void:
	app.pick_image("Scegli il ritratto di %s" % app.state.find_entity(id).get("name", ""), func(img: Image, _fname: String):
		app.toast("Ritratto salvato" if app.state.set_portrait(id, img) else "Ritratto non salvato"))


func _new_char() -> void:
	var ch: Dictionary = app.state.add_character("Nuovo eroe")
	edit_dialog(ch.id)


func _import_pdf() -> void:
	app.pick_pdf("Scegli la scheda del personaggio (PDF)", _import_bytes)


func _import_bytes(bytes: PackedByteArray, fname: String) -> void:
	app.toast("Lettura di %s..." % fname)
	await get_tree().process_frame
	await get_tree().process_frame
	var doc: Dictionary = app.read_pdf(bytes)
	if doc.is_empty():
		return
	var res := SheetImport.parse(doc)
	var ch: Dictionary = app.state.import_character(res.char)
	var found: Array = res.found
	app.toast("Importato %s" % ch.name)
	var hint := "Dati letti da %s: %s.
Controlla la scheda: quello che non è stato trovato resta al valore base." % [fname, ", ".join(found) if not found.is_empty() else "nessuno"]
	edit_dialog(ch.id, hint)


func edit_dialog(id: String, hint := "") -> void:
	var ch: Dictionary = app.state.find_entity(id)
	if ch.is_empty():
		return
	var ed = SheetEditor.new()
	ed.build(ch)
	if hint != "":
		var l := UI.wrap_lbl(hint, 18, UI.GOLD)
		ed.add_child(l)
		ed.move_child(l, 0)
	app.show_modal("Scheda: %s" % ch.name, ed, [
		["Annulla", app.close_modal],
		["Salva", func(): _save_sheet(id, ed), Color(0.18, 0.48, 0.25)],
	], 1100)


func _save_sheet(id: String, ed) -> void:
	# only the fields changed in the form: PF or conditions changed meanwhile
	# (by a phone or a damage button) are not overwritten
	app.state.update_character(id, ed.changed_values())
	app.close_modal()


## Ask one or more players for a roll; the DC stays hidden on their phones.
func request_dialog(preselect: Array) -> void:
	var st: GameState = app.state
	var box := UI.vbox([], 10)
	var types := [["skill", "Prova di abilità"], ["save", "Tiro salvezza"], ["init", "Iniziativa"], ["free", "Tiro libero (1d20)"]]
	var type_names: Array = []
	for t in types:
		type_names.append(t[1])
	var param := OptionButton.new()
	param.custom_minimum_size = Vector2(0, 48)
	var fill_params := func(i: int):
		param.clear()
		match types[i][0]:
			"skill":
				for s in Rules.SKILLS:
					param.add_item(s[1])
			"save":
				for a in Rules.ABILITIES:
					param.add_item(Rules.ABILITY_NAMES[a])
			_:
				param.add_item("-")
	var type_opt := UI.option(type_names, 0, fill_params)
	fill_params.call(0)
	box.add_child(UI.hbox([UI.lbl("Tipo", 20, UI.DIM), UI.expand(type_opt), UI.expand(param)]))
	var dc := UI.spin(0, 40, 0, Callable(), 120)
	box.add_child(UI.hbox([UI.lbl("CD (0 = nessuna; i giocatori non la vedono)", 20, UI.DIM), dc]))
	var reason := UI.edit("", "Motivo mostrato ai giocatori (facoltativo)")
	box.add_child(reason)
	box.add_child(UI.lbl("Destinatari", 22, UI.GOLD))
	var checks := {}
	for ch in st.characters():
		var on := preselect.is_empty() or preselect.has(ch.id)
		var label := str(ch.name) + ("" if st.online_chars.has(ch.id) else "  (non connesso)")
		var cb := UI.check(label, on)
		checks[ch.id] = cb
		box.add_child(cb)
	app.show_modal("Richiedi un tiro", box, [
		["Annulla", app.close_modal],
		["Invia richiesta", func(): _send_request(types, type_opt, param, dc, reason, checks), Color(0.2, 0.36, 0.6)],
	])


func _send_request(types: Array, type_opt: OptionButton, param: OptionButton, dc: SpinBox, reason: LineEdit, checks: Dictionary) -> void:
	var ids: Array = []
	for id in checks:
		if checks[id].button_pressed:
			ids.append(id)
	if ids.is_empty():
		app.toast("Scegli almeno un giocatore")
		return
	var t: String = types[type_opt.selected][0]
	var p := ""
	match t:
		"skill":
			p = Rules.SKILLS[param.selected][0]
		"save":
			p = Rules.ABILITIES[param.selected]
		"free":
			p = "1d20"
	dc.apply()
	var dcv := int(dc.value)
	app.state.make_request(ids, t, p, dcv if dcv > 0 else -1, reason.text)
	app.close_modal()
	app.toast("Richiesta inviata: %s" % Rules.check_label(t, p))


## Menu of the Player's Handbook conditions, ticked when active.
func _cond_menu(ch: Dictionary) -> MenuButton:
	var id: String = ch.id
	var mb := MenuButton.new()
	mb.text = "Condizioni"
	mb.custom_minimum_size = Vector2(0, 48)
	mb.flat = false
	var pm := mb.get_popup()
	var active: Array = []
	for p in str(ch.get("conditions", "")).split(","):
		active.append(p.strip_edges().to_lower())
	for i in Rules.CONDITIONS.size():
		var cn: String = Rules.CONDITIONS[i][0]
		pm.add_check_item(cn, i)
		pm.set_item_checked(i, active.has(cn.to_lower()))
		pm.set_item_tooltip(i, Rules.CONDITIONS[i][1])
	pm.hide_on_checkable_item_selection = false
	pm.id_pressed.connect(func(i: int): app.state.toggle_condition(id, Rules.CONDITIONS[i][0]))
	return mb


## Death saving throws for a character at 0 PF.
func _death_row(ch: Dictionary) -> Control:
	var id: String = ch.id
	var ok := int(ch.get("death_ok", 0))
	var ko := int(ch.get("death_ko", 0))
	var st: GameState = app.state
	var marks := "Successi %s   Fallimenti %s" % ["●".repeat(ok) + "○".repeat(3 - ok), "●".repeat(mini(ko, 3)) + "○".repeat(3 - mini(ko, 3))]
	var state_txt := "Stabile" if ok >= 3 else ("Morto (per riportarlo in vita: Azzera, poi Cura)" if ko >= 3 else "A terra: tiri salvezza contro la morte")
	var items: Array = [UI.lbl(state_txt, 20, UI.RED), UI.lbl(marks, 20, UI.TEXT)]
	if ok < 3 and ko < 3:
		var roll_ts := func():
			var r := st.rng.randi_range(1, 20)
			app.toast("%s, TS contro la morte: %d. %s" % [ch.name, r, st.death_save(id, r)])
		items.append(UI.color_btn("Tira TS (d20)", Color(0.45, 0.12, 0.12), roll_ts, 44))
		items.append(UI.btn("+ Successo", func(): st.set_death(id, ok + 1, ko), 44))
		items.append(UI.btn("+ Fallimento", func(): st.set_death(id, ok, ko + 1), 44))
	items.append(UI.btn("Azzera", func(): st.set_death(id, 0, 0), 44))
	return UI.flow(items)


## Spell slots as pips: gold = available, dark = spent. Clicking an
## available pip spends a slot, clicking a spent one gives it back.
func _slots_row(ch: Dictionary) -> Control:
	var mx: Array = ch.get("slots_max", [])
	var used: Array = ch.get("slots_used", [])
	var any := false
	for v in mx:
		any = any or int(v) > 0
	if not any:
		return null
	var id: String = ch.id
	var row := UI.hbox([UI.lbl("Slot incantesimo", 18, UI.DIM)], 6)
	for i in 9:
		var m := int(mx[i])
		if m <= 0:
			continue
		var u := int(used[i])
		row.add_child(UI.lbl("  %d°" % (i + 1), 18, UI.GOLD))
		for k in m:
			var free := k < m - u
			var b := Button.new()
			b.text = "◆" if free else "◇"
			b.flat = true
			b.add_theme_font_size_override("font_size", 22)
			b.add_theme_color_override("font_color", UI.GOLD if free else UI.DIM)
			b.tooltip_text = ("Usa uno slot di %d° livello" if free else "Recupera uno slot di %d° livello") % (i + 1)
			var lvl := i + 1
			b.pressed.connect(func(): app.state.use_slot(id, lvl, 1 if free else -1))
			row.add_child(b)
	return row


## Class resources (Rage, Channel Divinity...) and the master's own ones:
## pips up to 8 uses (gold = available), otherwise a counter with buttons.
func _res_rows(ch: Dictionary) -> Control:
	var list: Array = Rules.resources(ch)
	if list.is_empty():
		return null
	var id: String = ch.id
	var st: GameState = app.state
	var use := func(key: String, d: int):
		var t := st.use_resource(id, key, d)
		if t != "":
			app.toast(t)
	var box := UI.vbox([], 2)
	for r in list:
		var mx := int(r.max)
		var left := mx - int(r.used)
		var row := UI.hbox([UI.lbl(str(r.name), 18, UI.GOLD)], 6)
		var tip := "Si recupera: %s" % Rules.RESET_NAMES.get(r.reset, "")
		if str(r.note) != "":
			tip = str(r.note) + "\n" + tip
		if mx <= 8:
			for k in mx:
				var free := k < left
				var b := Button.new()
				b.text = "◆" if free else "◇"
				b.flat = true
				b.add_theme_font_size_override("font_size", 22)
				b.add_theme_color_override("font_color", UI.GOLD if free else UI.DIM)
				b.tooltip_text = ("Usa: %s" if free else "Recupera: %s") % r.name
				UI.named(b, b.tooltip_text)
				b.pressed.connect(use.bind(str(r.key), 1 if free else -1))
				row.add_child(b)
		else:
			row.add_child(UI.lbl("%d/%d" % [left, mx], 18, UI.TEXT))
			for d in [1, 5, -1]:
				if d == 5 and mx < 10:
					continue
				var b := UI.btn("Usa %d" % d if d > 0 else "Recupera 1", use.bind(str(r.key), d), 40)
				UI.named(b, "%s: %s" % [r.name, b.text])
				row.add_child(b)
		var rl := UI.lbl("  (%s)" % Rules.RESET_NAMES.get(r.reset, ""), 16, UI.DIM)
		rl.tooltip_text = tip
		rl.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(rl)
		row.tooltip_text = tip
		box.add_child(row)
	return box


## Resources added by hand (magic items, feats, multiclass): name, uses and
## how they come back. The class ones are computed from class and level.
func _res_dialog(id: String) -> void:
	var ch: Dictionary = app.state.find_entity(id)
	if ch.is_empty():
		return
	var resets: Array = Rules.RESET_NAMES.keys()
	var reset_labels: Array = resets.map(func(k): return "Torna con: " + str(Rules.RESET_NAMES[k]))
	var rows := UI.vbox([], 6)
	var add_row := func(r: Dictionary):
		var n := UI.edit(str(r.get("name", "")), "Nome (es. Bacchetta dei dardi)", Callable(), 300)
		var m := UI.spin(1, 999, int(r.get("max", 1)), Callable(), 100)
		UI.named(m, "Usi massimi")
		var o := UI.option(reset_labels, maxi(0, resets.find(str(r.get("reset", "long")))), Callable(), 330)
		var row := UI.hbox([n, m, o], 8)
		row.add_child(UI.btn("X", func(): row.queue_free(), 44))
		row.set_meta("f", [n, m, o])
		rows.add_child(row)
	for r in ch.get("res_custom", []):
		add_row.call(r)
	var auto: Array = Rules.class_resources(str(ch.cls), int(ch.level), ch.get("ab", {}))
	var info := "Dalla classe (%s liv. %d): %s." % [ch.cls, int(ch.level),
		", ".join(auto.map(func(r): return "%s %d" % [r.name, int(r.max)])) if not auto.is_empty() else "nessuna risorsa"]
	info += " Qui aggiungi le altre: oggetti magici, talenti, multiclasse."
	var box := UI.vbox([UI.wrap_lbl(info, 17, UI.DIM), rows,
		UI.btn("+ Aggiungi risorsa", func(): add_row.call({"name": "", "max": 1, "reset": "long"}), 48)], 10)
	app.show_modal("Risorse di %s" % ch.name, box, [
		["Annulla", app.close_modal],
		["Salva", func():
			var out: Array = []
			for r in rows.get_children():
				if r.is_queued_for_deletion() or not r.has_meta("f"):
					continue
				var f: Array = r.get_meta("f")
				f[1].apply()
				out.append({"name": f[0].text, "max": int(f[1].value), "reset": resets[maxi(0, f[2].selected)]})
			app.state.set_custom_resources(id, out)
			app.close_modal(), Color(0.18, 0.48, 0.25)],
	], 900)


## Maximum slots per level; "automatic" follows class and level (PHB table).
func _slots_dialog(id: String) -> void:
	var ch: Dictionary = app.state.find_entity(id)
	if ch.is_empty():
		return
	Rules.sync_slots(ch)
	var auto := UI.check("Calcola da classe e livello (%s liv. %d)" % [ch.cls, int(ch.level)], bool(ch.slots_auto))
	var spins: Array = []
	var g := GridContainer.new()
	g.columns = 6
	for i in 9:
		var sp := UI.spin(0, 9, int(ch.slots_max[i]), Callable(), 90)
		spins.append(sp)
		g.add_child(UI.lbl("%d° livello" % (i + 1), 18, UI.DIM))
		g.add_child(sp)
	var hint := UI.wrap_lbl("Con il calcolo automatico gli slot seguono la tabella del Manuale del Giocatore 2024 (incantatori completi, paladino e ranger dal 1° livello, warlock con Magia del Patto). Toglilo per scrivere i valori a mano, per esempio per un multiclasse. Il riposo lungo ripristina tutti gli slot; quello breve solo gli slot del warlock.", 17, UI.DIM)
	app.show_modal("Slot incantesimo di %s" % ch.name, UI.vbox([auto, g, hint], 10), [
		["Annulla", app.close_modal],
		["Salva", func():
			var mx: Array = []
			for sp in spins:
				sp.apply()
				mx.append(int(sp.value))
			app.state.set_slots_max(id, mx, auto.button_pressed)
			app.close_modal(), Color(0.18, 0.48, 0.25)],
	])


## One-line summary: save DC, attack bonus and spells grouped by level.
func _spells_text(ch: Dictionary) -> String:
	var spells: Array = ch.get("spells", [])
	var nums: Array = Rules.spell_numbers(ch)
	if spells.is_empty():
		return ""
	var by := {}
	for sp in spells:
		var k := int(sp.lvl)
		if not by.has(k):
			by[k] = []
		by[k].append(str(sp.name) + ("" if bool(sp.get("prep", true)) else " (non prep.)"))
	var parts: Array = []
	for k in range(10):
		if by.has(k):
			parts.append(("Trucchetti" if k == 0 else "%d°" % k) + ": " + ", ".join(by[k]))
	var head := "Incantesimi"
	if not nums.is_empty():
		head += " (CD %d, attacco %s)" % [int(nums[0]), Rules.fmt_mod(int(nums[1]))]
	return head + " - " + ";  ".join(parts)


## Editable spell list: name, level (0 = cantrip), prepared.
func _spells_dialog(id: String) -> void:
	var ch: Dictionary = app.state.find_entity(id)
	if ch.is_empty():
		return
	var rows := UI.vbox([], 6)
	var levels: Array = ["Trucchetto", "1°", "2°", "3°", "4°", "5°", "6°", "7°", "8°", "9°"]
	var add_row := func(sp: Dictionary):
		var n := UI.edit(str(sp.get("name", "")), "Nome dell'incantesimo", Callable(), 320)
		var l := UI.option(levels, int(sp.get("lvl", 1)), Callable(), 150)
		var p := UI.check("Preparato", bool(sp.get("prep", true)))
		var r := UI.hbox([n, l, p], 8)
		r.add_child(UI.btn("X", func(): r.queue_free(), 44))
		r.set_meta("f", [n, l, p])
		rows.add_child(r)
	for sp in ch.get("spells", []):
		add_row.call(sp)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var nums: Array = Rules.spell_numbers(ch)
	var info := "Scrivi solo i nomi: la descrizione è sul Manuale del Giocatore."
	if not nums.is_empty():
		info = "Caratteristica da incantatore %s: CD del tiro salvezza %d, attacco con incantesimo %s. " % [nums[2], int(nums[0]), Rules.fmt_mod(int(nums[1]))] + info
	var box := UI.vbox([UI.wrap_lbl(info, 17, UI.DIM), scroll,
		UI.btn("+ Aggiungi incantesimo", func(): add_row.call({"name": "", "lvl": 1, "prep": true}), 48)], 10)
	app.show_modal("Incantesimi di %s" % ch.name, box, [
		["Annulla", app.close_modal],
		["Salva", func():
			var out: Array = []
			for r in rows.get_children():
				if r.is_queued_for_deletion() or not r.has_meta("f"):
					continue
				var f: Array = r.get_meta("f")
				out.append({"name": f[0].text, "lvl": f[1].selected, "prep": f[2].button_pressed})
			app.state.update_character(id, {"spells": out})
			app.close_modal(), Color(0.18, 0.48, 0.25)],
	], 900)
