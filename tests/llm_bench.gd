extends SceneTree
# Reference tests for the local narrator of Dnd The Game.
#
# Plays fixed table situations against the real model (Ollama must be running
# or installed) and checks each reply with simple, repeatable rules: short,
# ends with a question, never acts for the players' characters, Italian, no
# dice numbers, and the right marker ([[PROVA]], [[COMBATTIMENTO]],
# [[FINE CAPITOLO]] or none). Every scenario runs several times because the
# model is not deterministic.
#
# Writes tests/llm_results/<date>_<model>.md with every reply and appends one
# line to tests/llm_results/storico.csv, so a change of model or prompt can
# be compared with the previous runs.
#
# godot --headless --path . -s tests/llm_bench.gd -- [--model qwen2.5:3b] [--runs 3] [--only combattimento]

const PCS := ["Aria", "Bruno"]
const ENGLISH := [" the ", " and ", " you ", " is ", " of the ", " with ", " what do "]

## expect: "prova", "combattimento", "fine capitolo", "nessuno" or "libero" (any).
## kind "summary" checks the chapter summary instead of a narrator reply.
var SCENARIOS := [
	{"name": "apertura", "expect": "nessuno", "lines": [
		["user", "Tavolo", "Inizia l'avventura. Presenta il luogo e la situazione iniziale ai personaggi."]]},
	{"name": "esplorazione", "expect": "libero", "lines": [
		["assistant", "Master", "La strada fangosa porta a una collina. Le tracce della carovana spariscono tra i cespugli, verso l'imbocco buio di una grotta. Cosa fate?"],
		["user", "Il gruppo", "Seguiamo le tracce ed entriamo nella grotta con le armi in pugno."]]},
	{"name": "prova_percezione", "expect": "prova", "lines": [
		["assistant", "Master", "In fondo al corridoio c'è una porta di legno rinforzata con ferro. Dall'altra parte arriva un ronzio sommesso. Cosa fate?"],
		["user", "Aria", "Prima di toccarla cerco con attenzione trappole o fili sulla porta."]]},
	{"name": "prova_atletica", "expect": "prova", "lines": [
		["assistant", "Master", "Il sentiero finisce contro una parete di roccia bagnata, alta una decina di metri. In cima si vede la luce di una torcia. Cosa fate?"],
		["user", "Bruno", "Provo ad arrampicarmi sulla parete fino in cima."]]},
	{"name": "combattimento", "expect": "combattimento", "lines": [
		["assistant", "Master", "Nella caverna tre goblin ridono attorno a un fuoco, rosicchiando ossa. Non vi hanno ancora visti. Cosa fate?"],
		["user", "Bruno", "Carico i goblin con l'ascia alzata, urlando!"]]},
	{"name": "imboscata", "expect": "combattimento", "lines": [
		["assistant", "Master", "Il bosco si fa fitto e silenzioso. Cosa fate?"],
		["user", "Il gruppo", "Andiamo avanti sul sentiero."],
		["user", "Tavolo", "Due lupi affamati sbucano dai cespugli e attaccano il gruppo."]]},
	{"name": "dialogo", "expect": "nessuno", "lines": [
		["assistant", "Master", "La locanda del Cinghiale è piena di fumo. Il locandiere, un uomo grasso con un grembiule macchiato, asciuga un boccale. Cosa fate?"],
		["user", "Aria", "Mi avvicino al bancone e gli chiedo se ha visto passare una carovana tre giorni fa."]]},
	{"name": "dopo_combattimento", "expect": "nessuno", "lines": [
		["assistant", "Master", "I goblin vi si lanciano contro brandendo le scimitarre!"],
		["user", "Tavolo", "Il combattimento è finito: i goblin sono stati sconfitti. Aria ha 9 PF su 21, Bruno 31 su 31."]]},
	{"name": "fine_capitolo", "expect": "fine capitolo", "lines": [
		["assistant", "Master", "Il capo goblin crolla a terra. I prigionieri della carovana vi guardano increduli dalle gabbie. Cosa fate?"],
		["user", "Il gruppo", "Liberiamo i prigionieri e li riportiamo tutti al villaggio."],
		["user", "Tavolo", "Il gruppo arriva al villaggio con i prigionieri liberati: la gente festeggia. La missione è compiuta."]]},
	{"name": "riassunto", "kind": "summary", "must": ["goblin", "carovana"], "lines": [
		["user", "Tavolo", "Inizia l'avventura."],
		["assistant", "Master", "Al villaggio di Roccalta vi chiedono di ritrovare una carovana scomparsa sulla strada del nord."],
		["user", "Il gruppo", "Seguiamo le tracce della carovana."],
		["assistant", "Master", "Le tracce portano a una grotta. Dentro, tre goblin attorno a un fuoco."],
		["user", "Tavolo", "Il combattimento è finito: i goblin sono stati sconfitti."],
		["assistant", "Master", "In fondo alla grotta trovate i mercanti della carovana chiusi in gabbie di legno."],
		["user", "Il gruppo", "Li liberiamo e torniamo al villaggio."]]},
]

