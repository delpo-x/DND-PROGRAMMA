extends VBoxContainer
## Character sheet form (used by the master; players have the web version).

var ch: Dictionary
var fields: Dictionary = {}
var ab_spins: Dictionary = {}
var save_checks: Dictionary = {}
var skill_opts: Dictionary = {}
var attacks_box: VBoxContainer
var notes: TextEdit


func build(character: Dictionary) -> void:
	ch = character.duplicate(true)
	add_theme_constant_override("separation", 10)
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 8)
	for f in [["name", "Nome"], ["player", "Giocatore"], ["cls", "Classe"], ["race", "Razza"], ["conditions", "Condizioni"]]:
		g.add_child(UI.lbl(f[1], 18, UI.DIM))
		var e := UI.edit(str(ch.get(f[0], "")), f[1], Callable(), 220)
		fields[f[0]] = e
		g.add_child(e)
	for f in [["level", "Livello", 1, 20], ["hp", "PF attuali", 0, 999], ["hp_max", "PF massimi", 1, 999], ["hp_temp", "PF temporanei", 0, 999],
			["ac", "CA", 0, 40], ["speed", "Velocità (m)", 0, 60], ["prof", "Bonus competenza", 0, 9], ["init_bonus", "Bonus iniziativa extra", -20, 20]]:
		g.add_child(UI.lbl(f[1], 18, UI.DIM))
		var s := UI.spin(f[2], f[3], int(ch.get(f[0], 0)), Callable(), 140)
		fields[f[0]] = s
		g.add_child(s)
	add_child(g)
	add_child(UI.lbl("Caratteristiche e tiri salvezza", 22, UI.GOLD))
	var ag := GridContainer.new()
	ag.columns = 3
	ag.add_theme_constant_override("h_separation", 16)
	for a in Rules.ABILITIES:
		var s := UI.spin(1, 30, int(ch.ab.get(a, 10)), Callable(), 120)
		ab_spins[a] = s
		var c := UI.check("TS competente", ch.saves.has(a))
		save_checks[a] = c
		ag.add_child(UI.lbl(Rules.ABILITY_NAMES[a], 20))
		ag.add_child(s)
		ag.add_child(c)
	add_child(ag)
	add_child(UI.lbl("Abilità", 22, UI.GOLD))
	var sg := GridContainer.new()
	sg.columns = 4
	sg.add_theme_constant_override("h_separation", 12)
	for s in Rules.SKILLS:
		sg.add_child(UI.lbl("%s (%s)" % [s[1], s[2]], 18))
		var o := UI.option(["-", "Competente", "Maestria"], int(ch.skills.get(s[0], 0)), Callable(), 170)
		skill_opts[s[0]] = o
		sg.add_child(o)
	add_child(sg)
	add_child(UI.lbl("Attacchi", 22, UI.GOLD))
	attacks_box = UI.vbox([], 6)
	add_child(attacks_box)
	for at in ch.attacks:
		_attack_row(at)
	add_child(UI.btn("+ Aggiungi attacco", func(): _attack_row({"name": "Attacco", "bonus": 0, "damage": "1d6"}), 48))
	add_child(UI.lbl("Note", 22, UI.GOLD))
	notes = TextEdit.new()
	notes.text = str(ch.get("notes", ""))
	notes.custom_minimum_size = Vector2(0, 110)
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	add_child(notes)


func _attack_row(at: Dictionary) -> void:
	var row := UI.hbox([], 6)
	var n := UI.edit(str(at.name), "Nome")
	var b := UI.spin(-20, 30, int(at.bonus), Callable(), 110)
	var d := UI.edit(str(at.damage), "Danni (es. 1d8+3)", Callable(), 180)
	row.add_child(n)
	row.add_child(UI.lbl("Colpire", 16, UI.DIM))
	row.add_child(b)
	row.add_child(d)
	row.add_child(UI.btn("X", func(): row.queue_free(), 48, 48))
	row.set_meta("fields", [n, b, d])
	attacks_box.add_child(row)


## Only the fields that differ from the sheet as it was when the form opened.
func changed_values() -> Dictionary:
	var all := values()
	var out := {}
	for k in all:
		if not ch.has(k) or var_to_str(all[k]) != var_to_str(ch[k]):
			out[k] = all[k]
	return out


func values() -> Dictionary:
	var out := {}
	for k in fields:
		var f = fields[k]
		if f is LineEdit:
			out[k] = f.text
		elif f is SpinBox:
			f.apply()
			out[k] = int(f.value)
	var ab := {}
	var saves: Array = []
	for a in Rules.ABILITIES:
		ab_spins[a].apply()
		ab[a] = int(ab_spins[a].value)
		if save_checks[a].button_pressed:
			saves.append(a)
	out.ab = ab
	out.saves = saves
	var sk := {}
	for s in skill_opts:
		if skill_opts[s].selected > 0:
			sk[s] = skill_opts[s].selected
	out.skills = sk
	var at: Array = []
	for row in attacks_box.get_children():
		if row.is_queued_for_deletion() or not row.has_meta("fields"):
			continue
		var f: Array = row.get_meta("fields")
		f[1].apply()
		at.append({"name": f[0].text, "bonus": int(f[1].value), "damage": f[2].text})
	out.attacks = at
	out.notes = notes.text
	return out
