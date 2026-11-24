extends SceneTree
# A whole evening of Dnd The Game played by itself: the real local narrator
# and four players, each played by the same local model with their own
# character, temper and memory (they only know what was said at the table,
# plus their own secrets). Fights are played by simple rules on the battle
# map: walk to the nearest enemy, Scatto when too far, Rialzati when prone,
# attack.
#
# It measures what can be counted (times, length, markers, checks, fights,
# reading adapted or skipped, secrets, names the narrator invents, how much a
# reply picks up the player's words) and writes the whole evening to
# tests/llm_results/<date>_partita.md so a person can judge the rest:
# coherence, quotes, how the story bends to the players' choices.
#
# godot --headless --path . -s tests/playtest.gd -- [--minutes 60] [--model gemma4:e4b-it-q4_K_M]

const STOP := ["della", "delle", "degli", "nella", "nelle", "sulla", "dalla", "questo", "questa", "quello", "quella",
	"sono", "siamo", "come", "cosa", "fate", "ancora", "anche", "verso", "dove", "quando", "mentre", "prima", "dopo",
	"molto", "tutto", "tutti", "ogni", "senza", "perché", "allora", "vostro", "vostra", "vostri", "nostro", "nostra"]
const ENGLISH := [" the ", " and ", " you ", " is ", " of the ", " with ", " what do "]