## --story prosa|elenco: the same chapter with its outline written as prose
## or as a short list with a timeline. The long text after the outline holds
## details the narrator gets only through GameStory.passages().
const SHEETS := {
	"prosa": "Obiettivo: ritrovare i mercanti rapiti della carovana. I personaggi arrivano all'imbocco della grotta, umido e con un forte odore di fumo. Più avanti c'è la sala del fuoco, dove tre goblin dormono attorno alle braci. In fondo ci sono le gabbie, dove sono chiusi i mercanti; tra loro c'è Tobia, un mercante anziano e spaventato che sa dove si trova la chiave. Vicino alle gabbie veglia il capo goblin. Mostri: Goblin x3 nella sala del fuoco, Capo goblin vicino alle gabbie. Prove: Furtività CD 12 per passare la sala senza svegliare i goblin; Atletica CD 14 per forzare le gabbie. Il capitolo finisce quando i mercanti sono liberi e il gruppo esce dalla grotta.",
	"elenco": "Obiettivo: liberare mercanti rapiti, carovana.\nLuoghi: imbocco grotta, umido, odore fumo; sala fuoco, 3 goblin dormono su braci; gabbie in fondo, mercanti chiusi.\nPNG: Tobia, mercante anziano, spaventato, sa dove sta chiave.\nMostri: Goblin x3 nella sala fuoco, Capo goblin vicino gabbie\nProve: Furtività CD 12 passare sala senza svegliare; Atletica CD 14 forzare gabbie.\nLinea temporale:\n1. imbocco grotta, tracce carovana\n2. sala fuoco: passare o combattere\n3. gabbie: Tobia, chiave\n4. capo goblin\nFine: mercanti liberi, gruppo fuori dalla grotta.",
}
const FULL_TEXT := "\n\n## La sala del fuoco\n\nLa sala è bassa e annerita dal fumo. Sul fuoco gira uno spiedo con mezza capra. Accanto alle braci c'è una pila di sacchi della carovana: stoffe, sale e una cassetta di spezie.\n\n## Le gabbie\n\nLe gabbie sono di legno legato con corde. Tobia sa che il capo goblin porta la chiave delle gabbie appesa a un dente d'orco intorno al collo, e lo dice solo se il gruppo promette di cercare sua figlia Lisetta, portata via dai goblin il giorno prima.\n\n## Il capo goblin\n\nIl capo goblin si chiama Sgnacco e ha paura del fuoco: se il gruppo lo minaccia con una torcia, prova a trattare."

