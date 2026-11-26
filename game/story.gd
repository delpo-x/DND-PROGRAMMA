class_name GameStory
extends RefCounted
## Memory of Dnd The Game, kept small on purpose: the local model is slow
## to read long prompts. What the narrator receives each time:
##   - the rules of the master (fixed for the whole chapter, so Ollama can
##     reuse it from its cache instead of reading it again);
##   - riassunto.md: the story so far, rewritten at the end of each chapter;
##   - the last lines said at the table in this chapter.
## Each finished chapter is saved as capitolo_NN.md: summary, facts written
## by the app (combat, defeats, experience...) and the full transcript.
## Files: user://the_game/<campaign id>/

const RECENT := 14  # lines of the chapter sent with each request
const PASSAGE_CHARS := 600  # text of the adventure added to one request
const PARA_CHARS := 420     # longest piece of one paragraph
const STOP := ["sono", "siamo", "della", "delle", "dello", "degli", "nella", "nelle", "nello", "negli",
	"sulla", "sulle", "dalla", "dalle", "alla", "alle", "allo", "agli", "questo", "questa", "quello",
	"quella", "quelli", "quelle", "cosa", "fate", "come", "dove", "quando", "anche", "ancora",
	"verso", "dentro", "fuori", "sopra", "sotto", "molto", "tutto", "tutti", "tutte", "ogni", "loro",
	"essere", "avere", "fare", "andiamo", "vado", "provo", "voglio", "vediamo", "chiedo", "guardo",
	"cerco", "prendo", "mentre", "perché", "però", "ecco", "inizia", "capitolo", "storia",
	"master", "gruppo", "tavolo", "risultato", "vostro", "vostra", "vostri", "nostro", "nostra"]
const TAG_RE := "\\[\\[\\s*([A-Za-zÀ-ÿ ]+?)\\s*(?::\\s*([^\\]]*))?\\]\\]"

var st  # GameState
var dir := ""
var chapter := 1
var chapter_title := ""
var transcript: Array = []  # {role: "user"|"assistant", who, text}
var chron_start := 0
var summary := ""
## Plots a player told the master privately: {cid, who, text, reply}. They are
## not in the transcript (so not in the table feed, the chapter text or its
## summary) but the narrator always knows them.
var secrets: Array = []
const SECRETS_MAX := 30
var read_pos := 0  # next "Da leggere" paragraph of the chapter to read aloud
var read_mark := 0  # transcript size right after the last paragraph read


func open(state) -> void:
	st = state
	dir = "user://the_game/%s" % str(st.data.get("id", "campagna"))
	DirAccess.make_dir_recursive_absolute(dir)
	chapter = 1
	chapter_title = ""
	transcript = []
	read_pos = 0
	read_mark = 0
	chron_start = st.data.get("chronicle", []).size()
	summary = _read(dir + "/riassunto.md")
	var saved := _read(dir + "/corrente.json")
	var j = JSON.parse_string(saved) if saved.strip_edges() != "" else null
	if j is Dictionary:
		chapter = maxi(1, int(j.get("chapter", 1)))
		chapter_title = str(j.get("title", ""))
		transcript = j.get("transcript", []) if j.get("transcript") is Array else []
		secrets = j.get("secrets", []) if j.get("secrets") is Array else []
		chron_start = clampi(int(j.get("chron_start", chron_start)), 0, st.data.get("chronicle", []).size())
		read_pos = maxi(0, int(j.get("read_pos", 0)))
		read_mark = clampi(int(j.get("read_mark", transcript.size())), 0, transcript.size())


func save() -> void:
	if not st.persist:
		return
	_write(dir + "/corrente.json", JSON.stringify({"chapter": chapter, "title": chapter_title,
		"transcript": transcript, "secrets": secrets, "chron_start": chron_start, "read_pos": read_pos, "read_mark": read_mark}, "\t"))


## Paragraphs of the current chapter written to be read aloud to the players:
## those starting with "Da leggere:" and those under a "Da leggere" heading
## (up to the next heading). Everything else is for the master only.
func read_aloud() -> Array:
	return StoryImport.read_aloud(str(chapter_info().get("text", "")))


func reading_left() -> bool:
	return read_pos < read_aloud().size()


## True when something happened at the table since the last paragraph read
## (a player acted, a check, a fight): the next paragraph may no longer fit.
func reading_diverged() -> bool:
	return read_pos > 0 and transcript.size() > read_mark


## Asks the narrator to fit the next paragraph to what the players did: the
## paragraph rewritten, LEGGI (it fits as written) or SALTA (it no longer makes
## sense). With gemma4 e4b, asking for the rewrite first works: given LEGGI as
## the first option, it read a quiet inn while the players had set it on fire.
func adapt_messages(passage: String) -> Array:
	return messages("[Il prossimo testo da leggere ai giocatori è: \"%s\"\n" % passage
		+ "Il tuo compito: riscrivi questo testo perché sia coerente con quello che i giocatori hanno appena fatto e con la situazione di adesso (luogo, atmosfera, persone), con la stessa lunghezza, tenendo persone e indizi, senza la domanda finale. "
		+ "Se il testo è già coerente parola per parola, rispondi solo LEGGI. "
		+ "Se racconta cose già successe o un luogo dove il gruppo non andrà più, rispondi solo SALTA.]")


