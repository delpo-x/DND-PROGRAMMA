extends VBoxContainer
## Initiative: full ranking with scores, current turn, round counter,
## next turn, add/remove combatants, damage and healing.

var app
var head_lbl: Label
var diff_lbl: Label  # encounter difficulty of the fight
var list: VBoxContainer
var panel  # turn panel: what the current combatant does (turn_panel.gd)
var amounts: Dictionary = {}
var last_turn := ""  # "round:combatant id" shown last time, to animate changes
var last_hp: Dictionary = {}  # ref -> hp shown last time


func setup(a) -> void:
	app = a
	head_lbl = UI.lbl("", 30, UI.GOLD)
	head_lbl.clip_text = true
	head_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_lbl.custom_minimum_size = Vector2(200, 0)
	UI.engrave(head_lbl)
	var top := UI.hbox([head_lbl,
		UI.color_btn("<< Turno precedente", UI.PANEL2, func(): app.state.prev_turn(), 64),
		UI.color_btn("TURNO SUCCESSIVO >>", Color(0.66, 0.4, 0.1), func(): app.state.next_turn(), 72)], 12)
	top.get_child(2).add_theme_font_size_override("font_size", 26)
	add_child(top)
	add_child(UI.flow([
		UI.btn("Nuovo combattimento", _new_combat, 56),
		UI.btn("Aggiungi combattente", _add_dialog, 56),
		UI.btn("Tira iniziativa mostri", func(): app.state.roll_monster_initiative(true), 56),
		UI.btn("Avvicina mostro", func():
			var cur: Dictionary = app.state.current_combatant()
			app.toast(app.state.monster_auto_move(str(cur.get("ref", ""))) if not cur.is_empty() else "Nessun turno in corso"), 56),
		UI.btn("Richiedi iniziativa ai giocatori", _ask_players, 56),
		UI.color_btn("Termina combattimento", Color(0.45, 0.15, 0.12), func(): app.confirm("Terminare il combattimento?", func(): app.state.combat_end()), 56),
	]))
	diff_lbl = UI.wrap_lbl("", 19)
	add_child(diff_lbl)
	panel = preload("res://scripts/turn_panel.gd").new()
	panel.setup(app)
	list = UI.vbox([], 8)
	add_child(UI.scroll(UI.vbox([panel, list], 10)))


func _ask_players() -> void:
	app.state.request_player_initiative()
	app.toast("Richiesta di iniziativa inviata ai telefoni")


func refresh() -> void:
	panel.refresh()
	var ini: Dictionary = app.state.ini()
	var cur: Dictionary = app.state.current_combatant()
	if not ini.active:
		head_lbl.text = "Nessun combattimento in corso"
	else:
		head_lbl.text = "Round %d   -   Turno di: %s" % [int(ini.round), cur.get("name", "(premi Turno successivo)")]
	diff_lbl.visible = not ini.combatants.is_empty()
	UI.difficulty_line(diff_lbl, app.state.combat_encounter())
	UI.clear(list)
	if ini.combatants.is_empty():
		list.add_child(UI.wrap_lbl("Premi \"Nuovo combattimento\" per scegliere chi combatte. Poi tira l'iniziativa dei mostri e chiedi ai giocatori di tirare la loro: la classifica si ordina da sola.", 22, UI.DIM))
		return
	var pos := 1
	for c in ini.combatants:
		var e: Dictionary = app.state.find_entity(c.ref)
		if e.is_empty():
			continue
		var is_cur: bool = c.id == ini.current
		var row := UI.hbox([], 5)
		var img_key := Art.key_for(e, c.type)
		var marker := UI.lbl(">>" if is_cur else "%d." % pos, 26, UI.GOLD if is_cur else UI.DIM)
		marker.custom_minimum_size = Vector2(40, 0)
		row.add_child(marker)
		row.add_child(Art.avatar(img_key, 50))
		var name_box := UI.vbox([], 0)
		var nm := UI.lbl(str(e.name), 26, Color.WHITE if is_cur else UI.TEXT)
		name_box.add_child(nm)
		var sub := "Personaggio" if c.type == "pc" else str(e.get("kind", "Mostro"))
		if c.type == "monster" and not bool(e.get("revealed", false)):
			sub += " (nascosto)"
		name_box.add_child(UI.lbl(sub, 16, UI.DIM))
		name_box.custom_minimum_size = Vector2(170, 0)
		row.add_child(name_box)
		row.add_child(UI.lbl("Iniz.", 18, UI.DIM))
		var score := int(c.score)
		var sp := UI.spin(-10, 60, score if score != Rules.NO_SCORE else 0, func(v): app.state.set_score(c.id, v), 80)
		if score == Rules.NO_SCORE:
			sp.get_line_edit().text = ""
			sp.get_line_edit().placeholder_text = "?"
		row.add_child(sp)
		row.add_child(UI.lbl("(%s)" % Rules.fmt_mod(c.mod), 18, UI.DIM))
		var hp_text := "PF %d/%d" % [int(e.hp), int(e.hp_max)]
		if int(e.get("hp_temp", 0)) > 0:
			hp_text += " +%d" % int(e.hp_temp)
		var hp_col := UI.RED if int(e.hp) <= 0 else (UI.GOLD if int(e.hp) * 2 <= int(e.hp_max) else UI.TEXT)
		var hp_l := UI.lbl(hp_text, 22, hp_col)
		hp_l.custom_minimum_size = Vector2(116, 0)
		row.add_child(hp_l)
		row.add_child(UI.lbl("CA %d" % int(e.ac), 22))
		# the status may be long ("Sconfitto", conditions...): it takes the free
		# space and is cut, so the row never grows past the window
		var status := UI.lbl(app.state.status_of(e), 18, UI.DIM)
		status.clip_text = true
		status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status.tooltip_text = status.text
		status.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(status)
		var amt := UI.spin(1, 999, int(amounts.get(c.ref, 5)), func(v): amounts[c.ref] = v, 76)
		row.add_child(amt)
		row.add_child(CombatUI.damage_btn(app, c.ref, func(): return UI.spin_value(amt), 52))
		row.add_child(UI.color_btn("Cura", Color(0.18, 0.48, 0.25), func(): app.state.change_hp(c.ref, UI.spin_value(amt)), 52))
		var cm: MenuButton = app.tab_players._cond_menu(e)
		cm.text = "Cond."
		cm.custom_minimum_size.y = 52
		row.add_child(cm)
		row.add_child(UI.btn("Rimuovi", func(): app.state.combat_remove(c.id), 52))
		var content: Control = row
		var conds := str(e.get("conditions", "")).strip_edges()
		var extra: Array = [row]
		var defs := Rules.defenses_text(e)
		if conds != "" or defs != "":
			var info := (("Condizioni: " + conds + "   ") if conds != "" else "") + defs
			extra.append(UI.lbl(info.strip_edges(), 16, Color(0.85, 0.6, 0.95)))
		if c.type == "pc" and int(e.hp) <= 0:
			# Same death-save controls as the Players tab.
			extra.append(app.tab_players._death_row(e))
		if extra.size() > 1:
			content = UI.vbox(extra, 6)
		var card := UI.card(content, Color(0.32, 0.22, 0.1) if is_cur else UI.PANEL, 10)
		list.add_child(card)
		if is_cur:
			_pulse(card)
		var hp_now := int(e.hp)
		if last_hp.has(c.ref) and int(last_hp[c.ref]) != hp_now:
			_hp_flash(card, hp_now < int(last_hp[c.ref]))
		last_hp[c.ref] = hp_now
		if is_cur:
			var key := "%d:%s" % [int(ini.round), str(c.id)]
			if key != last_turn:
				if last_turn != "" and is_visible_in_tree():
					app.turn_banner(str(e.name), "Round %d - tocca a" % int(ini.round), img_key)
				last_turn = key
		pos += 1


