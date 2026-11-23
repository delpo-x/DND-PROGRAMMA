extends SceneTree
# Character portraits: saved square and small, used as picture key everywhere,
# replaced without leaving old files, removed with the character.
# godot --headless --path . -s tests/portrait_test.gd

var fails := 0


func check(name: String, ok: bool, info = "") -> void:
	print(("ok   " if ok else "FAIL ") + name + " " + str(info))
	if not ok:
		fails += 1


func _init() -> void:
	var st := GameState.new()
	st.persist = false
	st.new_campaign("Test ritratti")
	var a: Dictionary = st.add_character("Aria", "")
	check("no portrait at first", Art.key_for(a, "pc") == "")
	var tall := Image.create(900, 1600, false, Image.FORMAT_RGB8)
	tall.fill(Color(0.2, 0.3, 0.8))
	check("portrait saved", st.set_portrait(a.id, tall))
	var file := str(a.portrait)
	var key := Art.key_for(a, "pc")
	check("key points to the saved file", key == "r/" + file and FileAccess.file_exists(GameState.portrait_path(file)), key)
	var saved := Image.load_from_file(GameState.portrait_path(file))
	check("square, at most 384 px", saved != null and saved.get_width() == 384 and saved.get_height() == 384)
	check("texture loads", Art.texture(key) != null)
	check("party and choices carry the picture", st._party()[0].img == key and st.char_choices("x")[0].img == key)
	check("phone gets its own picture", st.player_view(a.id).me_img == key)
	OS.delay_msec(5)
	check("replaced", st.set_portrait(a.id, tall))
	check("old file removed", str(a.portrait) != file and not FileAccess.file_exists(GameState.portrait_path(file)))
	# a phone can't point the portrait at another file through the sheet
	st.update_character(a.id, {"portrait": "../mappe/x"})
	check("sheet update can't change the portrait", str(a.portrait).begins_with(a.id + "_"))
	var keep := str(a.portrait)
	a.portrait = "../mappe/x"
	check("bad name ignored", Art.key_for(a, "pc") == "")
	a.portrait = keep
	st.clear_portrait(a.id)
	st.set_portrait(a.id, tall)
	var f2 := str(a.portrait)
	st.clear_portrait(a.id)
	check("cleared", str(a.portrait) == "" and not FileAccess.file_exists(GameState.portrait_path(f2)))
	st.set_portrait(a.id, tall)
	var f3 := str(a.portrait)
	st.delete_character(a.id)
	check("deleted with the character", not FileAccess.file_exists(GameState.portrait_path(f3)))
	check("monster can't get one", not st.set_portrait(st.add_monster({"name": "Goblin"}).id, tall))
	check("no files left", DirAccess.get_files_at(GameState.PORTRAIT_DIR).size() == 0)
	print("portrait test: " + ("OK" if fails == 0 else "%d FAIL" % fails))
	quit()