## Room for a rewrite as long as the paragraph (Italian is about 3.5
## characters per token), so a long paragraph is not cut short.
static func adapt_tokens(passage: String) -> int:
	return clampi(int(passage.length() / 3.2) + 40, 260, 900)


## Reads the narrator's answer to adapt_messages():
## {mode: "read" | "skip" | "text", text}.
static func parse_adapt(full: String) -> Dictionary:
	var t := full.strip_edges()
	var word := t.left(12).to_upper().strip_edges()
	if word.begins_with("SALTA"):
		return {"mode": "skip", "text": ""}
	# "Leggete: <text>" / "Da leggere: <text>": a label before the text
	var m := RegEx.create_from_string("(?i)^(leggi|leggete|da leggere|testo)\\s*[:.]\\s*").search(t)
	if m:
		t = t.substr(m.get_end())
	for q in ["\"", "«", "»", "“", "”"]:
		t = t.trim_prefix(q).trim_suffix(q)
	t = t.strip_edges()
	return {"mode": "text", "text": t} if t.length() >= 20 else {"mode": "read", "text": ""}


## Off only in tests/llm_bench.gd --no-hint, to measure the narrator alone.
static var check_hints := true
var route := {}  # the router's reading of the last player line (see route_messages)

## Words of a player's action that call for a check, and which skill.
## Just looking ("osservo", "con attenzione") is left out: in the playtest it
## asked for a check at almost every line, also where failing changed nothing.
## Order matters: the first match wins. Words at the start of a word only.
const CHECK_WORDS: Array = [
	["Percezione", ["cerco trappol", "trappol", "ascolt", "orecchio", "sbirci", "origli", "annus"]],
	["Indagare", ["esamin", "ispezion", "frug", "perquis", "cerco indiz", "indizi", "cerco passagg", "cerco", "rovist"]],
	["Atletica", ["arrampic", "scalo", "scalare", "salto", "saltare", "nuot", "sfond", "forzo", "forzare", "spingo", "sollev", "trascin"]],
	["Acrobazia", ["equilibri", "capriol", "schiv", "rotol", "in bilico"]],
	["Furtività", ["di nascosto", "nascond", "furtiv", "silenzios", "senza farmi", "senza fare rumore", "pedin", "sgattaiol"]],
	["Rapidità di Mano", ["borseggi", "scassin", "grimald", "rubo", "serratur", "disinnesc"]],
	["Persuasione", ["convinc", "persuad", "supplic"]],
	["Inganno", ["mento", "mentire", "ingann", "bluff", "fingo", "fingere", "travest"]],
	["Intimidire", ["minacc", "intimid", "spavent"]],
	["Intuizione", ["sta mentendo", "mi fido", "intenzion"]],
	["Sopravvivenza", ["tracce", "orme", "orient"]],
	["Medicina", ["curo", "medico", "fascio", "stabilizz"]],
	["Arcano", ["rune", "runa", "magia", "incantes", "glif"]],
	["Storia", ["ricordo", "leggend"]],
	["Religione", ["simbolo sacr", "divinit", "altare"]],
	["Addestrare Animali", ["calmo il", "calmare il", "addomest"]],
]


## The skill a player's action probably needs, or "" (see CHECK_WORDS).
static func check_hint(text: String) -> String:
	var low := " " + text.to_lower() + " "
	for row in CHECK_WORDS:
		for w in row[1]:
			var i := low.find(str(w))
			while i >= 0:
				if (i == 0 or not low[i - 1].is_valid_identifier()) and not low.left(i).ends_with("non "):
					return str(row[0])
				i = low.find(str(w), i + 1)
	return ""


## The last line, if it is a player's action outside a fight that probably
## needs a check: {skill, who}; otherwise {}.
func pending_check() -> Dictionary:
	if transcript.is_empty() or st.ini().active:
		return {}
	var last: Dictionary = transcript.back()
	if str(last.role) != "user" or str(last.who) in ["Tavolo", "Master"]:
		return {}
	# the router read this very line: its answer wins over the word list
	if not route.is_empty() and str(route.get("line", "")) == str(last.text):
		if str(route.tipo) != "prova" or str(route.abilita) == "":
			return {}
		return {"skill": str(route.abilita), "who": "tutti" if str(last.who) == "Il gruppo" else str(last.who), "dc": int(route.cd)}
	var skill := check_hint(str(last.text))
	if skill == "":
		return {}
	return {"skill": skill, "who": "tutti" if str(last.who) == "Il gruppo" else str(last.who)}


func add(role: String, who: String, text: String) -> void:
	var t := text.strip_edges()
	if t == "":
		return
	transcript.append({"role": role, "who": who, "text": t})
	save()


