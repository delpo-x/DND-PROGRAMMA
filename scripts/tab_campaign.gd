extends VBoxContainer
## Campaigns and sessions: autosave, new / open / duplicate / delete,
## new session and the master's private notes.

var app
var body: VBoxContainer
var name_edit: LineEdit
var notes_edit: TextEdit
var camp_notes: TextEdit
var new_name: LineEdit
var open_chapters: Dictionary = {}


func setup(a) -> void:
	app = a
	body = UI.vbox([], 12)
	add_child(UI.scroll(body))


func refresh() -> void:
	if is_instance_valid(notes_edit) and is_instance_valid(camp_notes) and (notes_edit.has_focus() or camp_notes.has_focus() or name_edit.has_focus()):
		return
	UI.clear(body)
	var st: GameState = app.state
	body.add_child(UI.title("Campagna attuale"))
	name_edit = UI.edit(str(st.data.name), "Nome della campagna")
	body.add_child(UI.hbox([name_edit, UI.btn("Rinomina", _rename, 52),
		UI.lbl("Sessione %d" % int(st.data.session), 24, UI.GOLD),
		UI.color_btn("Inizia nuova sessione", Color(0.66, 0.4, 0.1), func(): app.confirm("Iniziare la sessione %d?" % (int(st.data.session) + 1), func(): st.new_session()), 52)]))
	body.add_child(UI.wrap_lbl("Salvataggio automatico attivo: ogni modifica viene salvata sul dispositivo dopo un secondo. Ultimo salvataggio: %s" % st.data.get("updated", "-"), 17, UI.DIM))
	body.add_child(UI.lbl("Note private della sessione %d (solo master)" % int(st.data.session), 22, UI.GOLD))
	notes_edit = TextEdit.new()
	notes_edit.text = str(st.current_session().get("notes", ""))
	notes_edit.custom_minimum_size = Vector2(0, 140)
	notes_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes_edit.text_changed.connect(_session_notes_changed)
	body.add_child(notes_edit)
	body.add_child(UI.lbl("Note private della campagna (solo master)", 22, UI.GOLD))
	camp_notes = TextEdit.new()
	camp_notes.text = str(st.data.get("notes", ""))
	camp_notes.custom_minimum_size = Vector2(0, 110)
	camp_notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	camp_notes.text_changed.connect(_camp_notes_changed)
	body.add_child(camp_notes)
	var sess: Array = []
	for s in st.data.sessions:
		sess.append("Sessione %d - %s" % [int(s.n), str(s.date).replace("T", " ").left(16)])
	body.add_child(UI.wrap_lbl("Sessioni: " + "   |   ".join(sess), 17, UI.DIM))
	_save_section(st)
	_story_section(st)
	body.add_child(UI.title("Tutte le campagne"))
	new_name = UI.edit("", "Nome della nuova campagna")
	body.add_child(UI.hbox([new_name, UI.color_btn("Crea nuova campagna", Color(0.18, 0.42, 0.25), _create, 52)]))
	for c in st.list_campaigns():
		var id: String = c.id
		var is_cur: bool = id == st.data.id
		var row := UI.hbox([], 10)
		row.add_child(UI.lbl(str(c.name), 24, UI.GOLD if is_cur else Color.WHITE))
		row.add_child(UI.lbl("%d personaggi - sessione %d - %s" % [int(c.chars), int(c.session), str(c.updated).replace("T", " ").left(16)], 17, UI.DIM))
		row.add_child(UI.spacer())
		if is_cur:
			row.add_child(UI.lbl("IN USO", 18, UI.GREEN))
		else:
			row.add_child(UI.color_btn("Apri", Color(0.2, 0.36, 0.6), func(): _open(id), 48))
		row.add_child(UI.btn("Duplica", _duplicate.bind(id), 48))
		if not is_cur:
			row.add_child(UI.color_btn("Elimina", Color(0.35, 0.12, 0.1), _ask_delete.bind(id, str(c.name)), 48))
		body.add_child(UI.card(row, Color(0.25, 0.18, 0.1) if is_cur else UI.PANEL, 10))


