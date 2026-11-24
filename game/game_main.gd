extends Control
## Dnd The Game: the app is the master. Same rules engine and phone pages as
## D&D Tavolo Master, plus:
##   - monsters play their own turns (MonsterAI, rule-based, offline);
##   - a local model tells the story (Narrator, Ollama on this PC);
##   - the master's voice comes from the system's text-to-speech (Voice);
##   - players talk from the phone or type on this screen;
##   - every chapter ends in a recap file (GameStory).

const SETTINGS := "user://the_game/impostazioni.json"
const FEED_KEEP := 80
## Short lines the master says right away while the narrator is still
## writing, so the table never waits in silence. They must fit any scene:
## no actions of the characters, nothing about what will happen.
const FILLERS := {
	"base": ["Mmh, vediamo...", "Interessante.", "D'accordo.", "Bene, bene...", "Lasciatemi pensare un attimo...",
		"Uhm...", "Va bene.", "Vediamo un po'.", "Ah, sentite qua.", "Bene."],
	"start": ["Mettetevi comodi.", "Bene, cominciamo.", "Prendete i dadi e ascoltate."],
	"check": ["Vediamo com'è andata...", "I dadi hanno parlato.", "Bene, vediamo."],
	"after": ["Riprendete fiato.", "Il silenzio torna, piano piano."],
	"combat": ["Attenti...", "Vediamo..."],
}

var state := GameState.new()
var net := NetServer.new()
var narrator := Narrator.new()
var voice := Voice.new()
var ambience := Ambience.new()
var story := GameStory.new()
var rng := RandomNumberGenerator.new()
var settings := {"model": Narrator.DEFAULT_MODEL, "voice": "", "voice_on": true, "ambience_on": true}

var test_mode := false  # no files, no network outside this PC, no window tweaks
var llm_in_tests := false  # tests: ask the real local model too
var screenshot_path := ""
var frame := 0

# UI
var feed_box: VBoxContainer
var feed_scroll: ScrollContainer
var party_box: VBoxContainer
var combat_box: VBoxContainer
var input: LineEdit
var lbl_campaign: Label
var lbl_status: Label
var lbl_clients: Label
var chk_voice: CheckBox
var chk_ambience: CheckBox
var btn_read: Button
var _reading := false   # reading the "Da leggere" text of the chapter aloud
var _read_clock := 0.0  # time since the paragraph started
var _read_quiet := 0.0  # time the voice has been silent
var _read_min := 0.0    # time to leave a paragraph on screen without voice
var _adapting := false  # the narrator is checking the next paragraph
var _adapt_raw := ""
## The adaptation of the next paragraph, prepared while the reading is paused:
## {key: [read_pos, transcript size], full, ok}. Valid only for that key.
var _prep := {}
var _prep_key: Array = []
var modal_layer: Control
var toast_box: VBoxContainer

var feed: Array = []  # {who, text, kind, node}
var _live: Dictionary = {}  # entry of the reply being written
var _want_narration := false
var _feed_dirty := false
var _sync_clock := 0.0
var _last_filler := ""
var _save_clock := 0.0
var _ui_dirty := true

var _turn_key := ""
var _wait := 0.0
var _wait_call: Callable = Callable()
var _wait_max := 0.0
var checks: Dictionary = {}  # request id -> {label, dc, chars, results: {cid: [total, outcome]}}
var _closing := false
var _chapter_prose := ""


func _init() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--screenshot" and i + 1 < args.size():
			screenshot_path = args[i + 1]
	if screenshot_path != "":
		test_mode = true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.make_theme()
	rng.randomize()
	_background()
	if test_mode:
		state.persist = false
	else:
		DisplayServer.window_set_title("Dnd The Game")
		DisplayServer.screen_set_keep_on(true)
		_load_settings()
	if test_mode or not state.load_last():
		_example_campaign()
	state.ai_master = true
	net.setup(state)
	add_child(net)
	net.start("127.0.0.1" if test_mode else "*")
	narrator.model = str(settings.model)
	add_child(narrator)
	narrator.chunk.connect(_on_chunk)
	narrator.finished.connect(_on_finished)
	narrator.status_changed.connect(func(t): lbl_status.text = t)
	voice.setup(str(settings.voice))
	voice.enabled = bool(settings.voice_on)
	ambience.voice = voice
	ambience.enabled = bool(settings.ambience_on) and not test_mode
	add_child(ambience)
	_build_ui()
	state.changed.connect(func(): _ui_dirty = true)
	state.notice.connect(toast)
	state.roll_added.connect(_on_roll)
	net.clients_changed.connect(func(): _ui_dirty = true)
	net.player_message.connect(toast)
	net.player_said.connect(_on_player_said)
	net.player_end_turn.connect(func(cid): _end_pc_turn(cid))
	net.player_read.connect(_on_player_read)
	net.player_action.connect(_on_player_action)
	_open_story()
	if screenshot_path != "":
		_demo_feed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		state.save_now()
		story.save()


# ---------------------------------------------------------------- settings
func _load_settings() -> void:
	DirAccess.make_dir_recursive_absolute("user://the_game")
	if FileAccess.file_exists(SETTINGS):
		var j = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
		if j is Dictionary:
			for k in j:
				settings[k] = j[k]


func _save_settings() -> void:
	if test_mode:
		return
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings, "\t"))


func _example_campaign() -> void:
	state.new_campaign("Dnd The Game - prima avventura")
	var a := state.add_character("Aria", "Giocatore 1")
	state.update_character(a.id, {"cls": "Ladra", "race": "Elfa", "level": 3, "hp_max": 21, "hp": 21, "ac": 15,
		"ab": {"FOR": 10, "DES": 17, "COS": 13, "INT": 12, "SAG": 14, "CAR": 11},
		"saves": ["DES", "INT"], "skills": {"furtivita": 2, "percezione": 1, "acrobazia": 1, "indagare": 1},
		"attacks": [{"name": "Spada corta", "bonus": 5, "damage": "1d6+3"}, {"name": "Arco corto", "bonus": 5, "damage": "1d6+3"}]})
	var b := state.add_character("Bruno", "Giocatore 2")
	state.update_character(b.id, {"cls": "Guerriero", "race": "Nano", "level": 3, "hp_max": 31, "hp": 31, "ac": 18,
		"ab": {"FOR": 16, "DES": 12, "COS": 16, "INT": 9, "SAG": 11, "CAR": 10},
		"saves": ["FOR", "COS"], "skills": {"atletica": 1, "intimidire": 1},
		"attacks": [{"name": "Ascia da battaglia", "bonus": 5, "damage": "1d8+3"}]})
	state.add_monster({"name": "Goblin", "ac": 15, "hp": 7, "init_mod": 2, "notes": "Scimitarra +4, 1d6+2; arco corto +4, 1d6+2", "xp": 50})
	state.add_monster({"name": "Capo goblin", "ac": 17, "hp": 21, "init_mod": 1, "notes": "Multiattacco: due attacchi. Scimitarra +4, 1d6+2", "xp": 200})
	state.save_now()


