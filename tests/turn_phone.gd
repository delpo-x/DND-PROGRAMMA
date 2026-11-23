extends SceneTree
# Serves a combat where it's a wizard's turn, to try the phone turn panel:
# godot --path . -s tests/turn_phone.gd -- --serve-for 600
# then open http://127.0.0.1:8080/giocatore?char=<printed id>
# Test mode: the app saves nothing while --serve-for is given.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var app = load("res://scripts/main.gd").new()
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 20:
		await process_frame
	var st: GameState = app.state
	var wiz: Dictionary = st.add_character("Mira", "")
	st.update_character(wiz.id, {"cls": "Mago", "level": 5, "ab": {"INT": 18, "DES": 14}, "prof": 3, "hp_max": 28, "hp": 28,
		"attacks": [{"name": "Pugnale", "bonus": 5, "damage": "1d4+2"}],
		"spells": [{"name": "Dardo di fuoco", "lvl": 0}, {"name": "Dardo incantato", "lvl": 1, "prep": true},
			{"name": "Blocca persone", "lvl": 2, "prep": true}, {"name": "Palla di fuoco", "lvl": 3, "prep": true}]})
	var ids: Array = [wiz.id]
	for m in [{"name": "Goblin A", "ac": 15, "hp": 7, "revealed": true}, {"name": "Goblin B", "ac": 15, "hp": 7, "revealed": true},
			{"name": "Orco", "ac": 13, "hp": 15, "revealed": true}, {"name": "Assassino", "ac": 15, "hp": 40, "revealed": false}]:
		ids.append(st.add_monster(m).id)
	for c in st.characters():
		if c.id != wiz.id:
			ids.append(c.id)
	st.combat_start(ids)
	while str(st.current_combatant().get("ref", "")) != wiz.id:
		st.next_turn()
	app.tabs.current_tab = 1
	print("CHAR ", wiz.id)
	await create_timer(float(args[args.find("--serve-for") + 1])).timeout
	quit()
