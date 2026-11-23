extends SceneTree
# Dnd The Game: monster turns, combat from the narrator's tags, checks,
# chapters, phone view. The local model is not called (test_mode).
# godot --headless --path . -s tests/game_test.gd

var fails := 0


func check(name: String, ok: bool, info = "") -> void:
	print(("ok   " if ok else "FAIL ") + name + " " + str(info))
	if not ok:
		fails += 1


func _init() -> void:
	var g = load("res://game/game_main.gd").new()
	g.test_mode = true
	root.add_child(g)
	for i in 5:
		await process_frame
	var st: GameState = g.state
	check("example campaign", st.characters().size() == 2, st.characters().size())
	check("phones see the AI master box", st.player_view(str(st.characters()[0].id)).get("ai") is Dictionary)

	# tags written by the narrator
	var t := GameStory.tags("Escono dal bosco.\n[[COMBATTIMENTO: Goblin x2, Lupo]]\n[[PROVA: Percezione CD 15: Aria]]")
	check("tags read", t.size() == 2 and t[0][0] == "combattimento" and t[0][1] == "Goblin x2, Lupo" and t[1][0] == "prova", t)
	check("tags hidden from the text", GameStory.strip_tags("Ciao.\n[[FINE CAPITOLO]]") == "Ciao.")
	check("half tag hidden", GameStory.strip_tags("Ciao. [[COMBATT") == "Ciao.")
	check("voice skips tags", Voice.clean("Attenti! (1d6) [[PROVA: x]]") == "Attenti!", Voice.clean("Attenti! (1d6) [[PROVA: x]]"))
	check("voice reads the question after a tag", Voice.clean("Un rumore. [[PROVA: Percezione CD 15: Aria]] Cosa fate?") == "Un rumore. Cosa fate?")

	# combat from a tag: the campaign's goblin plus copies and a wolf from the bestiary
	check("combat starts", g.start_combat("Goblin x2, Lupo"))
	var names: Array = []
	for c in st.ini().combatants:
		if c.type == "monster":
			names.append(str(c.name))
	names.sort()
	check("monsters spawned and numbered", names == ["Goblin 1", "Goblin 2", "Lupo"], names)
	var gob := ""
	for m in st.monsters():
		if m.name == "Goblin 1":
			gob = str(m.id)
	check("everyone has initiative", st.ini().combatants.all(func(c): return int(c.score) != Rules.NO_SCORE))
	var d := MonsterAI.choose(st, gob, g.rng)
	check("goblin attacks a character", d.kind == "act" and st.is_pc(str(d.targets[0])), d)

	# play the whole fight: monsters alone, characters attack and end their turn
	var guard := 0
	while st.ini().active and guard < 3000:
		guard += 1
		var cur: Dictionary = st.current_combatant()
		if not cur.is_empty() and cur.type == "pc" and g._turn_key == "%d:%s" % [int(st.ini().round), str(cur.id)] and not g._wait_call.is_valid():
			var me: Dictionary = st.find_entity(str(cur.ref))
			if int(me.hp) > 0:
				var target := ""
				for c in st.ini().combatants:
					if c.type == "monster" and int(st.find_entity(c.ref).hp) > 0:
						target = str(c.ref)
				if target != "":
					var a: Dictionary = Actions.list_for(st, str(cur.ref))[0]
					var res := Actions.resolve(st, str(cur.ref), a, [target])
					g._on_player_action(str(cur.ref), "attacco", res.lines)
			if st.ini().active:
				g._end_pc_turn(str(cur.ref))
		g._process(0.5)
		await process_frame
	check("fight ends by itself", not st.ini().active, "round %d" % int(st.ini().round))
	var combat_lines: Array = g.feed.filter(func(e): return e.kind == "combat")
	check("monster turns in the story", combat_lines.size() >= 3, combat_lines.size())
	for e in combat_lines.slice(0, 4):
		print("     | ", str(e.who), ": ", str(e.text).replace("\n", " / "))
	var ended: Array = g.story.transcript.filter(func(x): return str(x.text).begins_with("Il combattimento è finito"))
	check("narrator told the fight is over", ended.size() == 1, ended)

	# recharge ability: breath first, then not again until it recharges
	var dr := st.add_monster({"name": "Draghetto", "ac": 16, "hp": 40, "init_mod": 1,
		"notes": "Morso +5, 1d10+3. Soffio di fuoco (ricarica 5-6): cono 4,5 m, 7d6, TS Des CD 13"})
	for e in st.characters():
		e.hp = e.hp_max
		e.death_ok = 0
		e.death_ko = 0
	st.combat_start([st.characters()[0].id, st.characters()[1].id, dr.id])
	MonsterAI.reset()
	var first := MonsterAI.choose(st, str(dr.id), g.rng)
	check("breath on two characters", first.kind == "act" and str(first.action.name).begins_with("Soffio") and first.targets.size() == 2, [first.get("action", {}).get("name"), first.get("targets")])
	check("breath spent", MonsterAI.spent.get(str(dr.id) + "|" + str(first.get("action", {}).get("name", "")), false))
	check("spent breath not offered", MonsterAI.usable(st, str(dr.id)).all(func(a): return not str(a.name).begins_with("Soffio")))
	# fleeing when badly hurt, never for the fearless
	var ban := st.add_monster({"name": "Bandito", "ac": 12, "hp": 20, "notes": "Scimitarra +3, 1d6+1"})
	ban.hp = 3
	st.combat_add(ban.id)
	var fled := 0
	for i in 60:
		if MonsterAI.choose(st, str(ban.id), g.rng).kind == "flee":
			fled += 1
	check("wounded bandit sometimes flees", fled > 5 and fled < 55, fled)
	dr.hp = 3
	var dfled := 0
	for i in 40:
		if MonsterAI.choose(st, str(dr.id), g.rng).kind == "flee":
			dfled += 1
	check("dragon never flees", dfled == 0, dfled)
	var orc := st.add_monster({"name": "Orco", "ac": 11, "hp": 30, "notes": "Ascia +6, 1d12+4"})
	orc.conditions = "Paralizzato"
	check("paralysed monster skips", MonsterAI.choose(st, str(orc.id), g.rng).kind == "skip")
	st.combat_end()

	# a check asked by the narrator: nobody has a phone, so the app rolls
	var before: int = g.story.transcript.size()
	var r = g.ask_check("Percezione CD 12: tutti")
	check("check request made", r is Dictionary and str(r.get("type", "")) == "skill" and r.param == "percezione", r)
	check("check rolled for players without phone", g.checks.is_empty())
	var res_line: Array = g.story.transcript.slice(before).filter(func(x): return str(x.text).begins_with("Risultato della prova"))
	check("result sent to the narrator", res_line.size() == 1, res_line)
	var sv = g.ask_check("TS Destrezza CD 13: Bruno")
	check("saving throw for one character", sv is Dictionary and sv.type == "save" and sv.param == "DES" and sv.chars.size() == 1, sv)

	# a player talks from the phone
	g.net.player_said.emit(str(st.characters()[0].id), "Apro la porta piano")
	check("phone words in the story", g.story.transcript.back().text == "Apro la porta piano" and g.story.transcript.back().who == "Aria")
	g._sync_phones()
	var feed: Array = st.player_view(str(st.characters()[0].id)).ai.feed
	check("phones get the last lines", feed.size() > 0 and feed.size() <= 8, feed.size())

	# chapter: closed, numbered, transcript emptied
	g._ask_close_chapter()
	check("chapter closed", g.story.chapter == 2, g.story.chapter)
	check("next chapter starts", g.story.transcript.size() == 1 and str(g.story.transcript[0].text).begins_with("Inizia il capitolo 2"), g.story.transcript)
	var md: String = g.story.chapter_markdown("Il gruppo ha sconfitto i goblin.")
	check("chapter markdown", md.contains("# Capitolo 2") and md.contains("## Riassunto") and md.contains("sconfitto i goblin"))
	var sys: String = g.story.system_prompt()
	check("prompt lists the party and the bestiary", sys.contains("Aria") and sys.contains("Goblin") and sys.contains("[[COMBATTIMENTO"))
	check("prompt stays short", sys.length() < 4500, sys.length())
	print("game test: " + ("OK" if fails == 0 else "%d FAIL" % fails))
	quit()