func _open_story() -> void:
	story.open(state)
	UI.clear(feed_box)
	feed.clear()
	for t in story.transcript.slice(maxi(0, story.transcript.size() - 20)):
		add_feed(str(t.who), str(t.text), "master" if t.role == "assistant" else "player")
	_guess_place()
	_check_chapter()
	if story.is_new():
		add_feed("Tavolo", "Benvenuti. Il master è pronto: tra poco descrive la scena iniziale.", "info")
		_start_chapter("Inizia l'avventura. Presenta il luogo e la situazione iniziale ai personaggi.")
	elif story.transcript.is_empty():
		_start_chapter("Inizia il capitolo %d. Riprendi la storia da dove si era interrotta." % story.chapter)
	else:
		add_feed("Tavolo", "Bentornati al capitolo %d. Scrivete cosa fate, o premete %s." % [story.chapter,
			"Riprendi lettura" if story.reading_left() else "Continua"], "info")
		if not test_mode:
			narrator.warm_up()
	_refresh_read_btn()
	_ui_dirty = true


# ----------------------------------------------------------------------- UI
func _background() -> void:
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.13, 0.1, 0.12))
	grad.set_color(1, Color(0.03, 0.025, 0.035))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.4, 0.35)
	gt.fill_to = Vector2(1.2, 1.1)
	gt.width = 256
	gt.height = 256
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := UI.vbox([], 12)
	margin.add_child(root)
	# top bar
	var title := UI.lbl("DND THE GAME", 30, UI.GOLD)
	title.add_theme_font_override("font", UI.display_font())
	lbl_campaign = UI.lbl("", 20, UI.DIM)
	lbl_campaign.clip_text = true
	lbl_campaign.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl_clients = UI.lbl("", 18, UI.DIM)
	chk_voice = UI.check("Voce", voice.enabled, _toggle_voice)
	chk_voice.disabled = not voice.available
	chk_voice.tooltip_text = ("Voce: " + voice.voice_name) if voice.available else "Nessuna voce di sintesi trovata su questo dispositivo"
	chk_ambience = UI.check("Ambiente", bool(settings.ambience_on), _toggle_ambience)
	chk_ambience.tooltip_text = "Suoni di sottofondo del luogo (grotta, locanda, bosco...)"
	root.add_child(UI.hbox([title, UI.expand(lbl_campaign), lbl_clients, chk_voice, chk_ambience,
		UI.btn("Telefoni", _show_qr, 44), UI.btn("Campagna", _show_campaigns, 44),
		UI.btn("Diario", _open_diary, 44), UI.btn("Impostazioni", _show_settings, 44)], 12))
	lbl_status = UI.lbl(narrator.status, 17, UI.DIM)
	lbl_status.clip_text = true
	root.add_child(lbl_status)
	# story + side panel
	var mid := UI.hbox([], 14)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	feed_box = UI.vbox([], 14)
	feed_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_scroll = UI.scroll(feed_box)
	feed_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var feed_card := UI.card(feed_scroll, Color(0.09, 0.07, 0.07, 0.92), 18)
	feed_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(feed_card)
	var side := UI.vbox([], 12)
	side.custom_minimum_size = Vector2(340, 0)
	party_box = UI.vbox([], 6)
	combat_box = UI.vbox([], 6)
	side.add_child(UI.card(UI.vbox([UI.title("Gruppo"), party_box]), UI.PANEL, 12))
	var cb := UI.card(UI.vbox([combat_box]), UI.PANEL, 12)
	side.add_child(cb)
	var side_scroll := UI.scroll(side)
	side_scroll.custom_minimum_size = Vector2(360, 0)
	side_scroll.size_flags_horizontal = Control.SIZE_FILL
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(side_scroll)
	# input
	input = UI.edit("", "Cosa fate? Scrivete qui, oppure parlate al master dal telefono")
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 54)
	input.text_submitted.connect(func(_t): _send_input())
	root.add_child(UI.hbox([input, UI.color_btn("Invia", Color(0.18, 0.42, 0.25), _send_input, 54),
		UI.btn("Continua", func(): _event("Continua la storia."), 54),
		_make_read_btn(),
		UI.color_btn("Fine capitolo", UI.WINE, _ask_close_chapter, 54)], 10))
	# overlays
	toast_box = UI.vbox([], 8)
	toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_box.position = Vector2(0, 80)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_box)
	modal_layer = Control.new()
	modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_layer)


func _toggle_voice(on: bool) -> void:
	voice.enabled = on
	settings.voice_on = on
	_save_settings()
	if not on:
		voice.stop()


func _toggle_ambience(on: bool) -> void:
	settings.ambience_on = on
	_save_settings()
	ambience.set_enabled(on)


func toast(text: String) -> void:
	var l := UI.lbl(text, 20, Color.WHITE)
	var c := UI.card(l, Color(0.25, 0.17, 0.08, 0.95), 10)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(c)
	toast_box.position.x = (size.x - 600) / 2.0
	var tw := create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(c, "modulate:a", 0.0, 0.6)
	tw.tween_callback(c.queue_free)


func _modal(title_text: String, content: Control, width := 760) -> void:
	_close_modal()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(dim)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(center)
	var box := UI.vbox([UI.title(title_text), content, UI.btn("Chiudi", _close_modal, 48)], 14)
	box.custom_minimum_size = Vector2(width, 0)
	center.add_child(UI.card(box, UI.PANEL, 22))


func _close_modal() -> void:
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.clear(modal_layer)


