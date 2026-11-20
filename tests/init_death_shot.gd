extends SceneTree
# Screenshot of the Initiative tab with a character at 0 PF.

func _init() -> void:
	var app = load("res://scripts/main.gd").new()
	app.screenshot_path = OS.get_cmdline_user_args()[0] + ".auto.png"  # test mode: nothing is saved to disk
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 20:
		await process_frame
	var st: GameState = app.state
	st.add_monster({"name": "Scheletro", "hp": 13, "ac": 13, "vuln": "Contundente", "immune": "Veleno"})
	st.give_temp_hp(st.monsters()[0].id, 6)
	var pcs := st.characters()
	var ids: Array = []
	for ch in pcs:
		ids.append(ch.id)
	for m in st.monsters():
		ids.append(m.id)
	st.combat_start(ids)
	st.update_character(pcs[1].id, {"resist": "Fuoco, Veleno", "cls": "Paladino", "level": 5})
	st.use_slot(pcs[1].id, 1, 1)
	st.update_character(pcs[1].id, {"spells": [{"name": "Benedizione", "lvl": 1}, {"name": "Punizione divina", "lvl": 1}, {"name": "Aiuto", "lvl": 2, "prep": false}]})
	st.give_temp_hp(pcs[1].id, 8)
	st.change_hp(pcs[0].id, -999)
	st.death_save(pcs[0].id, 14)
	st.death_save(pcs[0].id, 5)
	st.toggle_condition(st.monsters()[0].id, "Prono")
	st.toggle_condition(st.monsters()[0].id, "Spaventato")
	app.tabs.current_tab = int(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 1
	app.tab_init.refresh()
	for i in 30:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	quit()