## The adventure: three chapters written as GUIDA_STORIE.md asks (outline in
## the first 1400 characters, "Da leggere" paragraphs, full text after).
const ADVENTURE := {"title": "La carovana scomparsa", "chapters": [
	{"title": "La locanda del Corvo Zoppo", "text": "Obiettivo: scoprire che fine ha fatto la carovana del mercante Ilario, attesa a Roccalta da tre giorni.\nLuoghi: la locanda del Corvo Zoppo, piena di fumo e di odore di zuppa di cipolle; la stalla dietro la locanda, dove dorme un carrettiere ferito; la piazza del villaggio, con il pozzo e la bacheca degli avvisi.\nPNG: Marta, l'ostessa, sa che il carrettiere Gualtiero è tornato da solo ieri notte con una freccia nella spalla. Gualtiero, carrettiere della carovana, ferito e spaventato: racconta dell'assalto dei goblin al Guado dei Salici. Gualtiero mente su un punto: ha venduto ai goblin la strada della carovana per un sacchetto d'argento; lo ammette solo se minacciato o se qualcuno trova il sacchetto nella paglia. Ilario il mercante è tra i prigionieri.\nMostri: nessuno in questo capitolo.\nProve: Intuizione CD 13 per capire che Gualtiero nasconde qualcosa; Indagare CD 12 per trovare il sacchetto d'argento nella paglia della stalla.\nMomenti: la sera alla locanda e la richiesta di Marta; la stalla e il racconto di Gualtiero; la partenza verso il bosco dei Salici.\nIl capitolo finisce quando il gruppo lascia Roccalta diretto al bosco dei Salici.\n\nDa leggere: La pioggia batte sulle finestre della locanda del Corvo Zoppo. Dentro, il fuoco scoppietta e l'aria sa di zuppa di cipolle e di lana bagnata. Al bancone, Marta l'ostessa asciuga lo stesso boccale da troppo tempo e guarda la porta ogni volta che si apre.\n\nDa leggere: Quando vi vede, Marta posa il boccale e vi fa cenno di avvicinarvi. Parla a bassa voce: la carovana del mercante Ilario doveva arrivare tre giorni fa con il sale e le stoffe per l'inverno, e ieri notte è tornato solo uno dei carrettieri, con una freccia nella spalla. Ora dorme nella stalla, dietro la locanda.\n\nDa leggere: Nella stalla l'aria è calda e sa di fieno. Gualtiero, il carrettiere, è sdraiato sulla paglia con la spalla fasciata. Quando vi vede si tira su a fatica, con gli occhi che scappano verso un angolo della stalla.\n\n## La stalla\n\nIl sacchetto d'argento è nascosto nella paglia sotto la mangiatoia: trenta monete d'argento nuove, con il marchio di un banco di città. Gualtiero dice che i goblin hanno attaccato al Guado dei Salici, che erano almeno una dozzina e che hanno portato via Ilario e gli altri due carrettieri verso nord, oltre il bosco. Se messo alle strette piange e confessa: uno straniero col mantello verde gli ha pagato la strada e l'ora del passaggio.\n\n## La piazza\n\nSulla bacheca del pozzo c'è un avviso del capo villaggio: una ricompensa di cinquanta monete d'oro a chi riporta il sale della carovana."},
	{"title": "Il bosco dei Salici", "text": "Obiettivo: seguire le tracce della carovana attraverso il bosco dei Salici fino al covo dei goblin.\nLuoghi: il Guado dei Salici, con i carri rovesciati nel fango e le casse sfondate; il sentiero nel bosco, stretto, con rami bassi e odore di muschio; la radura dei lupi, dove le ossa scricchiolano sotto i piedi.\nPNG: Pippo, un giovane goblin esploratore rimasto indietro, impaurito: se catturato e trattato bene indica la grotta e dice che il capo si chiama Sgnacco.\nMostri: Lupo x2 nella radura.\nProve: Sopravvivenza CD 12 per seguire le tracce oltre il guado; Percezione CD 13 per accorgersi dei lupi prima che attacchino.\nMomenti: il guado con i carri distrutti; il sentiero e l'incontro con Pippo; la radura e i lupi; il fumo della grotta in lontananza.\nIl capitolo finisce quando il gruppo vede l'imbocco della grotta dei goblin.\n\nDa leggere: All'alba la pioggia ha smesso. Il Guado dei Salici è un pantano: due carri giacciono rovesciati nel fango, le casse sfondate, il sale sciolto in rivoli bianchi verso il fiume. Tra le impronte degli zoccoli si vedono piedi piccoli e nudi, tanti, diretti a nord.\n\nDa leggere: Il sentiero entra nel bosco. I salici piangono sull'acqua e i loro rami bassi vi sfiorano il viso. Dopo un'ora di cammino sentite un rametto spezzarsi, poco più avanti, e una vocina che impreca.\n\nDa leggere: La radura si apre all'improvviso. Il terreno è coperto di ossa spolpate e due lupi magri alzano il muso dal loro pasto, con il pelo ritto sulla schiena. [[COMBATTIMENTO: Lupo x2]]\n\n## Il guado\n\nNel fango c'è un frammento di mantello verde impigliato a una ruota: lo stesso colore dello straniero di cui parla Gualtiero, se ha confessato.\n\n## Pippo\n\nPippo è alto come un bambino, ha un orecchio mozzato e un arco troppo grande per lui. Ha paura di Sgnacco più che del gruppo. Sa che i prigionieri sono chiusi in gabbie in fondo alla grotta e che Sgnacco porta la chiave al collo."},
	{"title": "La grotta dei goblin", "text": "Obiettivo: liberare il mercante Ilario e i carrettieri prigionieri nella grotta.\nLuoghi: l'imbocco della grotta, umido e con un forte odore di fumo; la sala del fuoco, dove tre goblin dormono attorno alle braci; le gabbie in fondo, dove sono chiusi i prigionieri.\nPNG: Ilario, mercante grasso e lamentoso, sa che Sgnacco aspetta lo straniero col mantello verde per dividere il bottino. Sgnacco, il capo goblin, ha paura del fuoco e prova a trattare se minacciato con una torcia.\nMostri: Goblin x3 nella sala del fuoco, Capo goblin vicino alle gabbie.\nProve: Furtività CD 12 per passare la sala senza svegliare i goblin; Atletica CD 14 per forzare le gabbie.\nMomenti: l'imbocco; la sala del fuoco; le gabbie e Ilario; Sgnacco.\nIl capitolo finisce quando i prigionieri sono liberi e il gruppo esce dalla grotta.\n\nDa leggere: L'imbocco della grotta è una bocca nera tra le rocce, da cui esce un filo di fumo grasso. Dentro, il suolo è viscido e l'eco porta il russare di qualcuno, più in fondo.\n\nDa leggere: La sala del fuoco è bassa e annerita. Tre goblin dormono attorno alle braci, uno con la bocca aperta e un osso in mano. Dall'altra parte, oltre un arco di pietra, si intravedono le sbarre di legno delle gabbie.\n\n## Le gabbie\n\nLe gabbie sono di legno legato con corde. Ilario è dentro con due carrettieri, affamati ma vivi. Sgnacco dorme seduto su un forziere, con la chiave appesa al collo a un dente d'orco."},
]}