func _show_qr() -> void:
	var url := net.base_url() + "/giocatore"
	var q := QR.encode(url)
	var border := 3
	var sc := 8
	var n := q.size + border * 2
	var img := Image.create(n * sc, n * sc, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for y in q.size:
		for x in q.size:
			if q.get_module(x, y):
				img.fill_rect(Rect2i((x + border) * sc, (y + border) * sc, sc, sc), Color.BLACK)
	var tex := TextureRect.new()
	tex.texture = ImageTexture.create_from_image(img)
	tex.custom_minimum_size = Vector2(300, 300)
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var u := UI.lbl(url, 20)
	u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modal("Collega i telefoni", UI.vbox([tex, u,
		UI.wrap_lbl("Stessa rete Wi-Fi di questo PC: inquadrate il codice. Dal telefono scegliete il personaggio, tirate i dadi, giocate il vostro turno e parlate al master (anche col microfono della tastiera).", 19, UI.DIM)], 12), 640)


func _show_campaigns() -> void:
	var box := UI.vbox([], 8)
	for c in state.list_campaigns():
		var cid := str(c.id)
		var label := "%s  (%d personaggi)" % [c.name, int(c.chars)]
		if cid == str(state.data.get("id", "")):
			label += "  - in gioco"
		box.add_child(UI.btn(label, func(): _load_campaign(cid), 48))
	box.add_child(UI.wrap_lbl("Le campagne sono quelle dell'app D&D Tavolo Master: preparate lì personaggi, mostri e avventura, poi giocatele qui.", 18, UI.DIM))
	box.add_child(UI.btn("Nuova avventura di prova", _new_example, 48))
	_modal("Scegli la campagna", UI.scroll(box) if box.get_child_count() > 8 else box)


func _new_example() -> void:
	state.save_now()
	story.save()
	_example_campaign()
	_close_modal()
	_open_story()


func _load_campaign(cid: String) -> void:
	state.save_now()
	story.save()
	if state.load_campaign(cid):
		_close_modal()
		_open_story()


func _open_diary() -> void:
	var p := ProjectSettings.globalize_path(story.dir)
	DirAccess.make_dir_recursive_absolute(story.dir)
	OS.shell_open(p)
	toast("Diario della campagna: " + p)


func _show_settings() -> void:
	var model := UI.edit(str(settings.model), Narrator.DEFAULT_MODEL, Callable(), 300)
	var tone := UI.edit(str(state.data.get("tone", "")), "es. cupo, poca luce, PNG sospettosi")
	tone.max_length = StoryImport.TONE_MAX
	var box := UI.vbox([UI.lbl("Tono dell'avventura (lo segue in ogni risposta)", 20, UI.DIM), tone,
		UI.wrap_lbl("Una riga breve e concreta: atmosfera, ritmo, come si comportano i PNG. Vale per questa campagna.", 17, UI.DIM),
		UI.lbl("Modello del narratore (Ollama, su questo PC)", 20, UI.DIM), model,
		UI.wrap_lbl("Più piccolo = più veloce ma racconta peggio. Provati: gemma4:e4b-it-q4_K_M (consigliato), qwen3.5:4b (più veloce), qwen2.5:7b. Per scaricarne uno: ollama pull nome", 17, UI.DIM)], 8)
	var opt: OptionButton = null
	var vlist := voice.voices()
	if not vlist.is_empty():
		var names: Array = []
		var sel := 0
		for i in vlist.size():
			names.append("%s (%s)" % [vlist[i].get("name", "?"), vlist[i].get("language", "")])
			if str(vlist[i].get("id", "")) == voice.voice_id:
				sel = i
		opt = UI.option(names, sel)
		box.add_child(UI.lbl("Voce del master", 20, UI.DIM))
		box.add_child(opt)
	box.add_child(UI.color_btn("Salva", Color(0.18, 0.42, 0.25), func(): _apply_settings(model, opt, vlist, tone), 50))
	_modal("Impostazioni", box, 640)


func _apply_settings(model: LineEdit, opt: OptionButton, vlist: Array, tone: LineEdit) -> void:
	if tone.text.strip_edges() != str(state.data.get("tone", "")):
		state.set_tone(tone.text)
	settings.model = model.text.strip_edges() if model.text.strip_edges() != "" else Narrator.DEFAULT_MODEL
	narrator.model = str(settings.model)
	if opt:
		settings.voice = str(vlist[opt.selected].get("id", ""))
		voice.setup(str(settings.voice))
	_save_settings()
	_close_modal()
	toast("Impostazioni salvate")


# ---------------------------------------------------------------------- feed
func add_feed(who: String, text: String, kind := "player") -> Dictionary:
	var col: Color = {"master": UI.GOLD, "player": Color(0.55, 0.75, 0.95), "combat": Color(0.9, 0.55, 0.45), "info": UI.DIM}.get(kind, UI.TEXT)
	var head := UI.lbl(who.to_upper() if kind == "master" else who, 16, col)
	var body := UI.wrap_lbl(text, 25 if kind == "master" else 21, UI.TEXT if kind != "info" else UI.DIM)
	var box := UI.vbox([head, body], 2)
	feed_box.add_child(box)
	var e := {"who": who, "text": text, "kind": kind, "node": body}
	feed.append(e)
	while feed.size() > FEED_KEEP:
		var old: Dictionary = feed.pop_front()
		if is_instance_valid(old.node):
			old.node.get_parent().queue_free()
	_feed_dirty = true
	_scroll_down.call_deferred()
	return e


func _scroll_down() -> void:
	await get_tree().process_frame
	feed_scroll.scroll_vertical = int(feed_scroll.get_v_scroll_bar().max_value)


func _set_feed_text(e: Dictionary, text: String) -> void:
	e.text = text
	if is_instance_valid(e.node):
		e.node.text = text
	_feed_dirty = true


## Sends the last lines to the phones. While a reply is being written it is
## sent as it grows (light = only the phones, not the side panel).
func _sync_phones(light := false) -> void:
	var out: Array = []
	for e in feed.slice(maxi(0, feed.size() - 8)):
		var live := is_same(e, _live)
		if str(e.text) != "" or live:
			out.append({"who": e.who, "text": e.text, "live": live})
	state.ai_feed = out
	state.ai_busy = narrator.busy and narrator.current_tag() != "prep"
	if light:
		net.broadcast_pending = true
	else:
		state.changed.emit()


func _demo_feed() -> void:
	add_feed("Master", "La pioggia batte sulle tegole della locanda del Cinghiale Zoppo. Un mercante entra fradicio e cerca qualcuno con lo sguardo: la sua carovana non è mai arrivata a valle. Cosa fate?", "master")
	add_feed("Aria", "Mi avvicino e gli chiedo dove l'ha vista l'ultima volta.", "player")
	add_feed("Goblin 1", "Goblin 1 usa Scimitarra. Bruno: colpito, 6 danni.", "combat")


# ----------------------------------------------------------------- narration
func _send_input() -> void:
	var t := input.text.strip_edges()
	if t == "":
		return
	input.text = ""
	_player_says("Il gruppo", t)


func _on_player_said(cid: String, text: String) -> void:
	_player_says(str(state.find_entity(cid).get("name", "Giocatore")), text)


func _player_says(who: String, text: String) -> void:
	add_feed(who, text, "player")
	story.add("user", who, text)
	narrate()


## Something happened at the table that the master should react to.
func _event(text: String) -> void:
	story.add("user", "Tavolo", text)
	narrate()


func narrate() -> void:
	pause_reading()
	if narrator.current_tag() == "prep":
		narrator.cancel()
	_prep_key = []
	if narrator.busy or _closing:
		_want_narration = true
		return
	_want_narration = false
	if test_mode and not llm_in_tests:
		return
	_live = add_feed("Master", "", "master")
	voice.begin()
	var filler := filler_line()
	if filler != "":
		voice.say(filler)
	narrator.ask(story.messages())
	_sync_phones()


## A filler line that suits what just happened at the table ("" = none).
func filler_line() -> String:
	if story.transcript.is_empty():
		return ""
	var last: Dictionary = story.transcript.back()
	var txt := str(last.text)
	var kind := "base"
	if state.ini().active:
		kind = "combat"
	elif str(last.who) == "Tavolo":
		if txt.begins_with("Risultato"):
			kind = "check"
		elif txt.begins_with("Inizia"):
			kind = "start"
		elif txt.begins_with("Il combattimento è finito"):
			kind = "after"
	var pool: Array = FILLERS[kind].filter(func(x): return x != _last_filler)
	_last_filler = str(pool[rng.randi_range(0, pool.size() - 1)])
	return _last_filler


func _on_chunk(piece: String) -> void:
	if _live.is_empty():
		return
	voice.feed(piece)
	var raw := str(_live.get("raw", "")) + piece
	_live["raw"] = raw
	_set_feed_text(_live, GameStory.strip_tags(raw))
	_scroll_down.call_deferred()


func _on_finished(full: String, ok: bool, tag: String) -> void:
	match tag:
		"warm":
			pass
		"chap":
			_chapter_prose = full.strip_edges() if ok else ""
			if ok:
				narrator.ask(story.campaign_summary_prompt(_chapter_prose), {"max": 420, "temp": 0.3, "tag": "camp"})
				return
			_finish_chapter("")
		"camp":
			_finish_chapter(full.strip_edges() if ok else "")
		"adapt":
			_adapt_done(full, ok)
		"prep":
			_prep_done(full, ok)
		_:
			voice.end()
			var e := _live
			_live = {}
			if e.is_empty():
				e = add_feed("Master", "", "master")
			if not ok:
				if str(e.text) == "":
					_set_feed_text(e, "(Il narratore non risponde: %s)" % narrator.status)
					e.kind = "info"
			else:
				var clean := GameStory.strip_tags(full)
				_set_feed_text(e, clean)
				story.add("assistant", "Master", clean)
				ambience.follow(clean)
				for t in GameStory.tags(full):
					_on_tag(str(t[0]), str(t[1]))
	_sync_phones()
	if _want_narration and not narrator.busy:
		narrate()
	else:
		_prepare_next()


func _on_tag(name: String, arg: String) -> void:
	match name:
		"combattimento":
			start_combat(arg)
		"prova":
			ask_check(arg)
		"fine capitolo":
			_ask_close_chapter()


# ------------------------------------------------------------------ chapters
func _ask_close_chapter() -> void:
	if _closing:
		return
	if narrator.current_tag() == "prep":
		narrator.cancel()
		_prep_key = []
	if state.ini().active:
		toast("Prima finite il combattimento")
		return
	if story.transcript.is_empty():
		toast("Il capitolo è ancora vuoto")
		return
	_closing = true
	add_feed("Tavolo", "Fine del capitolo %d: il master scrive il riassunto..." % story.chapter, "info")
	_wait_for_narrator(_summarize_chapter)


func _summarize_chapter() -> void:
	if test_mode and not llm_in_tests:
		_finish_chapter("")
	elif not narrator.ask(story.chapter_summary_prompt(), {"max": 300, "temp": 0.3, "tag": "chap"}):
		_finish_chapter("")


func _wait_for_narrator(cb: Callable) -> void:
	if not narrator.busy:
		cb.call()
		return
	_wait = 0.5
	_wait_max = 120.0
	_wait_call = func(): _wait_for_narrator(cb)


## Warns the person at the PC when the current chapter outline lacks what the
## narrator needs (toast only: the phones must not see monster names).
func _check_chapter() -> void:
	var ch := story.chapter_info()
	if ch.is_empty():
		return
	var pr := StoryImport.check({"chapters": [ch]}, StoryImport.known_monsters(state))
	if not pr.is_empty():
		toast("Capitolo %d: %s" % [story.chapter, str(pr[0].issues[0])])


# ------------------------------------------------------------- read aloud
## A chapter with "Da leggere" paragraphs starts by reading them: no wait for
## the model. Without them the narrator opens the chapter as before.
func _start_chapter(event_text: String) -> void:
	if story.reading_left():
		add_feed("Tavolo", "Il master legge l'inizio del capitolo. Premete Pausa per fermarlo, o scrivete cosa fate: il master risponde.", "info")
		start_reading()
	else:
		_event(event_text)


func start_reading() -> void:
	if _adapting:  # paused and resumed while the narrator was checking
		_reading = true
		_refresh_read_btn()
		return
	if not story.reading_left():
		return
	_reading = true
	_read_next()


## Stops the reading (a player acts, a pause, a check or a fight).
func pause_reading() -> void:
	if not _reading:
		return
	_reading = false
	voice.stop()
	_refresh_read_btn()


func _read_next() -> void:
	var paras := story.read_aloud()
	if story.read_pos >= paras.size():
		_reading = false
		_refresh_read_btn()
		add_feed("Tavolo", "Fine del testo da leggere: ora tocca a voi. Cosa fate?", "info")
		voice.say("Cosa fate?")
		_sync_phones()
		return
	var raw := str(paras[story.read_pos])
	# the players made choices since the last paragraph: the narrator decides
	# whether this one is read as written, skipped or adapted
	if story.reading_diverged():
		_adapt(raw)
		return
	_read_paragraph(raw, raw)


func _adapt(raw: String) -> void:
	var key := _reading_key()
	if not _prep.is_empty() and _prep.key == key:
		# prepared during the pause: no wait
		_adapting = true
		_adapt_raw = raw
		var ready: Dictionary = _prep
		_prep = {}
		_adapt_done(str(ready.full), bool(ready.ok))
		return
	if narrator.current_tag() == "prep" or (test_mode and _prep_key == key):
		if _prep_key == key:
			_adapting = true  # being prepared: _on_finished hands it over
			_adapt_raw = raw
			_refresh_read_btn()
			return
		narrator.cancel()
	if narrator.busy:
		return  # _reading_tick tries again when the narrator is free
	_adapting = true
	_adapt_raw = raw
	_refresh_read_btn()
	if test_mode and not llm_in_tests:
		return  # tests answer with _on_finished(..., "adapt")
	add_feed("Tavolo", "Il master adatta il prossimo testo alle vostre scelte...", "info")
	if not narrator.ask(story.adapt_messages(GameStory.strip_tags(raw)), {"max": 260, "temp": 0.4, "tag": "adapt"}):
		_adapt_done("", false)


func _adapt_done(full: String, ok: bool) -> void:
	_adapting = false
	var raw := _adapt_raw
	_adapt_raw = ""
	if not _reading or raw == "":
		_refresh_read_btn()  # paused meanwhile: the next resume asks again
		return
	var r := GameStory.parse_adapt(full) if ok else {"mode": "read", "text": ""}
	match str(r.mode):
		"skip":
			story.read_pos += 1
			story.save()
			add_feed("Tavolo", "Il master salta un pezzo del testo: le vostre scelte l'hanno cambiato.", "info")
			_read_next()  # still diverged: the next paragraph is checked too
		"text":
			_read_paragraph(raw, str(r.text))
		_:
			_read_paragraph(raw, raw)


func _reading_key() -> Array:
	return [story.read_pos, story.transcript.size()]


## While the reading is paused after the players' choices, the narrator is
## idle: it prepares the next paragraph then, so Riprendi lettura reads it at
## once. A player acting cancels it (the situation changed).
func _prepare_next() -> void:
	if _reading or _adapting or _closing or narrator.busy or _want_narration:
		return
	if not story.reading_left() or not story.reading_diverged() or state.ini().active or not checks.is_empty():
		return
	var key := _reading_key()
	if (not _prep.is_empty() and _prep.key == key) or _prep_key == key:
		return
	_prep = {}
	_prep_key = key
	if test_mode and not llm_in_tests:
		return  # tests answer with _on_finished(..., "prep")
	var raw := str(story.read_aloud()[story.read_pos])
	narrator.ask(story.adapt_messages(GameStory.strip_tags(raw)), {"max": 260, "temp": 0.4, "tag": "prep"})


func _prep_done(full: String, ok: bool) -> void:
	var key := _prep_key
	_prep_key = []
	if _adapting and _adapt_raw != "" and key == _reading_key():
		_adapt_done(full, ok)  # Riprendi lettura was pressed meanwhile
	elif ok and key == _reading_key():
		_prep = {"key": key, "full": full, "ok": ok}


## Reads one paragraph (text: as written or adapted) and moves past raw.
func _read_paragraph(raw: String, text: String) -> void:
	story.read_pos += 1
	var clean := GameStory.strip_tags(text)
	if clean != "":
		add_feed("Master", clean, "master")
		story.add("assistant", "Master", clean)
		ambience.follow(clean)
		voice.begin()
		voice.say(clean)
	story.read_mark = story.transcript.size()
	story.save()
	_read_clock = 0.0
	_read_quiet = 0.0
	_read_min = clampf(clean.split(" ", false).size() * 0.33, 2.0, 40.0)
	# a check or a fight written in the text: the players act, the reading waits
	var tags := GameStory.tags(text)
	if tags.is_empty():
		tags = GameStory.tags(raw)
	if not tags.is_empty():
		_reading = false
		for t in tags:
			_on_tag(str(t[0]), str(t[1]))
	_refresh_read_btn()
	_sync_phones()


func _reading_tick(delta: float) -> void:
	if not _reading or _adapting or narrator.busy:
		return
	_read_clock += delta
	var talking := voice.enabled and voice.available
	if talking:
		_read_quiet = 0.0 if voice.speaking() else _read_quiet + delta
		if _read_clock > 1.5 and _read_quiet > 0.8:
			_read_next()
	elif _read_clock > _read_min:
		_read_next()


func _make_read_btn() -> Button:
	btn_read = UI.btn("Riprendi lettura", _toggle_reading, 54)
	btn_read.visible = false
	return btn_read


## A phone pressed Pausa or Riprendi lettura.
func _on_player_read(cid: String, on: bool) -> void:
	var who := str(state.find_entity(cid).get("name", "Un giocatore"))
	if on and not _reading and story.reading_left():
		add_feed("Tavolo", "%s riprende la lettura." % who, "info")
		start_reading()
	elif not on and _reading:
		add_feed("Tavolo", "%s mette in pausa la lettura." % who, "info")
		pause_reading()
		_sync_phones()


func _toggle_reading() -> void:
	if _reading:
		pause_reading()
	else:
		start_reading()


func _refresh_read_btn() -> void:
	var mode := "on" if _reading else ("paused" if story.reading_left() else "")
	if mode != state.ai_reading:
		state.ai_reading = mode
		state.changed.emit()  # the phones show Pausa / Riprendi
	if btn_read == null:
		return
	btn_read.visible = _reading or story.reading_left()
	btn_read.text = "Pausa" if _reading else "Riprendi lettura"


## Picks the background sound at the start: the place of the last master
## reply, or else the place named in the chapter outline.
func _guess_place() -> void:
	for i in range(story.transcript.size() - 1, -1, -1):
		var t: Dictionary = story.transcript[i]
		if t.role == "assistant" and ambience.follow(str(t.text)) != "":
			return
	var ch := story.chapter_info()
	if not ch.is_empty():
		ambience.follow(str(ch.get("title", "")) + " " + str(ch.get("text", "")).left(1400))


func _finish_chapter(new_summary: String) -> void:
	var n := story.chapter
	var path := story.close_chapter(_chapter_prose, new_summary)
	_closing = false
	add_feed("Tavolo", "Capitolo %d salvato nel diario (%s)." % [n, path.get_file()], "info")
	if _chapter_prose != "":
		add_feed("Riassunto", _chapter_prose, "info")
	_chapter_prose = ""
	_check_chapter()
	_start_chapter("Inizia il capitolo %d. Riprendi la storia da dove si era interrotta." % story.chapter)


# --------------------------------------------------------------------- checks
## [[PROVA: Percezione CD 15: Aria]] / [[PROVA: TS Destrezza CD 13: tutti]]
func ask_check(arg: String) -> Dictionary:
	var who := ""
	var main := arg
	var parts := arg.split(":")
	if parts.size() >= 2:
		main = parts[0]
		who = ":".join(parts.slice(1)).strip_edges()
	var m := RegEx.create_from_string("(?i)^\\s*(ts|tiro salvezza)?\\s*(?:su |di )?([A-Za-zÀ-ÿ' ]+?)\\s*(?:cd|CD)\\s*([0-9]+)").search(main)
	if not m:
		return {}
	var dc := clampi(int(m.get_string(3)), 5, 30)
	var what := Actions.norm(m.get_string(2))
	var type := "free"
	var param := m.get_string(2).strip_edges()
	if m.get_string(1) != "":
		for k in Actions.ABILITY_NAMES:
			if Actions.norm(Actions.ABILITY_NAMES[k]).begins_with(what.left(4)):
				type = "save"
				param = k
	else:
		for s in Rules.SKILLS:
			if Actions.norm(s[1]) == what or s[0] == what or Actions.norm(s[1]).begins_with(what) and what.length() >= 4:
				type = "skill"
				param = s[0]
				break
	var chars: Array = []
	var nw := Actions.norm(who)
	for e in state.characters():
		if int(e.hp) <= 0:
			continue
		if nw == "" or nw.contains("tutti") or nw.contains("gruppo") or nw.contains(Actions.norm(str(e.name))):
			chars.append(str(e.id))
	if chars.is_empty():
		for e in state.characters():
			if int(e.hp) > 0:
				chars.append(str(e.id))
	if chars.is_empty():
		return {}
	var label := Rules.check_label(type, param) + " (CD %d)" % dc
	var r := state.make_request(chars, type, param, dc, "Il master chiede: " + Rules.check_label(type, param))
	checks[r.id] = {"label": label, "dc": dc, "chars": chars, "results": {}, "type": type, "param": param, "reason": r.reason}
	add_feed("Tavolo", label + ": " + ", ".join(chars.map(func(c): return str(state.find_entity(c).name))) + ". Tirate dal telefono.", "info")
	# characters without a phone roll at once
	for cid in chars:
		if not state.online_chars.has(cid):
			_auto_roll_check(r.id, cid)
	_check_done()
	return r


func _auto_roll_check(rid: String, cid: String) -> void:
	var ck: Dictionary = checks.get(rid, {})
	var req: Dictionary = state.find_request(rid)
	var e: Dictionary = state.find_entity(cid)
	if ck.is_empty() or e.is_empty() or ck.results.has(cid):
		return
	var mod := 0
	if ck.type == "skill":
		mod = Rules.skill_mod(e, str(ck.param))
	elif ck.type == "save":
		mod = Rules.save_mod(e, str(ck.param))
	var d := rng.randi_range(1, 20)
	state.add_roll({"who": e.name, "who_id": cid, "who_type": "pc", "kind": "Tiro salvezza" if ck.type == "save" else "Prova",
		"dice": [{"s": 20, "v": d, "drop": false}], "mod": mod, "adv": "none", "reason": ck.reason,
		"secret": false, "formula": "1d20%+d" % mod, "dc": int(ck.dc)})
	if not req.is_empty():
		req.done.append(cid)
		if req.done.size() >= req.chars.size():
			state.data.requests.erase(req)
		state.touch()


func _on_roll(entry: Dictionary) -> void:
	var cid := str(entry.get("who_id", ""))
	for rid in checks:
		var ck: Dictionary = checks[rid]
		if ck.chars.has(cid) and not ck.results.has(cid) and int(entry.get("dc", -1)) == int(ck.dc) and str(entry.get("kind", "")) != "Iniziativa":
			ck.results[cid] = [int(entry.total), str(entry.get("outcome", ""))]
			break
	_check_done.call_deferred()


func _check_done() -> void:
	for rid in checks.keys():
		var ck: Dictionary = checks[rid]
		if ck.results.size() < ck.chars.size():
			continue
		checks.erase(rid)
		var bits: Array = []
		for cid in ck.chars:
			var r: Array = ck.results[cid]
			bits.append("%s %d %s" % [state.find_entity(cid).get("name", "?"), int(r[0]), "riuscita" if r[1] == "success" else "fallita"])
		var txt: String = "%s: %s." % [ck.label, ", ".join(bits)]
		add_feed("Tavolo", txt, "info")
		_event("Risultato della prova. " + txt + " Racconta cosa succede.")


func _roll_missing() -> void:
	for rid in checks.keys():
		for cid in checks[rid].chars:
			_auto_roll_check(rid, cid)
	_check_done()


# --------------------------------------------------------------------- combat
## [[COMBATTIMENTO: Goblin x2, Lupo]]: the monsters come from the campaign's
## bestiary first, then from the Monster Manual list of the app.
func start_combat(arg: String) -> bool:
	if state.ini().active:
		return false
	var mons := spawn(arg)
	if mons.is_empty():
		add_feed("Tavolo", "Nessun mostro riconosciuto in \"%s\": il combattimento non parte." % arg, "info")
		return false
	var refs: Array = []
	for e in state.characters():
		if int(e.hp) > 0:
			refs.append(str(e.id))
	state.combat_start(refs + mons)
	MonsterAI.reset()
	state.roll_monster_initiative()
	for c in state.ini().combatants:
		if c.type != "pc":
			continue
		var e: Dictionary = state.find_entity(c.ref)
		var d := rng.randi_range(1, 20)
		var entry := state.add_roll({"who": e.name, "who_id": c.ref, "who_type": "pc", "kind": "Iniziativa",
			"dice": [{"s": 20, "v": d, "drop": false}], "mod": int(c.mod), "adv": "none", "reason": "Iniziativa",
			"secret": false, "formula": "1d20%+d" % int(c.mod)})
		c.score = int(entry.total)
	state.sort_combatants()
	state.next_turn()
	var order: Array = []
	for c in state.ini().combatants:
		order.append(str(c.name))
	var txt := "Combattimento! Ordine di iniziativa: " + ", ".join(order) + "."
	add_feed("Tavolo", txt, "combat")
	voice.say(txt)
	_turn_key = ""
	_ui_dirty = true
	return true


func spawn(arg: String) -> Array:
	var out: Array = []
	for part in arg.split(","):
		var p := part.strip_edges()
		if p == "":
			continue
		var count := 1
		var mx := RegEx.create_from_string("(?i)^(.*?)\\s*[x×]\\s*([0-9]+)$").search(p)
		if mx:
			p = mx.get_string(1).strip_edges()
			count = int(mx.get_string(2))
		else:
			var mn := RegEx.create_from_string("^([0-9]+)\\s+(.+)$").search(p)
			if mn:
				count = int(mn.get_string(1))
				p = mn.get_string(2).strip_edges()
		count = clampi(count, 1, 8)
		var want := Actions.norm(p)
		if want == "":
			continue
		var template: Dictionary = {}
		var got: Array = []
		for fuzzy in [false, true]:
			if not template.is_empty():
				break
			for m in state.monsters():
				var base := Actions.norm(state._base_name(str(m.name)))
				var hit: bool = base == want or (fuzzy and want.length() >= 4 and (base.contains(want) or want.contains(base)))
				if not hit:
					continue
				if template.is_empty():
					template = m
				if int(m.hp) > 0 and not state.in_combat(str(m.id)) and got.size() < count and not out.has(str(m.id)):
					got.append(str(m.id))
		if template.is_empty():
			for mm in Rules.MONSTERS:
				var it := Actions.norm(str(mm[0]).get_slice(" (", 0))
				var en := Actions.norm(str(mm[0]))
				if it == want or (want.length() >= 4 and (it.contains(want) or en.contains(want))):
					template = {"name": str(mm[0]).get_slice(" (", 0), "kind": "Mostro", "ac": int(mm[2]), "hp_max": int(mm[3]),
						"init_mod": int(mm[4]), "notes": str(mm[6]), "xp": Rules.cr_xp(str(mm[5]))}
					break
		if template.is_empty():
			template = {"name": p.left(1).to_upper() + p.substr(1), "kind": "Mostro", "ac": 12, "hp_max": 11, "init_mod": 1, "notes": "", "xp": 50}
		var base_name: String = state._base_name(str(template.name))
		while got.size() < count:
			var t := template.duplicate()
			t.hp_max = int(template.get("hp_max", 7))
			t.erase("id")
			var m2 := state.add_monster(t)
			got.append(str(m2.id))
		if count > 1:
			for i in got.size():
				state.find_entity(got[i]).name = "%s %d" % [base_name, i + 1]
		for id in got:
			state.find_entity(id).revealed = true
		out.append_array(got)
	state.touch()
	return out


func _combat_tick(delta: float) -> void:
	if _wait_call.is_valid():
		_wait -= delta
		_wait_max -= delta
		if _wait <= 0.0:
			var cb := _wait_call
			_wait_call = Callable()
			cb.call()
		return
	if not state.ini().active:
		return
	var cur: Dictionary = state.current_combatant()
	if cur.is_empty():
		return
	var key := "%d:%s" % [int(state.ini().round), str(cur.id)]
	if key == _turn_key:
		return
	_turn_key = key
	_turn_start(cur)


func _after(secs: float, cb: Callable) -> void:
	_wait = secs
	_wait_max = 30.0
	_wait_call = cb


func _turn_start(cur: Dictionary) -> void:
	var ref := str(cur.ref)
	var e: Dictionary = state.find_entity(ref)
	_ui_dirty = true
	if e.is_empty():
		state.next_turn()
		return
	if cur.type == "monster":
		if int(e.hp) <= 0:
			state.next_turn()
			return
		_after(0.4 if test_mode else 1.8, func(): _monster_turn_when_free(ref))
		return
	if int(e.hp) <= 0:
		if state.is_dead(e) or int(e.get("death_ok", 0)) >= 3:
			state.next_turn()
			return
		var d := rng.randi_range(1, 20)
		var res := state.death_save(ref, d)
		var txt := "%s è a terra: tiro salvezza contro la morte %d. %s" % [e.name, d, res]
		add_feed("Tavolo", txt, "combat")
		voice.say(txt)
		_after(0.4 if test_mode else 2.5, func(): state.next_turn())
		return
	var t2 := "Tocca a %s." % e.name
	add_feed("Tavolo", t2 + (" Scegli l'azione sul telefono, poi Fine turno." if state.online_chars.has(ref) else " Nessun telefono collegato: premete Fine turno qui quando avete finito."), "info")
	voice.say(t2)


## The monster acts once the narrator has finished speaking (or after 25 s).
func _monster_turn_when_free(ref: String) -> void:
	if narrator.busy and _wait_max > 5.0:
		_wait = 0.5
		_wait_call = func(): _monster_turn_when_free(ref)
		return
	monster_turn(ref)


func monster_turn(ref: String) -> void:
	var cur: Dictionary = state.current_combatant()
	if cur.is_empty() or str(cur.ref) != ref:
		return
	var m: Dictionary = state.find_entity(ref)
	var d := MonsterAI.choose(state, ref, rng)
	match str(d.kind):
		"skip":
			if int(m.get("hp", 0)) > 0:
				add_feed(str(m.name), "%s non può agire (%s)." % [m.name, d.why], "combat")
			state.next_turn()
		"flee":
			var txt := "%s fugge dal combattimento!" % m.name
			add_feed(str(m.name), txt, "combat")
			voice.say(txt)
			state.chronicle_add("combattimento", txt)
			state.combat_remove(str(cur.id))
			_check_end()
		"act":
			var res := Actions.resolve(state, ref, d.action, d.targets, {"adv": "auto"})
			var lines: Array = Actions.public_lines(state, res.get("lines", []))
			if not res.ok:
				lines = ["%s esita (%s)." % [m.name, res.error]]
			add_feed(str(m.name), "\n".join(lines), "combat")
			voice.say(spoken(lines))
			if not _check_end():
				_after(0.4 if test_mode else 1.5, func(): state.next_turn())


## Outcome lines as they are read aloud: the first three, without numbers in brackets.
static func spoken(lines: Array) -> String:
	var out: Array = []
	for l in lines.slice(0, 3):
		var s := str(l).strip_edges().replace("→", ",").replace(":", ",")
		out.append(s)
	return ". ".join(out) + "."


func _on_player_action(cid: String, title: String, lines: Array) -> void:
	var pub: Array = Actions.public_lines(state, lines)
	add_feed(str(state.find_entity(cid).get("name", "?")), "\n".join(pub), "combat")
	voice.say(spoken(pub))
	_check_end()


func _end_pc_turn(cid: String) -> void:
	var cur: Dictionary = state.current_combatant()
	if not state.ini().active or cur.is_empty() or str(cur.ref) != cid:
		return
	state.next_turn()


## Ends the fight when one side is down. Returns true when it ended.
func _check_end() -> bool:
	if not state.ini().active:
		return true
	var mons_up := 0
	var pcs_up := 0
	for c in state.ini().combatants:
		var e: Dictionary = state.find_entity(str(c.ref))
		if e.is_empty() or int(e.hp) <= 0:
			continue
		if c.type == "monster":
			mons_up += 1
		else:
			pcs_up += 1
	if mons_up > 0 and pcs_up > 0:
		return false
	var rounds := int(state.ini().round)
	var defeated: Array = []
	for id in state.ini().get("defeated", []):
		defeated.append(str(state.find_entity(str(id)).get("name", "")))
	state.combat_end()
	_turn_key = ""
	_wait_call = Callable()
	if pcs_up > 0:
		var txt := "Vittoria dopo %d round.%s" % [rounds, (" Sconfitti: " + ", ".join(defeated) + ".") if not defeated.is_empty() else " I nemici sono fuggiti."]
		add_feed("Tavolo", txt, "combat")
		_event("Il combattimento è finito. " + txt + " Descrivi la scena dopo la battaglia.")
	else:
		add_feed("Tavolo", "Tutti i personaggi sono a terra.", "combat")
		_event("Il combattimento è finito: tutti i personaggi sono a terra. Racconta cosa succede ora, senza decidere chi muore.")
	_ui_dirty = true
	return true


# --------------------------------------------------------------- side panel
func _refresh_side() -> void:
	lbl_campaign.text = "%s  ·  capitolo %d" % [state.data.get("name", ""), story.chapter]
	var n := net.client_list().size()
	lbl_clients.text = "%d telefoni" % n
	UI.clear(party_box)
	for e in state.characters():
		var st_txt := "%s  ·  PF %d/%d  ·  CA %d" % [state.status_of(e), int(e.hp), int(e.hp_max), int(e.ac)]
		var row := UI.vbox([UI.lbl(str(e.name) + ("  (telefono)" if state.online_chars.has(str(e.id)) else ""), 21, UI.TEXT),
			UI.lbl(st_txt, 16, UI.RED if int(e.hp) <= 0 else UI.DIM)], 0)
		party_box.add_child(row)
	UI.clear(combat_box)
	if not checks.is_empty():
		combat_box.add_child(UI.title("Prove in corso"))
		for rid in checks:
			var ck: Dictionary = checks[rid]
			var miss: Array = ck.chars.filter(func(c): return not ck.results.has(c)).map(func(c): return str(state.find_entity(c).get("name", "?")))
			combat_box.add_child(UI.wrap_lbl("%s - mancano: %s" % [ck.label, ", ".join(miss)], 17, UI.DIM))
		combat_box.add_child(UI.btn("Tira per chi manca", _roll_missing, 44))
	if not state.ini().active:
		if checks.is_empty():
			combat_box.add_child(UI.title("Nessun combattimento"))
			combat_box.add_child(UI.wrap_lbl("Quando il master fa partire uno scontro, i mostri giocano da soli e qui compare l'ordine dei turni.", 16, UI.DIM))
		return
	combat_box.add_child(UI.title("Round %d" % int(state.ini().round)))
	var cur: Dictionary = state.current_combatant()
	for c in state.ini().combatants:
		var e: Dictionary = state.find_entity(str(c.ref))
		if e.is_empty():
			continue
		var is_cur: bool = not cur.is_empty() and c.id == cur.id
		var down := int(e.hp) <= 0
		var txt := "%s %s  %s" % ["▶" if is_cur else "  ", c.name, ("a terra" if down else state.status_of(e))]
		combat_box.add_child(UI.lbl(txt, 19, UI.GOLD if is_cur else (UI.DIM if down else UI.TEXT)))
	if not cur.is_empty() and cur.type == "pc":
		var cid := str(cur.ref)
		combat_box.add_child(UI.color_btn("Fine turno di %s" % cur.name, Color(0.18, 0.42, 0.25), func(): _end_pc_turn(cid), 48))
	combat_box.add_child(UI.btn("Ferma il combattimento", _stop_combat, 40))


func _stop_combat() -> void:
	state.combat_end()
	_turn_key = ""
	_wait_call = Callable()
	add_feed("Tavolo", "Combattimento interrotto.", "info")


func _process(delta: float) -> void:
	frame += 1
	_combat_tick(delta)
	_reading_tick(delta)
	_sync_clock += delta
	# a reply being written reaches the phones about three times a second
	if _feed_dirty and _sync_clock > (0.35 if not _live.is_empty() else 0.8):
		_sync_clock = 0.0
		_feed_dirty = false
		_sync_phones(not _live.is_empty())
	if _ui_dirty:
		_ui_dirty = false
		_refresh_side()
	_save_clock += delta
	if _save_clock > 5.0:
		_save_clock = 0.0
		if state.save_pending:
			state.save_now()
	if screenshot_path != "" and frame == 90:
		var img := get_viewport().get_texture().get_image()
		img.save_png(screenshot_path)
		get_tree().quit()