func _duplicate(id: String) -> void:
	app.state.duplicate_campaign(id)
	refresh()


func _ask_delete(id: String, cname: String) -> void:
	app.confirm("Eliminare definitivamente la campagna \"%s\"?" % cname, _delete.bind(id))


func _delete(id: String) -> void:
	app.state.delete_campaign(id)
	refresh()


func _session_notes_changed() -> void:
	var s: Dictionary = app.state.current_session()
	if not s.is_empty():
		s.notes = notes_edit.text
		app.state.save_pending = true


func _camp_notes_changed() -> void:
	app.state.data.notes = camp_notes.text
	app.state.save_pending = true


func _rename() -> void:
	if name_edit.text.strip_edges() != "":
		app.state.data.name = name_edit.text.strip_edges().left(60)
		app.state.touch()


func _create() -> void:
	var n := new_name.text.strip_edges()
	app.state.new_campaign(n if n != "" else "Nuova campagna")
	app.net.broadcast_state()


func _open(id: String) -> void:
	app.state.load_campaign(id)
	app.net.broadcast_state()


# ------------------------------------------------------------------ saving
func _save_section(st: GameState) -> void:
	body.add_child(UI.title("Salvataggi e copie di sicurezza"))
	body.add_child(UI.wrap_lbl("Ogni modifica viene salvata subito. In più l'app tiene dei punti di ripristino: uno ogni 10 minuti di gioco (gli ultimi 40) e uno all'inizio di ogni sessione (tenuti per sempre). Puoi anche esportare tutta la campagna in un file da conservare altrove.", 17, UI.DIM))
	body.add_child(UI.flow([
		UI.color_btn("Crea punto di ripristino", Color(0.18, 0.42, 0.25), func():
			st.backup_now("manuale")
			app.toast("Punto di ripristino creato")
			refresh(), 52),
		UI.btn("Esporta campagna su file", func(): app.save_text_file("Esporta la campagna", "%s.dndtavolo.json" % str(st.data.name).validate_filename(), "*.json ; Campagna D&D Tavolo", st.export_json()), 52),
		UI.btn("Importa campagna da file", func(): app.pick_text_file("Importa una campagna", "*.json ; Campagna D&D Tavolo", _import_campaign), 52),
	]))
	var backups := st.list_backups()
	if backups.is_empty():
		body.add_child(UI.wrap_lbl("Ancora nessun punto di ripristino per questa campagna.", 17, UI.DIM))
		return
	var shown := 0
	for b in backups:
		if shown >= 12:
			body.add_child(UI.wrap_lbl("... e altri %d punti di ripristino più vecchi." % (backups.size() - shown), 16, UI.DIM))
			break
		var why: String = {"auto": "automatico", "manuale": "creato a mano", "prima-del-ripristino": "prima di un ripristino", "importata": "importazione"}.get(b.reason, str(b.reason).replace("-", " "))
		var path: String = b.path
		var row := UI.hbox([UI.lbl(str(b.date), 19), UI.lbl(why, 17, UI.DIM), UI.spacer(),
			UI.lbl("%d KB" % ceili(b.size / 1024.0), 15, UI.DIM),
			UI.btn("Ripristina", func(): app.confirm("Riportare la campagna a com'era il %s?
Lo stato attuale viene prima salvato come punto di ripristino, quindi non si perde nulla." % b.date, func():
				if st.restore_backup(path):
					app.toast("Campagna ripristinata")
					app.net.broadcast_state()
				else:
					app.toast("Ripristino non riuscito")), 44)], 12)
		body.add_child(UI.card(row, UI.PANEL, 6))
		shown += 1


func _import_campaign(txt: String) -> void:
	var name: String = app.state.import_json(txt)
	if name == "":
		app.toast("Il file non è una campagna valida")
	else:
		app.toast("Campagna importata: %s" % name)
		app.net.broadcast_state()


