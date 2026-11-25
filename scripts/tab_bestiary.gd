extends VBoxContainer
## Session bestiary: monsters and NPCs with AC, HP, initiative, notes,
## reveal/hide, duplicate (Goblin 1, Goblin 2...), damage and healing.

var app
var list: VBoxContainer
var f_name: LineEdit
var f_kind: OptionButton
var f_ac: SpinBox
var f_hp: SpinBox
var f_init: SpinBox
var f_notes: LineEdit
var f_rev: CheckBox
var f_qty: SpinBox
var f_preset: OptionButton
var f_xp := 0
var diff_lbl: Label  # difficulty of the living monsters, plus the ones in the form
var f_defs := {}
var amounts: Dictionary = {}


func setup(a) -> void:
	app = a
	f_name = UI.edit("", "Nome (es. Goblin)", Callable(), 220)
	f_kind = UI.option(["Mostro", "PNG"], 0, Callable(), 130)
	f_kind.accessibility_name = "Mostro o PNG"
	f_ac = UI.spin(0, 40, 13, Callable(), 100)
	f_hp = UI.spin(1, 999, 10, Callable(), 110)
	f_init = UI.spin(-10, 20, 0, Callable(), 100)
	f_notes = UI.edit("", "Note private (attacchi, tattiche...)")
	f_rev = UI.check("Visibile ai giocatori", false)
	f_qty = UI.spin(1, 20, 1, func(_v): _show_difficulty(), 90)
	var names: Array = ["Dal Manuale dei Mostri…"]
	for mm in Rules.MONSTERS:
		names.append("%s  (GS %s, %d PE)" % [mm[0], mm[5], Rules.cr_xp(mm[5])])
	f_preset = UI.option(names, 0, _preset, 420)
	f_preset.accessibility_name = "Creatura dal Manuale dei Mostri"
	var form := UI.vbox([
		UI.title("Aggiungi mostro o PNG"),
		UI.hbox([f_preset]),
		UI.flow([f_name, f_kind, UI.lbl("CA", 18, UI.DIM), f_ac, UI.lbl("PF", 18, UI.DIM), f_hp,
			UI.lbl("Mod. iniz.", 18, UI.DIM), f_init, UI.lbl("Quanti", 18, UI.DIM), f_qty]),
		UI.hbox([f_notes, f_rev, UI.color_btn("Aggiungi", Color(0.18, 0.42, 0.25), _add, 52)]),
	], 8)
	diff_lbl = UI.wrap_lbl("", 19)
	form.add_child(diff_lbl)
	add_child(UI.card(form, UI.PANEL, 12))
	list = UI.vbox([], 8)
	add_child(UI.scroll(list))


func _add() -> void:
	for s in [f_ac, f_hp, f_init, f_qty]:
		s.apply()
	var m: Dictionary = app.state.add_monster({"name": f_name.text if f_name.text.strip_edges() != "" else "Mostro",
		"kind": ["Mostro", "PNG"][f_kind.selected], "ac": int(f_ac.value), "hp": int(f_hp.value),
		"init_mod": int(f_init.value), "notes": f_notes.text, "revealed": f_rev.button_pressed, "xp": f_xp,
		"resist": f_defs.get("resist", ""), "vuln": f_defs.get("vuln", ""), "immune": f_defs.get("immune", "")})
	if int(f_qty.value) > 1:
		app.state.duplicate_monster(m.id, int(f_qty.value) - 1)
	f_name.text = ""
	f_notes.text = ""
	f_qty.value = 1
	f_xp = 0
	f_defs = {}
	f_preset.selected = 0


## Difficulty (2024 rules) of all the living monsters of the bestiary against
## the whole party; with a creature chosen in the form, also "adding these".
func _show_difficulty() -> void:
	var st: GameState = app.state
	var ids: Array = []
	for m in st.monsters():
		ids.append(m.id)
	var d: Dictionary = st.encounter(ids)
	var extra := ""
	if f_xp > 0 and int(d.party) > 0:
		var qty := UI.spin_value(f_qty)
		var more: Dictionary = st.encounter(ids, [], f_xp * qty)
		extra = "\nAggiungendo %d x %s: %s (%s PE)" % [qty, f_name.text, str(more.name).to_lower(), Rules.fmt_thousands(int(more.xp))]
	UI.difficulty_line(diff_lbl, d, extra)


