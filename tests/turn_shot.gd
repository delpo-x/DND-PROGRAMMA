extends SceneTree
# Screenshots of the turn panel (Initiative tab): before and after a fireball.
# godot --path . -s tests/turn_shot.gd -- <out_prefix>

func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var app = load("res://scripts/main.gd").new()
	app.screenshot_path = out + ".auto.png"  # test mode: nothing is saved to disk
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 20:
		await process_frame
	var st: GameState = app.state
	st.rng.seed = 7
	var wiz: Dictionary = st.add_character("Mira", "")
	st.update_character(wiz.id, {"cls": "Mago", "level": 5, "ab": {"INT": 18, "DES": 14}, "prof": 3, "hp_max": 28, "hp": 28,
		"attacks": [{"name": "Pugnale", "bonus": 5, "damage": "1d4+2"}],
		"spells": [{"name": "Dardo di fuoco", "lvl": 0}, {"name": "Dardo incantato", "lvl": 1, "prep": true},
			{"name": "Blocca persone", "lvl": 2, "prep": true}, {"name": "Palla di fuoco", "lvl": 3, "prep": true}]})
	st.add_monster({"name": "Goblin", "ac": 15, "hp": 7, "notes": "Scimitarra +4, 1d6+2; arco corto +4, 1d6+2"})
	st.add_monster({"name": "Goblin 2", "ac": 15, "hp": 7, "notes": "Scimitarra +4, 1d6+2"})
	st.add_monster({"name": "Orco", "ac": 13, "hp": 15, "notes": "Ascia bipenne +5, 1d12+3"})
	var ids: Array = [wiz.id]
	for m in st.monsters():
		ids.append(m.id)
	st.combat_start(ids)
	# make sure the wizard acts first
	while str(st.current_combatant().get("ref", "")) != wiz.id:
		st.next_turn()
	app.tabs.current_tab = 1
	app.tab_init.refresh()
	for i in 25:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "_1.png")
	var p = app.tab_init.panel
	for a in Actions.list_for(st, wiz.id):
		if a.name == "Palla di fuoco":
			p._pick(a)
	for m in st.monsters():
		p.p_targets[m.id] = true
	p._execute()
	for i in 25:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "_2.png")
	print("log: ", st.data.log.size(), " goblin hp ", st.monsters()[0].hp)
	for i in 20:
		await process_frame
	for i in 5:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(out + "_3.png")
	print("app min ", app.get_combined_minimum_size(), " size ", app.size)
	quit()


func _wide(n: Node, depth := 0) -> void:
	if n is Control and (n as Control).get_combined_minimum_size().x > 1250:
		print("  ".repeat(depth), n.get_class(), " ", n.name, " ", (n as Control).get_combined_minimum_size(), " ", n.get("text") if n.get("text") != null else "")
	for c in n.get_children():
		_wide(c, depth + 1)