func add_secret(cid: String, who: String, text: String) -> void:
	secrets.append({"cid": cid, "who": who, "text": text.strip_edges().left(400), "reply": ""})
	if secrets.size() > SECRETS_MAX:
		secrets.pop_front()
	save()


## The master's private answer to the oldest unanswered secret of a player.
func set_secret_reply(cid: String, reply: String) -> void:
	for s in secrets:
		if str(s.cid) == cid and str(s.reply) == "":
			s.reply = reply.strip_edges()
			break
	save()


## For the phones: char id -> last secrets of that player [{q, a}].
func secrets_by_char() -> Dictionary:
	var out := {}
	for s in secrets:
		var l: Array = out.get(str(s.cid), [])
		l.append({"q": str(s.text), "a": str(s.reply)})
		out[str(s.cid)] = l.slice(maxi(0, l.size() - 4))
	return out


## Players' secrets for a request that answers a secret, with the master's
## earlier private answers. Public requests get only a line saying there are
## secrets: given the secrets themselves, even without the answers, the model
## narrated them aloud (two playtests in tests/llm_results).
func _secrets_note(private := false) -> String:
	if not private:
		return "" if secrets.is_empty() else "[Alcuni giocatori hanno fatto mosse segrete con te in privato: qui rispondi solo a quello che si dice al tavolo e non raccontare azioni nascoste di nessuno.]
"
	var lines: Array = []
	var seen := {}
	for s in secrets.slice(maxi(0, secrets.size() - (6 if private else 4))):
		var key := str(s.who) + str(s.text).left(60)
		if seen.has(key):
			continue  # the same secret said twice
		seen[key] = true
		lines.append("- %s: %s%s" % [s.who, str(s.text).left(200 if private else 140), (" (tu: %s)" % str(s.reply).left(160)) if private and str(s.reply) != "" else ""])
	if lines.is_empty():
		return ""
	return ("[Complotti segreti dei giocatori, gli altri giocatori non li conoscono:\n" + "\n".join(lines)
		+ "\nNon rivelarli, non nominarli e non riprenderne le parole in pubblico: falli pesare sulla storia solo quando accadono in scena.]\n")


## The master's private answer, cleaned: markers and bracketed notes the model
## copies from the request ("[Messaggio SEGRETO di ...]") and anything after
## the first paragraph (it went on narrating the public scene).
static func clean_secret(full: String) -> String:
	var s := RegEx.create_from_string(TAG_RE).sub(full, "", true)
	s = RegEx.create_from_string("\\[[^\\]]*\\]?").sub(s, "", true)
	s = s.strip_edges().trim_prefix(":").strip_edges()
	var para := s.find("\n\n")
	if para > 40:
		s = s.left(para)
	return s.strip_edges()


## Prompt for the private answer to one player's secret.
func secret_messages(who: String, text: String) -> Array:
	var out: Array = [{"role": "system", "content": system_prompt()}]
	for t in transcript.slice(maxi(0, transcript.size() - RECENT)):
		if t.role == "assistant":
			out.append({"role": "assistant", "content": t.text})
		else:
			out.append({"role": "user", "content": "%s: %s" % [t.who, t.text]})
	out.append({"role": "user", "content": _secrets_note(true)
		+ ("[Messaggio SEGRETO di %s: lo leggete solo tu e %s. Rispondi solo a %s, in seconda persona, in 2-4 frasi: " % [who, who, who]
		+ "cosa riesce a fare o a scoprire di nascosto e cosa potrebbe succedere. Niente tag, niente prove, non far parlare gli altri personaggi.]\n")
		+ "%s: %s" % [who, text]})
	return out


func is_new() -> bool:
	return transcript.is_empty() and summary.strip_edges() == "" and chapter == 1


# ----------------------------------------------------------------- prompts
func _pc_line(e: Dictionary) -> String:
	var bits: Array = []
	for k in ["race", "cls"]:
		if str(e.get(k, "")) != "":
			bits.append(str(e[k]))
	var lvl := "liv. %d" % int(e.get("level", 1))
	return "%s (%s, %s)" % [e.name, " ".join(bits) if not bits.is_empty() else "avventuriero", lvl]


static func bestiary_names() -> Array:
	var out: Array = []
	for mm in Rules.MONSTERS:
		out.append(str(mm[0]).get_slice(" (", 0))
	return out


## The outline of the current chapter from the imported story, or {} if none.
func chapter_info() -> Dictionary:
	var story: Dictionary = st.data.get("story", {})
	var chs: Array = story.get("chapters", [])
	if chs.is_empty() or chapter > chs.size():
		return {}
	return chs[clampi(chapter - 1, 0, chs.size() - 1)]


func chapters_total() -> int:
	return st.data.get("story", {}).get("chapters", []).size()


## True when every chapter of the imported adventure has been played.
func adventure_over() -> bool:
	var chs: Array = st.data.get("story", {}).get("chapters", [])
	return not chs.is_empty() and chapter > chs.size()


