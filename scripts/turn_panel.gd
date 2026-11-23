extends VBoxContainer
## Turn panel (Initiative tab): what the current combatant does, on whom, and
## the roll with every effect applied (see Actions). It shows the actions of
## the character or monster whose turn it is; every number can be changed
## before rolling.

var app
var p_actor := ""
var p_name := ""  # name of the chosen action
var p_edit: Dictionary = {}  # chosen action, with the master's changes
var p_targets: Dictionary = {}  # ref -> true
var p_adv := "auto"
var p_slot := 0
var p_result: Array = []
var p_result_title := ""
var result_box: Control = null  # shown after a roll; scrolled into view

const MODES := ["attack", "save", "auto", "heal", "effect"]
const ADV := ["auto", "adv", "none", "dis"]


func setup(a) -> void:
	app = a
	add_theme_constant_override("separation", 8)


## Rebuilt on every change (the HP shown on the targets stay fresh), except
## while the master is typing in one of its fields.
func refresh(force := false) -> void:
	var fo := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if not force and fo != null and is_ancestor_of(fo) and fo is LineEdit:
		return
	UI.clear(self)
	var st: GameState = app.state
	var ini: Dictionary = st.ini()
	var cur: Dictionary = st.current_combatant()
	if not ini.active or cur.is_empty():
		return
	var actor_id := str(cur.ref)
	var actor := st.find_entity(actor_id)
	if actor.is_empty():
		return
	var acts := Actions.list_for(st, actor_id)
	var still := false
	for a in acts:
		if a.name == p_name:
			still = true
	if actor_id != p_actor or not still:
		p_actor = actor_id
		_choose(acts[0])
	var pc := st.is_pc(actor_id)
	var box := UI.vbox([], 10)
	box.add_child(_head(actor, pc))
	box.add_child(UI.lbl("Cosa fa", 18, UI.DIM))
	var choices := UI.flow([], 6)
	for a in acts:
		var col := UI.PANEL2
		if a.name == p_name:
			col = Color(0.66, 0.4, 0.1)
		elif a.group == "Incantesimi":
			col = Color(0.2, 0.28, 0.45)
		elif a.group == "Speciali":
			col = Color(0.42, 0.16, 0.14)
		var b := UI.color_btn(_action_label(a), col, _pick.bind(a), 48)
		b.tooltip_text = str(a.get("note", ""))
		choices.add_child(b)
	box.add_child(choices)
	box.add_child(_details(actor, pc))
	box.add_child(_targets_box(actor_id))
	var go := UI.color_btn("ESEGUI: TIRA I DADI", Color(0.62, 0.18, 0.12), _execute, 64)
	go.add_theme_font_size_override("font_size", 24)
	go.custom_minimum_size.x = 320
	box.add_child(UI.hbox([go, UI.spacer(), UI.color_btn("TURNO SUCCESSIVO >>", Color(0.66, 0.4, 0.1), st.next_turn, 56)], 12))
	result_box = null
	if not p_result.is_empty():
		result_box = _result_box()
		box.add_child(result_box)
	var card := UI.card(box, Color(0.2, 0.14, 0.09), 14)
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
	sb.border_color = UI.GOLD
	sb.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)


func _head(actor: Dictionary, pc: bool) -> Control:
	var head := UI.hbox([], 12)
	head.add_child(Art.avatar(Art.key_for(actor, "pc" if pc else "monster"), 64))
	var who := UI.lbl("Turno di %s" % actor.name, 28, UI.GOLD)
	UI.engrave(who)
	head.add_child(who)
	head.add_child(UI.lbl("PF %d/%d   CA %d" % [int(actor.hp), int(actor.hp_max), int(actor.ac)], 20))
	if str(actor.get("conditions", "")) != "":
		head.add_child(UI.lbl(str(actor.conditions), 18, Color(0.85, 0.6, 0.95)))
	head.add_child(UI.spacer())
	if str(actor.get("concentration", "")) != "":
		head.add_child(UI.lbl("Concentrato su %s" % actor.concentration, 18, Color(0.6, 0.8, 1.0)))
		head.add_child(UI.btn("Fine concentrazione", _end_concentration.bind(str(actor.id)), 44))
	return head


