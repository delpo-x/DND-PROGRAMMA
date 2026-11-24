extends SceneTree
# Screen readers (Godot 4.5 AccessKit): every field, menu, spin box and symbol
# button of the master app and of Dnd The Game has a name, and toasts reach
# the live-region announcer.

var fails := 0


func check(name: String, cond: bool, detail = "") -> void:
	print("%s %s %s" % ["ok  " if cond else "FAIL", name, str(detail)])
	if not cond:
		fails += 1


## Controls that a screen reader would read without a name.
func _unnamed(n: Node, out: Array) -> void:
	if n is Control and n.is_visible_in_tree() and n.accessibility_name == "":
		var c := n as Control
		var needs := c is LineEdit or c is TextEdit or c is SpinBox or c is OptionButton
		if c is LineEdit and c.get_parent() is SpinBox:
			needs = false
		if c is Button and not (c is OptionButton):
			var t: String = (c as Button).text.strip_edges()
			needs = (t == "" and (c as Button).icon != null) or UI.SYMBOL_NAMES.has(t)
		if needs:
			out.append("%s %s" % [c.get_class(), c.get_path()])
	for ch in n.get_children():
		_unnamed(ch, out)


func _init() -> void:
	# master app, every tab
	var app = load("res://main.tscn").instantiate()
	app.state.persist = false
	root.add_child(app)
	for i in 10:
		await process_frame
	check("master announcer is a polite live region", app.sr is Label and app.sr.accessibility_live == DisplayServer.LIVE_POLITE)
	app.state.new_campaign("Test accessibilita")
	app.state.add_character("Aria", "")
	var missing: Array = []
	for t in app.tabs.get_tab_count():
		app.tabs.current_tab = t
		for i in 4:
			await process_frame
		_unnamed(app, missing)
	check("master: every field and symbol button has a name", missing.is_empty(), missing.slice(0, 8))
	app.toast("Prova di annuncio")
	check("master toast announced", app.sr.text == "Prova di annuncio", app.sr.text)
	app.toast("Prova di annuncio")
	check("same toast twice still changes the region", app.sr.text.strip_edges() == "Prova di annuncio" and app.sr.text != "Prova di annuncio")
	app.queue_free()
	await process_frame

	# Dnd The Game
	var g = load("res://game/game_main.gd").new()
	g.test_mode = true
	root.add_child(g)
	for i in 6:
		await process_frame
	missing = []
	_unnamed(g, missing)
	check("game: every field and symbol button has a name", missing.is_empty(), missing.slice(0, 8))
	g.add_feed("Aria", "Apro la porta.", "player")
	check("story line announced", g.sr.text == "Aria: Apro la porta.", g.sr.text)
	g.toast("Turno di Aria")
	check("game toast announced", g.sr.text == "Turno di Aria", g.sr.text)

	print("a11y test: %s" % ("OK" if fails == 0 else "%d FAIL" % fails))
	quit(0 if fails == 0 else 1)