# ------------------------------------------------------------------ story
func _story_section(st: GameState) -> void:
	body.add_child(UI.title("Storia della campagna (solo master)"))
	var story: Dictionary = st.data.get("story", {})
	var btns := UI.flow([UI.color_btn("Importa storia da PDF", Color(0.45, 0.3, 0.1), _import_story, 52)])
	if not story.is_empty():
		btns.add_child(UI.btn("Apri tutti", func(): _toggle_all(true), 52))
		btns.add_child(UI.btn("Chiudi tutti", func(): _toggle_all(false), 52))
		var pcs: Array = story.get("pcs", [])
		if pcs.size() > 0:
			btns.add_child(UI.color_btn("Crea i PG pronti (%d)" % pcs.size(), Color(0.18, 0.42, 0.25), _create_pcs, 52))
		btns.add_child(UI.color_btn("Rimuovi storia", Color(0.35, 0.12, 0.1), func(): app.confirm("Rimuovere la storia importata da questa campagna?", func(): st.set_story({})), 52))
	body.add_child(btns)
	body.add_child(_tone_row(st))
	body.add_child(_lines_row(st, "Fatti fissati", "pinned", GameState.PINNED_MAX,
		"Uno per riga: cose che devono restare vere anche dopo i riassunti (una promessa, un debito, un nome deciso al tavolo)", func(t): st.set_pinned(t)))
	body.add_child(_lines_row(st, "Fazioni", "factions", GameState.FACTIONS_MAX,
		"Una per riga, nome: cosa vuole. A fine capitolo Dnd The Game scrive cosa ha fatto ognuna nel frattempo", func(t): st.set_factions(t)))
	var moves: Array = st.data.get("faction_moves", [])
	if not moves.is_empty():
		body.add_child(UI.wrap_lbl("Ultime mosse delle fazioni: " + " ".join(moves), 17, UI.DIM))
	if story.is_empty():
		body.add_child(UI.wrap_lbl("Nessuna storia. Importa il PDF dell'avventura: il testo viene diviso in capitoli e resta visibile solo a te.", 18, UI.DIM))
		return
	body.add_child(UI.wrap_lbl("%s  -  %d capitoli  -  da %s, importata %s" % [story.get("title", ""), story.get("chapters", []).size(), story.get("source", ""), str(story.get("imported", "")).replace("T", " ").left(16)], 18, UI.DIM))
	var problems := StoryImport.check(story, StoryImport.known_monsters(st))
	if not problems.is_empty():
		var pbox := UI.vbox([UI.lbl("Da sistemare per il narratore di Dnd The Game (%d capitoli)" % problems.size(), 19, UI.GOLD)], 4)
		for pr in problems:
			pbox.add_child(UI.wrap_lbl("Capitolo %d, %s:
- %s" % [pr.chapter, pr.title, "
- ".join(pr.issues)], 17, UI.DIM))
		pbox.add_child(UI.wrap_lbl("Come scrivere la scheda di un capitolo: GUIDA_STORIE.md.", 16, UI.DIM))
		body.add_child(UI.card(pbox, Color(0.2, 0.15, 0.08, 0.9), 10))
	var chapters: Array = story.get("chapters", [])
	for i in chapters.size():
		var c: Dictionary = chapters[i]
		var is_open: bool = open_chapters.get(i, false)
		var head := UI.btn(("▼  " if is_open else "▶  ") + str(c.title), _toggle.bind(i), 48)
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var box := UI.vbox([head], 6)
		if is_open:
			var rt := RichTextLabel.new()
			rt.bbcode_enabled = true
			rt.fit_content = true
			rt.selection_enabled = true
			rt.add_theme_font_size_override("normal_font_size", 19)
			rt.add_theme_font_size_override("bold_font_size", 21)
			rt.text = _story_bbcode(str(c.text))
			box.add_child(rt)
		body.add_child(UI.card(box, UI.PANEL, 8))


## Tone of the adventure, read by the narrator of Dnd The Game in every reply.
func _tone_row(st: GameState) -> Control:
	var e := UI.edit(str(st.data.get("tone", "")), "Tono per il narratore di Dnd The Game, es. cupo, poca luce, PNG sospettosi")
	e.max_length = StoryImport.TONE_MAX
	var save := func(_t = ""):
		if e.text.strip_edges() != str(st.data.get("tone", "")):
			st.set_tone(e.text)
			app.toast("Tono salvato")
	e.text_submitted.connect(save)
	e.focus_exited.connect(save)
	return UI.hbox([UI.lbl("Tono", 19, UI.DIM), e], 10)


## A box of lines for the narrator of Dnd The Game (pinned facts, factions),
## saved when it loses focus.
func _lines_row(st: GameState, label: String, key: String, most: int, hint: String, setter: Callable) -> Control:
	var te := TextEdit.new()
	te.text = "\n".join(st.data.get(key, []))
	te.placeholder_text = hint
	te.custom_minimum_size = Vector2(0, 90)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.focus_exited.connect(func():
		if GameState.text_lines(te.text, most) != st.data.get(key, []):
			setter.call(te.text)
			app.toast("Salvato: " + label))
	return UI.vbox([UI.lbl("%s (al massimo %d)" % [label, most], 19, UI.DIM), te], 4)


func _story_bbcode(t: String) -> String:
	var out := PackedStringArray()
	for para in t.split("\n\n"):
		var p := para.replace("[", "[lb]")
		if p.begins_with("## "):
			out.append("[b][color=#e0b050]%s[/color][/b]" % p.substr(3))
		elif p == p.to_upper() and p.length() < 80:
			out.append("[i][color=#a0a0a0]%s[/color][/i]" % p)
		else:
			out.append(p)
	return "\n\n".join(out)


func _toggle(i: int) -> void:
	open_chapters[i] = not open_chapters.get(i, false)
	refresh()


func _toggle_all(v: bool) -> void:
	for i in app.state.data.get("story", {}).get("chapters", []).size():
		open_chapters[i] = v
	refresh()


func _import_story() -> void:
	app.pick_pdf("Scegli il PDF della storia", _story_bytes)


func _story_bytes(bytes: PackedByteArray, fname: String) -> void:
	app.toast("Lettura di %s..." % fname)
	await get_tree().process_frame
	await get_tree().process_frame
	var doc: Dictionary = app.read_pdf(bytes)
	if doc.is_empty():
		return
	var story := StoryImport.parse(doc, fname)
	if story.chapters.is_empty():
		app.toast("Nessun testo trovato nel PDF")
		return
	var apply := func():
		open_chapters = {}
		app.state.set_story(story)
		var problems := StoryImport.check(story, StoryImport.known_monsters(app.state))
		if problems.is_empty():
			app.toast("Storia importata: %d capitoli" % story.chapters.size())
		else:
			app.toast("Storia importata: %d capitoli, %d da sistemare per il narratore (vedi sotto)" % [story.chapters.size(), problems.size()])
		if story.pcs.size() > 0:
			var names: Array = []
			for pc in story.pcs:
				names.append("%s (%s %s, liv. %d)" % [pc.name, pc.race, pc.cls, int(pc.level)])
			app.confirm("La storia contiene %d personaggi pronti:\n%s\n\nCrearli adesso? Quelli che esistono già (stesso nome) vengono saltati." % [names.size(), "\n".join(names)], _create_pcs)
	if app.state.data.get("story", {}).is_empty():
		apply.call()
	else:
		app.confirm("Sostituire la storia attuale con \"%s\" (%d capitoli)?" % [story.title, story.chapters.size()], apply)


func _create_pcs() -> void:
	var made: Array = app.state.import_story_pcs()
	if made.is_empty():
		app.toast("I PG pronti esistono già")
	else:
		app.toast("Creati: %s" % ", ".join(made))
		app.net.broadcast_state()
