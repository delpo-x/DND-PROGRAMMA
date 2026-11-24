extends Control
## Master app: owns the game state, the local network server and the UI.

const TabDice := preload("res://scripts/tab_dice.gd")
const TabInit := preload("res://scripts/tab_init.gd")
const TabPlayers := preload("res://scripts/tab_players.gd")
const TabBestiary := preload("res://scripts/tab_bestiary.gd")
const TabQuests := preload("res://scripts/tab_quests.gd")
const TabLog := preload("res://scripts/tab_log.gd")
const TabCampaign := preload("res://scripts/tab_campaign.gd")
const TabChronicle := preload("res://scripts/tab_chronicle.gd")
const TabMap := preload("res://scripts/tab_map.gd")
const SelfTest := preload("res://scripts/self_test.gd")

var state := GameState.new()
var net := NetServer.new()
var tabs: TabContainer
var tab_dice
var tab_init
var tab_players
var tab_bestiary
var tab_quests
var tab_log
var tab_campaign
var tab_chronicle
var tab_map
var top_campaign: Label
var top_net: Label
var top_clients: Label
var btn_undo: Button
var modal_layer: Control
var toast_box: VBoxContainer
var fx_layer: Control
var ui_dirty := true
var ui_timer := 0.0
var save_timer := 0.0
var screenshot_path := ""
var selftest_path := ""
var frame := 0


func _init() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--screenshot" and i + 1 < args.size():
			screenshot_path = args[i + 1]
		elif args[i] == "--self-test" and i + 1 < args.size():
			selftest_path = args[i + 1]
	if screenshot_path != "" or selftest_path != "":
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)


func _ready() -> void:
	# Dnd The Game: same project, the app is the master (export preset with
	# the "game" feature, or --game on the command line)
	if OS.has_feature("game") or OS.get_cmdline_user_args().has("--game"):
		var game: Control = load("res://game/game_main.gd").new()
		get_parent().add_child.call_deferred(game)
		get_tree().set_current_scene.call_deferred(game)
		queue_free()
		return
	theme = UI.make_theme()
	# candlelight: warm glow in the middle, dark leather towards the edges
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.17, 0.115, 0.075))
	grad.set_color(1, Color(0.04, 0.03, 0.025))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.42)
	gt.fill_to = Vector2(1.15, 1.1)
	gt.width = 256
	gt.height = 256
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# faint leather grain over the glow
	var leather := TextureRect.new()
	leather.texture = Art.file_texture("cuoio.jpg")
	leather.stretch_mode = TextureRect.STRETCH_TILE
	leather.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	leather.modulate = Color(1, 0.9, 0.8, 0.18)
	leather.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leather.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(leather)
	var serve_for := OS.get_cmdline_user_args().find("--serve-for")
	if serve_for >= 0:
		# Test aid: serve the web pages on this PC only for N seconds, then quit.
		var secs := float(OS.get_cmdline_user_args()[serve_for + 1])
		get_tree().create_timer(secs).timeout.connect(get_tree().quit)
		state.roll_added.connect(func(e): print("[roll] %s %s %s = %d" % [e.who, e.reason, str(e.dice), int(e.total)]))
	var headless := screenshot_path != "" or selftest_path != "" or serve_for >= 0
	if headless:
		state.persist = false
	else:
		DisplayServer.screen_set_keep_on(true)
		get_tree().set_auto_accept_quit(false)
	if headless or not state.load_last():
		_make_example_campaign()
	net.setup(state)
	add_child(net)
	net.start("127.0.0.1" if headless else "*")
	_build_ui()
	state.changed.connect(_on_state_changed)
	net.clients_changed.connect(_on_state_changed)
	net.player_message.connect(toast)
	net.player_action.connect(func(cid, title, lines): tab_init.panel.show_result(cid, title, lines))
	state.notice.connect(toast)
	state.map_event.connect(func(title, lines): toast(title + ": " + " ".join(lines)))
	state.roll_added.connect(_on_roll_toast)
	_refresh_all()
	if selftest_path != "":
		var st = SelfTest.new()
		add_child(st)
		st.run(self, selftest_path)
	elif screenshot_path != "":
		var args := OS.get_cmdline_user_args()
		var ti := args.find("--tab")
		if ti >= 0 and ti + 1 < args.size():
			tabs.current_tab = int(args[ti + 1])
			if args.has("--qr"):
				show_qr()
		else:
			tab_dice.preset_demo()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		state.save_now()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		state.save_now()


