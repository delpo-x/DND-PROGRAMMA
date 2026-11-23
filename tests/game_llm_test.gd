extends SceneTree
# Dnd The Game with the real local narrator (Ollama must be installed, with
# the model in the settings). Prints the reply, its markers and the time.
# Slow on a PC without a big graphics card: run it by hand.
# godot --headless --path . -s tests/game_llm_test.gd

func _init() -> void:
	var g = load("res://game/game_main.gd").new()
	g.test_mode = true
	g.llm_in_tests = true
	root.add_child(g)
	for i in 5:
		await process_frame
	while g.narrator.busy:  # opening scene of the new adventure
		await process_frame
	print("APERTURA: ", g.feed.back().text)
	var t0 := Time.get_ticks_msec()
	var first := [-1]
	g.narrator.chunk.connect(func(_p):
		if first[0] < 0:
			first[0] = Time.get_ticks_msec() - t0)
	g._player_says("Il gruppo", "Seguiamo le tracce della carovana fino all'ingresso di una grotta. Entriamo con le armi in pugno.")
	while g.narrator.busy:
		await process_frame
	var full: String = g.story.transcript.back().text
	print("RISPOSTA: ", full)
	print("prima parola dopo %.1f s, risposta completa dopo %.1f s" % [first[0] / 1000.0, (Time.get_ticks_msec() - t0) / 1000.0])
	print("combattimento partito: ", g.state.ini().active, "  prove in corso: ", g.checks.size())
	print("stato: ", g.narrator.status)
	quit()