## Fixed part of the prompt: it changes only between chapters.
func system_prompt() -> String:
	var party: Array = []
	for e in st.characters():
		party.append(_pc_line(e))
	var known: Array = []
	for m in st.monsters():
		var base: String = st._base_name(str(m.name))
		if not known.has(base):
			known.append(base)
	var p := PackedStringArray()
	p.append("Sei il Dungeon Master di una partita di Dungeons & Dragons 5ª edizione. Parli sempre in italiano, a un gruppo di amici seduti attorno al tavolo.")
	p.append("Regole del tuo modo di narrare:")
	p.append("- Da 4 a 8 frasi, in uno o due paragrafi: racconta con calma e con dettagli concreti (luce, rumori, odori, gesti dei PNG). La tua voce viene letta ad alta voce.")
	p.append("- Comincia da come il luogo e i PNG reagiscono a quello che il giocatore ha appena fatto o detto, senza raccontare di nuovo la sua azione.")
	p.append("- Parla solo di luoghi, rumori, PNG e mostri. I personaggi dei giocatori fanno e dicono soltanto ciò che scrivono i giocatori: non farli muovere, parlare o pensare.")
	p.append("- Chiedi Cosa fate? solo quando i giocatori devono davvero decidere qualcosa. Se la scena va avanti da sola, chiudi senza domande: il racconto prosegue.")
	p.append("- Non tirare dadi e non inventare numeri: dadi, danni e punti ferita li gestisce il tavolo.")
	p.append("- Chiedi una prova solo se fallire cambierebbe la scena: parlare, guardarsi attorno o avvicinarsi senza pericolo riescono e basta.")
	p.append("- Se un'azione ha un esito incerto chiedi una prova scrivendo alla fine, su una riga a parte, ad esempio: [[PROVA: Percezione CD 15: Aria]] (abilità, difficoltà da 10 a 20, chi la tira oppure tutti).")
	p.append("- Per un tiro salvezza: [[PROVA: TS Destrezza CD 13: tutti]].")
	p.append("- Quando inizia un combattimento scrivi alla fine: [[COMBATTIMENTO: Goblin x2, Lupo]] usando i nomi dei mostri qui sotto. Poi non narrare i colpi: li risolve il tavolo.")
	if not adventure_over():
		p.append("- Quando il capitolo arriva a una conclusione naturale scrivi alla fine [[FINE CAPITOLO]].")
	p.append("- Quando un PNG con un nome cambia atteggiamento verso il gruppo, o ne incontrate uno nuovo che conta, scrivi alla fine [[PNG: Marta amichevole]] con uno di questi: ostile, diffidente, neutrale, amichevole, alleato.")
	p.append("- I marcatori tra doppie parentesi quadre vanno solo alla fine e solo quando servono.")
	p.append("- La traccia del capitolo può essere scritta ad appunti, senza articoli: tu racconta sempre in italiano pieno e scorrevole, senza sigle.")
	p.append("- Se la traccia ha una linea temporale, porta il gruppo da un momento al successivo seguendo le loro scelte, senza saltare avanti. Quando arriva il momento indicato come fine, chiudi il capitolo.")
	p.append("- Le battute del Master che vengono dal testo da leggere sono già state lette ai giocatori: non ripeterle, riprendi da lì.")
	p.append("- A volte ricevi un brano dal testo dell'avventura: usalo per luoghi, dialoghi e indizi, riassumendolo con parole tue.")
	p.append("Esempio di risposta giusta. Giocatore: Entriamo nella grotta. Master: L'aria si fa umida e fredda, e un odore di fumo e di carne bruciata vi punge la gola. Le pareti sono coperte di muschio scuro e l'acqua gocciola da qualche parte nel buio, con un ritmo lento. Dopo una curva il passaggio si allarga: tremola la luce rossastra di un fuoco e si sentono voci gracchianti che litigano in una lingua aspra. Una delle voci ride, poi qualcosa di metallico cade a terra con un clangore. Cosa fate?")
	p.append("")
	p.append("Il gruppo: " + "; ".join(party) + ".")
	if not known.is_empty():
		p.append("Mostri e PNG preparati per questa avventura: " + ", ".join(known) + ".")
	p.append("Altri mostri che puoi usare: " + ", ".join(bestiary_names()) + ".")
	var tone := str(st.data.get("tone", "")).strip_edges()
	if tone != "":
		p.append("")
		p.append("Tono dell'avventura (seguilo in ogni risposta): %s" % tone.left(StoryImport.TONE_MAX))
	var pinned: Array = st.data.get("pinned", [])
	if not pinned.is_empty():
		p.append("")
		p.append("Fatti fissati della campagna, sempre veri: non contraddirli e non dimenticarli.")
		for f in pinned:
			p.append("- " + str(f))
	var facs: Array = st.data.get("factions", [])
	if not facs.is_empty():
		p.append("")
		p.append("Fazioni e cosa vogliono (agiscono anche quando il gruppo non le vede):")
		for f in facs:
			p.append("- " + str(f))
		var moves: Array = st.data.get("faction_moves", [])
		if not moves.is_empty():
			p.append("Intanto, fuori scena (i giocatori non lo sanno: fallo capire solo con indizi e conseguenze, non raccontarlo):")
			for m in moves:
				p.append("- " + str(m))
	var npcs: Array = st.data.get("npcs", [])
	if not npcs.is_empty():
		p.append("")
		p.append("PNG già incontrati e cosa pensano del gruppo (fallo sentire in come parlano e in cosa sono disposti a fare):")
		for n in npcs:
			p.append("- %s: %s%s" % [n.name, n.att, (" (" + str(n.note) + ")") if str(n.get("note", "")) != "" else ""])
	var story: Dictionary = st.data.get("story", {})
	if not story.is_empty():
		p.append("")
		p.append("Avventura: %s." % str(story.get("title", "")))
		var ch := chapter_info()
		if not ch.is_empty():
			p.append("Traccia del capitolo (seguila liberamente): %s. %s" % [str(ch.get("title", "")), StoryImport.master_text(str(ch.get("text", ""))).left(StoryImport.READ_CHARS)])
	p.append("")
	p.append("La storia finora: " + (summary.strip_edges() if summary.strip_edges() != "" else "è l'inizio della campagna."))
	p.append("Capitolo attuale: %d%s." % [chapter, (" - " + chapter_title) if chapter_title != "" else ""])
	return "\n".join(p)