func _make_example_campaign() -> void:
	state.new_campaign("La mia prima campagna")
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
	state.add_monster({"name": "Goblin", "ac": 15, "hp": 7, "init_mod": 2, "notes": "Scimitarra +4, 1d6+2", "revealed": true})
	state.add_monster({"name": "Capo goblin", "ac": 17, "hp": 21, "init_mod": 1, "notes": "Nascosto nella caverna", "revealed": false})
	var q := state.add_quest("La caverna dei goblin", "Ritrovare la carovana scomparsa sulla strada del nord.", false)
	state.add_check(q.id, "skill", "sopravvivenza", 12, false, "")
	state.add_check(q.id, "skill", "percezione", 15, true, "")
	state.save_now()


# --------------------------------------------------------------------- UI
func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	var bar_panel := UI.card(bar, Color(0.1, 0.07, 0.055, 0.92), 10)
	root.add_child(bar_panel)
	var logo_tex := Art.file_texture("logo.png")
	if logo_tex:
		var logo := TextureRect.new()
		logo.texture = logo_tex
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(36.0 * logo_tex.get_width() / logo_tex.get_height(), 36)
		bar.add_child(logo)
	bar.add_child(UI.engrave(UI.lbl("MASTER", 18 if logo_tex else 26, UI.GOLD)))
	top_campaign = UI.lbl("", 20)
	UI.engrave(top_campaign)
	top_campaign.clip_text = true
	top_campaign.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_campaign.custom_minimum_size = Vector2(120, 0)
	bar.add_child(top_campaign)
	bar.add_child(UI.spacer())
	top_clients = UI.lbl("", 16, UI.DIM)
	top_net = UI.lbl("", 16, UI.TEXT)
	var info := UI.vbox([top_net, top_clients], 0)
	bar.add_child(info)
	btn_undo = UI.btn("Annulla", _undo, 50)
	btn_undo.tooltip_text = "Annulla l'ultima modifica (Ctrl+Z)"
	bar.add_child(btn_undo)
	bar.add_child(UI.engrave(UI.color_btn("QR Giocatori", Color(0.36, 0.25, 0.1), show_qr, 50)))
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.tab_focus_mode = Control.FOCUS_NONE
	root.add_child(tabs)
	tab_dice = TabDice.new()
	tab_init = TabInit.new()
	tab_players = TabPlayers.new()
	tab_bestiary = TabBestiary.new()
	tab_quests = TabQuests.new()
	tab_log = TabLog.new()
	tab_campaign = TabCampaign.new()
	tab_chronicle = TabChronicle.new()
	tab_map = TabMap.new()
	var pairs := [[tab_dice, "Dadi"], [tab_init, "Iniziativa"], [tab_map, "Mappa"], [tab_players, "Giocatori"], [tab_bestiary, "Bestiario"],
		[tab_quests, "Missioni"], [tab_log, "Tiri"], [tab_chronicle, "Cronaca"], [tab_campaign, "Campagne"]]
	for p in pairs:
		p[0].name = p[1]
		tabs.add_child(p[0])
		p[0].setup(self)
	tabs.tab_changed.connect(func(_i): ui_dirty = true)
	modal_layer = Control.new()
	modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_layer)
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	toast_box.position = Vector2(-300, -140)
	toast_box.custom_minimum_size = Vector2(600, 0)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	add_child(toast_box)
	fx_layer = Control.new()
	fx_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fx_layer)


