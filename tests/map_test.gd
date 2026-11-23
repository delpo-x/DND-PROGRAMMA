extends SceneTree
# Battle maps: grid detection on drawn grids, pieces moving square by square
# (one per square, like checkers), what players see, and the player's move.
# godot --headless --path . -s tests/map_test.gd

var fails := 0


func check(name: String, ok: bool, info = "") -> void:
	print(("ok   " if ok else "FAIL ") + name + " " + str(info))
	if not ok:
		fails += 1


## A parchment-like picture with a grid of `cell` px starting at (ox, oy).
func grid_image(w: int, h: int, cell: float, ox: float, oy: float, seed_n: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.85, 0.78, 0.62))
	for i in 60:  # rooms, rocks, stains
		var r := Rect2i(rng.randi_range(0, w), rng.randi_range(0, h), rng.randi_range(20, 300), rng.randi_range(20, 300))
		img.fill_rect(r, Color(rng.randf_range(0.2, 0.9), rng.randf_range(0.2, 0.8), rng.randf_range(0.1, 0.6)))
	var x := ox
	while x < w:
		img.fill_rect(Rect2i(int(x), 0, 2, h), Color(0.25, 0.2, 0.15))
		x += cell
	var y := oy
	while y < h:
		img.fill_rect(Rect2i(0, int(y), w, 2), Color(0.25, 0.2, 0.15))
		y += cell
	for i in 4000:  # paper grain
		img.set_pixel(rng.randi_range(0, w - 1), rng.randi_range(0, h - 1), Color(rng.randf(), rng.randf(), rng.randf()))
	return img


func _init() -> void:
	for case in [[1500, 1100, 57.3, 23.0, 11.0], [2400, 1800, 70.0, 0.0, 35.0], [900, 1300, 31.5, 9.0, 4.0]]:
		var img := grid_image(case[0], case[1], case[2], case[3], case[4], 7)
		var t0 := Time.get_ticks_msec()
		var g := MapGrid.detect(img)
		var ms := Time.get_ticks_msec() - t0
		var ok: bool = not g.is_empty() and absf(float(g.cell) - case[2]) < case[2] * 0.02
		# the found start must sit on a drawn line (within 3 px, modulo the step)
		if ok:
			var dx := fposmod(float(g.ox) - case[3] + 1.0, case[2])
			var dy := fposmod(float(g.oy) - case[4] + 1.0, case[2])
			ok = minf(dx, case[2] - dx) < 3.5 and minf(dy, case[2] - dy) < 3.5
		check("grid %sx%s step %s" % [case[0], case[1], case[2]], ok, "%s %dms" % [g, ms])
	var plain := Image.create(800, 600, false, Image.FORMAT_RGB8)
	plain.fill(Color(0.5, 0.4, 0.3))
	check("no grid on a plain picture", MapGrid.detect(plain).is_empty())

	var st := GameState.new()
	st.persist = false
	st.new_campaign("Test mappe")
	var a: Dictionary = st.add_character("Aria", "")
	var b: Dictionary = st.add_character("Bruno", "")
	var gob: Dictionary = st.add_monster({"name": "Goblin", "revealed": true})
	var orc: Dictionary = st.add_monster({"name": "Orco", "revealed": false})
	var mp: Dictionary = st.add_map("Cripta", grid_image(1500, 1100, 57.3, 23.0, 11.0, 3))
	check("map added with grid", not mp.is_empty() and bool(mp.auto_grid) and FileAccess.file_exists(GameState.map_path(mp.file)))
	var n := GameState.map_size(mp)
	check("squares", n.x >= 25 and n.y >= 18, n)
	check("place", st.place_token(mp.id, a.id, 2, 3) and st.place_token(mp.id, gob.id, 5, 5) and st.place_token(mp.id, orc.id, 6, 6))
	check("one piece per square", not st.place_token(mp.id, b.id, 2, 3))
	check("outside refused", not st.place_token(mp.id, b.id, n.x, 0) and not st.place_token(mp.id, b.id, -1, 0))
	check("free square next to taken one", st.free_square(mp.id, 2, 3) != Vector2i(2, 3))
	check("nothing shown before 'in gioco'", st.player_view(a.id).map == null)
	st.set_map_active(mp.id)
	var pv: Dictionary = st.player_view(a.id).map
	var refs: Array = pv.tokens.map(func(t): return t.ref)
	check("players see pieces but not the hidden orc", refs.has(a.id) and refs.has(gob.id) and not refs.has(orc.id), refs)
	check("url", str(pv.url) == "/mappa/%s.jpg" % mp.file)
	check("player moves own piece", st.player_move(a.id, 3, 3) == "" and int(mp.tokens[0].x) == 3)
	check("player can't move onto goblin", st.player_move(a.id, 5, 5) != "")
	check("player without piece refused", st.player_move(b.id, 1, 1) != "")
	st.update_map(mp.id, {"cell": 400.0})
	var n2 := GameState.map_size(mp)
	var inside := true
	for t in mp.tokens:
		inside = inside and int(t.x) < n2.x and int(t.y) < n2.y
	check("pieces kept on a smaller board", inside, n2)
	st.delete_monster(gob.id)
	check("deleted monster leaves the map", mp.tokens.filter(func(t): return t.ref == gob.id).is_empty())
	var file: String = mp.file
	st.delete_map(mp.id)
	check("map deleted", st.data.maps.is_empty() and str(st.data.map_active) == "" and not FileAccess.file_exists(GameState.map_path(file)))
	print("map test: " + ("OK" if fails == 0 else "%d FAIL" % fails))
	quit()
