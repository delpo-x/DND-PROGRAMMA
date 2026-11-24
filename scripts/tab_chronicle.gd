extends VBoxContainer
## Campaign chronicle: a diary of everything that happened, grouped by
## session. The app writes most lines by itself (sessions, fights, falls,
## defeats, quests, memorable rolls, rests, experience); the master adds
## events, NPCs, places, loot and notes. Nothing is ever deleted: lines can
## only be edited or hidden from the players.

var app
var cat_add: OptionButton
var text_add: TextEdit
var pub_add: CheckBox
var search: LineEdit
var cat_filter: OptionButton
var sess_filter: OptionButton
var sess_vals: Array = [-1]
var list: VBoxContainer
var info_lbl: Label
const SHOW_MAX := 400
const CAT_COLORS := {
	"sessione": Color(0.86, 0.69, 0.38), "combattimento": Color(0.8, 0.32, 0.25), "sconfitta": Color(0.62, 0.2, 0.2),
	"personaggio": Color(0.35, 0.6, 0.85), "mostro": Color(0.6, 0.45, 0.75), "missione": Color(0.4, 0.7, 0.4),
	"tiro": Color(0.95, 0.8, 0.35), "riposo": Color(0.45, 0.65, 0.7), "xp": Color(0.9, 0.6, 0.2),
	"storia": Color(0.7, 0.6, 0.45), "salvataggio": Color(0.55, 0.55, 0.55), "evento": Color(0.92, 0.88, 0.76),
	"png": Color(0.75, 0.55, 0.85), "luogo": Color(0.45, 0.75, 0.6), "bottino": Color(0.95, 0.75, 0.3), "nota": Color(0.7, 0.64, 0.56),
}


func setup(a) -> void:
	app = a
	var names: Array = []
	for c in GameState.CHRONICLE_MANUAL:
		names.append(GameState.CHRONICLE_CATS[c])
	cat_add = UI.option(names, 0, Callable(), 210)
	cat_add.accessibility_name = "Categoria della nuova voce"
	text_add = TextEdit.new()
	text_add.placeholder_text = "Cosa è successo? (es. Il gruppo incontra Mastro Brann, il fabbro di Valmora, che chiede aiuto contro i goblin)"
	text_add.custom_minimum_size = Vector2(0, 74)
	text_add.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pub_add = UI.check("Visibile ai giocatori", true)
	var form := UI.vbox([
		UI.title("Scrivi nella cronaca"),
		UI.hbox([UI.vbox([cat_add, pub_add], 6), text_add,
			UI.color_btn("Aggiungi", Color(0.45, 0.3, 0.1), _add, 74)], 10),
	], 6)
	add_child(UI.card(form, UI.PANEL, 12))
	search = UI.edit("", "Cerca nella cronaca...", func(_t): refresh())
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var all_names: Array = ["Tutte le voci"]
	for c in GameState.CHRONICLE_CATS:
		all_names.append(GameState.CHRONICLE_CATS[c])
	cat_filter = UI.option(all_names, 0, func(_i): refresh(), 220)
	sess_filter = UI.option(["Tutte le sessioni"], 0, func(_i): refresh(), 200)
	cat_filter.accessibility_name = "Mostra la categoria"
	sess_filter.accessibility_name = "Mostra la sessione"
	add_child(UI.hbox([search, cat_filter, sess_filter,
		UI.btn("Esporta cronaca", _export, 52)], 10))
	info_lbl = UI.wrap_lbl("", 16, UI.DIM)
	add_child(info_lbl)
	list = UI.vbox([], 6)
	add_child(UI.scroll(list))


func _add() -> void:
	var t := text_add.text.strip_edges()
	if t == "":
		app.toast("Scrivi qualcosa da ricordare")
		return
	app.state.chronicle_add(GameState.CHRONICLE_MANUAL[cat_add.selected], t, pub_add.button_pressed, false)
	text_add.text = ""
	app.net.broadcast_state()
	app.toast("Aggiunto alla cronaca")


func refresh() -> void:
	if text_add.has_focus() or search.has_focus():
		_fill()
		return
	var st: GameState = app.state
	# session filter choices
	var prev: int = sess_vals[sess_filter.selected] if sess_filter.selected >= 0 and sess_filter.selected < sess_vals.size() else -1
	sess_filter.clear()
	sess_vals = [-1]
	sess_filter.add_item("Tutte le sessioni")
	for s in st.data.sessions:
		sess_filter.add_item("Sessione %d" % int(s.n))
		sess_vals.append(int(s.n))
	sess_filter.select(maxi(0, sess_vals.find(prev)))
	_fill()