var g
var model := ""
var story := ""
var runs := 2
var only := ""
var reply := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var v := args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--model": model = v
			"--runs": runs = maxi(1, int(v))
			"--only": only = v
			"--story": story = v
	g = load("res://game/game_main.gd").new()
	g.test_mode = true  # no files, no opening scene
	root.add_child(g)
	for i in 5:
		await process_frame
	if story != "":
		if not SHEETS.has(story):
			print("--story: prosa oppure elenco")
			quit(1)
			return
		g.state.set_story({"title": "La carovana scomparsa", "chapters": [
			{"title": "La grotta dei goblin", "text": SHEETS[story] + FULL_TEXT}]})
		g.story.chapter = 1
		SCENARIOS.append({"name": "dettaglio_dal_testo", "expect": "libero", "any": ["dente", "lisetta", "figlia", "collo"], "lines": [
			["assistant", "Master", "In fondo alla grotta, dentro una gabbia di legno, un vecchio mercante vi fissa tremando. Cosa fate?"],
			["user", "Aria", "Mi avvicino piano e chiedo a Tobia se sa dove il capo tiene la chiave delle gabbie."]]})
	# the bench reads the replies itself: the game must not react to them
	g.narrator.chunk.disconnect(g._on_chunk)
	g.narrator.finished.disconnect(g._on_finished)
	g.narrator.finished.connect(func(full, ok, _tag): reply = {"full": full, "ok": ok})
	if model != "":
		g.narrator.model = model
	model = g.narrator.model

	print("carico il modello %s..." % model)
	var t0 := Time.get_ticks_msec()
	await _ask([{"role": "user", "content": "Rispondi solo: pronto"}], {"max": 2})
	if not reply.ok:
		print("NARRATORE SPENTO: ", g.narrator.status)
		quit(1)
		return
	var load_s := (Time.get_ticks_msec() - t0) / 1000.0

	var results: Array = []
	for sc in SCENARIOS:
		if only != "" and not str(sc.name).contains(only):
			continue
		for r in runs:
			var res := await _run(sc)
			res["run"] = r + 1
			results.append(res)
			var bad: Array = res.checks.keys().filter(func(k): return not res.checks[k])
			print("%-20s #%d  %d/%d  %4.1f s  %s" % [sc.name, r + 1, res.checks.size() - bad.size(), res.checks.size(),
				res.total, ("manca: " + ", ".join(bad)) if not bad.is_empty() else "ok"])
	_report(results, load_s)
	quit()


func _ask(msgs: Array, opts := {}) -> void:
	reply = {}
	g.narrator.ask(msgs, opts)
	while reply.is_empty():
		await process_frame


func _run(sc: Dictionary) -> Dictionary:
	var st = g.story
	st.transcript = []
	for l in sc.lines:
		st.transcript.append({"role": l[0], "who": l[1], "text": l[2]})
	var summary := str(sc.get("kind", "")) == "summary"
	# same requests the game makes
	var msgs: Array = st.chapter_summary_prompt() if summary else st.messages()
	var opts := {"max": 300, "temp": 0.3} if summary else {}
	var t0 := Time.get_ticks_msec()
	var first := [-1.0]
	var on_chunk := func(_p):
		if first[0] < 0:
			first[0] = (Time.get_ticks_msec() - t0) / 1000.0
	g.narrator.chunk.connect(on_chunk)
	await _ask(msgs, opts)
	g.narrator.chunk.disconnect(on_chunk)
	var total := (Time.get_ticks_msec() - t0) / 1000.0
	var full := str(reply.full)
	var stats: Dictionary = g.narrator.last_stats
	var tok := int(stats.get("eval_count", 0))
	var tps := tok / maxf(0.001, float(stats.get("eval_duration", 0)) / 1e9) if tok > 0 else 0.0
	var checks := _summary_checks(full, sc) if summary else _reply_checks(full, sc)
	checks["risposta arrivata"] = bool(reply.ok) and full.strip_edges() != ""
	return {"name": sc.name, "text": full, "checks": checks, "first": first[0], "total": total,
		"tokens": tok, "tps": tps, "prompt_tokens": int(stats.get("prompt_eval_count", 0))}