## Short state of the table, sent as the last message (it changes every turn).
func table_line() -> String:
	var bits: Array = []
	for e in st.characters():
		bits.append("%s %s" % [e.name, st.status_of(e).to_lower()])
	return "[Stato del tavolo: " + ", ".join(bits) + "]"


func messages(extra := "") -> Array:
	var out: Array = [{"role": "system", "content": system_prompt()}]
	for t in transcript.slice(maxi(0, transcript.size() - RECENT)):
		if t.role == "assistant":
			out.append({"role": "assistant", "content": t.text})
		else:
			out.append({"role": "user", "content": "%s: %s" % [t.who, t.text]})
	var last := table_line()
	var passage := passages()
	if passage != "":
		last = "[Dal testo dell'avventura, usalo se serve: " + passage + "]\n" + last
	var paras := read_aloud()
	if extra == "" and read_pos > 0 and read_pos < paras.size():
		last = "[Prossimo testo che verrà letto ai giocatori, non raccontarlo tu: %s]\n" % str(paras[read_pos]).left(200) + last
	var pc := pending_check() if extra == "" and check_hints else {}
	if not pc.is_empty():
		last = ("[L'azione di %s ha un esito incerto e serve una prova. Descrivi in una o due frasi solo l'ambiente e il rischio, " % pc.who
			+ "senza far muovere il personaggio e senza dire come finisce. Poi scrivi Cosa fate? e, su una riga a parte, "
			+ ("la prova, esattamente [[PROVA: %s CD %d: %s]].]\n" % [pc.skill, int(pc.dc), pc.who] if pc.has("dc")
				else "la prova, ad esempio [[PROVA: %s CD 15: %s]], con la difficoltà che scegli tu da 10 a 20.]\n" % [pc.skill, pc.who])) + last
	if extra != "":
		last = extra + "\n" + last
	last = _secrets_note() + last
	out.append({"role": "user", "content": last})
	return out


# ----------------------------------------------------------------- router
## JSON schema of the router's answer: Ollama keeps the model inside it.
static func route_schema() -> Dictionary:
	var skills: Array = [""]
	for s in Rules.SKILLS:
		skills.append(str(s[1]))
	return {"type": "object", "properties": {
		"tipo": {"type": "string", "enum": ["parla", "esplora", "prova", "attacco", "altro"]},
		"abilita": {"type": "string", "enum": skills},
		"cd": {"type": "integer", "minimum": 0, "maximum": 25},
		"mostri": {"type": "string"}},
		"required": ["tipo", "abilita", "cd", "mostri"]}


