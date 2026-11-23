extends VBoxContainer
## Full roll log (public and secret) with filters and CSV export.

var app
var who_opt: OptionButton
var who_vals: Array = ["*"]
var kind_opt: OptionButton
var vis_opt: OptionButton
var list: VBoxContainer
var info_lbl: Label
const SHOW_MAX := 300


func setup(a) -> void:
	app = a
	who_opt = UI.option(["Tutti"], 0, func(_i): refresh(), 240)
	var kinds: Array = ["Tutti i tipi"] + Rules.KINDS
	kind_opt = UI.option(kinds, 0, func(_i): refresh(), 200)
	vis_opt = UI.option(["Pubblici e segreti", "Solo pubblici", "Solo segreti"], 0, func(_i): refresh(), 230)
	add_child(UI.flow([UI.lbl("Chi", 18, UI.DIM), who_opt, UI.lbl("Tipo", 18, UI.DIM), kind_opt, vis_opt, UI.spacer(),
		UI.color_btn("Esporta CSV", Color(0.2, 0.36, 0.6), _export, 52)]))
	info_lbl = UI.wrap_lbl("", 17, UI.DIM)
	add_child(info_lbl)
	list = UI.vbox([], 4)
	add_child(UI.scroll(list))


func refresh() -> void:
	var st: GameState = app.state
	var cur: String = who_vals[who_opt.selected] if who_opt.selected >= 0 and who_opt.selected < who_vals.size() else "*"
	var names := {}
	for e in st.data.log:
		names[str(e.who)] = true
	who_opt.clear()
	who_vals = ["*"]
	who_opt.add_item("Tutti")
	var sorted_names: Array = names.keys()
	sorted_names.sort()
	for n in sorted_names:
		who_vals.append(n)
		who_opt.add_item(n)
	who_opt.select(maxi(0, who_vals.find(cur)))
	cur = who_vals[who_opt.selected]
	var kind: String = "*" if kind_opt.selected == 0 else Rules.KINDS[kind_opt.selected - 1]
	UI.clear(list)
	var shown := 0
	var lg: Array = st.data.log
	for i in range(lg.size() - 1, -1, -1):
		var e: Dictionary = lg[i]
		if cur != "*" and str(e.who) != cur:
			continue
		if kind != "*" and e.kind != kind:
			continue
		if vis_opt.selected == 1 and e.secret:
			continue
		if vis_opt.selected == 2 and not e.secret:
			continue
		list.add_child(_row(e))
		shown += 1
		if shown >= SHOW_MAX:
			break
	if shown == 0:
		list.add_child(UI.wrap_lbl("Nessun tiro registrato con questi filtri.", 20, UI.DIM))
	info_lbl.text = "%d tiri in totale. I giocatori vedono solo i tiri pubblici; al posto dei tiri segreti leggono \"Il master ha tirato in segreto\"." % lg.size()


func _row(e: Dictionary) -> Control:
	var dice: Array = []
	for d in e.dice:
		dice.append(("[%d]" if d.drop else "%d") % int(d.v))
	var row := UI.hbox([], 10)
	var t := UI.lbl(str(e.time), 18, UI.DIM)
	t.custom_minimum_size = Vector2(90, 0)
	row.add_child(t)
	var who := UI.lbl(str(e.who), 20, Color.WHITE)
	who.custom_minimum_size = Vector2(150, 0)
	row.add_child(who)
	var k := UI.lbl(str(e.kind), 18, UI.GOLD)
	k.custom_minimum_size = Vector2(120, 0)
	row.add_child(k)
	row.add_child(UI.wrap_lbl("%s   dadi: %s%s" % [e.formula, " ".join(dice), ("   motivo: %s" % e.reason) if str(e.reason) != "" else ""], 18))
	if int(e.nat) == 20:
		row.add_child(UI.lbl("20 NAT.", 18, UI.GOLD))
	elif int(e.nat) == 1:
		row.add_child(UI.lbl("1 NAT.", 18, UI.RED))
	if e.outcome != "":
		row.add_child(UI.lbl(("RIUSCITA" if e.outcome == "success" else "FALLITA") + " (CD %d)" % int(e.dc), 18, UI.GREEN if e.outcome == "success" else UI.RED))
	var tot := UI.lbl(str(int(e.total)), 28, Color.WHITE)
	tot.custom_minimum_size = Vector2(60, 0)
	tot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(tot)
	if bool(e.get("manual", false)):
		row.add_child(UI.lbl("dadi veri", 16, UI.GOLD))
	row.add_child(UI.lbl("SEGRETO" if e.secret else "pubblico", 16, UI.RED if e.secret else UI.DIM))
	return UI.card(row, Color(0.2, 0.1, 0.1) if e.secret else UI.PANEL, 8)


func export_csv() -> String:
	var st: GameState = app.state
	var csv := st.log_csv()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var fname := "registro_%s.csv" % stamp
	var dirs: Array = []
	if OS.get_name() == "Android":
		dirs.append(OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS))
	else:
		dirs.append(OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS))
	dirs.append(ProjectSettings.globalize_path("user://export"))
	for d in dirs:
		if str(d) == "":
			continue
		DirAccess.make_dir_recursive_absolute(d)
		var path: String = "%s/%s" % [d, fname]
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
			f.store_string(csv)
			f.close()
			return path
	return ""


func _export() -> void:
	var path := export_csv()
	var url: String = "%s/csv/%s.csv" % [app.net.base_url(), app.state.data.csv_token]
	var box := UI.vbox([], 10)
	if path != "":
		box.add_child(UI.wrap_lbl("File salvato in:\n%s" % path, 20))
	else:
		box.add_child(UI.wrap_lbl("Non è stato possibile salvare il file su questo dispositivo.", 20, UI.RED))
	box.add_child(UI.wrap_lbl("Puoi anche scaricarlo da un PC sulla stessa rete Wi-Fi aprendo questo indirizzo (link privato del master, contiene anche i tiri segreti):", 18, UI.DIM))
	box.add_child(UI.lbl(url, 20, UI.GOLD))
	var tex := TextureRect.new()
	tex.texture = app.qr_texture(url)
	tex.custom_minimum_size = Vector2(220, 220)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(tex)
	box.add_child(UI.btn("Copia il registro negli appunti", _copy, 52))
	app.show_modal("Esporta registro (CSV)", box)


func _copy() -> void:
	DisplayServer.clipboard_set(app.state.log_csv())
	app.toast("Registro copiato")
