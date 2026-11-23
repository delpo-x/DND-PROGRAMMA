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
const TAG_RE := "\\[\\[\\s*([A-Za-zÀ-ÿ ]+?)\\s*(?::\\s*([^\\]]*))?\\]\\]"

var st  # GameState
var dir := ""
var chapter := 1
var chapter_title := ""
var transcript: Array = []  # {role: "user"|"assistant", who, text}
var chron_start := 0
var summary := ""


func open(state) -> void:
	st = state
	dir = "user://the_game/%s" % str(st.data.get("id", "campagna"))
	DirAccess.make_dir_recursive_absolute(dir)
	chapter = 1
	chapter_title = ""
	transcript = []
	chron_start = st.data.get("chronicle", []).size()
	summary = _read(dir + "/riassunto.md")
	var saved := _read(dir + "/corrente.json")
	var j = JSON.parse_string(saved) if saved.strip_edges() != "" else null
	if j is Dictionary:
		chapter = maxi(1, int(j.get("chapter", 1)))
		chapter_title = str(j.get("title", ""))
		transcript = j.get("transcript", []) if j.get("transcript") is Array else []
		chron_start = clampi(int(j.get("chron_start", chron_start)), 0, st.data.get("chronicle", []).size())


func save() -> void:
	if not st.persist:
		return
	_write(dir + "/corrente.json", JSON.stringify({"chapter": chapter, "title": chapter_title,
		"transcript": transcript, "chron_start": chron_start}, "\t"))


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
	if extra != "":
		last = extra + "\n" + last
	out.append({"role": "user", "content": last})
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
