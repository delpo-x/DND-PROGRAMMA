extends VBoxContainer
## Battle maps: a picture (from a PDF or an image file) with its square grid,
## and one piece per character or monster that moves square by square like
## checkers. The map marked "in gioco" is shown on the shared screen and on
## the phones, where each player can move their own piece.

var app
var map_opt: OptionButton
var show_btn: Button
var cell_spin: SpinBox
var ox_spin: SpinBox
var oy_spin: SpinBox
var grid_chk: CheckBox
var view: MapView
var side: VBoxContainer
var empty_lbl: Label
var body: HBoxContainer
var cur_id := ""
var _map_ids: Array = []
var _sig := ""


func setup(a) -> void:
	app = a
	map_opt = UI.option([], 0, _on_pick, 260)
	show_btn = UI.btn("Mostra ai giocatori", _toggle_show, 48)
	add_child(UI.flow([
		map_opt,
		UI.color_btn("Da PDF…", Color(0.36, 0.25, 0.1), _import_pdf, 48),
		UI.color_btn("Da immagine…", Color(0.36, 0.25, 0.1), _import_image, 48),
		show_btn,
		UI.btn("Rinomina", _rename, 48),
		UI.color_btn("Elimina", Color(0.35, 0.12, 0.1), _delete, 48),
	]))
	cell_spin = _fspin(4, 1000, 0.25, func(v): _set_grid("cell", v))
	ox_spin = _fspin(-1000, 1000, 0.5, func(v): _set_grid("ox", v))
	oy_spin = _fspin(-1000, 1000, 0.5, func(v): _set_grid("oy", v))
	grid_chk = UI.check("Griglia visibile", true, func(on): if cur_id != "": app.state.update_map(cur_id, {"grid": on}))
	add_child(UI.flow([
		UI.lbl("Lato casella (px)", 18, UI.DIM), cell_spin,
		UI.lbl("Inizio X", 18, UI.DIM), ox_spin, UI.lbl("Y", 18, UI.DIM), oy_spin,
		UI.btn("Rileva griglia", _detect, 48), grid_chk,
		UI.check("Segna terreno difficile", false, func(on): view.paint_difficult = on),
		UI.btn("−", func(): view.zoom_by(1.0 / 1.25), 48, 48), UI.btn("+", func(): view.zoom_by(1.25), 48, 48),
		UI.btn("Adatta", func(): view.fit(), 48),
	]))
	body = UI.hbox([], 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view = MapView.new()
	view.app = app
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.clip_contents = true
	body.add_child(view)
	side = UI.vbox([], 6)
	var sc := UI.scroll(side)
	sc.custom_minimum_size = Vector2(300, 0)
	sc.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(sc)
	add_child(body)
	empty_lbl = UI.wrap_lbl("Nessuna mappa. Importa una mappa da un PDF (le mappe sono immagini dentro il PDF) o da un'immagine PNG/JPG, " +
		"poi controlla che la griglia combaci con le caselle e metti le pedine.", 20, UI.DIM)
	add_child(empty_lbl)


func _fspin(minv: float, maxv: float, step: float, cb: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.custom_minimum_size = Vector2(120, 48)
	s.select_all_on_focus = true
	s.value_changed.connect(cb)
	return s


func refresh() -> void:
	var st: GameState = app.state
	var maps: Array = st.data.get("maps", [])
	if cur_id != "" and st.find_map(cur_id).is_empty():
		cur_id = ""
	if cur_id == "" and maps.size() > 0:
		cur_id = str(st.data.map_active) if str(st.data.map_active) != "" else str(maps[-1].id)
	# map picker (rebuilt only when the list changes)
	var ids: Array = maps.map(func(m): return str(m.id) + "|" + str(m.name))
	if ids != _map_ids:
		_map_ids = ids
		map_opt.clear()
		for m in maps:
			map_opt.add_item(str(m.name))
	for i in maps.size():
		if maps[i].id == cur_id:
			map_opt.select(i)
	var mp := st.find_map(cur_id)
	var has := not mp.is_empty()
	body.visible = has
	empty_lbl.visible = not has
	map_opt.disabled = not has
	var live: bool = has and str(st.data.map_active) == cur_id
	show_btn.text = "In gioco ✔ (togli)" if live else "Mostra ai giocatori"
	show_btn.modulate = Color(0.6, 1.0, 0.6) if live else Color.WHITE
	if has:
		cell_spin.set_value_no_signal(float(mp.cell))
		ox_spin.set_value_no_signal(float(mp.ox))
		oy_spin.set_value_no_signal(float(mp.oy))
		grid_chk.set_pressed_no_signal(bool(mp.grid))
	view.set_map(mp)
	_refresh_side(mp)


func _refresh_side(mp: Dictionary) -> void:
	var st: GameState = app.state
	var on := {}
	if not mp.is_empty():
		for t in mp.tokens:
			on[t.ref] = true
	# rebuild only when something shown here changed
	var sig := str(cur_id) + str(on.keys()) + str(view.selected)
	for e in st.characters() + st.monsters():
		sig += str(e.id) + str(e.name) + str(e.get("revealed", true))
	if sig == _sig:
		return
	_sig = sig
	UI.clear(side)
	if mp.is_empty():
		return
	side.add_child(UI.lbl("Pedine", 22, UI.GOLD))
	side.add_child(UI.wrap_lbl("Trascina le pedine sulle caselle. Rotellina o +/− per lo zoom, trascina il vuoto per spostare la mappa. Tasto destro su una pedina = togli.", 15, UI.DIM))
	if not st.characters().is_empty():
		side.add_child(UI.btn("Metti tutto il gruppo", _place_party, 44))
	for e in st.characters() + st.monsters():
		var ref: String = e.id
		var pc := st.is_pc(ref)
		var nm := str(e.name)
		if not pc and not bool(e.get("revealed", false)):
			nm += " (nascosto)"
		var l := UI.lbl(nm, 18, Color(0.6, 0.75, 1.0) if pc else Color(1.0, 0.6, 0.55))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		var b: Button
		if on.has(ref):
			b = UI.btn("Togli", func(): st.remove_token(cur_id, ref), 40, 80)
		else:
			b = UI.btn("Metti", func(): _place(ref), 40, 80)
		var row := UI.hbox([l, b], 6)
		if ref == view.selected:
			side.add_child(UI.card(row, Color(0.3, 0.24, 0.1), 4))
		else:
			side.add_child(row)


func _place(ref: String) -> void:
	var c := view.center_square()
	var p: Vector2i = app.state.free_square(cur_id, c.x, c.y)
	if p.x < 0:
		app.toast("La mappa è piena")
		return
	app.state.place_token(cur_id, ref, p.x, p.y)
	view.selected = ref


func _place_party() -> void:
	for ch in app.state.characters():
		var on := false
		for t in app.state.find_map(cur_id).tokens:
			if t.ref == ch.id:
				on = true
		if not on:
			_place(ch.id)


func _on_pick(i: int) -> void:
	var maps: Array = app.state.data.get("maps", [])
	if i >= 0 and i < maps.size():
		cur_id = maps[i].id
		view.fit_next = true
		refresh()


func _toggle_show() -> void:
	if cur_id == "":
		return
	var st: GameState = app.state
	st.set_map_active("" if str(st.data.map_active) == cur_id else cur_id)


func _set_grid(k: String, v: float) -> void:
	if cur_id != "":
		app.state.update_map(cur_id, {k: v})


func _detect() -> void:
	var mp: Dictionary = app.state.find_map(cur_id)
	if mp.is_empty():
		return
	var img := Image.load_from_file(GameState.map_path(mp.file))
	var g := MapGrid.detect(img)
	if g.is_empty():
		app.toast("Griglia non trovata: imposta a mano il lato della casella")
		return
	app.state.update_map(cur_id, {"cell": g.cell, "ox": g.ox, "oy": g.oy, "grid": true})
	var n := GameState.map_size(app.state.find_map(cur_id))
	app.toast("Griglia trovata: %d × %d caselle" % [n.x, n.y])


func _rename() -> void:
	var mp: Dictionary = app.state.find_map(cur_id)
	if mp.is_empty():
		return
	var e := UI.edit(str(mp.name), "Nome della mappa")
	app.show_modal("Rinomina mappa", e, [
		["Annulla", app.close_modal],
		["Salva", func():
			app.state.update_map(cur_id, {"name": e.text})
			app.close_modal(), Color(0.18, 0.48, 0.25)],
	])


func _delete() -> void:
	if cur_id == "":
		return
	var id := cur_id
	app.confirm("Eliminare la mappa \"%s\" e le sue pedine?" % app.state.find_map(id).name, func():
		app.state.delete_map(id)
		cur_id = "")


# ------------------------------------------------------------------ import
func _added(mp: Dictionary) -> void:
	if mp.is_empty():
		app.toast("Impossibile salvare la mappa")
		return
	cur_id = mp.id
	view.fit_next = true
	var n := GameState.map_size(mp)
	if bool(mp.get("auto_grid", false)):
		app.toast("Mappa importata: griglia di %d × %d caselle trovata" % [n.x, n.y])
	else:
		app.toast("Mappa importata: griglia non trovata, regola il lato della casella")
	refresh()


func _import_image() -> void:
	app.pick_image("Scegli l'immagine della mappa", func(img: Image, fname: String):
		_added(app.state.add_map(fname.get_basename().replace("_", " "), img)))


func _import_pdf() -> void:
	app.pick_pdf("Scegli il PDF con la mappa", func(bytes: PackedByteArray, fname: String):
		var r := PdfImages.list(bytes)
		if str(r.error) != "":
			app.toast(str(r.error))
			return
		var imgs: Array = r.images
		if imgs.is_empty():
			app.toast("Nessuna immagine grande nel PDF: se la mappa è disegnata a linee, importa uno screenshot")
			return
		_pdf_chooser(bytes, fname, imgs.slice(0, 12)))


## Grid of thumbnails of the biggest pictures of the PDF: a tap imports one.
func _pdf_chooser(bytes: PackedByteArray, fname: String, imgs: Array) -> void:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	for it in imgs:
		var img := PdfImages.decode(bytes, it.ref)
		if img == null:
			continue
		var th: Image = img.duplicate()
		var f := 180.0 / maxf(th.get_width(), th.get_height())
		th.resize(maxi(1, int(th.get_width() * f)), maxi(1, int(th.get_height() * f)), Image.INTERPOLATE_BILINEAR)
		var b := Button.new()
		b.icon = ImageTexture.create_from_image(th)
		b.text = "Pag. %d  %d×%d" % [it.page, it.w, it.h]
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(190, 230)
		b.focus_mode = Control.FOCUS_NONE
		var page: int = it.page
		b.pressed.connect(func():
			app.close_modal()
			_added(app.state.add_map("%s p.%d" % [fname.get_basename().replace("_", " "), page], img)))
		g.add_child(b)
	if g.get_child_count() == 0:
		app.toast("Le immagini di questo PDF sono in un formato non supportato: importa uno screenshot")
		return
	var sc := UI.scroll(g)
	sc.custom_minimum_size = Vector2(0, 520)
	app.show_modal("Quale immagine è la mappa?", sc, [["Annulla", app.close_modal]], 860)


# ------------------------------------------------------------------ view
class MapView extends Control:
	var app
	var mp: Dictionary = {}
	var tex: Texture2D
	var tex_file := ""
	var zoom := 1.0
	var pan := Vector2.ZERO
	var fit_next := true
	var selected := ""
	var drag_ref := ""
	var drag_pos := Vector2.ZERO
	var panning := false
	var moved := 0.0
	var paint_difficult := false  # a click marks or clears difficult terrain

	func set_map(m: Dictionary) -> void:
		mp = m
		if mp.is_empty():
			tex = null
			tex_file = ""
		elif str(mp.file) != tex_file:
			tex_file = str(mp.file)
			var img := Image.load_from_file(GameState.map_path(tex_file))
			tex = ImageTexture.create_from_image(img) if img else null
			fit_next = true
		if fit_next and size.x > 10:
			fit()
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and fit_next and not mp.is_empty():
			fit()

	func fit() -> void:
		if mp.is_empty() or size.x < 10:
			return
		fit_next = false
		zoom = minf(size.x / float(mp.w), size.y / float(mp.h))
		pan = (size - Vector2(float(mp.w), float(mp.h)) * zoom) / 2.0
		queue_redraw()

	func zoom_by(f: float, at := Vector2(-1, -1)) -> void:
		if at.x < 0:
			at = size / 2.0
		var nz := clampf(zoom * f, 0.05, 8.0)
		pan = at - (at - pan) * (nz / zoom)
		zoom = nz
		queue_redraw()

	func _cell() -> float:
		return float(mp.cell)

	func _origin() -> Vector2:
		return Vector2(fposmod(float(mp.ox), _cell()), fposmod(float(mp.oy), _cell()))

	func square_at(p: Vector2) -> Vector2i:
		var img_p := (p - pan) / zoom - _origin()
		return Vector2i(floori(img_p.x / _cell()), floori(img_p.y / _cell()))

	func square_center(x: int, y: int) -> Vector2:
		return pan + (_origin() + Vector2(x + 0.5, y + 0.5) * _cell()) * zoom

	func center_square() -> Vector2i:
		if mp.is_empty():
			return Vector2i.ZERO
		return square_at(size / 2.0)

	func _token_at(p: Vector2) -> String:
		var r := _cell() * zoom * 0.45
		for t in mp.tokens:
			if square_center(int(t.x), int(t.y)).distance_to(p) <= r:
				return str(t.ref)
		return ""

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.05, 0.04))
		if mp.is_empty() or tex == null:
			return
		draw_texture_rect(tex, Rect2(pan, Vector2(float(mp.w), float(mp.h)) * zoom), false)
		var n := GameState.map_size(mp)
		var o := pan + _origin() * zoom
		var c := _cell() * zoom
		if bool(mp.grid):
			var col := Color(0.0, 0.0, 0.0, 0.45)
			for i in n.x + 1:
				draw_line(o + Vector2(i * c, 0), o + Vector2(i * c, n.y * c), col, 1.0)
			for j in n.y + 1:
				draw_line(o + Vector2(0, j * c), o + Vector2(n.x * c, j * c), col, 1.0)
		else:
			draw_rect(Rect2(o, Vector2(n.x, n.y) * c), Color(0, 0, 0, 0.35), false, 1.0)
		for k in mp.get("difficult", []):
			var q := str(k).split(",")
			var r0 := Rect2(o + Vector2(int(q[0]), int(q[1])) * c, Vector2(c, c))
			draw_rect(r0, Color(0.43, 0.24, 0.06, 0.28))
			for s in [1, 2, 3]:
				draw_line(r0.position + Vector2(s * c / 3.0, 0), r0.position + Vector2(0, s * c / 3.0), Color(0.24, 0.11, 0.02, 0.6), 1.0)
			for s in [1, 2]:
				draw_line(r0.position + Vector2(c, s * c / 3.0), r0.position + Vector2(s * c / 3.0, c), Color(0.24, 0.11, 0.02, 0.6), 1.0)
		var st: GameState = app.state
		var cur_ref := ""
		if bool(st.ini().active):
			cur_ref = str(st.current_combatant().get("ref", ""))
		for t in mp.tokens:
			var e := st.find_entity(t.ref)
			if e.is_empty():
				continue
			var p := square_center(int(t.x), int(t.y))
			if t.ref == drag_ref:
				# where it will land, and the piece under the finger
				var sq := square_at(drag_pos)
				if sq.x >= 0 and sq.y >= 0 and sq.x < n.x and sq.y < n.y:
					draw_rect(Rect2(o + Vector2(sq) * c, Vector2(c, c)), Color(1, 0.85, 0.3, 0.35))
				p = drag_pos
			_draw_token(e, st.is_pc(t.ref), p, c * 0.42, t.ref == cur_ref, t.ref == selected)

	func _draw_token(e: Dictionary, pc: bool, p: Vector2, r: float, cur: bool, sel: bool) -> void:
		var fill := Color(0.18, 0.38, 0.78) if pc else Color(0.72, 0.16, 0.13)
		var down := int(e.get("hp", 1)) <= 0
		if down:
			fill = Color(0.3, 0.3, 0.3)
		if not pc and not bool(e.get("revealed", false)):
			fill.a = 0.55
		draw_circle(p + Vector2(r * 0.08, r * 0.12), r, Color(0, 0, 0, 0.45))
		draw_circle(p, r, fill)
		var key := Art.key_for(e, "pc" if pc else "monster")
		var at: Texture2D = Art.texture(key) if key != "" and r >= 14 else null
		if at:
			var s := r * 1.3
			draw_texture_rect(at, Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, fill.a))
		else:
			var font := ThemeDB.fallback_font
			var fs := maxi(8, int(r * 0.85))
			var txt := _initials(str(e.name))
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, p + Vector2(-tw / 2.0, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		draw_arc(p, r, 0, TAU, 32, Color(0.95, 0.8, 0.4) if pc else Color(0.2, 0.05, 0.04), maxf(2.0, r * 0.1), true)
		if cur:
			draw_arc(p, r * 1.18, 0, TAU, 40, Color(1, 0.85, 0.2), maxf(2.5, r * 0.12), true)
		if sel:
			draw_arc(p, r * 1.32, 0, TAU, 40, Color.WHITE, 2.0, true)
		if down:
			draw_line(p - Vector2(r, r) * 0.6, p + Vector2(r, r) * 0.6, Color(0.9, 0.1, 0.1), 3.0)
			draw_line(p + Vector2(-r, r) * 0.6, p + Vector2(r, -r) * 0.6, Color(0.9, 0.1, 0.1), 3.0)

	static func _initials(n: String) -> String:
		var parts := n.strip_edges().split(" ", false)
		if parts.is_empty():
			return "?"
		var s := parts[0].left(1).to_upper()
		var last := parts[-1]
		if parts.size() > 1 and last.is_valid_int():
			s += last
		elif parts.size() > 1:
			s += last.left(1).to_upper()
		else:
			s += parts[0].substr(1, 1)
		return s

	func _gui_input(ev: InputEvent) -> void:
		if mp.is_empty():
			return
		if ev is InputEventMouseButton:
			var mb: InputEventMouseButton = ev
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				zoom_by(1.12, mb.position)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				zoom_by(1.0 / 1.12, mb.position)
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				var ref := _token_at(mb.position)
				if ref != "":
					app.state.remove_token(str(mp.id), ref)
			elif mb.button_index == MOUSE_BUTTON_LEFT and paint_difficult:
				if mb.pressed:
					var sq := square_at(mb.position)
					app.state.toggle_difficult(str(mp.id), sq.x, sq.y)
					queue_redraw()
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					moved = 0.0
					drag_ref = _token_at(mb.position)
					drag_pos = mb.position
					panning = drag_ref == ""
				else:
					if drag_ref != "":
						var sq := square_at(mb.position)
						var ref := drag_ref
						drag_ref = ""
						selected = ref
						if moved > 4.0 and not app.state.place_token(str(mp.id), ref, sq.x, sq.y):
							app.toast("Casella occupata o fuori dalla mappa")
						app.ui_dirty = true
					elif moved < 4.0 and selected != "":
						selected = ""
						app.ui_dirty = true
					panning = false
					queue_redraw()
			accept_event()
		elif ev is InputEventMouseMotion:
			var mm: InputEventMouseMotion = ev
			moved += mm.relative.length()
			if drag_ref != "":
				drag_pos = mm.position
				queue_redraw()
			elif panning:
				pan += mm.relative
				queue_redraw()
			accept_event()
		elif ev is InputEventMagnifyGesture:
			var mg: InputEventMagnifyGesture = ev
			zoom_by(mg.factor, mg.position)
			accept_event()
		elif ev is InputEventPanGesture:
			var pg: InputEventPanGesture = ev
			pan -= pg.delta * 20.0
			queue_redraw()
			accept_event()