## Four players: who they are and how they play. The schemers may plot in
## secret ("SEGRETO:" at the start of the answer).
const PLAYERS := [
	{"name": "Aria", "temper": "curiosa e furtiva: guarda ovunque, cerca trappole e indizi, ogni tanto ruba qualcosa", "secret": true},
	{"name": "Bruno", "temper": "impulsivo e diretto: preferisce le maniere forti, minaccia, sfonda le porte, fa battute da nano", "secret": false},
	{"name": "Clelia", "temper": "prudente e gentile: parla con i PNG, fa domande, cura i feriti, cerca di evitare la violenza", "secret": false},
	{"name": "Dario", "temper": "sapientone e calcolatore: fa domande sulla magia e sulla storia del posto, propone piani, ogni tanto fa una scelta inaspettata", "secret": true},
]

var g
var pl := Narrator.new()  # the players' brain: same model, its own requests
var minutes := 60.0
var t0 := 0
var tlog: Array = []      # {t, who, text, kind}
var replies: Array = []  # master replies with their measures
var adapts: Array = []
var secrets_log: Array = []
var events := {"fights": 0, "pc_attacks": 0, "dash": 0, "stand": 0, "opportunity": 0,
	"chapters_closed": 0, "forced_close": 0, "player_calls": 0, "player_fail": 0}
var _busy_since := 0
var _first_ms := -1
var _seen_tr := 0
var _seen_chapter := 1
var _seen_feed: Array = []
var _turn := 0
var _chapter_lines := 0
var _last_player := ""
var _pl_reply := {}
var _was_fighting := false


func now_s() -> float:
	return (Time.get_ticks_msec() - t0) / 1000.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var model := ""
	for i in args.size():
		var v := args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--minutes": minutes = maxf(1.0, float(v))
			"--model": model = v
	g = load("res://game/game_main.gd").new()
	g.test_mode = true
	root.add_child(g)
	for i in 5:
		await process_frame
	_setup_party()
	if model != "":
		g.narrator.model = model
	pl.model = g.narrator.model
	root.add_child(pl)
	pl.finished.connect(func(full, ok, _tag): _pl_reply = {"full": full, "ok": ok})
	g.narrator.chunk.connect(func(_p):
		if _first_ms < 0 and _busy_since > 0:
			_first_ms = Time.get_ticks_msec() - _busy_since)
	g.narrator.finished.connect(_on_master)
	g.state.map_event.connect(func(_t, _l): events.opportunity += 1)
	# the adventure starts now, with the real narrator
	g.llm_in_tests = true
	g.state.set_story(ADVENTURE.duplicate(true))
	t0 = Time.get_ticks_msec()
	g._open_story()
	await _play()
	_report()
	quit()


func _setup_party() -> void:
	var st: GameState = g.state
	var c := st.add_character("Clelia", "Giocatore 3")
	st.update_character(c.id, {"cls": "Chierica", "race": "Umana", "level": 3, "hp_max": 24, "hp": 24, "ac": 16,
		"ab": {"FOR": 13, "DES": 10, "COS": 14, "INT": 10, "SAG": 16, "CAR": 12},
		"saves": ["SAG", "CAR"], "skills": {"medicina": 1, "intuizione": 1, "persuasione": 1},
		"attacks": [{"name": "Mazza", "bonus": 3, "damage": "1d6+1"}]})
	var d := st.add_character("Dario", "Giocatore 4")
	st.update_character(d.id, {"cls": "Mago", "race": "Gnomo", "level": 3, "hp_max": 17, "hp": 17, "ac": 12,
		"ab": {"FOR": 8, "DES": 14, "COS": 12, "INT": 17, "SAG": 12, "CAR": 10},
		"saves": ["INT", "SAG"], "skills": {"arcano": 1, "storia": 1, "indagare": 1},
		"attacks": [{"name": "Balestra leggera", "bonus": 4, "damage": "1d8+2"}, {"name": "Pugnale", "bonus": 4, "damage": "1d4+2"}]})
	st.add_monster({"name": "Lupo", "ac": 13, "hp": 11, "init_mod": 2, "notes": "Morso +4, 2d4+2", "xp": 50})


func _pc(name: String) -> Dictionary:
	for e in g.state.characters():
		if e.name == name:
			return e
	return {}


# ------------------------------------------------------------------ the table
func _idle() -> bool:
	var tag: String = g.narrator.current_tag()
	return (not g.narrator.busy or tag == "prep") and not g._reading and not g._adapting and g.checks.is_empty() \
		and not g._closing and not g._want_narration and not g._wait_call.is_valid()


