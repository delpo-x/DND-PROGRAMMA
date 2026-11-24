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

	# waiting lines: never the same twice in a row, and calmer ones in combat
	var f1: String = g.filler_line()
	var f2: String = g.filler_line()
	check("filler line said", f1 != "" and f2 != "" and f1 != f2, [f1, f2])
	check("filler lines from the base pool", g.FILLERS.base.has(f1), f1)

	# a reply being written reaches the phones while it grows
	g._live = g.add_feed("Master", "", "master")
	g._sync_phones(true)
	var lf: Array = st.player_view(str(st.characters()[0].id)).ai.feed
	check("phones see the empty live reply", lf.size() > 0 and lf.back().live == true and lf.back().text == "", lf.back() if lf.size() > 0 else null)
	g._on_chunk("La porta cigola. ")
	g._sync_phones(true)
	lf = st.player_view(str(st.characters()[0].id)).ai.feed
	check("phones see the live words", str(lf.back().text).begins_with("La porta cigola"), lf.back())
	g._live = {}
	g.feed.pop_back()

	# background sound follows the place words of the narrator
	check("place: cave", Ambience.detect("Entrate nella grotta umida. Cosa fate?") == "grotta")
	check("place: the last word wins", Ambience.detect("Lasciate la locanda e prendete il sentiero nel bosco.") == "bosco")
	check("place: whole words only", Ambience.detect("Vi siete amati molto") == "", Ambience.detect("Vi siete amati molto"))
	check("place: none", Ambience.detect("Il mercante vi guarda.") == "")
	check("place: tavern", g.ambience.follow("Il bancone della taverna è affollato.") == "locanda" and g.ambience.current == "locanda")
	check("ambience silent in tests", not g.ambience.playing())
	var amb: AudioStreamWAV = g.ambience._stream("grotta")
	check("ambience loop loads and repeats", amb != null and amb.loop_mode == AudioStreamWAV.LOOP_FORWARD and amb.get_length() > 20.0, amb.get_length() if amb else 0)
	check("ambience loops exist", FileAccess.file_exists("res://web/amb/grotta.wav") and FileAccess.file_exists("res://web/amb/locanda.wav"))

	# chapter: closed, numbered, transcript emptied
	g._ask_close_chapter()
	check("chapter closed", g.story.chapter == 2, g.story.chapter)
	check("next chapter starts", g.story.transcript.size() == 1 and str(g.story.transcript[0].text).begins_with("Inizia il capitolo 2"), g.story.transcript)
	var md: String = g.story.chapter_markdown("Il gruppo ha sconfitto i goblin.")
	check("chapter markdown", md.contains("# Capitolo 2") and md.contains("## Riassunto") and md.contains("sconfitto i goblin"))
	var sys: String = g.story.system_prompt()
	check("prompt lists the party and the bestiary", sys.contains("Aria") and sys.contains("Goblin") and sys.contains("[[COMBATTIMENTO"))
	check("prompt stays short", sys.length() < 4500, sys.length())

	# tone of the adventure: read by the narrator, kept short
	st.set_tone("Cupo, poca luce, PNG sospettosi. " + "x".repeat(400))
	sys = g.story.system_prompt()
	check("tone in the prompt", sys.contains("Tono dell'avventura") and sys.contains("PNG sospettosi"))
	check("tone kept short", str(st.data.tone).length() == StoryImport.TONE_MAX, str(st.data.tone).length())
	st.set_tone("")
	check("no tone, no line", not g.story.system_prompt().contains("Tono dell'avventura"))

	# pinned facts: always in the prompt, kept few and short
	st.set_pinned("- Marta ha promesso 50 monete d'oro\n\n" + "y".repeat(300) + "\n" + "riga\n".repeat(20))
	check("pinned facts kept few and short", st.data.pinned.size() == GameState.PINNED_MAX and st.data.pinned[0] == "Marta ha promesso 50 monete d'oro" and str(st.data.pinned[1]).length() == GameState.FACT_CHARS, st.data.pinned)
	check("pinned facts in the prompt", g.story.system_prompt().contains("Fatti fissati") and g.story.system_prompt().contains("50 monete"))
	st.set_pinned("")
	check("no pinned facts, no line", not g.story.system_prompt().contains("Fatti fissati"))

	# factions: listed in the prompt, they move at the end of a chapter
	st.set_factions("Goblin di Sgnacco: vogliono il sale della carovana\nGilda dei vetrai: rivuole i carri")
	check("factions in the prompt", g.story.system_prompt().contains("Gilda dei vetrai"))
	check("factions prompt", str(g.story.factions_prompt("Il gruppo ha trovato la grotta.")[0].content).contains("Goblin di Sgnacco") and str(g.story.factions_prompt("x")[0].content).contains("Nome: cosa ha fatto"))
	var fm := GameStory.parse_faction_moves("Ecco le mosse:\n- **Goblin di Sgnacco**: hanno venduto il sale ai mercanti del nord.\nGilda dei vetrai: ha mandato un esattore alla locanda.\nDraghi: niente di nuovo da segnalare.", st.data.factions)
	check("faction moves read", fm.size() == 2 and str(fm[0]).begins_with("Goblin di Sgnacco: hanno venduto"), fm)
	var ch_before: int = g.story.chapter
	g.story.add("user", "Bruno", "Entriamo nella grotta.")
	g._closing = true
	g._on_finished("Il gruppo è entrato nella grotta.", true, "camp")
	check("factions move before the next chapter", g.story.chapter == ch_before)
	g._on_finished("Goblin di Sgnacco: hanno spostato i prigionieri nelle gabbie basse.\nGilda dei vetrai: ha messo una taglia sui goblin.", true, "factions")
	check("chapter closed after the factions", g.story.chapter == ch_before + 1 and st.data.faction_moves.size() == 2)
	check("moves in the prompt, off stage", g.story.system_prompt().contains("Intanto, fuori scena") and g.story.system_prompt().contains("taglia sui goblin"))
	check("moves in the chapter diary", g.story.chapter_markdown("x").contains("## Intanto, fuori scena"))
	st.set_factions("")
	check("no factions, no moves", st.data.faction_moves.is_empty() and not g.story.system_prompt().contains("Fazioni"))

	# chapter outlines checked for what the narrator needs
	var known := StoryImport.known_monsters(st)
	var good := {"title": "La grotta", "text": "Obiettivo: liberare i mercanti.
Mostri: Goblin x3 nella sala, Capo goblin, Lupo
Il capitolo finisce quando i mercanti escono." + "

Testo lungo.".repeat(200)}
	var bad := {"title": "Il ponte", "text": "Il troll chiede un pedaggio di 5 monete. Ha 84 PF e attacca con 2d6+4.
Mostri: Guardiano di vetro, Goblin x2 Prove: Atletica CD 14, Furtività CD 12
" + "

Altro.".repeat(300)}
	var res := StoryImport.check({"chapters": [good, bad]}, known)
	check("good outline passes", res.size() == 1 and res[0].chapter == 2, res)
	var iss: Array = res[0].issues if res.size() > 0 else []
	var all := "
".join(iss)
	check("outline: no objective in the part read", all.contains("obiettivo"), iss)
	check("outline: no end condition", all.contains("finisce quando"), iss)
	check("outline: dice and abbreviations", all.contains("1d6"), iss)
	check("outline: unknown monster only", all.contains("Guardiano di vetro") and not all.contains("\"Goblin") and not all.contains("Furtivit"), iss)
	check("outline: short list form accepted", StoryImport.check({"chapters": [{"title": "x", "text": "Obiettivo: mercanti liberi.\nFine: gruppo fuori con mercanti."}]}, known).is_empty())

	# passages of the full chapter text sent with one request
	var filler := "\n\nLa pioggia cade sui tetti di Roccalta e i contadini parlano del raccolto.".repeat(30)
	st.set_story({"title": "Prova", "chapters": [{"title": "La grotta", "text": "Obiettivo: liberare mercanti.\nFine: mercanti fuori." + filler
		+ "\n\nTobia il mercante tiene nascosta una chiave d'osso sotto la lingua: la mostra solo a chi gli promette di salvare sua figlia Lisetta."
		+ "\n\nLa sala del fuoco ha il soffitto basso annerito dal fumo e tre giacigli di paglia." + filler}]})
	g.story.chapter = 1
	g.story.transcript = [{"role": "assistant", "who": "Master", "text": "Nelle gabbie c'è un vecchio mercante. Cosa fate?"},
		{"role": "user", "who": "Aria", "text": "Chiedo a Tobia se sa dove sia la chiave."}]
	var pas: String = g.story.passages()
	check("passage found by name and word", pas.contains("chiave d'osso") and not pas.contains("giacigli"), pas)
	check("passage in the request", str(g.story.messages().back().content).contains("chiave d'osso"))
	check("passage kept short", pas.length() <= GameStory.PASSAGE_CHARS, pas.length())
	g.story.transcript = [{"role": "user", "who": "Aria", "text": "Aspetto e osservo il gruppo."}]
	check("no passage when nothing matches", g.story.passages() == "", g.story.passages())
	g.story.transcript = [{"role": "user", "who": "Bruno", "text": "Entro nella sala del fuoco e guardo i giacigli."}]
	check("passage for a room", g.story.passages().contains("giacigli"), g.story.passages())
	check("long paragraphs cut", GameStory._pieces("Frase uno. ".repeat(100)).all(func(p): return p.length() <= GameStory.PARA_CHARS))
	# read-aloud text: only the marked paragraphs, read without the model
	var ra := StoryImport.read_aloud("Obiettivo: segreto del master.\n\nDa leggere: La pioggia batte sulla strada.\n\nTobia mente.\n\n## Da leggere\n\nUna grotta si apre nella collina.\n\nUn fumo sottile esce dall'imbocco.\n\n## Note\n\nIl capo ha la chiave.")
	check("read aloud: marked paragraphs only", ra == ["La pioggia batte sulla strada.", "Una grotta si apre nella collina.", "Un fumo sottile esce dall'imbocco."], ra)
	var mt := StoryImport.master_text("Da leggere: " + "Lunga descrizione della valle. ".repeat(80) + "\n\nObiettivo: segreto del master.\n\n## Da leggere\n\nUna grotta.\n\n## Note\n\nIl capo ha la chiave.")
	check("master text: sheet without the long read-aloud text", mt == "Obiettivo: segreto del master.\n\n## Note\n\nIl capo ha la chiave.", mt)
	check("adapt room grows with the paragraph", GameStory.adapt_tokens("breve") == 260 and GameStory.adapt_tokens("x".repeat(2000)) > 600)
	st.set_story({"title": "Prova", "chapters": [{"title": "La strada", "text": "Obiettivo: segreto.\n\nDa leggere: La pioggia batte sulla strada.\n\nDa leggere: Due lupi sbucano dagli alberi. [[COMBATTIMENTO: Lupo x2]]\n\nDa leggere: Dopo la lotta, il silenzio."}]})
	var ch_was: int = g.story.chapter
	g.story.chapter = 2
	check("past the last chapter: adventure over, nothing repeated", g.story.adventure_over() and g.story.chapter_info().is_empty() and not g.story.reading_left())
	# found in the third playtest: the epilogue ended empty chapters again and again
	check("no chapter end asked after the adventure", not g.story.system_prompt().contains("[[FINE CAPITOLO]]"))
	g._on_tag("fine capitolo", "")
	check("narrator's chapter end ignored after the adventure", not g._closing and g.story.chapter == 2)
	g.story.chapter = 1
	check("first chapter not over", not g.story.adventure_over())
	g.story.chapter = ch_was
	g.story.transcript = []
	g.story.read_pos = 0
	check("chapter has text to read", g.story.reading_left())
	g.start_reading()
	check("reading starts with the first paragraph", g._reading and g.story.transcript.back().text == "La pioggia batte sulla strada." and g.story.read_pos == 1, g.story.transcript.back())
	check("read text not sent to the model", not g.narrator.busy)
	check("pause button shown", g.btn_read.visible and g.btn_read.text == "Pausa")
	check("phones see the reading", g.state.ai_reading == "on" and g.state.player_view(str(st.characters()[0].id)).ai.reading == "on")
	g.net.player_read.emit(str(st.characters()[0].id), false)
	check("a phone pauses the reading", not g._reading and g.state.ai_reading == "paused" and g.story.read_pos == 1)
	g.net.player_read.emit(str(st.characters()[0].id), true)
	check("a fight in the text stops the reading", not g._reading and g.state.ini().active and g.story.read_pos == 2)
	check("read text without markers", not str(g.story.transcript[1].text).contains("[["), g.story.transcript[1].text)
	check("resume button shown", g.btn_read.visible and g.btn_read.text == "Riprendi lettura")
	g.story.add("user", "Tavolo", "Il combattimento è finito: i lupi fuggono.")
	check("what happens at the table counts as a choice", g.story.reading_diverged())
	g.start_reading()
	check("after choices the model checks the next text", g._adapting and g.story.read_pos == 2)
	check("next text shown to the narrator", str(g.story.adapt_messages("Dopo la lotta.").back().content).contains("LEGGI"))
	g._on_finished("Sconfitti i lupi, sulla strada torna il silenzio.", true, "adapt")
	check("adapted text read", g.story.transcript.back().text == "Sconfitti i lupi, sulla strada torna il silenzio." and g.story.read_pos == 3 and not g.story.reading_diverged(), g.story.transcript.back())
	g._player_says("Aria", "Mi guardo intorno.")
	check("a player acting pauses the reading", not g._reading and g.story.read_pos == 3)
	g.start_reading()
	check("end of the text to read", not g._reading and not g.story.reading_left() and not g.btn_read.visible)
	check("adapt answer: read", GameStory.parse_adapt(" Leggi.").mode == "read")
	check("adapt answer: skip", GameStory.parse_adapt("SALTA").mode == "skip")
	check("adapt answer: label dropped", GameStory.parse_adapt("Leggete: Entrate nella locanda piena di fumo.").text == "Entrate nella locanda piena di fumo.")
	check("adapt answer: new text", GameStory.parse_adapt("«La porta è già aperta, il vento la sbatte.»").text == "La porta è già aperta, il vento la sbatte.")
	# a paragraph made pointless by the players is skipped, the next one checked
	g.story.read_pos = 1
	g.story.read_mark = 0
	g.start_reading()
	g._on_finished("SALTA", true, "adapt")
	check("skipped text, next one checked", g.story.read_pos == 2 and g._adapting, g.story.read_pos)
	g._on_finished("LEGGI", true, "adapt")
	check("text read as written", g.story.transcript.back().text == "Dopo la lotta, il silenzio." and g.story.read_pos == 3)
	# prepared during a pause: Riprendi lettura reads it at once
	g.pause_reading()
	g.state.combat_end()
	g.story.read_pos = 1
	g.story.read_mark = 0
	g._prep = {}
	g._prep_key = []
	g._prepare_next()
	check("pause prepares the next text", g._prep_key == g._reading_key(), [g._reading, g._adapting, g._closing, g.narrator.busy, g._want_narration, g.story.reading_diverged(), g.state.ini().active, g.checks.size()])
	g._on_finished("La strada è vuota, i lupi sono fuggiti.", true, "prep")
	check("prepared text kept", not g._prep.is_empty())
	g.start_reading()
	check("prepared text read without waiting", g.story.transcript.back().text == "La strada è vuota, i lupi sono fuggiti." and g.story.read_pos == 2, g.story.transcript.back())
	g.pause_reading()
	g.story.read_pos = 1
	g.story.read_mark = 0
	g._prep = {}
	g._prepare_next()
	g._player_says("Bruno", "Corro avanti.")
	check("a player acting drops the preparation", g._prep_key.is_empty() and g._prep.is_empty())
	g.story.read_pos = 1
	check("narrator told the next text", str(g.story.messages().back().content).contains("Prossimo testo"))
	# a check when the action needs one, even if the narrator forgets it
	check("hint: traps", GameStory.check_hint("Prima di toccarla cerco con attenzione trappole.") == "Percezione")
	check("hint: climbing", GameStory.check_hint("Provo ad arrampicarmi sulla parete.") == "Atletica")
	check("hint: talking", GameStory.check_hint("Saluto l'oste e ordino da bere.") == "")
	check("hint: negated word", GameStory.check_hint("Alzo le mani per sembrare non minacciosa.") == "")
	# found in tests/playtest.gd: the private answer copied the request's notes
	var cs := GameStory.clean_secret("[[MESSAGGIO SEGRETO per Dario]]: Noti un residuo sulla paglia, come di veleno.\n\nIl goblin strilla e scappa. Cosa fate?\n[Messaggio SEGRETO di Dario: altro]")
	check("secret answer cleaned", cs == "Noti un residuo sulla paglia, come di veleno.", cs)
	check("not a monster", g.spawn("Nessuno").is_empty())
	# public requests do not carry the secrets (the model told them aloud)
	g.story.add_secret(str(st.characters()[0].id), "Aria", "Prendo di nascosto il sacchetto d'argento.")
	var pub := str(g.story.messages().back().content)
	check("secret not in public request", not pub.contains("sacchetto") and pub.contains("mosse segrete"), pub.left(300))
	check("secret in the private request", str(g.story.secret_messages("Aria", "altro").back().content).contains("sacchetto"))
	g.story.secrets.clear()
	# everybody down: the party wakes up at 1 PF instead of standing still
	g.state.combat_end()
	check("fight for the defeat", g.start_combat("Goblin"))
	for e in st.characters():
		e.hp = 0
	g._check_end()
	check("defeat: party wakes at 1 PF", st.characters().all(func(e): return int(e.hp) == 1) and not g.state.ini().active)
	for e in st.characters():
		e.hp = int(e.hp_max)
	g.state.combat_end()
	g.checks.clear()
	g.story.add("user", "Bruno", "Provo ad arrampicarmi sulla parete fino in cima.")
	check("hint in the request", str(g.story.messages().back().content).contains("PROVA: Atletica"))
	g._want_check = g.story.pending_check()
	g._on_finished("Bruno afferra la roccia bagnata e comincia a salire. Cosa fate?", true, "")
	check("forgotten check asked by the table", g.feed.any(func(e): return str(e.text).contains("Atletica (CD 15)")), g.feed.back().text)
	g.checks.clear()
	g.story.add("user", "Bruno", "Provo ad arrampicarmi sulla parete.")
	g._want_check = g.story.pending_check()
	g._on_finished("Bruno sale. [[PROVA: Atletica CD 12: Bruno]]", true, "")
	check("narrator's own check kept", g.feed.any(func(e): return str(e.text).contains("Atletica (CD 12)")), g.feed.back().text)
	g.checks.clear()
	# secret plots: not on the table, only on that phone, known to the narrator
	var c0 := str(st.characters()[0].id)
	var c1 := str(st.characters()[1].id)
	var feed_n: int = g.feed.size()
	g.net.player_secret.emit(c0, "Di nascosto rubo la mappa dal tavolo del capitano.")
	check("secret not on the table", g.feed.size() == feed_n)
	check("secret queued for the narrator", g._secret_queue.has(c0) or g.narrator.current_tag() == "secret")
	var tr := ""
	for line in g.story.transcript:
		tr += str(line.text)
	check("secret not in the transcript", not tr.contains("mappa dal tavolo"))
	g._secret_cid = c0
	g._on_finished("Le tue dita scivolano sulla pergamena: la mappa ora è nel tuo mantello.", true, "secret")
	var v0: Dictionary = st.player_view(c0).ai
	var v1: Dictionary = st.player_view(c1).ai
	check("secret answered on own phone", v0.secrets.size() == 1 and str(v0.secrets[0].a).contains("mantello"), v0.secrets)
	check("other phone sees nothing", v1.secrets.is_empty())
	var msgs: Array = g.story.messages()
	# public requests only say there are secrets: with the text the model told
	# them aloud (tests/llm_results/2026-11-24_partita*.md)
	check("public request keeps the secret out", not str(msgs.back().content).contains("rubo la mappa") and str(msgs.back().content).contains("mosse segrete"))
	check("private request remembers the secret", str(g.story.secret_messages(str(st.find_entity(c0).name), "e poi?").back().content).contains("rubo la mappa"))
	g._secret_queue.clear()
	st.set_story({})
	print("game test: " + ("OK" if fails == 0 else "%d FAIL" % fails))
	quit()