## A short request before the story: what kind of action the last player
## line is. The table then asks the check or starts the fight by itself,
## and the narrator only tells what happens.
func route_messages() -> Array:
	var last: Dictionary = transcript.back()
	var before := ""
	for i in range(transcript.size() - 2, -1, -1):
		if transcript[i].role == "assistant":
			before = str(transcript[i].text).right(600)
			break
	var mons: Array = []
	for m in st.monsters():
		var b: String = st._base_name(str(m.name))
		if not mons.has(b):
			mons.append(b)
	var lines := PackedStringArray([
		"Sei l'arbitro delle regole di una partita di Dungeons & Dragons 5ª edizione. Leggi l'azione di un giocatore e rispondi solo con il JSON richiesto.",
		"tipo: parla (dialogo o domanda), esplora (guardarsi attorno o muoversi senza pericolo), prova (esito incerto con un rischio: serve una prova di abilità), attacco (attacca qualcuno o qualcosa), altro.",
		"abilita: solo per prova, l'abilità giusta; altrimenti vuota.",
		"cd: solo per prova, la difficoltà: 10 facile, 12-13 media, 15 difficile, 18-20 molto difficile; altrimenti 0.",
		"mostri: solo per attacco, chi viene attaccato, con i nomi dei mostri qui sotto e x2 se sono più di uno, ad esempio Goblin x2; altrimenti vuoto.",
		"Parlare, guardarsi attorno o avvicinarsi senza pericolo non sono prove.",
		"Abilità: scassinare, borseggiare, disinnescare = Rapidità di Mano; nascondersi, muoversi senza farsi sentire = Furtività; arrampicarsi, saltare, nuotare, forzare = Atletica; ascoltare, origliare, notare qualcosa di nascosto = Percezione; esaminare, cercare indizi = Indagare; convincere = Persuasione; mentire = Inganno; minacciare = Intimidire; capire se uno mente = Intuizione; equilibrio, capriole = Acrobazia.",
		"Mostri della campagna: " + (", ".join(mons) if not mons.is_empty() else "nessuno") + "."])
	var user := ("Scena: " + before + "\n" if before != "" else "") + "Azione di %s: %s" % [last.who, last.text]
	return [{"role": "system", "content": "\n".join(lines)}, {"role": "user", "content": user}]


## The router's JSON, checked: {} when it is not usable.
static func parse_route(text: String) -> Dictionary:
	var js := JSON.new()  # quietly: a broken answer is not an error of the app
	if js.parse(text.strip_edges()) != OK:
		return {}
	var j = js.data
	if not j is Dictionary or not str(j.get("tipo", "")) in ["parla", "esplora", "prova", "attacco", "altro"]:
		return {}
	var skill := ""
	for s in Rules.SKILLS:
		if str(s[1]).to_lower() == str(j.get("abilita", "")).to_lower():
			skill = str(s[1])
	var r := {"tipo": str(j.tipo), "abilita": skill, "cd": clampi(int(j.get("cd", 0)), 0, 25),
		"mostri": str(j.get("mostri", "")).strip_edges().left(80)}
	if r.tipo == "prova" and r.cd < 5:
		r.cd = 15
	return r


# ------------------------------------------------------------ second pass
## The narrator reads its own draft again and writes the final reply: small
## local models make fewer mistakes when they check a text than when they
## write it at once.
func revise_messages(draft: String) -> Array:
	var out := messages()
	out.append({"role": "assistant", "content": draft})
	out.append({"role": "user", "content": "[Rileggi la tua bozza qui sopra e scrivi la versione finale. Controlla che: "
		+ "i personaggi dei giocatori non facciano, dicano o pensino nulla che i giocatori non hanno scritto; "
		+ "luoghi, PNG e fatti siano quelli della storia e del capitolo; non ci siano dadi, numeri di danni o punti ferita; "
		+ "i mostri abbiano i nomi della lista; la domanda Cosa fate? ci sia solo se i giocatori devono decidere; "
		+ "i marcatori tra doppie parentesi quadre siano alla fine e solo se servono; l'italiano sia scorrevole. "
		+ "Correggi gli errori e tieni il resto. Scrivi solo il testo finale per i giocatori, senza commenti e senza titoli.]"})
	return out


## Cuts what a model writes before or around the final text of a revision
## ("Ecco la versione finale:", "Versione corretta:", quotes).
static func clean_revision(text: String) -> String:
	var t := text.strip_edges()
	var re := RegEx.create_from_string("(?i)^\\s*(\\*\\*)?(ecco|versione|testo|bozza|risposta)[^\\n:]{0,60}:\\s*(\\*\\*)?\\s*")
	var m := re.search(t)
	if m:
		t = t.substr(m.get_end()).strip_edges()
	if t.length() > 1 and t.begins_with("\"") and t.ends_with("\""):
		t = t.substr(1, t.length() - 2).strip_edges()
	return t


