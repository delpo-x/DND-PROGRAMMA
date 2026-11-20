extends VBoxContainer
## Quests with required checks (skill + DC). Hide or reveal quests and checks;
## the outcome is set automatically comparing the player's roll with the DC.

var app
var list: VBoxContainer
var q_title: LineEdit
var q_desc: LineEdit
var q_hidden: CheckBox

const STATUSES := ["attiva", "completata", "fallita"]
const STATUS_NAMES := ["Attiva", "Completata", "Fallita"]


func setup(a) -> void:
	app = a
	q_title = UI.edit("", "Titolo della missione", Callable(), 320)
	q_desc = UI.edit("", "Descrizione")
	q_hidden = UI.check("Nascosta ai giocatori", false)
	add_child(UI.card(UI.vbox([UI.title("Nuova missione"), UI.hbox([q_title, q_desc]),
		UI.hbox([q_hidden, UI.spacer(), UI.color_btn("Crea missione", Color(0.18, 0.42, 0.25), _add, 52)])]), UI.PANEL, 12))
	list = UI.vbox([], 10)
	add_child(UI.scroll(list))


func _add() -> void:
	app.state.add_quest(q_title.text, q_desc.text, q_hidden.button_pressed)
	q_title.text = ""
	q_desc.text = ""


func refresh() -> void:
	UI.clear(list)
	var st: GameState = app.state
	if st.data.quests.is_empty():
		list.add_child(UI.wrap_lbl("Nessuna missione. Creane una e aggiungi le prove richieste (abilità + CD).", 20, UI.DIM))
	for q in st.data.quests:
		var qid: String = q.id
		var hid: bool = q.hidden
		var v := UI.vbox([], 8)
		var status_opt := UI.option(STATUS_NAMES, STATUSES.find(q.status), _set_status.bind(q), 170)
		v.add_child(UI.hbox([
			UI.lbl(str(q.title), 26, Color.WHITE),
			UI.lbl("NASCOSTA" if hid else "VISIBILE", 18, UI.RED if hid else UI.GREEN),
			UI.spacer(), status_opt,
			UI.btn("Rivela" if hid else "Nascondi", _toggle_hidden.bind(q), 48),
			UI.color_btn("Elimina", Color(0.35, 0.12, 0.1), func(): app.confirm("Eliminare la missione?", func(): st.delete_quest(qid)), 48),
		]))
		if str(q.desc) != "":
			v.add_child(UI.wrap_lbl(str(q.desc), 18, UI.DIM))
		for c in q.checks:
			v.add_child(_check_row(q, c))
		v.add_child(_add_check_row(qid))
		list.add_child(UI.card(v, Color(0.14, 0.11, 0.12) if hid else UI.PANEL, 12))


func _check_row(q: Dictionary, c: Dictionary) -> Control:
	var st: GameState = app.state
	var qid: String = q.id
	var cid: String = c.id
	var row := UI.hbox([], 8)
	var res := "In attesa"
	var col := UI.DIM
	if c.result == "success":
		res = "RIUSCITA"
		col = UI.GREEN
	elif c.result == "fail":
		res = "FALLITA"
		col = UI.RED
	var target := "chiunque"
	if str(c.target) != "":
		target = str(st.find_entity(c.target).get("name", "?"))
	row.add_child(UI.lbl("•  %s  CD %d  (%s)" % [Rules.check_label(c.kind, c.param), int(c.dc), target], 20))
	if bool(c.hidden):
		row.add_child(UI.lbl("nascosta", 16, UI.RED))
	row.add_child(UI.lbl(res, 20, col))
	var tries: Array = []
	for t in c.attempts:
		tries.append("%s %d" % [t.who, int(t.total)])
	if tries.size() > 0:
		row.add_child(UI.lbl("[%s]" % ", ".join(tries), 16, UI.DIM))
	row.add_child(UI.spacer())
	row.add_child(UI.color_btn("Richiedi tiro", Color(0.2, 0.36, 0.6), _request.bind(qid, cid), 44))
	row.add_child(UI.btn("Riuscita", _set_result.bind(c, "success"), 44))
	row.add_child(UI.btn("Fallita", _set_result.bind(c, "fail"), 44))
	row.add_child(UI.btn("Azzera", _set_result.bind(c, ""), 44))
	row.add_child(UI.btn("Rivela" if bool(c.hidden) else "Nascondi", _toggle_hidden.bind(c), 44))
	row.add_child(UI.btn("X", func(): st.delete_check(qid, cid), 44, 44))
	return row


func _set_status(i: int, q: Dictionary) -> void:
	if q.status != STATUSES[i]:
		app.state.chronicle_add("missione", "Missione %s: %s" % [STATUS_NAMES[i].to_lower(), q.title], not bool(q.get("hidden", false)))
	q.status = STATUSES[i]
	app.state.touch()


func _toggle_hidden(d: Dictionary) -> void:
	d.hidden = not bool(d.hidden)
	app.state.touch()


func _set_result(c: Dictionary, r: String) -> void:
	c.result = r
	if r == "":
		c.attempts = []
	app.state.touch()


func _request(qid: String, cid: String) -> void:
	app.state.request_check(qid, cid)
	app.toast("Richiesta di tiro inviata")


func _add_check_row(qid: String) -> Control:
	var st: GameState = app.state
	var opts: Array = []
	var keys: Array = []
	for s in Rules.SKILLS:
		opts.append(s[1])
		keys.append(["skill", s[0]])
	for a in Rules.ABILITIES:
		opts.append("TS %s" % Rules.ABILITY_NAMES[a])
		keys.append(["save", a])
	var which := UI.option(opts, 12, Callable(), 220)
	var dc := UI.spin(1, 40, 12, Callable(), 100)
	var targets: Array = ["Chiunque"]
	var tids: Array = [""]
	for ch in st.characters():
		targets.append(str(ch.name))
		tids.append(ch.id)
	var target := UI.option(targets, 0, Callable(), 170)
	var hid := UI.check("Nascosta", false)
	return UI.flow([UI.lbl("Nuova prova:", 18, UI.DIM), which, UI.lbl("CD", 18, UI.DIM), dc, target, hid,
		UI.btn("Aggiungi prova", func(): _add_check(qid, keys[which.selected], dc, tids[target.selected], hid.button_pressed), 48)])


func _add_check(qid: String, key: Array, dc: SpinBox, target: String, hidden: bool) -> void:
	dc.apply()
	app.state.add_check(qid, key[0], key[1], int(dc.value), hidden, target)