func _end_concentration(id: String) -> void:
	var e: Dictionary = app.state.find_entity(id)
	if not e.is_empty():
		e.concentration = ""
		app.state.touch()


func _action_label(a: Dictionary) -> String:
	var t := str(a.name)
	match str(a.mode):
		"attack":
			t += "  %+d" % int(a.bonus)
			if int(a.times) > 1:
				t += " x%d" % int(a.times)
		"save":
			t += "  TS %s CD %d" % [str(a.save).capitalize(), int(a.dc)]
		"heal":
			t += "  cura"
	if str(a.dmg) != "" and str(a.mode) != "effect":
		t += "  " + str(a.dmg)
	if int(a.lvl) == 0:
		t += "  (trucchetto)"
	elif int(a.lvl) > 0:
		t += "  (%d°)" % int(a.lvl)
	if bool(a.conc):
		t += "  [C]"
	return t


func _pick(a: Dictionary) -> void:
	_choose(a)
	refresh(true)


## Picks an action and sensible targets: the first enemy still standing,
## the most wounded ally for a healing, oneself for a buff; nobody for an
## area (the master ticks who is caught in it).
func _choose(a: Dictionary) -> void:
	var st: GameState = app.state
	p_name = str(a.name)
	p_edit = a.duplicate(true)
	p_adv = "auto"
	p_slot = int(a.lvl)
	var pc := st.is_pc(p_actor)
	if p_slot >= 1 and pc:
		var ch := st.find_entity(p_actor)
		Rules.sync_slots(ch)
		for l in range(p_slot, 10):
			if int(ch.slots_used[l - 1]) < int(ch.slots_max[l - 1]):
				p_slot = l
				break
	p_targets = {}
	var mode := str(a.mode)
	var friendly := mode == "heal" or (mode == "effect" and str(a.cond) in ["", "Invisibile"])
	if mode == "effect" and str(a.cond) == "" and str(a.name).to_lower().contains("anatema"):
		friendly = false
	if int(a.targets) == 0 and not friendly:
		return
	if friendly and mode != "heal":
		p_targets[p_actor] = true
		return
	var best := ""
	var best_ratio := 2.0
	for c in st.ini().combatants:
		var e := st.find_entity(c.ref)
		if e.is_empty():
			continue
		var ally: bool = st.is_pc(c.ref) == pc
		if mode == "heal":
			var ratio := float(e.hp) / maxf(1.0, float(e.hp_max))
			if ally and ratio < best_ratio:
				best = c.ref
				best_ratio = ratio
		elif not ally and int(e.hp) > 0 and best == "":
			best = c.ref
	if best != "":
		p_targets[best] = true


func _set_mode(i: int) -> void:
	p_edit.mode = MODES[i]
	refresh(true)


