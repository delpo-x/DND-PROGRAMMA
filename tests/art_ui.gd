extends SceneTree
## godot --path app --script res://tests/art_ui.gd -- <out_dir>
## Starts a fight with pictured monsters, advances the turn (banner) and
## damages a goblin (flash), then screenshots initiative and bestiary.

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0]
	var main = load("res://main.tscn").instantiate()
	main.screenshot_path = "x"   # headless mode: no saving to the user's campaigns
	root.add_child(main)
	for i in 10:
		await process_frame
	var st = main.state
	for m in [{"name": "Capo goblin", "kind": "Umanoide"}, {"name": "Lupo grigio", "kind": "Bestia"}, {"name": "Scheletro", "kind": "Non morto"}, {"name": "Giovane drago rosso", "kind": "Drago"}]:
		var d: Dictionary = {"ac": 13, "hp": 20, "hp_max": 20, "init_mod": 2, "revealed": true}
		d.merge(m)
		st.add_monster(d)
	var refs: Array = []
	for c in st.characters():
		refs.append(c.id)
	for m in st.monsters():
		refs.append(m.id)
	st.combat_start(refs)
	var n := 0
	for c in st.ini().combatants:
		st.set_score(c.id, 20 - n)
		n += 1
	main.tabs.current_tab = 1
	for i in 20:
		await process_frame
	st.next_turn()
	for i in 6:
		await process_frame
	st.next_turn()
	for i in 12:
		await process_frame
	print("[art] min main=", main.get_combined_minimum_size(), " tab_init=", main.tab_init.get_combined_minimum_size(), " bar=", main.get_child(main.get_child_count()-1).get_combined_minimum_size())
	var row0 = main.tab_init.list.get_child(0).get_child(0)
	var parts := []
	for ch in row0.get_children():
		parts.append("%s:%d" % [ch.get_class(), int(ch.get_combined_minimum_size().x)])
	print("[art] row ", " ".join(parts))
	await _shot(out + "/art_init.png")
	var keys: Array = []
	for m in st.monsters():
		keys.append("%s=%s" % [m.name, Art.key_for(m, "monster")])
	print("[art] ", ", ".join(keys), " | banner children: ", main.fx_layer.get_child_count())
	st.change_hp(st.monsters()[1].id, -8)
	main.tabs.current_tab = 4
	for i in 40:
		await process_frame
	await _shot(out + "/art_bestiary.png")
	quit()