func _play() -> void:
	var quiet := 0.0
	while now_s() < minutes * 60.0:
		await process_frame
		_watch()
		if g.state.ini().active:
			if not _was_fighting:
				_was_fighting = true
				events.fights += 1
			await _fight_step()
			continue
		_was_fighting = false
		if not _idle():
			quiet = 0.0
			continue
		quiet += 1.0 / 60.0
		if quiet < 1.0:  # a breath between replies, as at a real table
			continue
		quiet = 0.0
		# the adventure is over: the epilogue and a few free turns, then stop
		if g.story.adventure_over() and g.story.transcript.size() >= 6:
			break
		# too long a chapter: the players close it by hand (as the guide says)
		if _chapter_lines >= 34:
			_chapter_lines = 0
			events.forced_close += 1
			_log("Il gruppo", "(preme Fine capitolo)", "player")
			g._ask_close_chapter()
			continue
		# after a couple of actions the players press Riprendi lettura
		if g.story.reading_left() and (not g.story.reading_diverged() or _turn % 3 == 2):
			_turn += 1
			_log("Il gruppo", "(preme Riprendi lettura)", "player")
			g.start_reading()
			continue
		await _player_turn()
	# let the last reply finish
	var wait := 0.0
	while g.narrator.busy and wait < 90.0:
		await process_frame
		wait += 1.0 / 60.0
		_watch()


## Copies what happened at the table into the log, with the time.
func _watch() -> void:
	if g.story.chapter != _seen_chapter:
		_seen_chapter = g.story.chapter
		_seen_tr = 0
		_chapter_lines = 0
		events.chapters_closed += 1
		_log("Tavolo", "Capitolo %d: %s" % [g.story.chapter, str(g.story.chapter_info().get("title", ""))], "chapter")
	for e in g.feed:
		if str(e.kind) in ["combat", "info"] and not _seen_feed.any(func(x): return is_same(x, e)):
			_seen_feed.append(e)
			_log(str(e.who), str(e.text), str(e.kind))
	var tr: Array = g.story.transcript
	if tr.size() < _seen_tr:
		_seen_tr = 0
	while _seen_tr < tr.size():
		var t: Dictionary = tr[_seen_tr]
		_seen_tr += 1
		_chapter_lines += 1
		if str(t.who) == "Tavolo" or t.role == "assistant":
			_log(str(t.who), str(t.text), "master" if t.role == "assistant" else "table")
	if _seen_feed.size() > 400:
		_seen_feed = _seen_feed.slice(200)
	if g.narrator.busy and _busy_since == 0:
		_busy_since = Time.get_ticks_msec()
		_first_ms = -1


func _log(who: String, text: String, kind: String) -> void:
	tlog.append({"t": now_s(), "who": who, "text": text, "kind": kind})


# ---------------------------------------------------------------- the players
func _player_turn() -> void:
	# who speaks: the one the master named last, else the next one around
	var last_master := ""
	for i in range(tlog.size() - 1, -1, -1):
		if tlog[i].kind == "master":
			last_master = str(tlog[i].text)
			break
	var pick: Dictionary = PLAYERS[_turn % PLAYERS.size()]
	for p in PLAYERS:
		if last_master.contains(str(p.name)) and str(p.name) != _last_player:
			pick = p
	if str(pick.name) == _last_player:
		pick = PLAYERS[(_turn + 1) % PLAYERS.size()]
	_turn += 1
	var me := _pc(str(pick.name))
	if me.is_empty() or int(me.hp) <= 0:
		return
	_last_player = str(pick.name)
	var text := await _ask_player(pick, me)
	if text == "":
		events.player_fail += 1
		return
	# "SEGRETO:" can come after a public action: the action is said aloud,
	# the rest goes to the master only
	var at := text.to_upper().find("SEGRETO")
	if bool(pick.secret) and at >= 0:
		var said := text.left(at).strip_edges()
		var rest := text.substr(at + 7).strip_edges().trim_prefix(":").strip_edges()
		if said != "":
			_log(str(pick.name), said, "player")
			g._on_player_said(str(me.id), said)
		var plot := rest
		_log(str(pick.name) + " (in segreto)", plot, "secret")
		secrets_log.append({"who": pick.name, "text": plot, "t": now_s(), "reply": "", "ms": 0})
		g._on_player_secret(str(me.id), plot)
		return
	_log(str(pick.name), text, "player")
	g._on_player_said(str(me.id), text)


