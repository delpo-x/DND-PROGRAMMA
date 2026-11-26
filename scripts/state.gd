class_name GameState
extends RefCounted
## All session data lives here, on the master device. Browsers only receive
## the filtered views built by player_view() / screen_view().

signal changed
signal roll_added(entry: Dictionary)
signal request_added(req: Dictionary)
signal notice(text: String)  # short message for the master (shown as a toast)
signal map_event(title: String, lines: Array)  # attacks of opportunity on the map

const SAVE_DIR := "user://campagne"
const SETTINGS := "user://impostazioni.json"
const LOG_LIMIT := 100000  # rolls kept per campaign (nothing is lost in practice)
const BACKUP_DIR := "user://campagne/backup"
const BACKUP_KEEP := 40
const BACKUP_EVERY := 600.0  # seconds between automatic snapshots
const VIEW_LOG := 40
const MAP_DIR := "user://mappe"
const PORTRAIT_DIR := "user://ritratti"
const PORTRAIT_SIDE := 384
const MAP_MAX_SIDE := 3072  # bigger pictures are scaled down (phones)

var data: Dictionary = {}
var persist := true
var online_chars: Dictionary = {}  # char_id -> true (filled by the network server)
var rng := RandomNumberGenerator.new()
var save_pending := false
## Undo: copies of `data` before each change. Changes less than UNDO_GAP ms
## apart are one step (an action with all its rolls, a drag on the map).
const UNDO_MAX := 30
const UNDO_GAP := 700
var _undo: Array = []
var _shadow := {}          # data as it was after the last finished change
var _shadow_stale := false
var _last_touch := -100000
var _restoring := false
var _last_backup := 0.0
# Dnd The Game (AI master): the phones show the master's last lines and a
# box to talk to it. Not saved with the campaign.
var ai_master := false
var ai_feed: Array = []  # [{who, text}]
var ai_secrets: Dictionary = {}  # char id -> [{q, a}]: each player sees only their own
var ai_busy := false
var ai_lobby: Array = []  # Dnd The Game: before the start, [{id, name, ready}] of the players on a phone
var ai_reading := ""  # Dnd The Game: "on" while the chapter text is read aloud, "paused" when there is more to read


func _init() -> void:
	rng.randomize()


# ------------------------------------------------------------------ helpers
func now_str() -> String:
	return Time.get_datetime_string_from_system(false, true)


func time_str() -> String:
	var t := Time.get_time_dict_from_system()
	return "%02d:%02d:%02d" % [t.hour, t.minute, t.second]


func new_id(prefix: String) -> String:
	var n := int(data.get("next_id", 1))
	data["next_id"] = n + 1
	return "%s%d" % [prefix, n]


func touch() -> void:
	_undo_track()
	save_pending = true
	changed.emit()


func _undo_track() -> void:
	if _restoring:
		return
	var now := Time.get_ticks_msec()
	if now - _last_touch >= UNDO_GAP and not _shadow_stale and not _shadow.is_empty() \
			and str(_shadow.get("id", "")) == str(data.get("id", "")):
		_undo.append(_shadow)
		if _undo.size() > UNDO_MAX:
			_undo.pop_front()
		_shadow = {}
	_last_touch = now
	_shadow_stale = true


## Called every frame by the apps: once the changes stop, a copy of the data
## is kept as the point to go back to. force: at once (tests).
func undo_tick(force := false) -> void:
	if _shadow_stale and (force or Time.get_ticks_msec() - _last_touch >= UNDO_GAP):
		_shadow = data.duplicate(true)
		_shadow_stale = false


## A new campaign was opened: nothing to undo.
func undo_reset() -> void:
	_undo.clear()
	_shadow = data.duplicate(true)
	_shadow_stale = false
	_last_touch = Time.get_ticks_msec()


func can_undo() -> bool:
	return not _undo.is_empty()


## Goes back to before the last change (damage, healing, an action with its
## rolls, a condition, a rest...). The phones keep their characters.
func undo() -> bool:
	if _undo.is_empty():
		return false
	var claims = data.get("claims", {})
	data = _undo.pop_back()
	data["claims"] = claims
	_shadow = data.duplicate(true)
	_shadow_stale = false
	_restoring = true
	touch()
	_restoring = false
	_last_touch = -100000
	notice.emit("Ultima modifica annullata")
	return true


# ---------------------------------------------------------------- campaigns
func empty_campaign(cname: String) -> Dictionary:
	var now := now_str()
	return {
		"version": 1,
		"id": "camp_%d_%d" % [int(Time.get_unix_time_from_system()), rng.randi() % 100000],
		"name": cname, "created": now, "updated": now, "next_id": 1,
		"characters": [], "monsters": [], "quests": [], "log": [], "requests": [],
		"claims": {}, "csv_token": "%08x%08x" % [rng.randi(), rng.randi()],
		"initiative": {"active": false, "round": 1, "current": "", "combatants": []},
		"session": 1, "sessions": [{"n": 1, "date": now, "notes": ""}], "notes": "",
		"story": {},
		# campaign chronicle: everything that happened, in order. Never trimmed.
		# {id, t (date-time), s (session), cat, text, auto, public}
		"chronicle": [],
		"xp_total": 0,
		# battle maps: {id, name, file, w, h, cell, ox, oy, grid, tokens: [{ref, x, y}]}
		# the picture is user://mappe/<file>.jpg; cell/ox/oy in picture pixels,
		# token x/y in squares. map_active = the map the players see ("" = none).
		"maps": [], "map_active": "",
	}


func new_campaign(cname: String) -> void:
	if not data.is_empty():
		save_now()
	data = empty_campaign(cname)
	save_now()
	touch()


func campaign_path(id: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, id]


func save_now() -> void:
	save_pending = false
	if not persist or data.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	data["updated"] = now_str()
	var path := campaign_path(str(data.id))
	# write to a temporary file first, then swap: a crash mid-write never
	# leaves a half-written campaign behind
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
		# the previous file stays as .bak until the new one is in place,
		# so there is always a complete copy on disk (see _read_campaign)
		var bak := path + ".bak"
		if FileAccess.file_exists(path):
			if FileAccess.file_exists(bak):
				DirAccess.remove_absolute(bak)
			DirAccess.rename_absolute(path, bak)
		if DirAccess.rename_absolute(tmp, path) == OK:
			DirAccess.remove_absolute(bak)
	var now := Time.get_unix_time_from_system()
	if now - _last_backup >= BACKUP_EVERY:
		backup_now("auto")
	var s := FileAccess.open(SETTINGS, FileAccess.WRITE)
	if s:
		s.store_string(JSON.stringify({"last": data.id}))
		s.close()


# ------------------------------------------------------------------ backups
func backup_dir(id: String) -> String:
	return "%s/%s" % [BACKUP_DIR, id]