# ------------------------------------------------------------------ checks
func _sentences(t: String) -> Array:
	var out: Array = []
	for m in RegEx.create_from_string("[^.!?]+[.!?]*").search_all(t):
		if m.get_string().strip_edges().length() > 2:
			out.append(m.get_string().strip_edges())
	return out


func _common(t: String) -> Dictionary:
	var low := " " + t.to_lower().replace("\n", " ") + " "
	var c := {}
	c["italiano"] = ENGLISH.all(func(w): return not low.contains(w))
	c["niente dadi o numeri di gioco"] = not RegEx.create_from_string("\\b\\d+d\\d+\\b|\\b\\d+\\s*(pf|punti ferita|danni)\\b").search(low)
	return c


func _reply_checks(full: String, sc: Dictionary) -> Dictionary:
	var text := GameStory.strip_tags(full)
	var sent := _sentences(text)
	var c := _common(text)
	c["corta (max 5 frasi, 90 parole)"] = sent.size() <= 5 and text.split(" ", false).size() <= 90
	c["chiude con una domanda"] = text.ends_with("?")
	# a sentence led by a character is the model playing for the player
	# ("Aria apre la porta"); "Aria, cosa fai?" is fine
	var acts := false
	for s in sent:
		for pc in PCS:
			if RegEx.create_from_string("^(%s)( e \\w+)?\\s+(?!,)" % pc).search(s) and not s.ends_with("?"):
				acts = true
	c["non fa agire i personaggi"] = not acts
	c["marcatori solo alla fine"] = not full.contains("[[") or full.strip_edges().ends_with("]]")
	# notes written without articles must not make the replies telegraphic
	var words := text.to_lower().replace("'", "' ").split(" ", false)
	var arts := 0
	for w in words:
		if w in ["il", "lo", "la", "i", "gli", "le", "un", "uno", "una", "l'", "un'", "del", "della", "dei", "delle", "al", "alla", "ai", "alle", "all'", "dal", "dalla", "nel", "nella", "nei", "sul", "sulla", "dell'", "nell'", "dall'"]:
			arts += 1
	c["italiano pieno, non ad appunti"] = words.size() < 10 or arts * 20 >= words.size()
	if sc.has("any"):
		var low := text.to_lower()
		c["usa un dettaglio del testo (%s)" % "/".join(sc.any)] = sc.any.any(func(w): return low.contains(w))
	var tags := GameStory.tags(full)
	var kinds: Array = tags.map(func(t): return t[0])
	match str(sc.expect):
		"nessuno":
			c["nessun marcatore"] = kinds.is_empty()
		"prova":
			c["chiede una prova"] = kinds.has("prova")
			for t in tags:
				if t[0] == "prova":
					c["prova scritta bene (abilità CD n: chi)"] = RegEx.create_from_string("^(TS )?[A-Za-zÀ-ÿ ]+ CD \\d{1,2}\\s*:\\s*\\S").search(t[1]) != null
		"combattimento":
			c["fa partire il combattimento"] = kinds.has("combattimento")
			for t in tags:
				if t[0] == "combattimento":
					c["mostri esistenti"] = _known_monsters(t[1])
		"fine capitolo":
			c["chiude il capitolo"] = kinds.has("fine capitolo")
			c.erase("chiude con una domanda")
	return c


func _known_monsters(arg: String) -> bool:
	var names: Array = GameStory.bestiary_names().map(func(n): return str(n).to_lower())
	for m in g.state.monsters():
		names.append(str(m.name).to_lower())
	var parts := arg.split(",", false)
	if parts.is_empty():
		return false
	for p in parts:
		var n := RegEx.create_from_string("\\s*(x\\s*\\d+|\\d+)\\s*$").sub(p.strip_edges().to_lower(), "")
		if not names.any(func(k): return k == n or k.begins_with(n) or n.begins_with(k)):
			return false
	return true


func _summary_checks(full: String, sc: Dictionary) -> Dictionary:
	var c := _common(full)
	var words := full.split(" ", false).size()
	c["massimo 170 parole"] = words <= 170
	c["nessun marcatore"] = not full.contains("[[")
	var low := full.to_lower()
	c["contiene i fatti (%s)" % ", ".join(sc.must)] = sc.must.all(func(w): return low.contains(w))
	c["al passato, non chiede"] = not full.strip_edges().ends_with("?")
	return c