## Animated banner announcing whose turn it is (drops in, holds, fades out).
func turn_banner(title_text: String, sub: String, img_key := "") -> void:
	for c in fx_layer.get_children():
		c.queue_free()
	var row := UI.hbox([], 16)
	if img_key != "":
		row.add_child(Art.avatar(img_key, 96))
	var sub_l := UI.lbl(sub.to_upper(), 16, UI.DIM)
	var name_l := UI.engrave(UI.lbl(title_text, 40, UI.GOLD))
	row.add_child(UI.vbox([sub_l, name_l], 0))
	var card := UI.card(row, Color(0.17, 0.11, 0.06, 0.97), 16)
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
	sb.border_color = UI.GOLD
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0.86, 0.69, 0.38, 0.35)
	sb.shadow_size = 18
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_layer.add_child(card)
	await get_tree().process_frame
	if not is_instance_valid(card):
		return
	var w := card.get_combined_minimum_size()
	card.size = w
	var end_pos := Vector2((size.x - w.x) / 2, size.y * 0.2)
	card.position = end_pos - Vector2(0, 40)
	card.pivot_offset = w / 2
	card.scale = Vector2(0.85, 0.85)
	card.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "position", end_pos, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.25)
	tw.chain().tween_interval(1.6)
	tw.chain().tween_property(card, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(card.queue_free)


func goto_tab(node: Control) -> void:
	tabs.current_tab = node.get_index()


func _on_state_changed() -> void:
	ui_dirty = true


func _refresh_all() -> void:
	top_campaign.text = "%s  -  Sessione %d" % [state.data.get("name", ""), int(state.data.get("session", 1))]
	if net.running:
		top_net.text = net.base_url()
	else:
		top_net.text = "Server non attivo"
	var players := 0
	var screens := 0
	for c in net.client_list():
		if c.role == "screen":
			screens += 1
		elif c.role == "player":
			players += 1
	top_clients.text = "Telefoni: %d   Schermi: %d" % [players, screens]
	var cur = tabs.get_current_tab_control()
	if cur and cur.has_method("refresh"):
		cur.refresh()


## A tap anywhere outside a number field being typed in confirms it first:
## buttons don't take the focus, so without this a damage amount or an
## initiative score typed without pressing Enter would be ignored.
func _undo() -> void:
	if not state.undo():
		toast("Niente da annullare")


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_Z and (event as InputEventKey).ctrl_pressed 			and not _typing():
		_undo()
		get_viewport().set_input_as_handled()
		return
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		pos = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch:
		pos = (event as InputEventScreenTouch).position
	else:
		return
	var fo := get_viewport().gui_get_focus_owner()
	if fo is LineEdit and fo.get_parent() is SpinBox:
		var sb := fo.get_parent() as SpinBox
		if not sb.get_global_rect().has_point(pos):
			sb.apply()
			fo.release_focus()


## True while the master is typing in a field of the open tab: the tab is
## not rebuilt then, or what is being typed would be lost.
func _typing() -> bool:
	var fo := get_viewport().gui_get_focus_owner()
	return (fo is LineEdit or fo is TextEdit) and tabs.is_ancestor_of(fo)


func _process(delta: float) -> void:
	frame += 1
	state.undo_tick()
	if btn_undo:
		btn_undo.disabled = not state.can_undo()
	ui_timer += delta
	if ui_dirty and ui_timer > 0.15 and not _typing():
		ui_dirty = false
		ui_timer = 0.0
		_refresh_all()
	if state.save_pending:
		save_timer += delta
		if save_timer > 1.0:
			save_timer = 0.0
			state.save_now()
	if screenshot_path != "" and frame == 120:
		_take_screenshot()


func _take_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(screenshot_path.get_base_dir())
	img.save_png(screenshot_path)
	get_tree().quit()


func _on_roll_toast(e: Dictionary) -> void:
	if e.who_type == "pc":
		var txt := "%s: %s = %d" % [e.who, e.reason if str(e.reason) != "" else e.kind, int(e.total)]
		if e.outcome == "success":
			txt += "  (RIUSCITA)"
		elif e.outcome == "fail":
			txt += "  (FALLITA)"
		if bool(e.get("inspired", false)):
			txt += "  + ispirazione"
		toast(txt)


func toast(text: String) -> void:
	var l := UI.lbl(text, 22, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var c := UI.card(l, Color(0.25, 0.17, 0.08, 0.95), 12)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(c)
	var tw := create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(c, "modulate:a", 0.0, 0.6)
	tw.tween_callback(c.queue_free)


# ------------------------------------------------------------------ modal
func show_modal(title_text: String, content: Control, buttons: Array = [], width := 760) -> void:
	close_modal()
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.add_child(center)
	var box := UI.vbox([], 12)
	var panel := UI.card(box, UI.PANEL, 18)
	var vp := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(mini(width, int(vp.x) - 40), 0)
	center.add_child(panel)
	box.add_child(UI.title(title_text))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, mini(int(vp.y) - 220, maxi(120, int(content.get_combined_minimum_size().y) + 10)))
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	box.add_child(sc)
	var row := UI.hbox([UI.spacer()], 12)
	for b in buttons:
		var cb: Callable = b[1]
		var col: Color = b[2] if b.size() > 2 else UI.PANEL2
		row.add_child(UI.color_btn(b[0], col, cb, 56))
	if buttons.is_empty():
		row.add_child(UI.color_btn("Chiudi", UI.PANEL2, close_modal, 56))
	box.add_child(row)


func close_modal() -> void:
	UI.clear(modal_layer)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


func confirm(text: String, on_yes: Callable) -> void:
	show_modal("Conferma", UI.wrap_lbl(text, 22), [
		["Annulla", close_modal],
		["Conferma", _confirm_yes.bind(on_yes), UI.RED],
	], 560)


func _confirm_yes(on_yes: Callable) -> void:
	close_modal()
	on_yes.call()


# ------------------------------------------------------------- PDF import
## On Android the system picker hands back a path in the shared storage,
## which the app can only read with "all files" access. Returns true when
## files can be read; otherwise asks for the permission (Android opens its
## settings page) and tells the master to press the button again.
func file_access_ok() -> bool:
	if OS.get_name() != "Android":
		return true
	var granted := OS.get_granted_permissions()
	if granted.has("android.permission.MANAGE_EXTERNAL_STORAGE") or granted.has("android.permission.READ_EXTERNAL_STORAGE"):
		return true
	OS.request_permissions()
	toast("Consenti all'app l'accesso ai file, poi torna qui e premi di nuovo il pulsante")
	return false


## System file picker shared by every import button; calls on_path(path).
## On Android the type filters are left out: the picker there greys out files
## whose type it doesn't recognise (a .json saved in Download, say). The
## content is checked anyway by whoever reads the file.
func open_file_dialog(title_text: String, filter: String, on_path: Callable, save := false, default_name := "") -> void:
	if not file_access_ok():
		return
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.title = title_text
	if save:
		fd.current_file = default_name
	if OS.get_name() != "Android":
		fd.filters = PackedStringArray([filter])
	fd.size = Vector2i(900, 600)
	add_child(fd)
	fd.file_selected.connect(func(path: String):
		fd.queue_free()
		on_path.call(path))
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered()


## Bytes of a picked file; empty with a message when it can't be read.
func read_picked(path: String) -> PackedByteArray:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		var hint := " (controlla che l'app abbia l'accesso ai file nelle impostazioni di Android)" if OS.get_name() == "Android" else ""
		toast("Impossibile leggere %s%s" % [path.get_file(), hint])
	return bytes


## Opens the system file picker for a PDF and calls on_bytes(bytes, file_name).
func pick_pdf(title_text: String, on_bytes: Callable) -> void:
	open_file_dialog(title_text, "*.pdf ; Documenti PDF", func(path: String):
		var bytes := read_picked(path)
		if bytes.is_empty():
			return
		# the header may follow a few bytes of junk (allowed in the first 1 KB)
		if bytes.slice(0, 1024).get_string_from_ascii().find("%PDF-") < 0:
			toast("%s non è un PDF" % path.get_file())
			return
		on_bytes.call(bytes, path.get_file()))


## Picks a PNG, JPG or WebP picture and calls on_image(image, file_name).
func pick_image(title_text: String, on_image: Callable) -> void:
	open_file_dialog(title_text, "*.png, *.jpg, *.jpeg, *.webp ; Immagini", func(path: String):
		var bytes := read_picked(path)
		if bytes.is_empty():
			return
		var img := Image.new()
		var ok := img.load_png_from_buffer(bytes) == OK or img.load_jpg_from_buffer(bytes) == OK or img.load_webp_from_buffer(bytes) == OK
		if not ok:
			toast("Immagine non leggibile (servono PNG, JPG o WebP)")
			return
		on_image.call(img, path.get_file()))


## Saves text to a file the master picks (export of chronicle / campaign).
func save_text_file(title_text: String, default_name: String, filter: String, text: String) -> void:
	open_file_dialog(title_text, filter, func(path: String):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			toast("Impossibile scrivere il file")
			return
		f.store_string(text)
		f.close()
		toast("Salvato: %s" % path.get_file()), true, default_name)


## Lets the master pick a text file and hands back its content.
func pick_text_file(title_text: String, filter: String, on_text: Callable) -> void:
	open_file_dialog(title_text, filter, func(path: String):
		var bytes := read_picked(path)
		if not bytes.is_empty():
			on_text.call(bytes.get_string_from_utf8()))


## Reads a PDF into text; returns {} and shows a message on failure.
func read_pdf(bytes: PackedByteArray) -> Dictionary:
	var doc := PdfText.extract(bytes)
	if str(doc.error) != "" and doc.pages.is_empty():
		toast(str(doc.error))
		return {}
	var chars := 0
	for pg in doc.pages:
		chars += pg.chunks.size()
	if chars == 0:
		toast("Nel PDF non c'è testo leggibile (forse è una scansione)")
		return {}
	return doc


# --------------------------------------------------------------------- QR
func show_qr() -> void:
	var box := UI.vbox([], 14)
	if not net.running:
		box.add_child(UI.wrap_lbl("Il server locale non è partito: controlla che nessun'altra app usi le porte 8080-8381.", 22, UI.RED))
	var base := net.base_url()
	var row := UI.hbox([], 30)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for pair in [["GIOCATORI", base + "/giocatore"], ["SCHERMO CONDIVISO", base + "/schermo"]]:
		var col := UI.vbox([], 8)
		var t := UI.lbl(pair[0], 24, UI.GOLD)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(t)
		var tex := TextureRect.new()
		tex.texture = qr_texture(pair[1])
		tex.custom_minimum_size = Vector2(300, 300)
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		col.add_child(tex)
		var u := UI.lbl(pair[1], 20)
		u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(u)
		row.add_child(col)
	box.add_child(row)
	box.add_child(UI.wrap_lbl("I giocatori si collegano alla stessa rete Wi-Fi del tablet e inquadrano il codice con la fotocamera del telefono (Safari o Chrome). Non serve installare nulla.", 20, UI.DIM))
	var ips := NetServer.local_ips()
	if ips.size() > 1:
		box.add_child(UI.wrap_lbl("Altri indirizzi di questo dispositivo: " + ", ".join(ips.slice(1)), 18, UI.DIM))
	if ips.is_empty():
		box.add_child(UI.wrap_lbl("Nessuna rete Wi-Fi trovata: collega il tablet al Wi-Fi (o attiva l'hotspot).", 20, UI.RED))
	show_modal("Collega i giocatori", box, [], 900)


func qr_texture(text: String) -> ImageTexture:
	var q := QR.encode(text)
	var border := 3
	var scale := 8
	var n := q.size + border * 2
	var img := Image.create(n * scale, n * scale, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	for y in q.size:
		for x in q.size:
			if q.get_module(x, y):
				img.fill_rect(Rect2i((x + border) * scale, (y + border) * scale, scale, scale), Color.BLACK)
	return ImageTexture.create_from_image(img)