func _fill() -> void:
	UI.clear(list)
	var st: GameState = app.state
	var q := search.text.strip_edges().to_lower()
	var cat := ""
	if cat_filter.selected > 0:
		cat = GameState.CHRONICLE_CATS.keys()[cat_filter.selected - 1]
	var sess: int = sess_vals[sess_filter.selected] if sess_filter.selected >= 0 and sess_filter.selected < sess_vals.size() else -1
	var shown: Array = []
	for e in st.data.chronicle:
		if cat != "" and e.cat != cat:
			continue
		if sess >= 0 and int(e.s) != sess:
			continue
		if q != "" and not str(e.text).to_lower().contains(q):
			continue
		shown.append(e)
	var total: int = st.data.chronicle.size()
	info_lbl.text = "%d voci nella cronaca%s. Le voci non si cancellano mai: si possono solo correggere o nascondere ai giocatori. PE totali del gruppo: %d." % [total, ("" if shown.size() == total else ", %d mostrate" % shown.size()), int(st.data.get("xp_total", 0))]
	if shown.is_empty():
		list.add_child(UI.wrap_lbl("La cronaca è vuota. Si riempie da sola durante il gioco (sessioni, combattimenti, cadute, missioni, tiri memorabili) e puoi aggiungere eventi, PNG, luoghi e bottino qui sopra." if total == 0 else "Nessuna voce corrisponde ai filtri.", 19, UI.DIM))
		return
	var start := maxi(0, shown.size() - SHOW_MAX)
	var dates := {}
	for s in st.data.sessions:
		dates[int(s.n)] = str(s.date).replace("T", " ").left(10)
	var cur := -1
	# newest session first, chronological inside each session
	var by_s := {}
	var order: Array = []
	for i in range(start, shown.size()):
		var e: Dictionary = shown[i]
		if not by_s.has(int(e.s)):
			by_s[int(e.s)] = []
			order.append(int(e.s))
		by_s[int(e.s)].append(e)
	order.reverse()
	for s in order:
		var head := UI.title("Sessione %d%s" % [s, ("   -   " + dates[s]) if dates.has(s) else ""])
		list.add_child(head)
		for e in by_s[s]:
			list.add_child(_row(e))


func _row(e: Dictionary) -> Control:
	var col: Color = CAT_COLORS.get(e.cat, UI.TEXT)
	var chip := UI.lbl(str(GameState.CHRONICLE_CATS.get(e.cat, e.cat)).to_upper(), 13, col)
	chip.custom_minimum_size = Vector2(150, 0)
	var time := UI.lbl(str(e.t).substr(11, 5), 15, UI.DIM)
	time.custom_minimum_size = Vector2(52, 0)
	var txt := UI.wrap_lbl(str(e.text), 19, UI.TEXT if bool(e.get("public", true)) else UI.DIM)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UI.hbox([time, chip, txt], 10)
	if not bool(e.get("public", true)):
		row.add_child(UI.lbl("solo master", 14, UI.RED))
	var id: String = e.id
	row.add_child(UI.btn("Mostra" if not bool(e.get("public", true)) else "Nascondi", func(): app.state.chronicle_update(id, {"public": not bool(e.get("public", true))}), 40))
	row.add_child(UI.btn("Modifica", _edit.bind(e), 40))
	var c := UI.card(row, Color(col.r * 0.12 + 0.1, col.g * 0.08 + 0.07, col.b * 0.06 + 0.055), 8)
	return c


func _edit(e: Dictionary) -> void:
	var te := TextEdit.new()
	te.text = str(e.text)
	te.custom_minimum_size = Vector2(0, 160)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var pub := UI.check("Visibile ai giocatori", bool(e.get("public", true)))
	app.show_modal("Modifica voce della cronaca", UI.vbox([te, pub], 10), [
		["Salva", func():
			app.state.chronicle_update(str(e.id), {"text": te.text, "public": pub.button_pressed})
			app.close_modal()],
		["Annulla", app.close_modal],
	])


func _export() -> void:
	var st: GameState = app.state
	app.save_text_file("Esporta la cronaca", "Cronaca - %s.md" % str(st.data.name).validate_filename(), "*.md ; Testo Markdown", st.chronicle_markdown())
