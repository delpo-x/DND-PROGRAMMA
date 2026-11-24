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
		chron_start = clampi(int(j.get("chron_start", chron_start)), 0, st.data.get("chronicle", []).size())
		read_pos = maxi(0, int(j.get("read_pos", 0)))
		read_mark = clampi(int(j.get("read_mark", transcript.size())), 0, transcript.size())


func save() -> void:
	if not st.persist:
		return
	_write(dir + "/corrente.json", JSON.stringify({"chapter": chapter, "title": chapter_title,
		"transcript": transcript, "chron_start": chron_start, "read_pos": read_pos, "read_mark": read_mark}, "\t"))


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

## Words of a player's action that call for a check, and which skill.
## Order matters: the first match wins. Words at the start of a word only.
const CHECK_WORDS: Array = [
	["Percezione", ["cerco trappol", "trappol", "ascolt", "orecchio", "scrut", "osserv", "guardo attent", "con attenzione", "sbirci", "origli", "annus"]],
	["Indagare", ["esamin", "ispezion", "frug", "perquis", "cerco indiz", "indizi", "cerco passagg", "cerco", "rovist"]],
	["Atletica", ["arrampic", "scalo", "scalare", "salto", "saltare", "nuot", "sfond", "forzo", "forzare", "spingo", "sollev", "trascin"]],
	["Acrobazia", ["equilibri", "capriol", "schiv", "rotol", "in bilico"]],
	["Furtività", ["di nascosto", "nascond", "furtiv", "silenzios", "senza farmi", "senza fare rumore", "pedin", "sgattaiol"]],
	["Rapidità di Mano", ["borseggi", "scassin", "grimald", "rubo", "serratur", "disinnesc"]],
	["Persuasione", ["convinc", "persuad", "supplic"]],
	["Inganno", ["mento", "mentire", "ingann", "bluff", "fingo", "fingere", "travest"]],
	["Intimidire", ["minacc", "intimid", "spavent"]],
	["Intuizione", ["sta mentendo", "mi fido", "capire se", "intenzion"]],
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
				if i == 0 or not low[i - 1].is_valid_identifier():
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
	if chs.is_empty():
		return {}
	return chs[clampi(chapter - 1, 0, chs.size() - 1)]


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
	p.append("- Al massimo 4 frasi, un solo paragrafo: la tua voce viene letta ad alta voce.")
	p.append("- Parla solo di luoghi, rumori, PNG e mostri. I personaggi dei giocatori fanno e dicono soltanto ciò che scrivono i giocatori: non farli muovere, parlare o pensare.")
	p.append("- Chiudi sempre con la domanda: Cosa fate?")
	p.append("- Non tirare dadi e non inventare numeri: dadi, danni e punti ferita li gestisce il tavolo.")
	p.append("- Se un'azione ha un esito incerto chiedi una prova scrivendo alla fine, su una riga a parte, ad esempio: [[PROVA: Percezione CD 15: Aria]] (abilità, difficoltà da 10 a 20, chi la tira oppure tutti).")
	p.append("- Per un tiro salvezza: [[PROVA: TS Destrezza CD 13: tutti]].")
	p.append("- Quando inizia un combattimento scrivi alla fine: [[COMBATTIMENTO: Goblin x2, Lupo]] usando i nomi dei mostri qui sotto. Poi non narrare i colpi: li risolve il tavolo.")
	p.append("- Quando il capitolo arriva a una conclusione naturale scrivi alla fine [[FINE CAPITOLO]].")
	p.append("- I marcatori tra doppie parentesi quadre vanno solo alla fine e solo quando servono.")
	p.append("- La traccia del capitolo può essere scritta ad appunti, senza articoli: tu racconta sempre in italiano pieno e scorrevole, senza sigle.")
	p.append("- Se la traccia ha una linea temporale, porta il gruppo da un momento al successivo seguendo le loro scelte, senza saltare avanti. Quando arriva il momento indicato come fine, chiudi il capitolo.")
	p.append("- Le battute del Master che vengono dal testo da leggere sono già state lette ai giocatori: non ripeterle, riprendi da lì.")
	p.append("- A volte ricevi un brano dal testo dell'avventura: usalo per luoghi, dialoghi e indizi, riassumendolo con parole tue.")
	p.append("Esempio di risposta giusta. Giocatore: Entriamo nella grotta. Master: L'aria si fa umida e un odore di fumo vi punge la gola. Oltre una curva tremola la luce di un fuoco e si sentono voci gracchianti. Cosa fate?")
	p.append("")
	p.append("Il gruppo: " + "; ".join(party) + ".")
	if not known.is_empty():
		p.append("Mostri e PNG preparati per questa avventura: " + ", ".join(known) + ".")
	p.append("Altri mostri che puoi usare: " + ", ".join(bestiary_names()) + ".")
	var tone := str(st.data.get("tone", "")).strip_edges()
	if tone != "":
		p.append("")
		p.append("Tono dell'avventura (seguilo in ogni risposta): %s" % tone.left(StoryImport.TONE_MAX))
	var story: Dictionary = st.data.get("story", {})
	if not story.is_empty():
		p.append("")
		p.append("Avventura: %s." % str(story.get("title", "")))
		var ch := chapter_info()
		if not ch.is_empty():
			p.append("Traccia del capitolo (seguila liberamente): %s. %s" % [str(ch.get("title", "")), str(ch.get("text", "")).left(StoryImport.READ_CHARS)])
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
			+ "la prova, ad esempio [[PROVA: %s CD 15: %s]], con la difficoltà che scegli tu da 10 a 20.]\n" % [pc.skill, pc.who]) + last
	if extra != "":
		last = extra + "\n" + last
	out.append({"role": "user", "content": last})
	return out


# ---------------------------------------------------------------- passages
## Paragraphs of the full chapter text that talk about what was just said:
## the narrator reads only the start of a chapter, so the details further on
## (a room, a NPC, a clue) are looked up by their words and sent with that
## one request. Words of the players count double, names count double too.
func passages(limit := PASSAGE_CHARS) -> String:
	var text := str(chapter_info().get("text", ""))
	if text.length() <= StoryImport.READ_CHARS or transcript.is_empty():
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
	for para in _pieces(text):
		at += para.length() + 1
		if at <= StoryImport.READ_CHARS or para.length() < 40:
			continue
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