func _ask_player(p: Dictionary, me: Dictionary) -> String:
	var seen: Array = []
	for e in tlog.slice(maxi(0, tlog.size() - 14)):
		if str(e.kind) in ["master", "player", "table", "combat"]:
			seen.append("%s: %s" % [e.who, str(e.text).left(500)])
	var mine: Array = []
	for s in g.story.secrets:
		if str(s.who) == str(p.name):
			mine.append("Tu in segreto: %s / Il master solo a te: %s" % [s.text, s.reply])
	var others: Array = []
	for x in PLAYERS:
		if x.name != p.name:
			others.append(x.name)
	var sys := ("Stai giocando a Dungeons & Dragons con degli amici, attorno a un tavolo. Il master è un altro. "
		+ "Tu interpreti %s, %s %s di livello %d. Il tuo modo di giocare: %s. " % [p.name, str(me.get("race", "")).to_lower(), str(me.get("cls", "")).to_lower(), int(me.get("level", 1)), p.temper]
		+ "Gli altri personaggi del gruppo sono: %s. " % ", ".join(others)
		+ "Rispondi con quello che fa o dice il tuo personaggio adesso, in prima persona, al massimo due frasi, in italiano parlato. "
		+ "Dici solo cosa provi a fare o cosa dici, mai cosa succede dopo. Non parlare per gli altri personaggi. Niente prefissi, niente virgolette, niente elenchi.")
	if bool(p.secret):
		sys += " Se vuoi fare qualcosa all'insaputa degli altri giocatori (un piano tuo, un furto, una domanda privata al master), comincia con SEGRETO: e poi scrivi la richiesta. Fallo di rado, e non ripetere una richiesta segreta che hai già fatto."
	var user := "Ecco cosa è successo finora al tavolo:\n" + "\n".join(seen)
	if not mine.is_empty():
		user += "\n\nCose che sai solo tu:\n" + "\n".join(mine.slice(maxi(0, mine.size() - 3)))
	user += "\n\nTocca a te. Cosa fa %s?" % p.name
	_pl_reply = {}
	events.player_calls += 1
	var tries := 0
	while not pl.ask([{"role": "system", "content": sys}, {"role": "user", "content": user}], {"max": 90, "temp": 0.9, "tag": "player"}):
		await process_frame
		tries += 1
		if tries > 3000:
			return ""
	while _pl_reply.is_empty():
		await process_frame
		_watch()
	if not bool(_pl_reply.ok):
		return ""
	var t := str(_pl_reply.full).strip_edges().replace("\n", " ")
	for pre in [p.name + ":", "**" + p.name + "**:", "\"", "«"]:
		t = t.trim_prefix(pre).strip_edges()
	return t.trim_suffix("\"").trim_suffix("»").strip_edges().left(300)


# ----------------------------------------------------------------- the fights
func _fight_step() -> void:
	var st: GameState = g.state
	var cur: Dictionary = st.current_combatant()
	if cur.is_empty() or str(cur.type) != "pc" or g._wait_call.is_valid():
		return
	var cid := str(cur.ref)
	var me := st.find_entity(cid)
	if me.is_empty() or int(me.hp) <= 0:
		return
	await create_timer(0.6).timeout
	if not st.ini().active or str(st.current_combatant().get("ref", "")) != cid:
		return
	if Actions.has_cond(me, "Prono") and bool(st.maneuver(cid, "stand").ok):
		events.stand += 1
		_log(me.name, "si rialza", "combat")
	# nearest enemy standing
	var tid := ""
	var bd := INF
	for c in st.ini().combatants:
		var e := st.find_entity(str(c.ref))
		if c.type == "monster" and not e.is_empty() and int(e.hp) > 0:
			var d := st.map_dist_m(cid, str(c.ref))
			if d < 0:
				d = 1.5
			if d < bd:
				bd = d
				tid = str(c.ref)
	if tid == "":
		return
	var melee: Dictionary = {}
	var ranged: Dictionary = {}
	for a in Actions.list_for(st, cid):
		if a.group != "Attacchi":
			continue
		if bool(a.ranged) and ranged.is_empty():
			ranged = a
		elif not bool(a.ranged) and melee.is_empty():
			melee = a
	var a: Dictionary = melee
	if not ranged.is_empty() and (melee.is_empty() or bd > 1.6) and str(me.name) in ["Aria", "Dario"]:
		a = ranged
	if a.is_empty():
		g._end_pc_turn(cid)
		return
	if not bool(a.get("ranged", false)) and bd > 1.6:
		_walk_to(cid, tid)
		if st.map_dist_m(cid, tid) > 1.6:
			if bool(st.maneuver(cid, "dash").ok):
				events.dash += 1
				_walk_to(cid, tid)
			_log(me.name, "corre verso il nemico (Scatto)", "combat")
			g._end_pc_turn(cid)
			return
	var res: Dictionary = Actions.resolve(st, cid, a, [tid], {"adv": "auto"})
	if bool(res.ok):
		events.pc_attacks += 1
		g._on_player_action(cid, "%s: %s" % [me.name, a.name], res.lines)
	else:
		_log(me.name, "non attacca: " + str(res.error), "combat")
	await create_timer(0.4).timeout
	if st.ini().active:
		g._end_pc_turn(cid)


