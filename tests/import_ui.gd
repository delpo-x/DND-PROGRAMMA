extends SceneTree
## godot --path app --script res://tests/import_ui.gd -- <sheet.pdf> <story.pdf> <out.png>
## Drives the master-side PDF imports through the real UI code, then screenshots.

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var main = load("res://main.tscn").instantiate()
	main.screenshot_path = "x"   # headless mode: no saving to the user's campaigns
	root.add_child(main)
	for i in 10:
		await process_frame
	main.tab_players._import_bytes(FileAccess.get_file_as_bytes(a[0]), "scheda.pdf")
	for i in 5:
		await process_frame
	main.close_modal()
	main.tab_campaign._story_bytes(FileAccess.get_file_as_bytes(a[1]), "storia.pdf")
	for i in 5:
		await process_frame
	var st = main.state
	var ch: Dictionary = st.characters()[-1]
	print("[import-ui] char=%s cls=%s ac=%d hp=%d | story=%s chapters=%d" % [ch.name, ch.cls, ch.ac, ch.hp_max, st.data.story.get("title", ""), st.data.story.get("chapters", []).size()])
	print("[import-ui] pcs found: ", JSON.stringify(st.data.story.get("pcs", [])))
	main.close_modal()
	main.tab_campaign._create_pcs()
	for c in st.characters():
		print("[import-ui] PG %s | %s %s liv %d CA %d PF %d" % [c.name, c.race, c.cls, c.level, c.ac, c.hp_max])
	main.tab_campaign.open_chapters = {1: true}
	main.tabs.current_tab = 6
	main.tab_campaign.refresh()
	for i in 10:
		await process_frame
	var sc: ScrollContainer = main.tab_campaign.get_child(0)
	sc.scroll_vertical = 520
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(a[2])
	quit()