func _new_combat() -> void:
	var box := UI.vbox([], 6)
	var checks: Dictionary = {}
	box.add_child(UI.lbl("Personaggi", 22, UI.GOLD))
	for c in app.state.characters():
		var cb := UI.check(str(c.name), true)
		checks[c.id] = cb
		box.add_child(cb)
	box.add_child(UI.lbl("Mostri e PNG", 22, UI.GOLD))
	for m in app.state.monsters():
		var cb := UI.check("%s  (PF %d/%d)%s" % [m.name, int(m.hp), int(m.hp_max), "" if m.revealed else "  - nascosto"], int(m.hp) > 0)
		checks[m.id] = cb
		box.add_child(cb)
	app.show_modal("Nuovo combattimento", box, [
		["Annulla", app.close_modal],
		["Inizia", _start_combat.bind(checks), Color(0.66, 0.4, 0.1)],
	])


func _start_combat(checks: Dictionary) -> void:
	var refs: Array = []
	for id in checks:
		if checks[id].button_pressed:
			refs.append(id)
	app.close_modal()
	app.state.combat_start(refs)


func _add_one(id: String) -> void:
	app.state.combat_add(id)
	app.close_modal()


func _add_dialog() -> void:
	var box := UI.vbox([], 6)
	var any := false
	for e in app.state.characters() + app.state.monsters():
		if app.state.in_combat(e.id):
			continue
		any = true
		box.add_child(UI.btn("Aggiungi %s" % e.name, _add_one.bind(str(e.id)), 52))
	if not any:
		box.add_child(UI.wrap_lbl("Tutti sono già in combattimento. Aggiungi nuovi mostri dal Bestiario.", 20, UI.DIM))
	app.show_modal("Aggiungi combattente", box)


## Slow golden breathing glow on the card of whoever is acting.
func _pulse(card: PanelContainer) -> void:
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
	sb.border_color = UI.GOLD
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0.86, 0.69, 0.38, 0.25)
	sb.shadow_size = 6
	card.add_theme_stylebox_override("panel", sb)
	var tw := card.create_tween().set_loops()
	tw.tween_property(sb, "shadow_size", 16, 1.1).set_trans(Tween.TRANS_SINE)
	tw.tween_property(sb, "shadow_size", 6, 1.1).set_trans(Tween.TRANS_SINE)


## Quick red (damage) or green (healing) flash on a row whose PF changed.
func _hp_flash(card: Control, damage: bool) -> void:
	card.self_modulate = Color(1.8, 0.6, 0.5) if damage else Color(0.7, 1.7, 0.8)
	var tw := card.create_tween()
	tw.tween_property(card, "self_modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if damage:
		var base := card.position.x
		var sh := card.create_tween()
		for dx in [8, -7, 5, -3, 0]:
			sh.tween_property(card, "position:x", base + dx, 0.05)