## Walks square by square toward the target with the movement left.
func _walk_to(cid: String, tid: String) -> void:
	var st: GameState = g.state
	var mp: Dictionary = st.find_map(str(st.data.get("map_active", "")))
	if mp.is_empty():
		return
	var n := GameState.map_size(mp)
	var t := st.map_pos(tid)
	for i in 30:
		var p := st.map_pos(cid)
		if maxi(absi(p.x - t.x), absi(p.y - t.y)) <= 1 or st.move_left(cid) <= 0:
			return
		var best := Vector2i(-1, -1)
		var bs := INF
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var q := p + Vector2i(dx, dy)
				if q == p or q.x < 0 or q.y < 0 or q.x >= n.x or q.y >= n.y or not st.token_at(mp, q.x, q.y).is_empty():
					continue
				var s := Vector2(q - t).length()
				if s < bs and s < Vector2(p - t).length():
					bs = s
					best = q
		if best.x < 0 or st.player_move(cid, best.x, best.y) != "":
			return


# ------------------------------------------------------------- the measures
func _on_master(full: String, ok: bool, tag: String) -> void:
	var ms := Time.get_ticks_msec() - _busy_since if _busy_since > 0 else -1
	var first := _first_ms
	_busy_since = 0
	if tag in ["adapt", "prep"]:
		var r := GameStory.parse_adapt(full) if ok else {"mode": "error"}
		var paras: Array = g.story.read_aloud()
		adapts.append({"t": now_s(), "tag": tag, "mode": r.mode, "text": full.strip_edges(), "ms": ms,
			"raw": str(paras[g.story.read_pos]) if g.story.read_pos < paras.size() else ""})
		return
	if tag == "secret":
		for s in secrets_log:
			if str(s.reply) == "":
				s.reply = full.strip_edges()
				s.ms = ms
				break
		return
	if tag in ["chap", "camp"]:
		_log("Riassunto", full.strip_edges(), "summary")
		return
	if tag != "":
		return
	if not ok:
		replies.append({"t": now_s(), "ok": false, "ms": ms})
		return
	# the line it answers: the last user line before it
	var prev := ""
	var tr: Array = g.story.transcript
	for i in range(tr.size() - 1, -1, -1):
		if tr[i].role == "user":
			prev = str(tr[i].text)
			break
	replies.append(_measure(full, prev, ms, first))


func _sentences(t: String) -> Array:
	var out: Array = []
	for m in RegEx.create_from_string("[^.!?]+[.!?]*").search_all(t):
		if m.get_string().strip_edges().length() > 2:
			out.append(m.get_string().strip_edges())
	return out


func _stems(t: String) -> Array:
	var out: Array = []
	for w in RegEx.create_from_string("[a-zàèéìòù]{5,}").search_all(t.to_lower()):
		var s := w.get_string()
		if not STOP.has(s) and not out.has(s.left(5)):
			out.append(s.left(5))
	return out


static func _to_player(prev: String) -> bool:
	return prev != "" and not prev.begins_with("Risultato") and not prev.begins_with("Il combattimento") and not prev.begins_with("Inizia")