## Snapshot of the current campaign in user://campagne/backup/<id>/.
## The oldest automatic snapshots are removed beyond BACKUP_KEEP; snapshots
## taken for a reason (new session, restore, import) are kept.
func backup_now(reason := "manuale") -> void:
	if not persist or data.is_empty():
		return
	_last_backup = Time.get_unix_time_from_system()
	var dir := backup_dir(str(data.id))
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var f := FileAccess.open("%s/%s_%s.json" % [dir, stamp, reason.validate_filename()], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
	var autos: Array = []
	for b in list_backups():
		if b.reason == "auto":
			autos.append(b)
	for i in range(BACKUP_KEEP, autos.size()):
		DirAccess.remove_absolute(autos[i].path)


## Backups of the current campaign, newest first: [{path, date, reason, size}].
func list_backups() -> Array:
	var out: Array = []
	if data.is_empty():
		return out
	var dir := backup_dir(str(data.id))
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for fn in d.get_files():
		if not fn.ends_with(".json"):
			continue
		var parts := fn.get_basename().split("_")
		var date := ("%s %s" % [parts[0], parts[1].replace("-", ":")]) if parts.size() >= 2 else fn
		var reason := "_".join(parts.slice(2)) if parts.size() > 2 else ""
		out.append({"path": "%s/%s" % [dir, fn], "date": date, "reason": reason,
			"size": FileAccess.get_file_as_bytes("%s/%s" % [dir, fn]).size()})
	out.sort_custom(func(a, b): return str(a.path) > str(b.path))
	return out


## Brings back a snapshot; the current state is saved as a backup first.
func restore_backup(path: String) -> bool:
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (j is Dictionary) or str(j.get("id", "")) != str(data.id):
		return false
	backup_now("prima-del-ripristino")
	data = _normalize(j)
	chronicle_add("salvataggio", "Campagna ripristinata dal salvataggio del %s" % path.get_file().left(19).replace("_", " "), false)
	save_now()
	touch()
	return true


## Whole campaign as JSON text (for export to a file).
func export_json() -> String:
	return JSON.stringify(data, "\t")


## Imports a campaign file as a NEW campaign (never overwrites an existing one).
func import_json(txt: String) -> String:
	var j = JSON.parse_string(txt)
	if not (j is Dictionary) or not j.has("characters"):
		return ""
	if not data.is_empty():
		save_now()
	j["id"] = "camp_%d_%d" % [int(Time.get_unix_time_from_system()), rng.randi() % 100000]
	j["claims"] = {}
	data = _normalize(j)
	chronicle_add("salvataggio", "Campagna importata da file", false)
	save_now()
	backup_now("importata")
	touch()
	return str(data.name)


# --------------------------------------------------------------- chronicle
const CHRONICLE_CATS := {
	"sessione": "Sessione", "combattimento": "Combattimento", "sconfitta": "Sconfitte e cadute",
	"personaggio": "Personaggi", "mostro": "Mostri e PNG", "missione": "Missioni", "tiro": "Tiri memorabili",
	"riposo": "Riposi", "xp": "Esperienza", "storia": "Storia", "salvataggio": "Salvataggi",
	"evento": "Evento", "png": "PNG incontrato", "luogo": "Luogo", "bottino": "Bottino", "nota": "Nota del master",
}
## Categories the master writes by hand.
const CHRONICLE_MANUAL := ["evento", "png", "luogo", "bottino", "nota"]


## Adds a line to the campaign chronicle. public = visible on the phones.
func chronicle_add(cat: String, text: String, public := true, auto := true) -> Dictionary:
	if data.is_empty():
		return {}
	var e := {"id": new_id("c"), "t": now_str(), "s": int(data.get("session", 1)), "cat": cat,
		"text": text.strip_edges().left(4000), "auto": auto, "public": public}
	data.chronicle.append(e)
	touch()
	return e


func chronicle_update(id: String, fields: Dictionary) -> void:
	for e in data.chronicle:
		if e.id == id:
			if fields.has("text"):
				e.text = str(fields.text).strip_edges().left(4000)
			if fields.has("public"):
				e.public = bool(fields.public)
			if fields.has("cat") and CHRONICLE_CATS.has(str(fields.cat)):
				e.cat = str(fields.cat)
			e["edited"] = now_str()
			touch()
			return


## Chronicle as Markdown, grouped by session (for export / printing).
func chronicle_markdown(only_public := false) -> String:
	var out := PackedStringArray()
	out.append("# Cronaca della campagna: %s" % data.name)
	out.append("")
	var dates := {}
	for ss in data.sessions:
		dates[int(ss.n)] = str(ss.date).left(10)
	var cur := -1
	for e in data.chronicle:
		if only_public and not bool(e.get("public", true)):
			continue
		if int(e.s) != cur:
			cur = int(e.s)
			out.append("")
			out.append("## Sessione %d%s" % [cur, ("  (%s)" % dates[cur]) if dates.has(cur) else ""])
			out.append("")
		var tag := str(CHRONICLE_CATS.get(e.cat, e.cat))
		out.append("- %s **%s**: %s%s" % [str(e.t).substr(11, 5), tag, str(e.text).replace("\n", "  \n  "), "" if bool(e.get("public", true)) else "  _(solo master)_"])
	return "\n".join(out) + "\n"


func _public_chronicle() -> Array:
	var out: Array = []
	for e in data.chronicle:
		if bool(e.get("public", true)):
			out.append({"t": e.t, "s": e.s, "cat": e.cat, "label": CHRONICLE_CATS.get(e.cat, e.cat), "text": e.text})
	return out.slice(maxi(0, out.size() - 300))


func list_campaigns() -> Array:
	var out: Array = []
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		return out
	for fn in d.get_files():
		if not fn.ends_with(".json"):
			continue
		var txt := FileAccess.get_file_as_string("%s/%s" % [SAVE_DIR, fn])
		var j = JSON.parse_string(txt)
		if j is Dictionary and j.has("id"):
			out.append({"id": j.id, "name": j.get("name", "?"), "updated": j.get("updated", ""),
				"session": int(j.get("session", 1)), "chars": j.get("characters", []).size()})
	out.sort_custom(func(a, b): return str(a.updated) > str(b.updated))
	return out


## Reads a campaign file; if the app stopped in the middle of a save, the
## complete new copy (.tmp) or the previous one (.bak) is used instead.
func _read_campaign(id: String):
	for p in [campaign_path(id), campaign_path(id) + ".tmp", campaign_path(id) + ".bak"]:
		if FileAccess.file_exists(p):
			var j = JSON.parse_string(FileAccess.get_file_as_string(p))
			if j is Dictionary:
				return j
	return null


func load_campaign(id: String) -> bool:
	var j = _read_campaign(id)
	if not (j is Dictionary):
		return false
	if not data.is_empty():
		save_now()
	data = _normalize(j)
	save_now()
	undo_reset()
	touch()
	return true


func load_last() -> bool:
	var j = null
	if FileAccess.file_exists(SETTINGS):
		j = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
	if j is Dictionary and j.has("last") and load_campaign(str(j.last)):
		return true
	var all := list_campaigns()
	if all.size() > 0:
		return load_campaign(str(all[0].id))
	return false


func delete_campaign(id: String) -> void:
	for ext in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(campaign_path(id) + ext)


func duplicate_campaign(id: String) -> void:
	var j = JSON.parse_string(FileAccess.get_file_as_string(campaign_path(id)))
	if not (j is Dictionary):
		return
	var copy: Dictionary = j
	copy["id"] = "camp_%d_%d" % [int(Time.get_unix_time_from_system()), rng.randi() % 100000]
	copy["name"] = "%s (copia)" % copy.get("name", "")
	copy["claims"] = {}
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(campaign_path(copy.id), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(copy))


## JSON numbers come back as floats: turn the known integer fields back into ints.
func _normalize(j: Dictionary) -> Dictionary:
	var base := empty_campaign(str(j.get("name", "Campagna")))
	for k in base:
		if not j.has(k):
			j[k] = base[k]
	j.next_id = int(j.next_id)
	j.session = int(j.session)
	for ch in j.characters:
		var blank := Rules.blank_character("")
		for k in blank:
			if not ch.has(k):
				ch[k] = blank[k]
		for k in ["level", "hp", "hp_max", "hp_temp", "ac", "speed", "prof", "init_bonus"]:
			ch[k] = int(ch[k])
		for a in Rules.ABILITIES:
			ch.ab[a] = int(ch.ab.get(a, 10))
		for s in ch.skills.keys():
			ch.skills[s] = int(ch.skills[s])
		for a in ch.attacks:
			a.bonus = int(a.get("bonus", 0))
	for m in j.monsters:
		for k in ["ac", "hp", "hp_max", "init_mod"]:
			m[k] = int(m.get(k, 0))
	for c in j.initiative.combatants:
		c.score = int(c.get("score", Rules.NO_SCORE))
		c.mod = int(c.get("mod", 0))
		c.tie = int(c.get("tie", rng.randi()))
	j.initiative.round = int(j.initiative.get("round", 1))
	for q in j.quests:
		for c in q.checks:
			c.dc = int(c.get("dc", 10))
	for e in j.log:
		e.total = int(e.get("total", 0))
		e.mod = int(e.get("mod", 0))
		e.nat = int(e.get("nat", 0))
		e.dc = int(e.get("dc", -1))
		for d in e.get("dice", []):
			d.s = int(d.s)
			d.v = int(d.v)
	for r in j.requests:
		r.dc = int(r.get("dc", -1))
	for e in j.chronicle:
		e.s = int(e.get("s", 1))
	j.xp_total = int(j.get("xp_total", 0))
	for mp in j.maps:
		for k in ["w", "h"]:
			mp[k] = int(mp.get(k, 0))
		for k in ["cell", "ox", "oy"]:
			mp[k] = float(mp.get(k, 0.0))
		mp.cell = maxf(4.0, mp.cell)
		mp.grid = bool(mp.get("grid", true))
		if not mp.has("tokens"):
			mp.tokens = []
		for t in mp.tokens:
			t.x = int(t.x)
			t.y = int(t.y)
	j.map_active = str(j.get("map_active", ""))
	for ch in j.characters:
		ch.death_ok = int(ch.get("death_ok", 0))
		ch.death_ko = int(ch.get("death_ko", 0))
		ch.xp = int(ch.get("xp", 0))
		ch.inspiration = bool(ch.get("inspiration", false))
		if not ch.get("res_used") is Dictionary:
			ch.res_used = {}
		if not ch.get("res_custom") is Array:
			ch.res_custom = []
		Rules.sync_slots(ch)
	for m in j.monsters:
		m.xp = int(m.get("xp", 0))
		m.conditions = str(m.get("conditions", ""))
		m.hp_temp = int(m.get("hp_temp", 0))
		for k in ["resist", "vuln", "immune"]:
			m[k] = str(m.get(k, ""))
	return j


func new_session() -> void:
	data.session = int(data.session) + 1
	data.sessions.append({"n": data.session, "date": now_str(), "notes": ""})
	chronicle_add("sessione", "Inizia la sessione %d" % int(data.session))
	backup_now("sessione-%d" % int(data.session))
	touch()


func current_session() -> Dictionary:
	for s in data.sessions:
		if int(s.n) == int(data.session):
			return s
	return {}


# --------------------------------------------------------------- characters
func characters() -> Array:
	return data.get("characters", [])


func monsters() -> Array:
	return data.get("monsters", [])


## Encounter difficulty (2024 rules) of the given monsters (ids; monsters at
## 0 PF do not count) plus extra_xp, against the given characters, by default
## every character of the campaign. Adds "unknown": monsters without XP (made
## by hand, challenge rating unknown) and "party": number of characters.
func encounter(monster_ids: Array, pc_ids: Array = [], extra_xp := 0) -> Dictionary:
	var levels: Array = []
	for c in characters():
		if pc_ids.is_empty() or pc_ids.has(c.id):
			levels.append(int(c.get("level", 1)))
	var xp := extra_xp
	var unknown := 0
	for m in monsters():
		if not monster_ids.has(m.id) or int(m.hp) <= 0:
			continue
		if int(m.get("xp", 0)) > 0:
			xp += int(m.xp)
		else:
			unknown += 1
	var d := Rules.encounter_difficulty(levels, xp)
	d.unknown = unknown
	d.party = levels.size()
	return d


## Encounter difficulty of the fight in progress: monsters and characters in
## the initiative order (every character when none is in it yet).
func combat_encounter() -> Dictionary:
	var mons: Array = []
	var pcs: Array = []
	for c in ini().combatants:
		if c.type == "monster":
			mons.append(c.ref)
		else:
			pcs.append(c.ref)
	return encounter(mons, pcs)


func find_entity(id: String) -> Dictionary:
	for c in characters():
		if c.id == id:
			return c
	for m in monsters():
		if m.id == id:
			return m
	return {}


func is_pc(id: String) -> bool:
	return id.begins_with("c")


func add_character(cname: String, player := "") -> Dictionary:
	var ch := Rules.blank_character(cname.strip_edges().left(40) if cname.strip_edges() != "" else "Nuovo eroe")
	Rules.sync_slots(ch)
	ch.id = new_id("c")
	ch.player = player.left(40)
	data.characters.append(ch)
	chronicle_add("personaggio", "%s si unisce al gruppo" % ch.name)
	touch()
	return ch


## Creates a character from a sheet dictionary (e.g. read from a PDF).
func import_character(sheet: Dictionary, player := "") -> Dictionary:
	var ch := add_character(str(sheet.get("name", "")), player if player != "" else str(sheet.get("player", "")))
	var fields := sheet.duplicate(true)
	fields.erase("id")
	if player != "":
		fields["player"] = player
	Rules.merge_sheet(ch, fields)
	touch()
	return ch


## Creates the story's ready-made characters that don't exist yet
## (same first name = already there). Returns the names created.
func import_story_pcs() -> Array:
	var made: Array = []
	for pc in data.get("story", {}).get("pcs", []):
		var first := str(pc.name).split(" ")[0].split(",")[0].to_lower()
		var exists := false
		for c in characters():
			if str(c.name).split(" ")[0].split(",")[0].to_lower() == first:
				exists = true
		if not exists:
			var sheet: Dictionary = pc.duplicate(true)
			sheet["notes"] = "PG pronto dell'avventura \"%s\". Completa la scheda." % data.story.get("title", "")
			import_character(sheet)
			made.append(pc.name)
	return made


## Tone of the adventure for the narrator of Dnd The Game ("cupo, PNG sospettosi").
func set_tone(t: String) -> void:
	data.tone = t.strip_edges().left(StoryImport.TONE_MAX)
	touch()


const PINNED_MAX := 8      # pinned facts the narrator reads in every reply
const FACTIONS_MAX := 5    # factions that move between chapters
const FACT_CHARS := 140    # longest pinned fact or faction line


## Lines of a text box: trimmed, without list dashes, empty ones dropped.
static func text_lines(t: String, most: int, chars := FACT_CHARS) -> Array:
	var out: Array = []
	for l in t.split("\n"):
		var s := l.strip_edges().trim_prefix("-").trim_prefix("*").strip_edges()
		if s != "" and out.size() < most:
			out.append(s.left(chars))
	return out


## Pinned facts of the campaign, one per line: what must stay true even after
## the chapters are summarised (a promise, a debt, a name decided at the table).
func set_pinned(t: String) -> void:
	data.pinned = text_lines(t, PINNED_MAX)
	touch()


## Factions of the campaign, one per line ("Goblin di Sgnacco: vogliono il sale
## della carovana"). At the end of each chapter the narrator writes what each
## one did meanwhile (faction_moves).
func set_factions(t: String) -> void:
	data.factions = text_lines(t, FACTIONS_MAX)
	if data.factions.is_empty():
		data.faction_moves = []
	touch()


func set_faction_moves(moves: Array) -> void:
	data.faction_moves = moves.slice(0, FACTIONS_MAX)
	touch()


const NPC_MAX := 12   # named NPCs whose attitude the narrator keeps
## How an NPC feels about the party, from worst to best.
const ATTITUDES := ["ostile", "diffidente", "neutrale", "amichevole", "alleato"]


## Attitude word in a text ("amichevole", "Amica", "alleata"), or "".
static func attitude_of(t: String) -> String:
	var low := t.to_lower()
	for a in ATTITUDES:
		if low.contains(a.left(a.length() - 1)):
			return a
	for pair in [["amic", "amichevole"], ["nemic", "ostile"], ["sospett", "diffidente"], ["indifferent", "neutrale"]]:
		if low.contains(pair[0]):
			return pair[1]
	return ""


## NPCs of the campaign from a text box, one per line: "Marta: amichevole,
## ci deve un favore". Lines without an attitude count as neutral.
func set_npcs(t: String) -> void:
	var out: Array = []
	for l in text_lines(t, NPC_MAX):
		var colon := str(l).find(":")
		var npc_name := (str(l).left(colon) if colon > 0 else str(l)).strip_edges()
		var rest := str(l).substr(colon + 1).strip_edges() if colon > 0 else ""
		var att := attitude_of(rest.get_slice(",", 0))
		var note := rest.substr(rest.find(",") + 1).strip_edges() if rest.contains(",") else ("" if att != "" else rest)
		if npc_name != "":
			out.append({"name": npc_name.left(40), "att": att if att != "" else "neutrale", "note": note.left(FACT_CHARS)})
	data.npcs = out
	touch()


## The NPC list as the text box shows it.
func npcs_text() -> String:
	var lines: Array = []
	for n in data.get("npcs", []):
		lines.append("%s: %s%s" % [n.name, n.att, (", " + str(n.note)) if str(n.get("note", "")) != "" else ""])
	return "\n".join(lines)


## Sets one NPC's attitude (added when new). Returns the attitude before, ""
## for a new NPC, or "-" when nothing changed.
func set_npc_attitude(npc_name: String, att: String) -> String:
	npc_name = npc_name.strip_edges().left(40)
	if npc_name == "" or not ATTITUDES.has(att):
		return "-"
	var npcs: Array = data.get("npcs", [])
	for n in npcs:
		if Actions.norm(str(n.name)) == Actions.norm(npc_name):
			if n.att == att:
				return "-"
			var before := str(n.att)
			n.att = att
			touch()
			return before
	if npcs.size() >= NPC_MAX:
		npcs.pop_front()  # the oldest one makes room
	npcs.append({"name": npc_name, "att": att, "note": ""})
	data.npcs = npcs
	touch()
	return ""


## Replaces the campaign story (chapters imported from a PDF). Master only.
func set_story(story: Dictionary) -> void:
	data.story = story
	if not story.is_empty():
		data.story["imported"] = now_str()
		chronicle_add("storia", "Importata l'avventura \"%s\" (%d capitoli)" % [story.get("title", ""), story.get("chapters", []).size()], false)
	touch()


func update_character(id: String, fields: Dictionary) -> void:
	var ch := find_entity(id)
	if ch.is_empty() or not is_pc(id):
		return
	var before := int(ch.get("hp", 0))
	Rules.merge_sheet(ch, fields)
	if int(ch.hp) != before:
		_hp_events(ch, id, before)
	_sync_combatant_mod(id)
	touch()


func delete_character(id: String) -> void:
	var gone := characters().filter(func(c): return c.id == id)
	data.characters = characters().filter(func(c): return c.id != id)
	for t in data.claims.keys():
		if data.claims[t] == id:
			data.claims.erase(t)
	_remove_ref_from_combat(id)
	_remove_ref_from_maps(id)
	if gone.size() == 1:
		_drop_portrait_file(str(gone[0].get("portrait", "")))
	touch()


# ---------------------------------------------------------------- portraits
static func portrait_path(file: String) -> String:
	return "%s/%s.jpg" % [PORTRAIT_DIR, file]


## Saves a character's picture: a square cut from the middle (from the upper
## part of a tall picture, where the face usually is), at most 384 px.
## Each change gets a new file name, so phones never show a cached old one.
func set_portrait(char_id: String, img: Image) -> bool:
	var ch := find_entity(char_id)
	if ch.is_empty() or not is_pc(char_id) or img == null or img.is_empty():
		return false
	var im: Image = img.duplicate()
	im.convert(Image.FORMAT_RGB8)
	var s := mini(im.get_width(), im.get_height())
	im = im.get_region(Rect2i((im.get_width() - s) / 2, (im.get_height() - s) / 4, s, s))
	if s > PORTRAIT_SIDE:
		im.resize(PORTRAIT_SIDE, PORTRAIT_SIDE, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(PORTRAIT_DIR)
	var file := "%s_%d" % [char_id, int(Time.get_unix_time_from_system() * 1000.0)]
	if im.save_jpg(portrait_path(file), 0.88) != OK:
		return false
	var old := str(ch.get("portrait", ""))
	ch.portrait = file
	_drop_portrait_file(old)
	touch()
	return true


func clear_portrait(char_id: String) -> void:
	var ch := find_entity(char_id)
	if ch.is_empty() or str(ch.get("portrait", "")) == "":
		return
	var old := str(ch.portrait)
	ch.portrait = ""
	_drop_portrait_file(old)
	touch()


## Removes the file unless a copy of this campaign still uses it.
func _drop_portrait_file(file: String) -> void:
	if file == "" or not Art.valid_file(file):
		return
	for c in list_campaigns():
		if c.id != data.id and FileAccess.get_file_as_string(campaign_path(c.id)).contains(file):
			return
	DirAccess.remove_absolute(portrait_path(file))


func _remove_ref_from_maps(ref: String) -> void:
	for mp in data.get("maps", []):
		mp.tokens = mp.tokens.filter(func(t): return t.ref != ref)


func char_claimed_by(id: String) -> Array:
	var out: Array = []
	for t in data.claims:
		if data.claims[t] == id:
			out.append(t)
	return out


# ----------------------------------------------------------------- monsters
func add_monster(m: Dictionary) -> Dictionary:
	var hp_max := maxi(1, int(m.get("hp_max", m.get("hp", 7))))
	var mon := {
		"id": new_id("m"), "name": str(m.get("name", "Mostro")).strip_edges().left(40),
		"kind": str(m.get("kind", "Mostro")), "ac": int(m.get("ac", 12)),
		"hp": hp_max, "hp_max": hp_max, "init_mod": int(m.get("init_mod", 0)),
		"notes": str(m.get("notes", "")), "revealed": bool(m.get("revealed", false)),
		"xp": maxi(0, int(m.get("xp", 0))), "conditions": "", "hp_temp": 0,
		"resist": str(m.get("resist", "")), "vuln": str(m.get("vuln", "")), "immune": str(m.get("immune", "")),
	}
	if mon.name == "":
		mon.name = "Mostro"
	data.monsters.append(mon)
	touch()
	return mon


func update_monster(id: String, fields: Dictionary) -> void:
	var m := find_entity(id)
	if m.is_empty() or is_pc(id):
		return
	for k in ["name", "kind", "notes", "conditions", "resist", "vuln", "immune"]:
		if fields.has(k):
			m[k] = str(fields[k]).left(2000)
	for k in ["ac", "hp", "hp_max", "init_mod", "hp_temp"]:
		if fields.has(k):
			m[k] = int(fields[k])
	if fields.has("revealed"):
		if bool(fields.revealed) and not bool(m.get("revealed", false)):
			chronicle_add("mostro", "Appare %s" % m.name)
		m.revealed = bool(fields.revealed)
	if fields.has("xp"):
		m.xp = maxi(0, int(fields.xp))
	m.hp_max = maxi(1, int(m.hp_max))
	m.hp = clampi(int(m.hp), 0, int(m.hp_max))
	m.hp_temp = maxi(0, int(m.get("hp_temp", 0)))
	_sync_combatant_mod(id)
	touch()


func _base_name(n: String) -> String:
	var re := RegEx.new()
	re.compile("^(.*?)\\s+(\\d+)$")
	var r := re.search(n)
	return r.get_string(1) if r else n


func _name_number(n: String, base: String) -> int:
	if n == base:
		return 1
	if n.begins_with(base + " ") and n.substr(base.length() + 1).is_valid_int():
		return int(n.substr(base.length() + 1))
	return 0


## Duplicates a monster: "Goblin" becomes "Goblin 1" and the copies "Goblin 2", "Goblin 3"...
func duplicate_monster(id: String, count := 1) -> Array:
	var src := find_entity(id)
	var made: Array = []
	if src.is_empty() or is_pc(id):
		return made
	var base := _base_name(str(src.name))
	var top := 0
	for m in monsters():
		top = maxi(top, _name_number(str(m.name), base))
	if str(src.name) == base:
		src.name = "%s 1" % base
		top = maxi(top, 1)
	for i in count:
		top += 1
		var copy: Dictionary = src.duplicate(true)
		copy.id = new_id("m")
		copy.name = "%s %d" % [base, top]
		copy.hp = int(copy.hp_max)
		copy.hp_temp = 0
		copy.conditions = ""
		data.monsters.append(copy)
		made.append(copy)
	touch()
	return made


func delete_monster(id: String) -> void:
	data.monsters = monsters().filter(func(m): return m.id != id)
	_remove_ref_from_combat(id)
	_remove_ref_from_maps(id)
	touch()


## amount < 0 = damage (temporary HP first), amount > 0 = healing.
## Characters (2024 rules): damage while at 0 PF = one failed death save
## (and no longer stable); damage still left after reaching 0 PF that equals
## or exceeds the PF maximum = instant death. A dead character can't be healed
## until the master resets the death saves (e.g. after a revival spell).
func change_hp(id: String, amount: int, crit := false) -> void:
	var e := find_entity(id)
	if e.is_empty() or amount == 0:
		return
	var pc := is_pc(id)
	if pc and is_dead(e):
		if amount > 0:
			notice.emit("%s è morto: per riportarlo in vita azzera prima i tiri contro la morte" % e.name)
		return
	var before := int(e.hp)
	if amount < 0:
		var dmg := -amount
		if int(e.get("hp_temp", 0)) > 0:
			var absorb := mini(dmg, int(e.hp_temp))
			e.hp_temp = int(e.hp_temp) - absorb
			dmg -= absorb
		e.hp = maxi(0, int(e.hp) - dmg)
		if pc and dmg > 0:
			var left := dmg - maxi(0, before)
			if left >= int(e.hp_max):
				e.death_ok = 0
				e.death_ko = 3
				chronicle_add("sconfitta", "%s muore sul colpo" % e.name)
				notice.emit("%s muore sul colpo: danni oltre i PF massimi" % e.name)
			elif before <= 0:
				if int(e.get("death_ok", 0)) >= 3:
					e.death_ok = 0  # damage ends the stable state
				e.death_ko = mini(3, int(e.get("death_ko", 0)) + (2 if crit else 1))
				notice.emit("%s subisce danni a 0 PF: %s al tiro contro la morte" % [e.name, "due fallimenti (critico)" if crit else "un fallimento"])
				if int(e.death_ko) >= 3:
					chronicle_add("sconfitta", "%s muore" % e.name)
	else:
		e.hp = mini(int(e.hp_max), int(e.hp) + amount)
	_hp_events(e, id, before)
	touch()


## A character at 0 PF with three failed death saves.
func is_dead(e: Dictionary) -> bool:
	return int(e.get("hp", 0)) <= 0 and int(e.get("death_ko", 0)) >= 3


## Damage of a given type: immunity, resistance and vulnerability are applied
## first. Returns [damage actually dealt, reason it changed].
func damage(id: String, amount: int, dtype := "", crit := false) -> Array:
	var e := find_entity(id)
	if e.is_empty():
		return [0, ""]
	var r: Array = Rules.apply_defenses(e, amount, dtype)
	if int(r[0]) > 0:
		change_hp(id, -int(r[0]), crit)
	return r


## Temporary hit points don't stack: the higher value is kept (PHB).
func give_temp_hp(id: String, amount: int) -> void:
	var e := find_entity(id)
	if e.is_empty() or amount <= 0:
		return
	e.hp_temp = maxi(int(e.get("hp_temp", 0)), amount)
	touch()


## Chronicle lines for falls, defeats and getting back up.
func _hp_events(e: Dictionary, id: String, before: int) -> void:
	var pc := is_pc(id)
	if before > 0 and int(e.hp) <= 0:
		if pc:
			# 0 PF: unconscious and prone (PHB), concentration ends
			set_condition(id, "Privo di sensi", true)
			set_condition(id, "Prono", true)
			if not is_dead(e):
				chronicle_add("sconfitta", "%s cade a terra, privo di sensi" % e.name)
		else:
			var r: int = int(ini().get("round", 1))
			chronicle_add("sconfitta", ("%s viene sconfitto" % e.name) + ((" al round %d" % int(r)) if ini().active else ""), bool(e.get("revealed", false)))
			if ini().active:
				if not ini().has("defeated"):
					ini()["defeated"] = []
				if not ini().defeated.has(id):
					ini().defeated.append(id)
	elif before <= 0 and int(e.hp) > 0:
		if pc:
			e.death_ok = 0
			e.death_ko = 0
			set_condition(id, "Privo di sensi", false)  # still prone: standing up costs movement
			chronicle_add("personaggio", "%s torna in piedi (%d PF)" % [e.name, int(e.hp)])
		elif ini().has("defeated"):
			# healed back up: no longer counts as defeated (no XP for it)
			ini().defeated.erase(id)


## Experience shared equally among the characters (rule of the Player's Handbook).
func award_xp(total: int, reason := "") -> void:
	var pcs := characters()
	if total <= 0 or pcs.is_empty():
		return
	var each := int(total / pcs.size())
	for ch in pcs:
		ch.xp = int(ch.get("xp", 0)) + each
	data.xp_total = int(data.get("xp_total", 0)) + total
	chronicle_add("xp", "%d PE guadagnati%s: %d a testa" % [total, (" (%s)" % reason) if reason != "" else "", each])
	touch()


## Short rest: just noted (hit dice are spent by the players).
## Long rest: characters with at least 1 PF back to full PF and spell slots;
## a character at 0 PF (stable or dead) gets no benefit (2024 rules).
func rest(long: bool) -> void:
	if long:
		var left_out: Array = []
		for ch in characters():
			if int(ch.hp) <= 0:
				left_out.append(str(ch.name))
				continue
			ch.hp = int(ch.hp_max)
			ch.hp_temp = 0
			ch.death_ok = 0
			ch.death_ko = 0
			ch.slots_used = [0, 0, 0, 0, 0, 0, 0, 0, 0]
			ch.res_used = {}  # every class resource back
			ch.hd_used = 0  # PHB 2024: all hit dice back
			if Rules.exhaustion(ch) > 0:
				exhaustion_add(str(ch.id), -1)
		var txt := "Il gruppo fa un riposo lungo: punti ferita, dadi vita, slot incantesimo e risorse di classe recuperati, un livello di indebolimento in meno"
		if left_out.size() > 0:
			txt += " (tranne %s: a 0 PF il riposo lungo non ha effetto)" % ", ".join(left_out)
			notice.emit("Riposo lungo senza effetto per %s (0 PF)" % ", ".join(left_out))
		chronicle_add("riposo", txt)
	else:
		# Pact Magic slots come back on a short rest.
		for ch in characters():
			if Rules.caster_kind(str(ch.cls)) == "pact":
				ch.slots_used = [0, 0, 0, 0, 0, 0, 0, 0, 0]
			# resources: "short" all back, "short1" one use back
			var used: Dictionary = ch.get("res_used", {})
			for r in Rules.resources(ch):
				if r.reset == "short":
					used.erase(r.key)
				elif r.reset == "short1" and int(r.used) > 0:
					used[r.key] = int(r.used) - 1
			ch.res_used = used
		chronicle_add("riposo", "Il gruppo fa un riposo breve")
	touch()


## Death saving throw for a character at 0 PF (d20: 10+ success, 1 = two
## failures, 20 = back to 1 PF). Returns a short description.
func death_save(id: String, roll: int) -> String:
	var ch := find_entity(id)
	if ch.is_empty() or not is_pc(id) or int(ch.hp) > 0:
		return ""
	if int(ch.get("death_ok", 0)) >= 3 or int(ch.get("death_ko", 0)) >= 3:
		return ""  # already stable or dead
	var out := ""
	if roll == 20:
		set_condition(id, "Privo di sensi", false)
		ch.hp = 1
		ch.death_ok = 0
		ch.death_ko = 0
		out = "20 naturale: %s torna a 1 PF!" % ch.name
		chronicle_add("personaggio", "%s si rialza con un 20 naturale al tiro salvezza contro la morte" % ch.name)
		if _grant_inspiration(ch):
			out += " E guadagna ispirazione."
	elif roll >= 10:
		ch.death_ok = int(ch.get("death_ok", 0)) + 1
		out = "Successo (%d/3)" % ch.death_ok
		if ch.death_ok >= 3:
			out = "%s è stabile" % ch.name
			chronicle_add("personaggio", "%s si stabilizza" % ch.name)
	else:
		ch.death_ko = int(ch.get("death_ko", 0)) + (2 if roll == 1 else 1)
		out = "Fallimento (%d/3)" % mini(3, ch.death_ko)
		if ch.death_ko >= 3:
			out = "%s muore" % ch.name
			chronicle_add("sconfitta", "%s muore" % ch.name)
	touch()
	return out


## Turns one Player's Handbook condition on or off in a character's
## comma-separated "conditions" text, keeping any free text already there.
## Spends (delta > 0) or recovers (delta < 0) spell slots of one level (1-9).
func use_slot(id: String, lvl: int, delta: int) -> void:
	var ch := find_entity(id)
	if ch.is_empty() or not is_pc(id) or lvl < 1 or lvl > 9:
		return
	Rules.sync_slots(ch)
	ch.slots_used[lvl - 1] = clampi(int(ch.slots_used[lvl - 1]) + delta, 0, int(ch.slots_max[lvl - 1]))
	touch()


## Casts a spell of the character's list: cantrips are free, otherwise the
## lowest free slot of the spell's level or higher is spent.
## Returns a short description, or "" if no slot is left.
func cast_spell(id: String, idx: int) -> String:
	var ch := find_entity(id)
	if ch.is_empty() or not is_pc(id):
		return ""
	var spells: Array = ch.get("spells", [])
	if idx < 0 or idx >= spells.size():
		return ""
	var sp: Dictionary = spells[idx]
	if int(sp.lvl) == 0:
		return "%s lancia %s (trucchetto)" % [ch.name, sp.name]
	Rules.sync_slots(ch)
	for l in range(int(sp.lvl), 10):
		if int(ch.slots_used[l - 1]) < int(ch.slots_max[l - 1]):
			ch.slots_used[l - 1] = int(ch.slots_used[l - 1]) + 1
			touch()
			var up := (" con uno slot di %d° livello" % l) if l > int(sp.lvl) else ""
			return "%s lancia %s%s" % [ch.name, sp.name, up]
	return ""


## Spends (delta > 0) or recovers (delta < 0) uses of a class resource (key
## from Rules.resources). Returns a short description, "" if nothing changed.
func use_resource(id: String, key: String, delta: int) -> String:
	var ch := find_entity(id)
	if ch.is_empty() or not is_pc(id):
		return ""
	for r in Rules.resources(ch):
		if r.key != key:
			continue
		var n := clampi(int(r.used) + delta, 0, int(r.max))
		if n == int(r.used):
			return ""
		if not ch.get("res_used") is Dictionary:
			ch.res_used = {}
		ch.res_used[key] = n
		touch()
		var left := int(r.max) - n
		if delta > 0:
			return "%s usa %s%s (%d rimast%s)" % [ch.name, r.name, (" x%d" % (n - int(r.used))) if n - int(r.used) > 1 else "", left, "a" if left == 1 else "e"]
		return "%s recupera %s (%d/%d)" % [ch.name, r.name, left, int(r.max)]
	return ""


## Resources added by the master (magic items, feats, multiclass): array of
## {name, max, reset}. Uses already spent are kept by position.
func set_custom_resources(id: String, list: Array) -> void:
	var ch := find_entity(id)
	if ch.is_empty() or not is_pc(id):
		return
	var out: Array = []
	for r in list:
		var n := str(r.get("name", "")).strip_edges().left(40)
		if n == "":
			continue
		var reset := str(r.get("reset", "long"))
		out.append({"name": n, "max": clampi(int(r.get("max", 1)), 1, 999),
			"reset": reset if Rules.RESET_NAMES.has(reset) else "long"})
	ch.res_custom = out
	var used: Dictionary = ch.get("res_used", {})
	for k in used.keys():
		if str(k).begins_with("c") and int(str(k).substr(1)) >= out.size():
			used.erase(k)
	ch.res_used = used
	touch()


## Master override of the maximum slots (auto = follow class and level).
func set_slots_max(id: String, mx: Array, auto: bool) -> void:
	var ch := find_entity(id)
	if ch.is_empty() or not is_pc(id):
		return
	ch.slots_auto = auto
	ch.slots_max = mx.duplicate()
	Rules.sync_slots(ch)
	touch()


const INCAPACITATING := ["Incapacitato", "Paralizzato", "Pietrificato", "Privo di sensi", "Stordito"]


## Adds (delta > 0) or removes exhaustion levels (PHB 2024). Level 6 kills.
func exhaustion_add(id: String, delta: int) -> void:
	var ch := find_entity(id)
	if ch.is_empty() or not ch.has("conditions"):
		return
	var lvl := clampi(Rules.exhaustion(ch) + delta, 0, 6)
	var parts: Array = []
	for p in str(ch.conditions).split(","):
		var t := p.strip_edges()
		if t != "" and not t.to_lower().begins_with("indebolimento"):
			parts.append(t)
	if lvl > 0:
		parts.append("Indebolimento %d" % lvl)
	ch.conditions = ", ".join(parts).left(200)
	if lvl >= 6 and delta > 0:
		ch.hp = 0
		ch.death_ko = 3
		notice.emit("%s muore per l'indebolimento (6° livello)" % ch.name)
		chronicle_add("sconfitta", "%s muore sfinito (indebolimento al 6° livello)" % ch.name)
	elif delta > 0:
		notice.emit("%s: indebolimento %d (-%d ai tiri di d20)" % [ch.name, lvl, 2 * lvl])
	touch()


## Short rest: the character spends one hit die (die + Constitution modifier).
## Returns a short description, or "" when none is left or nothing to heal.
func spend_hit_die(id: String) -> String:
	var ch := find_entity(id)
	if ch.is_empty() or not is_pc(id) or int(ch.hp) <= 0:
		return ""
	var used := int(ch.get("hd_used", 0))
	if used >= int(ch.get("level", 1)) or int(ch.hp) >= int(ch.hp_max):
		return ""
	var die := Rules.hit_die(str(ch.get("cls", "")))
	var v := rng.randi_range(1, die)
	var m := Rules.mod(ch.get("ab", {}).get("COS", 10))
	var heal := maxi(0, v + m)
	ch.hd_used = used + 1
	add_roll({"who": ch.name, "who_id": id, "who_type": "pc", "kind": "Dado vita",
		"dice": [{"s": die, "v": v, "drop": false}], "mod": m, "adv": "none", "reason": "Riposo breve",
		"secret": false, "formula": "1d%d%+d" % [die, m]}, false)
	change_hp(id, heal)
	return "%s spende un dado vita: +%d PF (%d/%d dadi vita usati)" % [ch.name, heal, used + 1, int(ch.get("level", 1))]


func toggle_condition(id: String, cond: String) -> void:
	if cond == "Indebolimento":
		exhaustion_add(id, 1)
		return
	var ch := find_entity(id)
	if ch.is_empty() or not ch.has("conditions"):
		return
	var parts: Array = []
	var had := false
	for p in str(ch.conditions).split(","):
		var t := p.strip_edges()
		if t == "":
			continue
		if t.to_lower() == cond.to_lower():
			had = true
		else:
			parts.append(t)
	if not had:
		parts.append(cond)
		# an incapacitating condition ends concentration (PHB)
		if INCAPACITATING.has(cond) and str(ch.get("concentration", "")) != "":
			notice.emit("%s perde la concentrazione su %s (%s)" % [ch.name, ch.concentration, cond.to_lower()])
			ch.concentration = ""
	ch.conditions = ", ".join(parts).left(200)
	touch()


## Turns a condition on or off whatever its state was.
func set_condition(id: String, cond: String, on: bool) -> void:
	var ch := find_entity(id)
	if ch.is_empty() or not ch.has("conditions"):
		return
	var has := false
	for p in str(ch.conditions).split(","):
		if p.strip_edges().to_lower() == cond.to_lower():
			has = true
	if has != on:
		toggle_condition(id, cond)


func set_death(id: String, ok: int, ko: int) -> void:
	var ch := find_entity(id)
	if ch.is_empty():
		return
	ch.death_ok = clampi(ok, 0, 3)
	ch.death_ko = clampi(ko, 0, 3)
	touch()


func status_of(e: Dictionary) -> String:
	return Rules.status_text(e.get("hp", 0), e.get("hp_max", 1))


# --------------------------------------------------------------- initiative
func ini() -> Dictionary:
	return data.initiative


func entity_init_mod(e: Dictionary) -> int:
	if is_pc(str(e.id)):
		return Rules.init_mod(e)
	return int(e.get("init_mod", 0))


func _sync_combatant_mod(id: String) -> void:
	var e := find_entity(id)
	for c in ini().combatants:
		if c.ref == id:
			c.mod = entity_init_mod(e)
			c.name = e.name


func in_combat(id: String) -> bool:
	for c in ini().combatants:
		if c.ref == id:
			return true
	return false


func combat_start(refs: Array) -> void:
	data.initiative = {"active": true, "round": 1, "current": "", "combatants": [], "defeated": []}
	for r in refs:
		_combat_add(str(r))
	sort_combatants()
	var names: Array = []
	for c in ini().combatants:
		var e := find_entity(c.ref)
		if c.type == "pc" or bool(e.get("revealed", false)):
			names.append(c.name)
	chronicle_add("combattimento", "Inizia un combattimento: %s" % ", ".join(names))
	touch()


func combat_add(ref: String) -> void:
	if not ini().active:
		ini().active = true
	_combat_add(ref)
	sort_combatants()
	touch()


func _combat_add(ref: String) -> void:
	if in_combat(ref):
		return
	var e := find_entity(ref)
	if e.is_empty():
		return
	ini().combatants.append({
		"id": new_id("x"), "ref": ref, "type": "pc" if is_pc(ref) else "monster",
		"name": e.name, "score": Rules.NO_SCORE, "mod": entity_init_mod(e), "tie": rng.randi(),
	})


func sort_combatants() -> void:
	ini().combatants.sort_custom(_cmp_combatants)


## Highest initiative first. Ties are broken at random (table choice): each
## combatant draws a random number when it joins, so the order stays put.
func _cmp_combatants(a, b) -> bool:
	if int(a.score) != int(b.score):
		return int(a.score) > int(b.score)
	if int(a.get("tie", 0)) != int(b.get("tie", 0)):
		return int(a.get("tie", 0)) > int(b.get("tie", 0))
	return str(a.name) < str(b.name)


func set_score(cid: String, score: int) -> void:
	for c in ini().combatants:
		if c.id == cid:
			c.score = score
	sort_combatants()
	touch()


func set_score_for_ref(ref: String, score: int) -> void:
	for c in ini().combatants:
		if c.ref == ref:
			c.score = score
	sort_combatants()
	touch()


func roll_d20() -> int:
	return rng.randi_range(1, 20)


## Automatic initiative for every monster in combat (secret rolls).
func roll_monster_initiative(only_missing := true) -> void:
	for c in ini().combatants:
		if c.type != "monster":
			continue
		if only_missing and int(c.score) != Rules.NO_SCORE:
			continue
		var d := roll_d20()
		var e := find_entity(c.ref)
		var entry := add_roll({
			"who": e.get("name", c.name), "who_id": c.ref, "who_type": "monster", "kind": "Iniziativa",
			"dice": [{"s": 20, "v": d, "drop": false}], "mod": int(c.mod), "adv": "none",
			"reason": "Iniziativa", "secret": true, "formula": "1d20%s" % _mod_suffix(int(c.mod)),
		}, false)
		c.score = int(entry.total)
	sort_combatants()
	touch()


func request_player_initiative() -> void:
	var ids: Array = []
	for c in ini().combatants:
		if c.type == "pc" and int(c.score) == Rules.NO_SCORE:
			ids.append(c.ref)
	if ids.size() > 0:
		make_request(ids, "init", "", -1, "Inizia il combattimento!")


func current_combatant() -> Dictionary:
	for c in ini().combatants:
		if c.id == ini().current:
			return c
	return {}


func next_turn() -> void:
	var list: Array = ini().combatants
	if list.is_empty():
		return
	var idx := -1
	for i in list.size():
		if list[i].id == ini().current:
			idx = i
	if idx < 0:
		ini().current = list[0].id
	else:
		idx += 1
		if idx >= list.size():
			idx = 0
			ini().round = int(ini().round) + 1
		ini().current = list[idx].id
	# a new turn: movement, Scatto and Disimpegno start again; the creature
	# whose turn it is gets its reaction back
	ini()["moved"] = {}
	ini()["dash"] = {}
	ini()["disengage"] = {}
	var reacted: Dictionary = ini().get("reacted", {})
	reacted.erase(str(current_combatant().get("ref", "")))
	ini()["reacted"] = reacted
	touch()


func prev_turn() -> void:
	var list: Array = ini().combatants
	if list.is_empty():
		return
	var idx := 0
	for i in list.size():
		if list[i].id == ini().current:
			idx = i
	idx -= 1
	if idx < 0:
		if int(ini().round) > 1:
			ini().round = int(ini().round) - 1
			idx = list.size() - 1
		else:
			idx = 0
	ini().current = list[idx].id
	touch()


func combat_remove(cid: String) -> void:
	var list: Array = ini().combatants
	if ini().current == cid and list.size() > 1:
		for i in list.size():
			if list[i].id == cid:
				ini().current = list[(i + 1) % list.size()].id
				break
	ini().combatants = list.filter(func(c): return c.id != cid)
	if ini().combatants.is_empty():
		ini().current = ""
	touch()


func _remove_ref_from_combat(ref: String) -> void:
	for c in ini().combatants.duplicate():
		if c.ref == ref:
			combat_remove(c.id)


func combat_end() -> void:
	if ini().active:
		var defeated: Array = ini().get("defeated", [])
		var names: Array = []
		var xp := 0
		for id in defeated:
			var m := find_entity(str(id))
			if not m.is_empty():
				names.append(str(m.name))
				xp += int(m.get("xp", 0))
		var txt := "Il combattimento finisce dopo %d round" % int(ini().round)
		if names.size() > 0:
			txt += ". Sconfitti: %s" % ", ".join(names)
		chronicle_add("combattimento", txt)
		if xp > 0:
			award_xp(xp, "combattimento")
	data.initiative = {"active": false, "round": 1, "current": "", "combatants": [], "defeated": []}
	for r in data.requests.duplicate():
		if r.type == "init":
			data.requests.erase(r)
	touch()


# ------------------------------------------------------------------- quests
func add_quest(title: String, desc: String, hidden: bool) -> Dictionary:
	var q := {"id": new_id("q"), "title": title.strip_edges().left(80) if title.strip_edges() != "" else "Nuova missione",
		"desc": desc.left(2000), "hidden": hidden, "status": "attiva", "checks": []}
	data.quests.append(q)
	chronicle_add("missione", "Nuova missione: %s" % q.title, not hidden)
	touch()
	return q


func find_quest(qid: String) -> Dictionary:
	for q in data.quests:
		if q.id == qid:
			return q
	return {}


func find_check(qid: String, cid: String) -> Dictionary:
	var q := find_quest(qid)
	for c in q.get("checks", []):
		if c.id == cid:
			return c
	return {}


func delete_quest(qid: String) -> void:
	data.quests = data.quests.filter(func(q): return q.id != qid)
	touch()


func add_check(qid: String, kind: String, param: String, dc: int, hidden: bool, target: String) -> void:
	var q := find_quest(qid)
	if q.is_empty():
		return
	q.checks.append({"id": new_id("k"), "kind": kind, "param": param, "dc": dc, "hidden": hidden,
		"target": target, "result": "", "attempts": []})
	touch()


func delete_check(qid: String, cid: String) -> void:
	var q := find_quest(qid)
	if q.is_empty():
		return
	q.checks = q.checks.filter(func(c): return c.id != cid)
	touch()


func request_check(qid: String, cid: String) -> void:
	var c := find_check(qid, cid)
	if c.is_empty():
		return
	var ids: Array = []
	if str(c.target) != "":
		ids.append(c.target)
	else:
		for ch in characters():
			ids.append(ch.id)
	if ids.is_empty():
		return
	var q := find_quest(qid)
	make_request(ids, c.kind, c.param, int(c.dc), "" if bool(q.hidden) or bool(c.hidden) else str(q.title), {"quest": qid, "check": cid})


# ----------------------------------------------------------------- requests
func make_request(char_ids: Array, type: String, param: String, dc: int, reason: String, link := {}) -> Dictionary:
	var r := {"id": new_id("r"), "chars": char_ids.duplicate(), "type": type, "param": param, "dc": dc,
		"reason": reason.left(120), "quest": link.get("quest", ""), "check": link.get("check", ""),
		"done": [], "time": time_str()}
	data.requests.append(r)
	request_added.emit(r)
	touch()
	return r


func find_request(rid: String) -> Dictionary:
	for r in data.requests:
		if r.id == rid:
			return r
	return {}


func cancel_request(rid: String) -> void:
	data.requests = data.requests.filter(func(r): return r.id != rid)
	touch()


func pending_for(char_id: String) -> Array:
	var out: Array = []
	for r in data.requests:
		if r.chars.has(char_id) and not r.done.has(char_id):
			out.append(r)
	return out


func request_label(r: Dictionary) -> String:
	return Rules.check_label(str(r.type), str(r.param))


# -------------------------------------------------------------------- rolls
func _mod_suffix(m: int) -> String:
	if m == 0:
		return ""
	return " + %d" % m if m > 0 else " - %d" % -m


## Adds a roll to the log. info: who, who_id, who_type, kind, dice [{s,v,drop}],
## mod, adv, reason, secret, formula, optional dc, check_hidden, manual
## (true = values typed in from real dice instead of the app's dice).
func add_roll(info: Dictionary, emit := true) -> Dictionary:
	var dice: Array = []
	var total := int(info.get("mod", 0))
	var kept20: Array = []
	for d in info.get("dice", []):
		var s := int(d.get("s", 20))
		var v := clampi(int(d.get("v", 1)), 1, s)
		var drop := bool(d.get("drop", false))
		dice.append({"s": s, "v": v, "drop": drop})
		if not drop:
			total += v
			if s == 20:
				kept20.append(v)
	var nat := 0
	if kept20.size() == 1 and (kept20[0] == 20 or kept20[0] == 1):
		nat = kept20[0]
	var dc := int(info.get("dc", -1))
	var outcome := ""
	if dc >= 0:
		outcome = "success" if total >= dc else "fail"
	var entry := {
		"id": new_id("l"), "time": time_str(), "date": Time.get_date_string_from_system(),
		"session": int(data.get("session", 1)),
		"who": str(info.get("who", "Master")), "who_id": str(info.get("who_id", "")),
		"who_type": str(info.get("who_type", "master")), "kind": str(info.get("kind", "Libero")),
		"formula": str(info.get("formula", "")), "dice": dice, "mod": int(info.get("mod", 0)),
		"total": total, "reason": str(info.get("reason", "")).left(120), "secret": bool(info.get("secret", false)),
		"adv": str(info.get("adv", "none")), "nat": nat, "dc": dc, "outcome": outcome,
		"check_hidden": bool(info.get("check_hidden", false)),
		"manual": bool(info.get("manual", false)),
	}
	data.log.append(entry)
	if nat == 20 and entry.who_type == "pc" and not entry.secret and str(entry.kind) in INSPIRING_KINDS:
		entry.inspired = _grant_inspiration(find_entity(entry.who_id))
	if nat != 0 and not entry.secret and str(entry.kind) != "Danni":
		chronicle_add("tiro", "%s di %s%s" % ["20 naturale" if nat == 20 else "1 naturale", entry.who, (" (%s)" % entry.reason) if entry.reason != "" else ""])
	if data.log.size() > LOG_LIMIT:
		data.log = data.log.slice(data.log.size() - LOG_LIMIT)
	roll_added.emit(entry)
	if emit:
		touch()
	return entry


## d20 tests whose natural 20 gives inspiration (house rule of this table:
## attacks, ability checks and saving throws; not initiative).
const INSPIRING_KINDS := ["Attacco", "Prova", "Tiro salvezza"]


## Gives inspiration to a character who has none (one at a time, as in the
## Player's Handbook). True when it was given.
func _grant_inspiration(ch: Dictionary) -> bool:
	if ch.is_empty() or not is_pc(str(ch.get("id", ""))) or bool(ch.get("inspiration", false)):
		return false
	ch.inspiration = true
	chronicle_add("personaggio", "%s guadagna ispirazione con un 20 naturale" % ch.name)
	return true


## Inspiration on or off, from the master's sheet.
func set_inspiration(id: String, on: bool) -> void:
	var ch := find_entity(id)
	if ch.is_empty() or not is_pc(id):
		return
	ch.inspiration = on
	touch()


## Spends a character's inspiration (advantage on one d20 roll). False when
## the character has none.
func use_inspiration(id: String) -> bool:
	var ch := find_entity(id)
	if ch.is_empty() or not is_pc(id) or not bool(ch.get("inspiration", false)):
		return false
	ch.inspiration = false
	touch()
	return true


## Master roll from the 3D tray.
func master_roll(who_id: String, kind: String, dice: Array, mod: int, adv: String, reason: String, secret: bool, formula: String, manual := false) -> Dictionary:
	var e := find_entity(who_id)
	var who_type := "master"
	var who := "Master"
	if not e.is_empty():
		who = str(e.name)
		who_type = "pc" if is_pc(who_id) else "monster"
	var entry := add_roll({"who": who, "who_id": who_id, "who_type": who_type, "kind": kind, "dice": dice,
		"mod": mod, "adv": adv, "reason": reason, "secret": secret, "formula": formula, "manual": manual}, false)
	if kind == "Iniziativa" and who_id != "" and in_combat(who_id):
		set_score_for_ref(who_id, int(entry.total))
	touch()
	return entry


## A roll arriving from a player's phone.
func player_roll(char_id: String, msg: Dictionary) -> Dictionary:
	var ch := find_entity(char_id)
	if ch.is_empty():
		return {}
	var dice: Array = []
	var raw = msg.get("dice", [])
	if not (raw is Array):
		return {}
	for d in raw:
		if not (d is Dictionary) or dice.size() >= 60:
			continue
		var s := int(d.get("s", 0))
		if not Rules.DIE_SIDES.has(s):
			continue
		dice.append({"s": s, "v": clampi(int(d.get("v", 1)), 1, s), "drop": bool(d.get("drop", false))})
	if dice.is_empty():
		return {}
	var kind := str(msg.get("kind", "Libero"))
	if not Rules.KINDS.has(kind):
		kind = "Libero"
	var info := {"who": ch.name, "who_id": char_id, "who_type": "pc", "kind": kind, "dice": dice,
		"mod": clampi(int(msg.get("mod", 0)), -50, 50), "adv": str(msg.get("adv", "none")).left(8),
		"reason": str(msg.get("reason", "")).left(120), "secret": false,
		"formula": str(msg.get("formula", "")).left(80), "manual": bool(msg.get("manual", false))}
	# advantage paid with inspiration (the phone rolled 2d20)
	if bool(msg.get("insp", false)) and info.adv == "adv" and use_inspiration(char_id):
		info.reason = (str(info.reason) + " (ispirazione)").strip_edges()
	var req := find_request(str(msg.get("request_id", "")))
	var check := {}
	if not req.is_empty() and req.chars.has(char_id) and not req.done.has(char_id):
		info.dc = int(req.dc)
		if str(req.check) != "":
			check = find_check(str(req.quest), str(req.check))
			var q := find_quest(str(req.quest))
			info.check_hidden = bool(check.get("hidden", false)) or bool(q.get("hidden", false))
		if info.reason == "":
			info.reason = request_label(req)
	else:
		req = {}
	var entry := add_roll(info, false)
	if not req.is_empty():
		req.done.append(char_id)
		if req.type == "init":
			set_score_for_ref(char_id, int(entry.total))
		if not check.is_empty():
			check.attempts.append({"who": ch.name, "total": entry.total, "ok": entry.outcome == "success"})
			if entry.outcome == "success":
				if check.result != "success":
					chronicle_add("missione", "%s supera la prova di %s (CD %d)" % [ch.name, Rules.skill_name(str(check.param)) if str(check.param) != "" else str(check.kind), int(check.dc)], not bool(check.get("hidden", false)))
				check.result = "success"
			elif check.result == "":
				var all_done := true
				for cid in req.chars:
					if not req.done.has(cid):
						all_done = false
				if all_done:
					check.result = "fail"
		var all := true
		for cid in req.chars:
			if not req.done.has(cid):
				all = false
		if all:
			data.requests.erase(req)
	touch()
	return entry


# --------------------------------------------------------------- visibility
## What everyone may see about a roll. Secret rolls become a placeholder.
func public_entry(e: Dictionary) -> Dictionary:
	if bool(e.secret):
		return {"id": e.id, "time": e.time, "secret": true, "who": "Master", "text": "Il master ha tirato in segreto"}
	var who := str(e.who)
	var mod_hidden := false
	if e.who_type == "monster":
		mod_hidden = true
		var m := find_entity(str(e.who_id))
		if m.is_empty() or not bool(m.get("revealed", false)):
			who = "Master"
	var p := {"id": e.id, "time": e.time, "who": who, "who_id": e.who_id if e.who_type == "pc" else "",
		"kind": e.kind, "dice": e.dice, "total": e.total, "reason": e.reason, "adv": e.adv, "nat": e.nat,
		"secret": false, "manual": bool(e.get("manual", false))}
	if mod_hidden:
		p.formula = _dice_formula(e.dice)
		p.mod_hidden = true
	else:
		p.formula = e.formula
		p.mod = e.mod
	if str(e.outcome) != "" and not bool(e.get("check_hidden", false)):
		p.outcome = e.outcome
	return p


func _dice_formula(dice: Array) -> String:
	var counts := {}
	for d in dice:
		if bool(d.drop):
			continue
		counts[int(d.s)] = int(counts.get(int(d.s), 0)) + 1
	var parts: Array = []
	for s in Rules.DIE_SIDES:
		if counts.has(s):
			parts.append("%dd%d" % [counts[s], s])
	return " + ".join(parts)


func _public_log() -> Array:
	var out: Array = []
	var lg: Array = data.get("log", [])
	var start := maxi(0, lg.size() - VIEW_LOG)
	for i in range(lg.size() - 1, start - 1, -1):
		out.append(public_entry(lg[i]))
	return out


func _public_init(char_id: String) -> Dictionary:
	var order: Array = []
	var hidden_turn := false
	var cur := str(ini().current)
	for c in ini().combatants:
		var e := find_entity(c.ref)
		if e.is_empty():
			continue
		if c.type == "monster" and not bool(e.get("revealed", false)):
			if c.id == cur:
				hidden_turn = true
			continue
		var item := {"name": e.name, "kind": c.type, "current": c.id == cur, "me": c.ref == char_id,
			"status": status_of(e), "img": Art.key_for(e, c.type), "cond": str(e.get("conditions", ""))}
		if c.ref == char_id and int(c.score) != Rules.NO_SCORE:
			item.score = c.score
		order.append(item)
	return {"active": bool(ini().active), "round": int(ini().round), "order": order, "hidden_turn": hidden_turn}


func _public_quests() -> Array:
	var out: Array = []
	for q in data.get("quests", []):
		if bool(q.hidden):
			continue
		var checks: Array = []
		for c in q.checks:
			if bool(c.hidden):
				continue
			var target := ""
			if str(c.target) != "":
				target = str(find_entity(str(c.target)).get("name", ""))
			checks.append({"label": Rules.check_label(str(c.kind), str(c.param)), "result": c.result, "target": target})
		out.append({"id": q.id, "title": q.title, "desc": q.desc, "status": q.status, "checks": checks})
	return out


func _party() -> Array:
	var out: Array = []
	for c in characters():
		out.append({"id": c.id, "name": c.name, "cls": c.cls, "race": c.race, "level": c.level,
			"status": status_of(c), "online": online_chars.has(c.id), "img": Art.key_for(c, "pc")})
	return out


func _public_monsters() -> Array:
	var out: Array = []
	for m in monsters():
		if bool(m.revealed):
			out.append({"id": m.id, "name": m.name, "kind": m.kind, "status": status_of(m), "conditions": str(m.get("conditions", ""))})
	return out


func player_view(char_id: String) -> Dictionary:
	var me := find_entity(char_id) if is_pc(char_id) else {}
	var reqs: Array = []
	if not me.is_empty():
		for r in pending_for(char_id):
			reqs.append({"id": r.id, "type": r.type, "param": r.param, "label": request_label(r), "reason": r.reason})
	return {
		"campaign": data.get("name", ""), "session": int(data.get("session", 1)),
		"me": _me_view(me) if not me.is_empty() else null,
		"party": _party(), "monsters": _public_monsters(), "init": _public_init(char_id),
		"quests": _public_quests(), "log": _public_log(), "requests": reqs,
		"chronicle": _public_chronicle(), "xp_total": int(data.get("xp_total", 0)),
		"map": _public_map(char_id),
		"me_img": Art.key_for(me, "pc") if not me.is_empty() else "",
		"turn": Actions.phone_turn(self, char_id) if not me.is_empty() else {},
		"ai": {"feed": ai_feed.slice(maxi(0, ai_feed.size() - 8)), "busy": ai_busy, "reading": ai_reading, "lobby": ai_lobby,
			"secrets": ai_secrets.get(char_id, [])} if ai_master else null,
	}


func _me_view(me: Dictionary) -> Dictionary:
	var v := me.duplicate(true)
	v.resources = Rules.resources(me)
	return v


func screen_view() -> Dictionary:
	return {
		"map": _public_map(""),
		"campaign": data.get("name", ""), "session": int(data.get("session", 1)),
		"party": _party(), "monsters": _public_monsters(), "init": _public_init(""),
		"quests": _public_quests(), "log": _public_log(),
		"chronicle": _public_chronicle().slice(-6),
	}


func char_choices(token: String) -> Array:
	var out: Array = []
	for c in characters():
		var taken := false
		for t in char_claimed_by(c.id):
			if t != token and online_chars.has(c.id):
				taken = true
		out.append({"id": c.id, "name": c.name, "cls": c.cls, "level": c.level, "player": c.player, "taken": taken,
			"img": Art.key_for(c, "pc")})
	return out


# ---------------------------------------------------------------- battle maps
func find_map(id: String) -> Dictionary:
	for mp in data.get("maps", []):
		if mp.id == id:
			return mp
	return {}


static func map_path(file: String) -> String:
	return "%s/%s.jpg" % [MAP_DIR, file]


## Number of whole squares across and down.
static func map_size(mp: Dictionary) -> Vector2i:
	var c := maxf(4.0, float(mp.cell))
	return Vector2i(maxi(1, int((float(mp.w) - fposmod(float(mp.ox), c)) / c)),
		maxi(1, int((float(mp.h) - fposmod(float(mp.oy), c)) / c)))


## Saves the picture and adds the map. The grid is detected when possible,
## otherwise 20 squares across is assumed (the master can fix it).
func add_map(map_name: String, img: Image) -> Dictionary:
	if img == null or img.is_empty():
		return {}
	img = img.duplicate()
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	var big := maxi(img.get_width(), img.get_height())
	if big > MAP_MAX_SIDE:
		var f := float(MAP_MAX_SIDE) / big
		img.resize(int(img.get_width() * f), int(img.get_height() * f), Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(MAP_DIR)
	var file := "map_%d_%05d" % [int(Time.get_unix_time_from_system()), rng.randi() % 100000]
	if img.save_jpg(map_path(file), 0.9) != OK:
		return {}
	var g := MapGrid.detect(img)
	var mp := {"id": new_id("map"), "name": map_name.strip_edges().left(60), "file": file,
		"w": img.get_width(), "h": img.get_height(),
		"cell": float(g.get("cell", img.get_width() / 20.0)), "ox": float(g.get("ox", 0.0)), "oy": float(g.get("oy", 0.0)),
		"grid": true, "tokens": [], "auto_grid": not g.is_empty()}
	if mp.name == "":
		mp.name = "Mappa"
	data.maps.append(mp)
	touch()
	return mp


func update_map(id: String, fields: Dictionary) -> void:
	var mp := find_map(id)
	if mp.is_empty():
		return
	if fields.has("name"):
		mp.name = str(fields.name).strip_edges().left(60)
	for k in ["cell", "ox", "oy"]:
		if fields.has(k):
			mp[k] = float(fields[k])
	mp.cell = clampf(mp.cell, 4.0, float(maxi(int(mp.w), int(mp.h))))
	if fields.has("grid"):
		mp.grid = bool(fields.grid)
	# squares may have changed: keep every piece on the board
	var n := map_size(mp)
	for t in mp.tokens:
		t.x = clampi(int(t.x), 0, n.x - 1)
		t.y = clampi(int(t.y), 0, n.y - 1)
	touch()


func delete_map(id: String) -> void:
	var mp := find_map(id)
	if mp.is_empty():
		return
	data.maps = data.maps.filter(func(m): return m.id != id)
	if data.map_active == id:
		data.map_active = ""
	# the picture may be shared with a copy of this campaign
	var used := false
	for c in list_campaigns():
		if c.id != data.id and FileAccess.get_file_as_string(campaign_path(c.id)).contains(str(mp.file)):
			used = true
	if not used:
		DirAccess.remove_absolute(map_path(mp.file))
	touch()


func set_map_active(id: String) -> void:
	data.map_active = id if not find_map(id).is_empty() else ""
	touch()


func token_at(mp: Dictionary, x: int, y: int) -> Dictionary:
	for t in mp.tokens:
		if int(t.x) == x and int(t.y) == y and not find_entity(t.ref).is_empty():
			return t
	return {}


## Puts (or moves) the piece of a character/monster on square x, y.
## Like checkers: one piece per square. Returns false if it can't go there.
func place_token(map_id: String, ref: String, x: int, y: int) -> bool:
	var mp := find_map(map_id)
	if mp.is_empty() or find_entity(ref).is_empty():
		return false
	var n := map_size(mp)
	if x < 0 or y < 0 or x >= n.x or y >= n.y:
		return false
	var other := token_at(mp, x, y)
	if not other.is_empty() and other.ref != ref:
		return false
	for t in mp.tokens:
		if t.ref == ref:
			t.x = x
			t.y = y
			touch()
			return true
	mp.tokens.append({"ref": ref, "x": x, "y": y})
	touch()
	return true


## First free square nearest to (x, y), or Vector2i(-1, -1) if the board is full.
func free_square(map_id: String, x: int, y: int) -> Vector2i:
	var mp := find_map(map_id)
	if mp.is_empty():
		return Vector2i(-1, -1)
	var n := map_size(mp)
	x = clampi(x, 0, n.x - 1)
	y = clampi(y, 0, n.y - 1)
	for r in range(0, maxi(n.x, n.y)):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var p := Vector2i(x + dx, y + dy)
				if p.x >= 0 and p.y >= 0 and p.x < n.x and p.y < n.y and token_at(mp, p.x, p.y).is_empty():
					return p
	return Vector2i(-1, -1)


func remove_token(map_id: String, ref: String) -> void:
	var mp := find_map(map_id)
	if mp.is_empty():
		return
	mp.tokens = mp.tokens.filter(func(t): return t.ref != ref)
	touch()


## Square of a piece on the map in play, or (-1, -1).
func map_pos(ref: String) -> Vector2i:
	var mp := find_map(str(data.get("map_active", "")))
	if not mp.is_empty():
		for t in mp.tokens:
			if t.ref == ref:
				return Vector2i(int(t.x), int(t.y))
	return Vector2i(-1, -1)


## Distance in metres between two pieces on the map in play (PHB 2024: every
## square, diagonals too, is 1.5 m), or -1 when one is not on the map.
func map_dist_m(a: String, b: String) -> float:
	var pa := map_pos(a)
	var pb := map_pos(b)
	if pa.x < 0 or pb.x < 0:
		return -1.0
	return 1.5 * maxi(absi(pa.x - pb.x), absi(pa.y - pb.y))


## Squares a creature may move in one turn: its speed, 0 when grappled,
## restrained or incapacitated, 1.5 m less per exhaustion level (PHB 2024).
func speed_squares(e: Dictionary) -> int:
	for c in ["Afferrato", "Trattenuto"] + INCAPACITATING:
		if Actions.has_cond(e, c):
			return 0
	return maxi(0, int(float(e.get("speed", 9)) / 1.5) - Rules.exhaustion(e))


static func _sq_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


## Difficult terrain (PHB): every square of it costs one extra square of
## movement. Kept per map as "x,y" keys.
static func is_difficult(mp: Dictionary, x: int, y: int) -> bool:
	return mp.get("difficult", []).has(_sq_key(x, y))


func toggle_difficult(map_id: String, x: int, y: int) -> void:
	var mp := find_map(map_id)
	if mp.is_empty():
		return
	var n := map_size(mp)
	if x < 0 or y < 0 or x >= n.x or y >= n.y:
		return
	var l: Array = mp.get("difficult", [])
	var k := _sq_key(x, y)
	if l.has(k):
		l.erase(k)
	else:
		l.append(k)
	mp["difficult"] = l
	touch()


## Movement cost in squares along the most direct route (a diagonal step
## costs like a straight one); difficult squares count double.
static func path_cost(mp: Dictionary, from: Vector2i, to: Vector2i) -> int:
	var p := from
	var cost := 0
	while p != to:
		p += Vector2i(signi(to.x - p.x), signi(to.y - p.y))
		cost += 2 if is_difficult(mp, p.x, p.y) else 1
	return cost


## Per-turn flags of the fight: "dash", "disengage", "reacted".
func turn_flag(key: String, ref: String) -> bool:
	return bool(ini().get(key, {}).get(ref, false))


func set_turn_flag(key: String, ref: String) -> void:
	var d: Dictionary = ini().get(key, {})
	d[ref] = true
	ini()[key] = d


## Squares of movement left this turn (Scatto doubles the speed).
func move_left(ref: String) -> int:
	var allow := speed_squares(find_entity(ref)) * (2 if turn_flag("dash", ref) else 1)
	return maxi(0, allow - int(ini().get("moved", {}).get(ref, 0)))


func _spend_move(ref: String, sq: int) -> void:
	var moved: Dictionary = ini().get("moved", {})
	moved[ref] = int(moved.get(ref, 0)) + sq
	ini()["moved"] = moved


func _fighting(ref: String) -> bool:
	if not bool(ini().active):
		return false
	for c in ini().combatants:
		if str(c.ref) == ref:
			return true
	return false


## A player moves their own piece on the map they are shown. "" = done.
## In a fight: only on their own turn and as far as their movement allows
## (difficult terrain and crawling while prone cost double), and leaving an
## enemy's reach provokes its attack of opportunity.
func player_move(char_id: String, x: int, y: int) -> String:
	var mp := find_map(str(data.get("map_active", "")))
	if mp.is_empty():
		return "Nessuna mappa in gioco"
	var from := map_pos(char_id)
	if from.x < 0:
		return "La tua pedina non è sulla mappa"
	var me := find_entity(char_id)
	var prone := Actions.has_cond(me, "Prono")
	var cost := path_cost(mp, from, Vector2i(x, y)) * (2 if prone else 1)
	var fighting := _fighting(char_id)
	if fighting:
		if str(current_combatant().get("ref", "")) != char_id:
			return "Non è il tuo turno: aspetta per muoverti"
		var left := move_left(char_id)
		if cost > left:
			return "Troppo lontano: ti restano %s m di movimento%s" % [_m(1.5 * left), " (da prono strisci: rialzati prima)" if prone else ""]
	if not place_token(mp.id, char_id, x, y):
		return "Casella occupata"
	if fighting:
		_spend_move(char_id, cost)
		touch()
		_opportunity_attacks(char_id, from)
	return ""


## First melee attack of a creature: a character's weapon ({} when none), a
## monster's attack from its notes or a plain one sized on its hit points.
func melee_action(ref: String) -> Dictionary:
	for a in Actions.list_for(self, ref):
		if str(a.get("mode", "")) == "attack" and not bool(a.get("ranged", false)) and str(a.get("group", "")) != "Personalizzata":
			return a
	return {} if is_pc(ref) else MonsterAI.fallback_attack(find_entity(ref))


## Reach in squares: 2 with a reach weapon, otherwise 1.
func reach_squares(ref: String) -> int:
	var a := melee_action(ref)
	return 2 if not a.is_empty() and Actions.is_reach(a) else 1


## PHB: a character leaving the reach of a monster that can still react takes
## one attack from it, unless they took the Disimpegno action this turn.
func _opportunity_attacks(ref: String, from: Vector2i) -> void:
	if turn_flag("disengage", ref) or not is_pc(ref):
		return
	var mp := find_map(str(data.get("map_active", "")))
	var to := map_pos(ref)
	for tok in mp.get("tokens", []).duplicate():
		var oref := str(tok.ref)
		var o := find_entity(oref)
		if o.is_empty() or is_pc(oref) or int(o.get("hp", 0)) <= 0 or not _fighting(oref) or turn_flag("reacted", oref):
			continue
		var free := true
		for c in INCAPACITATING:
			if Actions.has_cond(o, c):
				free = false
		if not free:
			continue
		var r := reach_squares(oref)
		var p := Vector2i(int(tok.x), int(tok.y))
		if maxi(absi(p.x - from.x), absi(p.y - from.y)) > r or maxi(absi(p.x - to.x), absi(p.y - to.y)) <= r:
			continue
		var a := melee_action(oref)
		if a.is_empty():
			continue
		a = a.duplicate()
		a["times"] = 1
		set_turn_flag("reacted", oref)
		var res: Dictionary = Actions.resolve(self, oref, a, [ref], {"adv": "auto"})
		if bool(res.get("ok", false)):
			map_event.emit("Attacco di opportunità",
				["%s si allontana da %s: attacco di opportunità." % [find_entity(ref).get("name", "?"), o.name]] + Actions.public_lines(self, res.lines))
		if int(find_entity(ref).get("hp", 0)) <= 0:
			break


## Movement actions of a turn (PHB): Scatto (Dash) doubles this turn's
## movement, Disimpegno (Disengage) avoids attacks of opportunity, Rialzati
## (stand up from prone) costs half the speed. Returns {ok, error, line}.
func maneuver(ref: String, kind: String) -> Dictionary:
	var e := find_entity(ref)
	if e.is_empty():
		return {"ok": false, "error": "Personaggio non trovato"}
	var fighting := _fighting(ref)
	if fighting and str(current_combatant().get("ref", "")) != ref:
		return {"ok": false, "error": "Non è il tuo turno"}
	match kind:
		"dash", "disengage":
			if not fighting:
				return {"ok": false, "error": "Serve solo in combattimento"}
			if turn_flag(kind, ref):
				return {"ok": false, "error": "Già fatto in questo turno"}
			set_turn_flag(kind, ref)
			touch()
			if kind == "dash":
				return {"ok": true, "line": "%s usa l'azione Scatto: ora ha %s m di movimento." % [e.name, _m(1.5 * move_left(ref))]}
			return {"ok": true, "line": "%s usa l'azione Disimpegno: si allontana senza subire attacchi di opportunità." % e.name}
		"stand":
			if not Actions.has_cond(e, "Prono"):
				return {"ok": false, "error": "Non sei a terra"}
			if fighting:
				var cost := ceili(speed_squares(e) / 2.0)
				if speed_squares(e) == 0 or cost > move_left(ref):
					return {"ok": false, "error": "Non ti resta abbastanza movimento per rialzarti"}
				_spend_move(ref, cost)
			toggle_condition(ref, "Prono")
			return {"ok": true, "line": "%s si rialza (costa metà del movimento)." % e.name}
	return {"ok": false, "error": "Azione sconosciuta"}


## Moves a monster toward a target, one square at a time, until it is within
## `want` squares or its movement runs out. Difficult squares cost double;
## other pieces are walked around when a free square still gets it closer.
## Returns the squares of movement spent.
func monster_approach(ref: String, tid: String, want: int) -> int:
	var mp := find_map(str(data.get("map_active", "")))
	var p := map_pos(ref)
	var t := map_pos(tid)
	if mp.is_empty() or p.x < 0 or t.x < 0:
		return 0
	var left := move_left(ref) if _fighting(ref) else speed_squares(find_entity(ref))
	var n := map_size(mp)
	var spent := 0
	while maxi(absi(p.x - t.x), absi(p.y - t.y)) > want:
		var cur_d := maxi(absi(p.x - t.x), absi(p.y - t.y))
		var best := Vector2i(-1, -1)
		var best_s := INF
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var q := p + Vector2i(dx, dy)
				if q == p or q.x < 0 or q.y < 0 or q.x >= n.x or q.y >= n.y or not token_at(mp, q.x, q.y).is_empty():
					continue
				var d := maxi(absi(q.x - t.x), absi(q.y - t.y))
				var c := 2 if is_difficult(mp, q.x, q.y) else 1
				if d >= cur_d or c > left - spent:
					continue
				var score := d * 10.0 + Vector2(q - t).length() + (3.0 if c == 2 else 0.0)
				if score < best_s:
					best_s = score
					best = q
		if best.x < 0:
			break
		spent += 2 if is_difficult(mp, best.x, best.y) else 1
		p = best
	if spent > 0:
		place_token(mp.id, ref, p.x, p.y)
		if _fighting(ref):
			_spend_move(ref, spent)
		touch()
	return spent


## Master helper: the monster walks toward the nearest character standing.
func monster_auto_move(ref: String) -> String:
	var e := find_entity(ref)
	if e.is_empty() or is_pc(ref) or map_pos(ref).x < 0:
		return "Il mostro non è sulla mappa in gioco"
	var best := ""
	var bd := INF
	for c in characters():
		var d := map_dist_m(ref, str(c.id))
		if d >= 0 and int(c.hp) > 0 and d < bd:
			bd = d
			best = str(c.id)
	if best == "":
		return "Nessun personaggio sulla mappa"
	var spent := monster_approach(ref, best, reach_squares(ref))
	if spent == 0:
		return "%s non si sposta (già vicino o senza movimento)" % e.name
	return "%s si avvicina a %s (%s m)" % [e.name, find_entity(best).name, _m(1.5 * spent)]


static func _m(v: float) -> String:
	return ("%d" % int(v)) if is_equal_approx(v, roundf(v)) else ("%.1f" % v).replace(".", ",")


func _public_map(char_id: String) -> Variant:
	var mp := find_map(str(data.get("map_active", "")))
	if mp.is_empty():
		return null
	var cur_ref := ""
	if bool(ini().active):
		cur_ref = str(current_combatant().get("ref", ""))
	var toks: Array = []
	for t in mp.tokens:
		var e := find_entity(t.ref)
		if e.is_empty():
			continue
		var pc := is_pc(t.ref)
		if not pc and not bool(e.get("revealed", false)):
			continue
		toks.append({"ref": t.ref, "x": int(t.x), "y": int(t.y), "name": e.name, "kind": "pc" if pc else "monster",
			"img": Art.key_for(e, "pc" if pc else "monster"), "status": status_of(e),
			"me": t.ref == char_id, "cur": t.ref == cur_ref})
	var n := map_size(mp)
	return {"id": mp.id, "name": mp.name, "url": "/mappa/%s.jpg" % mp.file, "w": int(mp.w), "h": int(mp.h),
		"cell": float(mp.cell), "ox": fposmod(float(mp.ox), float(mp.cell)), "oy": fposmod(float(mp.oy), float(mp.cell)),
		"cols": n.x, "rows": n.y, "grid": bool(mp.grid), "tokens": toks, "difficult": mp.get("difficult", [])}


# ---------------------------------------------------------------- csv export
func log_csv() -> String:
	var lines: Array = ["Data;Ora;Sessione;Chi;Tipo;Formula;Dadi;Modificatore;Totale;Motivo;Visibilita;CD;Esito;Dadi veri"]
	for e in data.get("log", []):
		var dice: Array = []
		for d in e.dice:
			dice.append(("d%d:%d" % [d.s, d.v]) + (" (scartato)" if d.drop else ""))
		var esito := ""
		if e.outcome == "success":
			esito = "Riuscita"
		elif e.outcome == "fail":
			esito = "Fallita"
		var row: Array = [e.get("date", ""), e.time, e.get("session", 1), e.who, e.kind, e.formula, " ".join(dice),
			e.mod, e.total, e.reason, "Segreto" if e.secret else "Pubblico", "" if int(e.dc) < 0 else str(e.dc), esito,
			"Sì" if bool(e.get("manual", false)) else ""]
		var cells: Array = []
		for c in row:
			var s := str(c).replace("\"", "\"\"")
			cells.append("\"%s\"" % s)
		lines.append(";".join(cells))
	return "\n".join(lines) + "\n"