func _details(actor: Dictionary, pc: bool) -> Control:
	var a := p_edit
	var f := UI.flow([], 8)
	f.add_child(UI.option(["Tiro per colpire", "Tiro salvezza", "Colpisce sempre", "Cura", "Solo effetto"], MODES.find(str(a.mode)), _set_mode, 190))
	match str(a.mode):
		"attack":
			f.add_child(UI.lbl("Bonus", 18, UI.DIM))
			f.add_child(UI.spin(-10, 30, int(a.bonus), func(v): p_edit.bonus = v, 90))
			f.add_child(UI.lbl("Attacchi", 18, UI.DIM))
			f.add_child(UI.spin(1, 10, int(a.times), func(v): p_edit.times = v, 80))
			f.add_child(UI.option(["Vantaggio: automatico", "Vantaggio", "Normale", "Svantaggio"], ADV.find(p_adv), func(i): p_adv = ADV[i], 220))
		"save":
			var abl: Array = Rules.ABILITIES
			f.add_child(UI.lbl("TS di", 18, UI.DIM))
			f.add_child(UI.option(abl.map(func(x): return Actions.ABILITY_NAMES.get(x, x)), maxi(0, abl.find(str(a.save))), func(i): p_edit.save = abl[i], 170))
			f.add_child(UI.lbl("CD", 18, UI.DIM))
			f.add_child(UI.spin(1, 30, int(a.dc), func(v): p_edit.dc = v, 80))
			f.add_child(UI.check("Metà danni se lo supera", bool(a.half), func(on): p_edit.half = on))
		"auto":
			f.add_child(UI.lbl("Volte", 18, UI.DIM))
			f.add_child(UI.spin(1, 10, int(a.times), func(v): p_edit.times = v, 80))
	if str(a.mode) != "effect":
		f.add_child(UI.lbl("Cura" if str(a.mode) == "heal" else "Danni", 18, UI.DIM))
		f.add_child(UI.edit(str(a.dmg), "es. 2d6+3", func(t): p_edit.dmg = t, 120))
		if str(a.mode) != "heal":
			f.add_child(_type_opt(str(a.type), "type"))
			f.add_child(UI.lbl("+", 18, UI.DIM))
			f.add_child(UI.edit(str(a.dmg2), "altri danni", func(t): p_edit.dmg2 = t, 110))
			f.add_child(_type_opt(str(a.type2), "type2"))
	if str(a.mode) != "heal":
		var conds: Array = ["Nessuna condizione"]
		for c in Rules.CONDITIONS:
			conds.append(c[0])
		if str(a.cond) != "" and not conds.has(str(a.cond)):
			conds.append(str(a.cond))
		var lab: String = {"attack": "Se colpisce:", "save": "Se fallisce:", "auto": "Applica:", "effect": "Applica:"}.get(str(a.mode), "")
		f.add_child(UI.lbl(lab, 18, UI.DIM))
		f.add_child(UI.option(conds, maxi(0, conds.find(str(a.cond))), func(i): p_edit.cond = "" if i == 0 else conds[i], 210))
	if int(a.lvl) >= 1 and pc:
		Rules.sync_slots(actor)
		var levels: Array = []
		var items: Array = []
		for l in range(int(a.lvl), 10):
			if int(actor.slots_max[l - 1]) > 0:
				levels.append(l)
				items.append("Slot %d° (%d liberi)" % [l, int(actor.slots_max[l - 1]) - int(actor.slots_used[l - 1])])
		if levels.is_empty():
			f.add_child(UI.lbl("Nessuno slot di questo livello", 18, UI.RED))
		else:
			if not levels.has(p_slot):
				p_slot = levels[0]
			f.add_child(UI.option(items, levels.find(p_slot), func(i): p_slot = levels[i], 210))
	var col := UI.vbox([f], 4)
	var info: Array = []
	var hs: Dictionary = a.get("hit_save", {})
	if not hs.is_empty():
		info.append("Se colpisce: TS %s CD %d%s" % [Actions.ABILITY_NAMES.get(str(hs.save), hs.save), int(hs.dc), (" o " + str(hs.cond).to_lower()) if str(hs.cond) != "" else ""])
	if bool(a.get("conc", false)):
		info.append("Richiede concentrazione")
	if int(a.get("lvl", -1)) >= 1 and pc and str(a.get("upcast", "")) != "":
		info.append("+%s per ogni livello di slot in più" % a.upcast)
	if bool(a.get("up_times", false)):
		info.append("+1 dardo o raggio per ogni livello di slot in più")
	if str(a.get("note", "")) != "":
		info.append(str(a.note))
	if not info.is_empty():
		col.add_child(UI.wrap_lbl("   ·   ".join(info), 17, Color(0.7, 0.78, 0.95)))
	return col


func _type_opt(cur: String, key: String) -> OptionButton:
	var items: Array = ["Tipo..."]
	items.append_array(Rules.DAMAGE_TYPES)
	return UI.option(items, maxi(0, items.find(cur)), func(i): p_edit[key] = "" if i == 0 else items[i], 150)


func _toggle_target(on: bool, ref: String) -> void:
	if on:
		p_targets[ref] = true
	else:
		p_targets.erase(ref)
	refresh(true)