func _measure(full: String, prev: String, ms: int, first: int) -> Dictionary:
	var text := GameStory.strip_tags(full)
	var sent := _sentences(text)
	var low := " " + text.to_lower() + " "
	var acts: Array = []
	for s in sent:
		for p in PLAYERS:
			if RegEx.create_from_string("^(%s)( e \\w+)?\\s+(?!,)" % p.name).search(s) and not s.ends_with("?"):
				acts.append(s)
	var ps := _stems(prev)
	var rs := _stems(text)
	var shared: Array = ps.filter(func(x): return rs.has(x))
	var kinds: Array = GameStory.tags(full).map(func(t): return t[0])
	return {"t": now_s(), "ok": true, "ms": ms, "first": first, "words": text.split(" ", false).size(), "sentences": sent.size(),
		"question": text.ends_with("?"), "acts": acts, "english": ENGLISH.any(func(w): return low.contains(w)),
		"numbers": RegEx.create_from_string("\\b\\d+d\\d+\\b|\\b\\d+\\s*(pf|punti ferita|danni)\\b").search(low) != null,
		"tags": kinds, "prev": prev, "shared": shared, "text": text}


func _report() -> void:
	var ok_r: Array = replies.filter(func(r): return r.ok)
	var n := maxi(1, ok_r.size())
	var sum_ms := 0
	var sum_first := 0
	var nf := 0
	var words := 0
	var long := 0
	var q := 0
	var acts := 0
	var eng := 0
	var nums := 0
	var picks := 0
	var to_players := 0
	var kinds := {}
	var max_ms := 0
	for r in ok_r:
		sum_ms += int(r.ms)
		max_ms = maxi(max_ms, int(r.ms))
		if int(r.first) > 0:
			sum_first += int(r.first)
			nf += 1
		words += int(r.words)
		long += int(int(r.sentences) > 5 or int(r.words) > 90)
		q += int(bool(r.question))
		acts += int(not r.acts.is_empty())
		eng += int(bool(r.english))
		nums += int(bool(r.numbers))
		if _to_player(str(r.prev)):
			to_players += 1
			picks += int(not r.shared.is_empty())
		for k in r.tags:
			kinds[k] = int(kinds.get(k, 0)) + 1
	var modes := {}
	for a in adapts:
		modes[a.mode] = int(modes.get(a.mode, 0)) + 1
	# paragraphs read word for word without asking the model (nothing had
	# happened at the table since the last one)
	var written := {}
	for ch in ADVENTURE.chapters:
		for para in StoryImport.read_aloud(str(ch.text)):
			written[GameStory.strip_tags(str(para))] = true
	for e in tlog:
		if str(e.kind) == "master" and written.has(str(e.text).strip_edges()):
			modes["read"] = int(modes.get("read", 0)) + 1
	# capitalised words the adventure and the party don't have
	var known := ["Aria", "Bruno", "Clelia", "Dario", "Marta", "Gualtiero", "Ilario", "Pippo", "Sgnacco", "Roccalta", "Salici", "Corvo", "Zoppo", "Cosa", "Goblin", "Lupo", "Capo", "Guado"]
	var invented := {}
	for r in ok_r:
		for s in _sentences(str(r.text)):
			var ws: PackedStringArray = str(s).split(" ", false)
			for i in range(1, ws.size()):
				var w: String = ws[i].strip_edges().trim_suffix(",").trim_suffix(".").trim_suffix("!").trim_suffix("?").trim_suffix(":").trim_suffix(";")
				if w.length() > 2 and w[0] == w[0].to_upper() and w[0] != w[0].to_lower() and not known.has(w):
					invented[w] = int(invented.get(w, 0)) + 1
	# secrets: their own words in later public replies
	var leaks: Array = []
	for s in secrets_log:
		var ss := _stems(str(s.text))
		for r in ok_r:
			if float(r.t) > float(s.t):
				var rs := _stems(str(r.text))
				var hit: Array = ss.filter(func(x): return rs.has(x))
				if hit.size() >= 3:
					leaks.append("%s (%.0f min): %s" % [s.who, float(r.t) / 60.0, ", ".join(hit)])
	var L: Array = []
	var date := Time.get_date_string_from_system()
	L.append("# Partita simulata: %s, %s" % [ADVENTURE.title, date])
	L.append("")
	L.append("Modello: `%s`. Durata: %.0f minuti. Quattro giocatori simulati dallo stesso modello, ognuno con il suo carattere e solo quello che ha sentito al tavolo. Generato da `tests/playtest.gd`." % [g.narrator.model, now_s() / 60.0])
	L.append("")
	L.append("## Misure")
	L.append("")
	L.append("| Misura | Valore |")
	L.append("|---|---|")
	L.append("| Risposte del master | %d (%d errori) |" % [ok_r.size(), replies.size() - ok_r.size()])
	L.append("| Tempo medio di risposta | %.1f s (prima parola %.1f s, massimo %.1f s) |" % [sum_ms / 1000.0 / n, sum_first / 1000.0 / maxi(1, nf), max_ms / 1000.0])
	L.append("| Parole per risposta | %.0f |" % (float(words) / n))
	L.append("| Troppo lunghe (più di 5 frasi o 90 parole) | %d (%.0f%%) |" % [long, 100.0 * long / n])
	L.append("| Chiudono con una domanda | %d (%.0f%%) |" % [q, 100.0 * q / n])
	L.append("| Fanno agire un personaggio dei giocatori | %d (%.0f%%) |" % [acts, 100.0 * acts / n])
	L.append("| Parole inglesi / numeri di gioco | %d / %d |" % [eng, nums])
	L.append("| Riprendono parole del giocatore | %d su %d (%.0f%%) |" % [picks, to_players, 100.0 * picks / maxi(1, to_players)])
	L.append("| Marcatori | %s |" % (", ".join(kinds.keys().map(func(k): return "%s %d" % [k, kinds[k]])) if not kinds.is_empty() else "nessuno"))
	L.append("| Testo da leggere: letto / adattato / saltato | %d / %d / %d (errori %d) |" % [int(modes.get("read", 0)), int(modes.get("text", 0)), int(modes.get("skip", 0)), int(modes.get("error", 0))])
	L.append("| Segreti / risposte private | %d / %d |" % [secrets_log.size(), secrets_log.filter(func(s): return str(s.reply) != "").size()])
	L.append("| Segreti che riaffiorano in pubblico (3+ parole) | %d |" % leaks.size())
	L.append("| Capitoli chiusi / chiusi a mano dai giocatori | %d / %d |" % [events.chapters_closed, events.forced_close])
	L.append("| Combattimenti; attacchi dei PG, Scatto, Rialzati, attacchi di opportunità | %d; %d, %d, %d, %d |" % [events.fights, events.pc_attacks, events.dash, events.stand, events.opportunity])
	L.append("| Chiamate ai giocatori simulati (fallite) | %d (%d) |" % [events.player_calls, events.player_fail])
	L.append("")
	if not invented.is_empty():
		var inv: Array = invented.keys()
		inv.sort_custom(func(x, y): return invented[x] > invented[y])
		L.append("Parole con la maiuscola che l'avventura non ha (PNG o luoghi inventati, o solo l'inizio di una battuta): " + ", ".join(inv.slice(0, 30).map(func(k): return "%s (%d)" % [k, invented[k]])) + ".")
		L.append("")
	if not leaks.is_empty():
		L.append("Possibili fughe di segreti: " + "; ".join(leaks) + ".")
		L.append("")
	var puppets: Array = []
	for r in ok_r:
		for s in r.acts:
			puppets.append("- %s" % s)
	if not puppets.is_empty():
		L.append("### Frasi in cui il master fa agire un personaggio")
		L.append("")
		L.append_array(puppets.slice(0, 20))
		L.append("")
	L.append("## Testo da leggere adattato")
	L.append("")
	for a in adapts:
		L.append("- **%s** (%.0f', %s, %.1f s)  \n  originale: %s  \n  risposta: %s" % [a.mode, float(a.t) / 60.0, a.tag, int(a.ms) / 1000.0, str(a.raw).left(300), str(a.text).left(500)])
	L.append("")
	L.append("## Segreti")
	L.append("")
	for s in secrets_log:
		L.append("- **%s** (%.0f'): %s  \n  il master, solo a lui: %s" % [s.who, float(s.t) / 60.0, s.text, s.reply])
	L.append("")
	L.append("## La partita")
	L.append("")
	for e in tlog:
		var who := str(e.who)
		var txt := str(e.text).replace("\n", " ")
		match str(e.kind):
			"chapter":
				L.append("")
				L.append("### " + txt)
				L.append("")
			"master":
				L.append("`%5.1f'` **Master:** %s" % [float(e.t) / 60.0, txt])
				L.append("")
			"player", "secret":
				L.append("`%5.1f'` **%s:** _%s_" % [float(e.t) / 60.0, who, txt])
				L.append("")
			_:
				L.append("`%5.1f'` %s: %s" % [float(e.t) / 60.0, who, txt])
				L.append("")
	var path := "res://tests/llm_results/%s_partita.md" % date
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(L) + "\n")
	f.close()
	print("partita: %d risposte, %.1f s di media, report in %s" % [ok_r.size(), sum_ms / 1000.0 / n, path])
