extends SceneTree
# Screenshot of the Map tab: godot --path . -s tests/map_shot.gd -- <out.png> <map picture> [--serve-for N]
# Test mode (screenshot_path): the campaign is not saved; the map picture is
# removed at the end.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var app = load("res://scripts/main.gd").new()
	# test mode: nothing is saved (with --serve-for the app itself turns saving off)
	if not args.has("--serve-for"):
		app.screenshot_path = args[0] + ".auto.png"
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in 20:
		await process_frame
	var st: GameState = app.state
	var mp := st.add_map("Cripta del faro", Image.load_from_file(args[1]))
	var gob := st.add_monster({"name": "Goblin", "revealed": true})
	var gob2 := st.add_monster({"name": "Goblin 2", "revealed": true})
	var orc := st.add_monster({"name": "Orco", "revealed": false})
	var pcs := st.characters()
	for i in pcs.size():
		st.place_token(mp.id, pcs[i].id, 4 + i, 14)
	st.place_token(mp.id, gob.id, 18, 14)
	st.place_token(mp.id, gob2.id, 20, 15)
	st.place_token(mp.id, orc.id, 16, 4)
	st.set_map_active(mp.id)
	var ids: Array = []
	for e in pcs + st.monsters():
		ids.append(e.id)
	st.combat_start(ids)
	app.tabs.current_tab = 2
	for i in 30:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png(args[0])
	# with "--serve-for N" the phone pages stay served for N seconds (manual checks)
	if args.has("--serve-for"):
		await create_timer(float(args[args.find("--serve-for") + 1]) - 5.0).timeout
	print("grid ", mp.cell, " ", mp.ox, " ", mp.oy, " auto ", mp.auto_grid, " size ", GameState.map_size(mp))
	print("screen view map tokens: ", st.screen_view().map.tokens.size())
	DirAccess.remove_absolute(GameState.map_path(mp.file))
	quit()