func _targets_box(actor_id: String) -> Control:
	var st: GameState = app.state
	var pc := st.is_pc(actor_id)
	var hint := "Su chi"
	var n := int(p_edit.get("targets", 1))
	if n == 0:
		hint += " (area: spunta tutti quelli colpiti)"
	elif n > 1:
		hint += " (fino a %d)" % n
	if int(p_edit.get("times", 1)) > 1 and str(p_edit.mode) in ["attack", "auto"]:
		hint += " - gli attacchi (o i dardi) vanno ai bersagli spuntati, a turno"
	var f := UI.flow([], 6)
	var enemies: Array = []
	var allies: Array = []
	for c in st.ini().combatants:
		if st.find_entity(c.ref).is_empty():
			continue
		if st.is_pc(c.ref) == pc:
			allies.append(c.ref)
		else:
			enemies.append(c.ref)
	for ref in enemies + allies:
		var e := st.find_entity(ref)
		var txt := "%s  CA %d  PF %d/%d" % [e.name, int(e.ac), int(e.hp), int(e.hp_max)]
		if ref == actor_id:
			txt += "  (sé)"
		var cb := UI.check(txt, p_targets.has(ref), _toggle_target.bind(ref))
		if int(e.hp) <= 0:
			cb.modulate = Color(1, 1, 1, 0.5)
		elif enemies.has(ref):
			cb.add_theme_color_override("font_color", Color(1.0, 0.72, 0.6))
		f.add_child(cb)
	var col := UI.vbox([UI.lbl(hint, 18, UI.DIM), f], 4)
	if str(p_edit.mode) == "attack" and p_targets.size() == 1 and p_adv == "auto":
		var t := st.find_entity(str(p_targets.keys()[0]))
		var aa := Actions.auto_adv(st.find_entity(actor_id), t, bool(p_edit.get("ranged", false)))
		if int(aa[0]) != 0:
			col.add_child(UI.lbl("Tirerà con %s (%s)" % ["vantaggio" if int(aa[0]) > 0 else "svantaggio", ", ".join(aa[1])], 17, UI.GOLD))
	return col


func _result_box() -> Control:
	var res := UI.vbox([UI.lbl(p_result_title, 20, UI.GOLD)], 2)
	for l in p_result:
		var s := str(l)
		var col := UI.TEXT
		if s.contains("CRITICO") or s.contains("SCONFITTO") or s.contains("A TERRA"):
			col = Color(1.0, 0.78, 0.3)
		elif s.contains("mancato") or s.contains("perde la concentrazione"):
			col = UI.DIM
		elif s.begins_with("Nota"):
			col = Color(0.7, 0.78, 0.95)
		res.add_child(UI.wrap_lbl(s, 18, col))
	return UI.card(res, Color(0.1, 0.07, 0.05), 10)


## Outcome of an action a player ran from their phone.
func show_result(_actor_id: String, title: String, lines: Array) -> void:
	p_result = lines
	p_result_title = title + "  (dal telefono)"
	refresh(true)


func _execute() -> void:
	var st: GameState = app.state
	var targets: Array = []
	# initiative order, so darts and rays follow what the master sees
	for c in st.ini().combatants:
		if p_targets.has(c.ref):
			targets.append(c.ref)
	var actor_name := str(st.find_entity(p_actor).get("name", "?"))
	var res := Actions.resolve(st, p_actor, p_edit, targets, {"adv": p_adv, "slot": p_slot})
	if not res.ok:
		app.toast(str(res.error))
		return
	p_result = res.lines
	p_result_title = "Round %d - %s: %s" % [int(st.ini().round), actor_name, p_name]
	refresh(true)
	# bring the outcome into view (the panel sits in the tab's scroll area)
	await get_tree().process_frame
	await get_tree().process_frame
	var sc := get_parent()
	while sc != null and not sc is ScrollContainer:
		sc = sc.get_parent()
	if sc != null and is_instance_valid(result_box):
		(sc as ScrollContainer).ensure_control_visible(result_box)