func refresh() -> void:
	_show_difficulty()
	UI.clear(list)
	var st: GameState = app.state
	if st.monsters().is_empty():
		list.add_child(UI.wrap_lbl("Il bestiario della sessione è vuoto.", 20, UI.DIM))
	for m in st.monsters():
		var id: String = m.id
		var rev: bool = m.revealed
		var top := UI.hbox([], 12)
		var key := Art.key_for(m, "monster")
		if key != "":
			top.add_child(Art.avatar(key, 64))
		top.add_child(UI.engrave(UI.lbl(str(m.name), 26, Color.WHITE)))
		top.add_child(UI.lbl(str(m.kind), 18, UI.DIM))
		top.add_child(UI.lbl("VISIBILE" if rev else "NASCOSTO", 18, UI.GREEN if rev else UI.RED))
		top.add_child(UI.spacer())
		top.add_child(UI.lbl("CA %d" % int(m.ac), 24))
		var hp_txt := "PF %d/%d" % [int(m.hp), int(m.hp_max)]
		if int(m.get("hp_temp", 0)) > 0:
			hp_txt += " +%d temp." % int(m.hp_temp)
		top.add_child(UI.lbl(hp_txt, 24, UI.RED if int(m.hp) <= 0 else UI.TEXT))
		top.add_child(UI.lbl("Iniz. %s" % Rules.fmt_mod(m.init_mod), 22))
		top.add_child(UI.lbl("(%s)" % st.status_of(m), 18, UI.DIM))
		var v := UI.vbox([top], 6)
		if str(m.notes) != "":
			v.add_child(UI.wrap_lbl("Note: %s" % m.notes, 17, UI.DIM))
		if Rules.defenses_text(m) != "":
			v.add_child(UI.wrap_lbl(Rules.defenses_text(m), 18, Color(0.95, 0.75, 0.45)))
		if str(m.get("conditions", "")).strip_edges() != "":
			v.add_child(UI.wrap_lbl("Condizioni: " + str(m.conditions), 18, Color(0.85, 0.6, 0.95)))
		var amt := UI.spin(1, 999, int(amounts.get(id, 5)), func(x): amounts[id] = x, 100)
		v.add_child(UI.flow([
			UI.btn("Nascondi" if rev else "Rivela", func(): st.update_monster(id, {"revealed": not rev}), 48),
			UI.btn("Duplica", func(): st.duplicate_monster(id, 1), 48),
			UI.btn("Già in combattimento" if st.in_combat(id) else "Metti in combattimento", func(): st.combat_add(id), 48),
			amt,
			CombatUI.damage_btn(app, id, func(): return UI.spin_value(amt), 48),
			UI.color_btn("Cura", Color(0.18, 0.48, 0.25), func(): st.change_hp(id, UI.spin_value(amt)), 48),
			UI.btn("PF temp.", func(): st.give_temp_hp(id, UI.spin_value(amt)), 48),
			app.tab_players._cond_menu(m),
			UI.btn("Modifica", _edit.bind(id), 48),
			UI.color_btn("Elimina", Color(0.35, 0.12, 0.1), func(): app.confirm("Eliminare %s?" % m.name, func(): st.delete_monster(id)), 48),
		]))
		list.add_child(UI.card(v, UI.PANEL if rev else Color(0.14, 0.11, 0.12), 12))