# ------------------------------------------------------------------ report
func _report(results: Array, load_s: float) -> void:
	var passed := 0
	var total := 0
	var first_sum := 0.0
	var time_sum := 0.0
	var tps_sum := 0.0
	var by_name := {}
	for r in results:
		var ok: int = r.checks.values().filter(func(v): return v).size()
		passed += ok
		total += r.checks.size()
		first_sum += maxf(0.0, r.first)
		time_sum += r.total
		tps_sum += r.tps
		if not by_name.has(r.name):
			by_name[r.name] = [0, 0, 0.0, 0]
		by_name[r.name][0] += ok
		by_name[r.name][1] += r.checks.size()
		by_name[r.name][2] += r.total
		by_name[r.name][3] += 1
	var n := maxi(1, results.size())
	var score := 100.0 * passed / maxf(1.0, total)
	var date := Time.get_datetime_string_from_system().replace("T", " ").left(16)
	var prompt_id := "%08x" % (g.story.system_prompt().hash() & 0xffffffff)

	var md := PackedStringArray()
	md.append("# Test di riferimento del narratore")
	md.append("")
	md.append("- Modello: `%s`" % model)
	md.append("- Data: %s" % date)
	md.append("- Istruzioni del master: versione `%s` (cambia quando cambia il prompt)" % prompt_id)
	md.append("- Ripetizioni per scenario: %d" % runs)
	md.append("- Caricamento del modello: %.1f s" % load_s)
	md.append("")
	md.append("**Punteggio: %d/%d controlli (%.0f%%)**. Prima parola in media dopo %.1f s, risposta completa %.1f s, %.1f token/s." % [
		passed, total, score, first_sum / n, time_sum / n, tps_sum / n])
	md.append("")
	md.append("| Scenario | Controlli superati | Tempo medio |")
	md.append("|---|---|---|")
	for k in by_name:
		var b: Array = by_name[k]
		md.append("| %s | %d/%d | %.1f s |" % [k, b[0], b[1], b[2] / b[3]])
	md.append("")
	md.append("## Risposte")
	for r in results:
		md.append("")
		md.append("### %s #%d (%.1f s, %d token)" % [r.name, r.run, r.total, r.tokens])
		md.append("")
		md.append("> " + str(r.text).strip_edges().replace("\n", "\n> "))
		md.append("")
		for k in r.checks:
			md.append("- [%s] %s" % ["x" if r.checks[k] else " ", k])

	var dir := "res://tests/llm_results"
	DirAccess.make_dir_recursive_absolute(dir)
	var safe := model.replace(":", "-").replace("/", "-") + ("_storia-" + story if story != "" else "")
	var path := "%s/%s_%s.md" % [dir, date.left(10), safe]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("\n".join(md) + "\n")
	f.close()
	var csv := dir + "/storico.csv"
	var lines := FileAccess.get_file_as_string(csv) if FileAccess.file_exists(csv) else "data,modello,prompt,ripetizioni,superati,controlli,punteggio,prima_parola_s,risposta_s,token_s\n"
	if only == "":
		lines += "%s,%s,%s,%d,%d,%d,%.0f,%.1f,%.1f,%.1f\n" % [date, model + (" storia-" + story if story != "" else ""), prompt_id, runs, passed, total, score, first_sum / n, time_sum / n, tps_sum / n]
		var fc := FileAccess.open(csv, FileAccess.WRITE)
		fc.store_string(lines)
		fc.close()
	print("")
	print("llm bench %s: %d/%d (%.0f%%), prima parola %.1f s, risposta %.1f s, %.1f token/s" % [model, passed, total, score, first_sum / n, time_sum / n, tps_sum / n])
	print("report: ", ProjectSettings.globalize_path(path))