# ---------------------------------------------------------------- passages
## Paragraphs of the full chapter text that talk about what was just said:
## the narrator reads only the start of a chapter, so the details further on
## (a room, a NPC, a clue) are looked up by their words and sent with that
## one request. Words of the players count double, names count double too.
func passages(limit := PASSAGE_CHARS) -> String:
	var full := str(chapter_info().get("text", ""))
	var text := StoryImport.master_text(full)
	# what has been read aloud already is public: its details and lore can be
	# looked up too, so the narrator answers questions about it
	var done: Array = StoryImport.read_aloud(full).slice(0, read_pos)
	if (text.length() <= StoryImport.READ_CHARS and done.is_empty()) or transcript.is_empty():
		return ""
	var want := {}
	var seen := 0
	for i in range(transcript.size() - 1, -1, -1):
		var t: Dictionary = transcript[i]
		if str(t.who) == "Tavolo":
			continue
		var w := 2.0 if t.role == "user" else 1.0
		for word in _words(str(t.text), true):
			var k: String = word.trim_prefix("!")
			var v := w * (2.0 if word.begins_with("!") else 1.0)
			want[k] = maxf(float(want.get(k, 0.0)), v)
		seen += 1
		if seen >= 2:
			break
	if want.is_empty():
		return ""
	# paragraphs past the part the narrator already reads
	var scored: Array = []
	var at := 0
	var cands: Array = []
	for para in _pieces(text):
		at += para.length() + 1
		if at > StoryImport.READ_CHARS and para.length() >= 40:
			cands.append(para)
	for d in done:
		cands.append_array(_pieces(str(d)))
	for para in cands:
		var have := {}
		for word in _words(para, false):
			have[word] = true
		var score := 0.0
		for k in want:
			if have.has(k):
				score += want[k]
		if score >= 3.0:
			scored.append([score, para.strip_edges().trim_prefix("## ")])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out := PackedStringArray()
	var used := 0
	for sc in scored:
		var piece: String = sc[1]
		if piece.length() > PARA_CHARS:
			piece = piece.left(PARA_CHARS)
			piece = piece.left(piece.rfind(" ")) + "..."
		if used + piece.length() > limit:
			continue
		out.append(piece)
		used += piece.length()
	return " ".join(out)


## The text cut into paragraphs; a long paragraph is cut at sentence ends into
## pieces of about PARA_CHARS, so the matching part of it can be sent alone.
static func _pieces(text: String) -> Array:
	var out: Array = []
	for para in text.split("\n\n"):
		var p := para.strip_edges()
		while p.length() > PARA_CHARS:
			var cut := -1
			for mark in [". ", "! ", "? "]:
				cut = maxi(cut, p.left(PARA_CHARS).rfind(mark))
			if cut < PARA_CHARS / 3:
				cut = p.left(PARA_CHARS).rfind(" ")
			if cut <= 0:  # one very long word
				cut = PARA_CHARS - 1
			out.append(p.left(cut + 1).strip_edges())
			p = p.substr(cut + 1).strip_edges()
		out.append(p)
	return out


## Words worth looking up: no short or common words, cut to a rough stem so
## "gabbia" and "gabbie" match. With names = true, capitalised words that do
## not start a sentence are marked with "!".
static func _words(text: String, names: bool) -> Array:
	var out: Array = []
	var sentence_start := true
	for raw in text.replace("\n", " ").replace("'", " ").replace("’", " ").split(" ", false):
		var w := ""
		for c in raw:
			if c.to_lower() != c.to_upper():
				w += c
		var low := w.to_lower()
		var is_name := names and not sentence_start and w != "" and w.left(1) != low.left(1)
		sentence_start = raw.ends_with(".") or raw.ends_with("!") or raw.ends_with("?") or raw.ends_with(":")
		if low.length() < 4 or STOP.has(low):
			continue
		var stem := low.left(low.length() - 1) if low.length() > 5 else low
		out.append(("!" if is_name else "") + stem)
	return out


# -------------------------------------------------------------------- tags
## [[NAME: arg]] markers of a reply: [[name lowercased, arg], ...].
static func tags(text: String) -> Array:
	var out: Array = []
	for m in RegEx.create_from_string(TAG_RE).search_all(text):
		out.append([m.get_string(1).strip_edges().to_lower(), m.get_string(2).strip_edges()])
	return out


static func strip_tags(text: String) -> String:
	var s := RegEx.create_from_string(TAG_RE).sub(text, "", true)
	# a marker cut in half at the end of a reply
	var cut := s.find("[[")
	if cut >= 0:
		s = s.left(cut)
	return s.strip_edges()


# ---------------------------------------------------------------- chapters
## Facts of this chapter written by the app itself (always exact).
func facts() -> Array:
	var out: Array = []
	var chron: Array = st.data.get("chronicle", [])
	for i in range(chron_start, chron.size()):
		out.append(str(chron[i].text))
	return out


func transcript_text(limit := 0) -> String:
	var lines := PackedStringArray()
	var from := 0 if limit <= 0 else maxi(0, transcript.size() - limit)
	for t in transcript.slice(from):
		lines.append("%s: %s" % [t.who, t.text])
	return "\n".join(lines)


## Prompt for the summary of the chapter that just ended.
func chapter_summary_prompt() -> Array:
	var f := facts()
	var txt := "Riassumi questo capitolo di una partita di D&D in al massimo 150 parole, in italiano, al passato. Solo fatti accaduti: luoghi, PNG, scoperte, combattimenti, decisioni del gruppo, cose rimaste in sospeso.\n\n"
	if not f.is_empty():
		txt += "Fatti registrati dal tavolo:\n- " + "\n- ".join(f) + "\n\n"
	txt += "Trascrizione:\n" + transcript_text(60)
	return [{"role": "user", "content": txt}]