func _edit(id: String) -> void:
	var m: Dictionary = app.state.find_entity(id)
	if m.is_empty():
		return
	var n := UI.edit(str(m.name), "Nome")
	var kind := UI.option(["Mostro", "PNG"], 1 if m.kind == "PNG" else 0)
	var ac := UI.spin(0, 40, int(m.ac))
	var hp := UI.spin(0, 999, int(m.hp))
	var hpm := UI.spin(1, 999, int(m.hp_max))
	var ini := UI.spin(-10, 20, int(m.init_mod))
	var tmp := UI.spin(0, 999, int(m.get("hp_temp", 0)))
	# challenge rating: gives the XP used by the encounter difficulty
	var crs: Array = Rules.CR_XP.keys()
	var cr_names: Array = ["Sconosciuto"]
	var cr_sel := 0
	for i in crs.size():
		cr_names.append("GS %s (%s PE)" % [crs[i], Rules.fmt_thousands(Rules.cr_xp(crs[i]))])
		if cr_sel == 0 and Rules.cr_xp(crs[i]) == int(m.get("xp", 0)):
			cr_sel = i + 1
	var cr := UI.option(cr_names, cr_sel, Callable(), 260)
	var defs := {}
	var dg := GridContainer.new()
	dg.columns = 4
	for t in Rules.DAMAGE_TYPES:
		var sel := 0
		if Rules._has_type(str(m.get("resist", "")), t):
			sel = 1
		if Rules._has_type(str(m.get("vuln", "")), t):
			sel = 2
		if Rules._has_type(str(m.get("immune", "")), t):
			sel = 3
		defs[t] = UI.option(["Normale", "Resistenza", "Vulnerabile", "Immune"], sel, Callable(), 170)
		dg.add_child(UI.lbl(t, 18, UI.DIM))
		dg.add_child(defs[t])
	var rev := UI.check("Visibile ai giocatori", bool(m.revealed))
	var notes := TextEdit.new()
	notes.text = str(m.notes)
	notes.custom_minimum_size = Vector2(0, 140)
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var g := GridContainer.new()
	g.columns = 2
	for pair in [["Nome", n], ["Tipo", kind], ["CA", ac], ["PF attuali", hp], ["PF massimi", hpm], ["PF temporanei", tmp], ["Mod. iniziativa", ini], ["Grado di sfida", cr]]:
		g.add_child(UI.lbl(pair[0], 20, UI.DIM))
		g.add_child(pair[1])
	var box := UI.vbox([g, rev, UI.lbl("Resistenze, vulnerabilità e immunità ai danni", 20, UI.GOLD), dg, UI.lbl("Note private del master", 20, UI.GOLD), notes], 10)
	app.show_modal("Modifica %s" % m.name, box, [
		["Annulla", app.close_modal],
		["Salva", func(): _save(id, n, kind, ac, hp, hpm, ini, rev, notes, tmp, defs, cr), Color(0.18, 0.48, 0.25)],
	])


func _save(id, n, kind, ac, hp, hpm, ini, rev, notes, tmp, defs: Dictionary, cr: OptionButton) -> void:
	for s in [ac, hp, hpm, ini, tmp]:
		s.apply()
	var lists: Array = [[], [], [], []]
	for t in defs:
		lists[defs[t].selected].append(t)
	app.state.update_monster(id, {"name": n.text, "kind": ["Mostro", "PNG"][kind.selected], "ac": int(ac.value),
		"hp_max": int(hpm.value), "hp": int(hp.value), "init_mod": int(ini.value), "revealed": rev.button_pressed,
		"notes": notes.text, "hp_temp": int(tmp.value), "resist": ", ".join(lists[1]), "vuln": ", ".join(lists[2]), "immune": ", ".join(lists[3]),
		"xp": Rules.cr_xp(str(Rules.CR_XP.keys()[cr.selected - 1])) if cr.selected > 0 else 0})
	app.close_modal()


## Fills the form from a ready-made Monster Manual (SRD) creature.
func _preset(i: int) -> void:
	if i <= 0:
		return
	var mm: Array = Rules.MONSTERS[i - 1]
	f_name.text = str(mm[0]).get_slice(" (", 0)
	f_kind.selected = 0
	f_ac.value = int(mm[2])
	f_hp.value = int(mm[3])
	f_init.value = int(mm[4])
	f_xp = Rules.cr_xp(str(mm[5]))
	f_defs = Rules.monster_defenses(str(mm[0]))
	f_notes.text = "%s, GS %s (%d PE). %s" % [mm[1], mm[5], f_xp, mm[6]]
	_show_difficulty()
