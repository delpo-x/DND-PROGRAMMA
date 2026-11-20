class_name CombatUI
extends RefCounted
## Damage button shared by the Bestiary and Initiative tabs. For a creature
## with resistances, vulnerabilities or immunities it opens a menu of damage
## types, so the right multiplier is applied.


static func damage_btn(app, id: String, amount: Callable, h := 52) -> Button:
	var e: Dictionary = app.state.find_entity(id)
	var has_def := Rules.defenses_text(e) != ""
	var b := UI.color_btn("Danno ▾" if has_def else "Danno", Color(0.6, 0.15, 0.12), Callable(), h)
	if not has_def:
		b.pressed.connect(func(): app.state.change_hp(id, -int(amount.call())))
		return b
	var pm := PopupMenu.new()
	b.add_child(pm)
	pm.add_item("Danno normale", 0)
	for i in Rules.DAMAGE_TYPES.size():
		var t: String = Rules.DAMAGE_TYPES[i]
		var note: String = Rules.apply_defenses(e, 2, t)[1]
		pm.add_item(t + (("  (%s)" % note) if note != "" else ""), i + 1)
	pm.id_pressed.connect(func(i: int):
		var n := int(amount.call())
		if i == 0:
			app.state.change_hp(id, -n)
			return
		var t: String = Rules.DAMAGE_TYPES[i - 1]
		var r: Array = app.state.damage(id, n, t)
		if str(r[1]) != "":
			app.toast("%s: %d danni da %s, %s: %d inflitti" % [e.name, n, t.to_lower(), r[1], int(r[0])]))
	b.pressed.connect(func():
		pm.position = Vector2i(b.get_screen_position() + Vector2(0, b.size.y))
		pm.popup())
	return b


## Dialog to set, for each damage type, normal / resistance / vulnerability /
## immunity of a character or monster.
static func defenses_dialog(app, id: String) -> void:
	var e: Dictionary = app.state.find_entity(id)
	if e.is_empty():
		return
	var opts := {}
	var g := GridContainer.new()
	g.columns = 4
	for t in Rules.DAMAGE_TYPES:
		var sel := 0
		if Rules._has_type(str(e.get("resist", "")), t):
			sel = 1
		if Rules._has_type(str(e.get("vuln", "")), t):
			sel = 2
		if Rules._has_type(str(e.get("immune", "")), t):
			sel = 3
		opts[t] = UI.option(["Normale", "Resistenza", "Vulnerabile", "Immune"], sel, Callable(), 170)
		g.add_child(UI.lbl(t, 18, UI.DIM))
		g.add_child(opts[t])
	var hint := UI.wrap_lbl("Resistenza: danni dimezzati. Vulnerabile: danni raddoppiati. Immune: nessun danno.", 17, UI.DIM)
	app.show_modal("Difese di %s" % e.name, UI.vbox([hint, g], 10), [
		["Annulla", app.close_modal],
		["Salva", func():
			var lists: Array = [[], [], [], []]
			for t in opts:
				lists[opts[t].selected].append(t)
			var f := {"resist": ", ".join(lists[1]), "vuln": ", ".join(lists[2]), "immune": ", ".join(lists[3])}
			if app.state.is_pc(id):
				app.state.update_character(id, f)
			else:
				app.state.update_monster(id, f)
			app.close_modal(), Color(0.18, 0.48, 0.25)],
	])