## Prompt that merges the old summary with the new chapter.
func campaign_summary_prompt(chapter_text: String) -> Array:
	var txt := "Aggiorna il riassunto di una campagna di D&D. Scrivi in italiano, al massimo 250 parole, solo i fatti che contano per continuare la storia (personaggi, PNG, luoghi, misteri aperti, obiettivi).\n\n"
	txt += "Riassunto precedente:\n" + (summary if summary.strip_edges() != "" else "(nessuno, è il primo capitolo)") + "\n\n"
	txt += "Nuovo capitolo %d:\n%s" % [chapter, chapter_text]
	return [{"role": "user", "content": txt}]


## Prompt for what each faction did while the party played the chapter just
## closed. new_summary: the campaign summary that includes that chapter.
func factions_prompt(new_summary: String) -> Array:
	var txt := ("Sei il master di una campagna di D&D. Il gruppo ha appena finito un capitolo. Per ogni fazione qui sotto scrivi cosa ha fatto nel frattempo, "
		+ "lontano dagli occhi del gruppo: una frase concreta al passato prossimo, coerente con quello che vuole e con quello che è successo. "
		+ "Fai andare avanti i suoi piani, non risolvere i misteri e non anticipare i colpi di scena. "
		+ "Una riga per fazione, nella forma Nome: cosa ha fatto. Niente altro.\n\n")
	txt += "Fazioni:\n- " + "\n- ".join(st.data.get("factions", [])) + "\n\n"
	var moves: Array = st.data.get("faction_moves", [])
	if not moves.is_empty():
		txt += "Le loro mosse precedenti:\n- " + "\n- ".join(moves) + "\n\n"
	txt += "Riassunto della campagna:\n" + (new_summary.strip_edges() if new_summary.strip_edges() != "" else summary) + "\n"
	var chs: Array = st.data.get("story", {}).get("chapters", [])
	if chapter < chs.size():  # the next chapter, for coherence only
		var nx: Dictionary = chs[chapter]
		txt += "\nProssimo capitolo (solo per coerenza, non raccontarlo): %s. %s\n" % [str(nx.get("title", "")), StoryImport.master_text(str(nx.get("text", ""))).left(500)]
	return [{"role": "user", "content": txt}]


## Lines "Name: what it did" of the answer to factions_prompt(), only for the
## campaign's factions (matched by a word of their name).
static func parse_faction_moves(full: String, factions: Array) -> Array:
	var out: Array = []
	for line in full.split("\n"):
		var l := line.strip_edges().trim_prefix("-").trim_prefix("*").strip_edges().replace("**", "")
		var colon := l.find(":")
		if colon < 2 or l.length() - colon < 12:
			continue
		var head := Actions.norm(l.left(colon))
		for f in factions:
			var fname := Actions.norm(str(f).get_slice(":", 0))
			var hit := head == fname
			for w in fname.split(" "):
				if w.length() >= 4 and head.contains(w):
					hit = true
			if hit:
				out.append(l.left(GameState.FACT_CHARS + 40))
				break
		if out.size() >= GameState.FACTIONS_MAX:
			break
	return out


func chapter_markdown(prose: String) -> String:
	var md := PackedStringArray()
	md.append("# Capitolo %d%s" % [chapter, (": " + chapter_title) if chapter_title != "" else ""])
	md.append("")
	md.append("*%s - %s*" % [str(st.data.get("name", "")), Time.get_date_string_from_system()])
	md.append("")
	md.append("## Riassunto")
	md.append("")
	md.append(prose.strip_edges() if prose.strip_edges() != "" else "(riassunto non disponibile: il narratore era spento)")
	md.append("")
	var f := facts()
	if not f.is_empty():
		md.append("## Fatti registrati dal tavolo")
		md.append("")
		for x in f:
			md.append("- " + x)
		md.append("")
	var moves: Array = st.data.get("faction_moves", [])
	if not moves.is_empty():
		md.append("## Intanto, fuori scena")
		md.append("")
		for m in moves:
			md.append("- " + str(m))
		md.append("")
	md.append("## Trascrizione")
	md.append("")
	for t in transcript:
		md.append("**%s**: %s" % [t.who, t.text])
		md.append("")
	return "\n".join(md)


func chapter_path(n: int) -> String:
	return dir + "/capitolo_%02d.md" % n


## Saves the finished chapter and starts the next one.
func close_chapter(prose: String, new_summary: String) -> String:
	var path := chapter_path(chapter)
	_write(path, chapter_markdown(prose))
	if new_summary.strip_edges() != "":
		summary = new_summary.strip_edges()
	elif prose.strip_edges() != "":
		summary = (summary + "\n\nCapitolo %d: " % chapter + prose.strip_edges()).strip_edges()
	_write(dir + "/riassunto.md", summary)
	st.chronicle_add("storia", "Fine del capitolo %d%s" % [chapter, (": " + chapter_title) if chapter_title != "" else ""])
	chapter += 1
	chapter_title = ""
	transcript = []
	read_pos = 0
	read_mark = 0
	chron_start = st.data.get("chronicle", []).size()
	save()
	return path


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _write(path: String, text: String) -> void:
	if not st.persist:
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
