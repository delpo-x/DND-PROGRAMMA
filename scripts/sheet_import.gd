class_name SheetImport
extends RefCounted
## Turns the text of a character-sheet PDF (see PdfText) into a character
## dictionary compatible with Rules.merge_sheet. Works on Italian and English
## sheets by looking for labels and the values next to / below them.
## Fillable sheets (for example the PDF export of online character builders)
## keep their values in form fields: those are read by field name and win
## over what the page text suggests.
## Everything is a best guess: the master reviews the sheet before saving.

const AB_LABELS := {
	"FOR": ["Forza", "Strength", "FOR", "STR"],
	"DES": ["Destrezza", "Dexterity", "DES", "DEX"],
	"COS": ["Costituzione", "Constitution", "COS", "CON"],
	"INT": ["Intelligenza", "Intelligence", "INT"],
	"SAG": ["Saggezza", "Wisdom", "SAG", "WIS"],
	"CAR": ["Carisma", "Charisma", "CAR", "CHA"],
}
const SKILL_ALIASES := {
	"acrobazia": ["Acrobazia", "Acrobatics"], "addestrare": ["Addestrare Animali", "Animal Handling"],
	"arcano": ["Arcano", "Arcana"], "atletica": ["Atletica", "Athletics"], "furtivita": ["Furtività", "Furtivita", "Stealth"],
	"indagare": ["Indagare", "Investigation"], "inganno": ["Inganno", "Deception"], "intimidire": ["Intimidire", "Intimidazione", "Intimidation"],
	"intrattenere": ["Intrattenere", "Performance"], "intuizione": ["Intuizione", "Insight"], "medicina": ["Medicina", "Medicine"],
	"natura": ["Natura", "Nature"], "percezione": ["Percezione", "Perception"], "persuasione": ["Persuasione", "Persuasion"],
	"rapidita": ["Rapidità di Mano", "Rapidita di Mano", "Sleight of Hand"], "religione": ["Religione", "Religion"],
	"sopravvivenza": ["Sopravvivenza", "Survival"], "storia": ["Storia", "History"],
}
const CLASSES := ["Barbaro", "Barbara", "Bardo", "Barda", "Chierico", "Chierica", "Druido", "Druida", "Guerriero", "Guerriera",
	"Ladro", "Ladra", "Mago", "Maga", "Monaco", "Monaca", "Paladino", "Paladina", "Ranger", "Stregone", "Stregona", "Warlock",
	"Artefice", "Barbarian", "Bard", "Cleric", "Druid", "Fighter", "Rogue", "Wizard", "Monk", "Paladin", "Sorcerer", "Artificer"]
const RACES := ["Elfo", "Elfa", "Nano", "Nana", "Umano", "Umana", "Halfling", "Gnomo", "Gnoma", "Mezzelfo", "Mezzelfa",
	"Mezzorco", "Mezzorchessa", "Tiefling", "Dragonide", "Aasimar", "Goliath", "Tabaxi", "Genasi", "Firbolg", "Orco", "Orchessa",
	"Elf", "Dwarf", "Human", "Gnome", "Half-Elf", "Half-Orc", "Dragonborn", "Orc"]

var items: Array = []   # chunks with page index: {t, x0, x1, y, s, p}
var text := ""


static func parse(doc: Dictionary) -> Dictionary:
	var si := new()
	return si._parse(doc)


static func _re(p: String) -> RegEx:
	var r := RegEx.new()
	r.compile(p)
	return r


func _parse(doc: Dictionary) -> Dictionary:
	for pi in doc.get("pages", []).size():
		for c in doc.pages[pi].chunks:
			var it: Dictionary = c.duplicate()
			it.p = pi
			items.append(it)
	text = PdfText.plain_text(doc)
	var ch := Rules.blank_character("")
	var found: Array = []   # what was recognised, shown to the master
	# ---- name: biggest text on the first page that isn't a generic title
	var best := {}
	for it in items:
		if int(it.p) > 0:
			break
		var t := str(it.t)
		if t.length() < 2 or t.length() > 60 or _re("(?i)scheda|character sheet|d&d|dungeons|pagina|page").search(t):
			continue
		if _re("\\d").search(t) and t.length() < 4:
			continue
		if best.is_empty() or float(it.s) > float(best.s):
			best = it
	var nm := _after_label("(?i)\\b(?:nome del personaggio|nome personaggio|character name)\\b", "(.+)")
	if nm == "" and not best.is_empty():
		nm = str(best.t)
	if nm != "":
		ch.name = nm.strip_edges().left(40)
		found.append("nome")
	var pl := _match1("(?im)\\b(?:giocatore|player(?: name)?)\\s*:\\s*([^\\t\\n|]+)")
	if pl != "":
		ch.player = pl.strip_edges().left(40)
	# ---- race / class / level
	var lvl := _match1("(?i)\\b(?:livello|level|liv\\.)\\s*(\\d{1,2})\\b")
	if lvl == "":
		lvl = _match1("(?i)\\b(?:" + "|".join(CLASSES) + ")\\s+(\\d{1,2})\\b")
	if lvl != "":
		ch.level = clampi(int(lvl), 1, 20)
		found.append("livello")
	var cls_re := _re("(?i)\\b(" + "|".join(CLASSES) + ")\\b")
	var race_re := _re("(?i)\\b(" + "|".join(RACES) + ")\\b")
	for it in items:
		var t := str(it.t)
		if not cls_re.search(t) or t.length() > 120:
			continue
		var segs := _re("\\s*[—–|•·]\\s*|\\s+-\\s+").sub(t, "\u0001", true).split("\u0001", false)
		for sgm in segs:
			var s := str(sgm).strip_edges()
			if ch.cls == "" and cls_re.search(s):
				ch.cls = _re("(?i)\\s*(livello|level)\\s*\\d+").sub(s, "", true).strip_edges().left(40)
			elif ch.race == "" and race_re.search(s):
				ch.race = s.left(40)
		if ch.cls != "":
			break
	if ch.race == "":
		var rm := race_re.search(text)
		var r2 := _match1("(?im)\\b(?:razza|specie|race|species)\\s*:\\s*([^\\t\\n|]+)")
		ch.race = (r2 if r2 != "" else (rm.get_string(1) if rm else "")).strip_edges().left(40)
	if ch.cls == "":
		var c2 := _match1("(?im)\\b(?:classe|class)\\s*:\\s*([^\\t\\n|]+)")
		ch.cls = c2.strip_edges().left(40)
	if ch.cls != "":
		found.append("classe")
	if ch.race != "":
		found.append("razza")
	# ---- proficiency bonus
	var prof := _value("(?i)bonus (?:di )?competenza|proficiency bonus", "^\\+?(\\d)\\b")
	if prof != "":
		ch.prof = clampi(int(prof.trim_prefix("+")), 1, 9)
		found.append("competenza")
	else:
		ch.prof = 2 + int((int(ch.level) - 1) / 4)
	# ---- abilities and saves
	for a in Rules.ABILITIES:
		var res := _ability(a)
		if res.score > 0:
			ch.ab[a] = clampi(res.score, 1, 30)
			if not found.has("caratteristiche"):
				found.append("caratteristiche")
		if res.save_prof:
			ch.saves.append(a)
	if ch.saves.size() > 0:
		found.append("tiri salvezza")
	# ---- hit points, armour class, speed, initiative
	var hp := _value("(?i)punti ferita(?: massimi| max)?|hit points?(?: maximum)?|\\bpf\\b|\\bhp\\b", "^(\\d{1,3})\\b")
	if hp != "":
		ch.hp_max = clampi(int(hp), 1, 999)
		ch.hp = ch.hp_max
		found.append("PF")
	var ac := _value("(?i)classe armatura|armou?r class|\\bca\\b|\\bac\\b", "^(\\d{1,2})\\b")
	if ac != "":
		ch.ac = clampi(int(ac), 1, 40)
		found.append("CA")
	var sp := _value("(?i)velocit[àa]|speed", "^(\\d{1,3})\\s*(m|metri|ft|piedi|feet|')?")
	if sp != "":
		var m := _re("^(\\d{1,3})\\s*(m|metri|ft|piedi|feet|')?").search(sp)
		var v := int(m.get_string(1)) if m else int(sp)
		var unit := m.get_string(2).to_lower() if m else ""
		if unit in ["ft", "piedi", "feet", "'"] or (unit == "" and v >= 20):
			v = int(round(v * 0.3))
		ch.speed = clampi(v, 0, 60)
		found.append("velocità")
	var ini := _value("(?i)iniziativa|initiative", "^([+-]?\\d{1,2})\\b")
	if ini != "":
		ch.init_bonus = clampi(int(ini) - Rules.mod(ch.ab.DES), -20, 20)
	# ---- skills
	for sid in SKILL_ALIASES:
		for alias in SKILL_ALIASES[sid]:
			var m := _re("(?i)(?<![\\p{L}])" + _esc(alias) + "\\s*(?:\\([A-Za-z]{3}\\))?\\s*[:=]?\\s*([+-]\\d{1,2})\\b").search(text)
			if m:
				var val := int(m.get_string(1))
				var info := Rules.skill_info(sid)
				var base := Rules.mod(ch.ab[info[2]])
				if val >= base + 2 * int(ch.prof):
					ch.skills[sid] = 2
				elif val >= base + int(ch.prof):
					ch.skills[sid] = 1
				break
	if ch.skills.size() > 0:
		found.append("abilità")
	# ---- attacks
	ch.attacks = _attacks()
	if ch.attacks.size() > 0:
		found.append("attacchi")
	# ---- notes: the whole sheet as text, for reference
	var lines := PackedStringArray()
	var footer := _re("(?i)^(page|pagina)\\s*\\d+\\s*(of|di)\\s*\\d+$")
	for ln in text.split("\n"):
		var l := ln.replace("\t", "  ").strip_edges()
		if l != "" and not footer.search(l):
			lines.append(l)
	ch.notes = ("Importato da PDF.\n" + "\n".join(lines)).left(4000)
	var fields: Dictionary = doc.get("fields", {})
	if not fields.is_empty():
		_apply_fields(fields, ch, found)
	return {"char": ch, "found": found}


# ------------------------------------------------------------ form fields
## Ability names as they appear in field names (lower case, letters only).
const AB_KEYS := {
	"FOR": ["str", "strength", "for", "forza"], "DES": ["dex", "dexterity", "des", "destrezza"],
	"COS": ["con", "constitution", "cos", "costituzione"], "INT": ["int", "intelligence", "intelligenza"],
	"SAG": ["wis", "wisdom", "sag", "saggezza"], "CAR": ["cha", "charisma", "car", "carisma"],
}
const SAVE_PREFIXES := ["savingthrow", "tirosalvezza", "save", "st", "ts"]


## Last part of a field name, lower-case letters and digits only
## ("Wpn1 AtkBonus " -> "wpn1atkbonus").
static func _fkey(name: String) -> String:
	var s := name.to_lower()
	if s.contains("."):
		s = s.get_slice(".", s.count("."))
	for pair in [["à", "a"], ["è", "e"], ["é", "e"], ["ì", "i"], ["ò", "o"], ["ù", "u"]]:
		s = s.replace(pair[0], pair[1])
	var out := ""
	for c in s:
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out


static func _first_int(s: String, signed := false) -> String:
	var m := _re("[+-]?\\d+" if signed else "\\d+").search(s)
	return m.get_string() if m else ""


## Ability of a saving-throw field ("ststrength", "dexsave"), "" otherwise.
static func _save_ability(k: String) -> String:
	var rest := ""
	for pre in SAVE_PREFIXES:
		if k.begins_with(pre):
			rest = k.substr(pre.length())
			break
	if rest == "" and k.ends_with("save"):
		rest = k.trim_suffix("save")
	for a in AB_KEYS:
		if rest != "" and AB_KEYS[a].has(rest):
			return a
	return ""


## Level of a proficiency from a total bonus: 2 = expertise, 1 = proficient.
static func _prof_level(total: int, base: int, prof: int) -> int:
	if prof > 0 and total >= base + 2 * prof:
		return 2
	if prof > 0 and total >= base + prof:
		return 1
	return 0


func _apply_fields(fields: Dictionary, ch: Dictionary, found: Array) -> void:
	var by := {}  # reduced name -> value (first one wins: page 1 before page 2)
	for n in fields:
		var k := _fkey(str(n))
		if k != "" and not by.has(k):
			by[k] = str(fields[n]).strip_edges()
	var pick := func(keys: Array) -> String:
		for k in keys:
			if by.has(k) and str(by[k]) != "":
				return str(by[k])
		return ""
	var mark := func(what: String):
		if not found.has(what):
			found.append(what)
	var v: String = pick.call(["charactername", "charname", "name", "nome", "nomepersonaggio", "nomedelpersonaggio"])
	if v != "":
		ch.name = v.left(40)
		mark.call("nome")
	v = pick.call(["playername", "player", "giocatore", "nomegiocatore", "nomedelgiocatore"])
	if v != "":
		ch.player = v.left(40)
	v = pick.call(["race", "species", "razza", "specie"])
	if v != "":
		ch.race = v.left(40)
		mark.call("razza")
	# class and level: "Fighter 5", "Guerriero 3 / Mago 2" (multiclass: first
	# class, levels added up)
	v = pick.call(["classlevel", "classandlevel", "classelivello", "classeelivello", "class", "classe"])
	if v != "":
		var cname := _re("\\s*\\d+").sub(v.get_slice("/", 0), "", true).strip_edges()
		if cname != "":
			ch.cls = cname.left(40)
			mark.call("classe")
		var total := 0
		for m in _re("\\d+").search_all(v):
			total += int(m.get_string())
		if total > 0:
			ch.level = clampi(total, 1, 20)
			mark.call("livello")
	v = _first_int(pick.call(["level", "livello", "characterlevel", "totallevel"]))
	if v != "":
		ch.level = clampi(int(v), 1, 20)
		mark.call("livello")
	v = _first_int(pick.call(["profbonus", "proficiencybonus", "proficiency", "bonuscompetenza", "competenza", "pb"]))
	if v != "":
		ch.prof = clampi(int(v), 1, 9)
		mark.call("competenza")
	elif not found.has("competenza"):
		ch.prof = Rules.prof_for(int(ch.level))
	# ability scores ("STR"); the modifier fields are not needed
	for a in AB_KEYS:
		for alias in AB_KEYS[a]:
			var sc := _first_int(str(by.get(alias, "")))
			if sc != "" and int(sc) >= 1 and int(sc) <= 30:
				ch.ab[a] = int(sc)
				mark.call("caratteristiche")
				break
	# saving throws and skills: proficiency read from the total bonus
	var saves: Array = []
	var save_fields := false
	for k in by:
		var a := _save_ability(k)
		var val := _first_int(str(by[k]), true)
		if a == "" or val == "":
			continue
		save_fields = true
		if not saves.has(a) and _prof_level(int(val), Rules.mod(ch.ab[a]), int(ch.prof)) > 0:
			saves.append(a)
	if save_fields:
		ch.saves = saves
		mark.call("tiri salvezza")
	var skills := {}
	var skill_fields := false
	for sid in SKILL_ALIASES:
		var keys: Array = []
		for alias in SKILL_ALIASES[sid]:
			keys.append(_fkey(alias))
		if sid == "addestrare":
			keys.append("animal")
		var val := _first_int(pick.call(keys), true)
		if val == "":
			continue
		skill_fields = true
		var lv := _prof_level(int(val), Rules.mod(ch.ab[Rules.skill_info(sid)[2]]), int(ch.prof))
		if lv > 0:
			skills[sid] = lv
	if skill_fields:
		ch.skills = skills
		mark.call("abilità")
	# armour class, hit points, speed, initiative
	v = _first_int(pick.call(["ac", "armorclass", "armourclass", "ca", "classearmatura"]))
	if v != "":
		ch.ac = clampi(int(v), 1, 40)
		mark.call("CA")
	v = _first_int(pick.call(["hpmax", "maxhp", "hitpointmaximum", "hitpointsmax", "maxhitpoints", "pfmax", "puntiferitamassimi"]))
	if v != "":
		ch.hp_max = clampi(int(v), 1, 999)
		ch.hp = ch.hp_max
		mark.call("PF")
		var cur := _first_int(pick.call(["hpcurrent", "currenthp", "currenthitpoints", "pfattuali", "puntiferitaattuali"]))
		if cur != "" and int(cur) <= int(ch.hp_max):
			ch.hp = int(cur)
	var spd: String = pick.call(["speed", "walkspeed", "velocita"])
	if spd != "":
		var m := _re("(\\d{1,3})\\s*(m|metri|ft|piedi|feet|')?").search(spd)
		if m:
			var n := int(m.get_string(1))
			var unit := m.get_string(2).to_lower()
			if unit in ["ft", "piedi", "feet", "'"] or (unit == "" and n >= 20):
				n = int(round(n * 0.3))
			ch.speed = clampi(n, 0, 60)
			mark.call("velocità")
	v = _first_int(pick.call(["initiative", "init", "iniziativa"]), true)
	if v != "":
		ch.init_bonus = clampi(int(v) - Rules.mod(ch.ab.DES), -20, 20)
	# weapons: "Wpn Name" / "Wpn1 AtkBonus" / "Wpn1 Damage", "Wpn Name 2" ...
	var rows := {}
	var dice_re := _re("(\\d+d\\d+(?:\\s*[+-]\\s*\\d+)?)")
	for k in by:
		var weapon := false
		for pre in ["wpn", "weapon", "arma", "attack", "attacco"]:
			weapon = weapon or k.begins_with(pre)
		if not weapon:
			continue
		var idx := _first_int(k)
		var i := int(idx) if idx != "" else 1
		var role := ""
		if k.contains("name") or k.contains("nome"):
			role = "name"
		elif k.contains("atk") or k.contains("bonus") or k.contains("hit") or k.contains("colpire"):
			role = "bonus"
		elif k.contains("damage") or k.contains("dmg") or k.contains("dann"):
			role = "damage"
		if role == "":
			continue
		if not rows.has(i):
			rows[i] = {}
		rows[i][role] = str(by[k])
	var idxs := rows.keys()
	idxs.sort()
	var atk: Array = []
	for i in idxs:
		var r: Dictionary = rows[i]
		if str(r.get("name", "")) == "":
			continue
		var dm := dice_re.search(str(r.get("damage", "")))
		atk.append({"name": str(r.name).left(40), "bonus": clampi(int(_first_int(str(r.get("bonus", "0")), true)), -20, 30),
			"damage": dm.get_string(1).replace(" ", "") if dm else "1d6"})
		if atk.size() >= 12:
			break
	if not atk.is_empty():
		ch.attacks = atk
		mark.call("attacchi")
	# long text fields (features, equipment, proficiencies) go to the notes
	var notes := PackedStringArray()
	for n in fields:
		var t := str(fields[n]).strip_edges()
		if t.length() >= 40 or t.contains("\n"):
			notes.append(t)
	if not notes.is_empty():
		ch.notes = ("Importato da PDF compilabile.\n" + "\n\n".join(notes)).left(4000)


static func _esc(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if "\\.^$|?*+()[]{}".contains(c) else c
	return out


func _match1(pattern: String) -> String:
	var m := _re(pattern).search(text)
	if not m:
		return ""
	for i in range(1, m.get_group_count() + 1):
		if m.get_string(i) != "":
			return m.get_string(i)
	return ""


## Value written after "Label:" in the same chunk.
func _after_label(label: String, value: String) -> String:
	var re := _re(label + "\\s*[:=]\\s*" + value)
	for it in items:
		var m := re.search(str(it.t))
		if m:
			return m.get_string(m.get_group_count())
	return ""


func _sort_x(a, b) -> bool:
	return float(a.x0) < float(b.x0)


## Finds a labelled value: inline ("CA: 15"), to the right in the same row,
## or below in the same column (table layouts).
func _value(label: String, value: String) -> String:
	var lre := _re(label)
	var vre := _re(value)
	for it in items:
		var t := str(it.t)
		var lm := lre.search(t)
		if not lm or t.length() > 60:
			continue
		var rest := _re("^\\s*\\([^)]{1,6}\\)").sub(t.substr(lm.get_end()), "").strip_edges().trim_prefix(":").trim_prefix("=").strip_edges()
		var vm := vre.search(rest)
		if vm:
			return vm.get_string(0)
		if rest.length() > 3:
			continue
		# right, same row
		var right: Array = []
		for o in items:
			if o.p == it.p and absf(float(o.y) - float(it.y)) < float(it.s) * 0.6 and float(o.x0) >= float(it.x1) - 1 and float(o.x0) - float(it.x1) < 60:
				right.append(o)
		right.sort_custom(_sort_x)
		if right.size() > 0:
			vm = vre.search(str(right[0].t))
			if vm:
				return vm.get_string(0)
		# below, same column
		var below: Array = []
		var cx := (float(it.x0) + float(it.x1)) / 2.0
		for o in items:
			if o.p != it.p or float(o.y) <= float(it.y) + 1 or float(o.y) - float(it.y) > float(it.s) * 9:
				continue
			if float(o.x1) < float(it.x0) - 15 or float(o.x0) > float(it.x1) + 15:
				continue
			var d := (float(o.y) - float(it.y)) + absf((float(o.x0) + float(o.x1)) / 2.0 - cx) * 0.2
			below.append([d, o])
		below.sort_custom(func(a, b): return a[0] < b[0])
		for e in below.slice(0, 3):
			vm = vre.search(str(e[1].t))
			if vm:
				return vm.get_string(0)
	return ""


func _ability(a: String) -> Dictionary:
	var out := {"score": 0, "save_prof": false}
	var names: Array = AB_LABELS[a]
	var full := str(names[0]) + "|" + str(names[1])
	var abbr := "|".join(names.slice(2))
	var label_re := _re("(?i)^(?:" + full + ")\\b|^\\(?(?:" + abbr + ")\\)?$")
	var num_re := _re("^(\\d{1,2})$")
	var sgn_re := _re("^([+-]\\d{1,2})")
	for it in items:
		var t := str(it.t)
		if not label_re.search(t) or t.length() > 40:
			continue
		# inline: "Forza 8 (-1)" / "FOR: 14"
		var im := _re("(?i)^(?:" + full + "|" + abbr + ")\\s*(?:\\((?:" + abbr + ")\\))?\\s*[:=]?\\s*(\\d{1,2})\\b").search(t)
		if im:
			out.score = int(im.get_string(1))
		var row: Array = []
		for o in items:
			if o.p == it.p and absf(float(o.y) - float(it.y)) < float(it.s) * 0.6 and float(o.x0) > float(it.x1) - 1 and float(o.x0) - float(it.x1) < 260:
				row.append(o)
		row.sort_custom(_sort_x)
		var signed: Array = []
		for o in row:
			var ot := str(o.t)
			if out.score == 0 and signed.is_empty() and num_re.search(ot):
				out.score = int(ot)
				continue
			var sm := sgn_re.search(ot)
			if sm:
				signed.append([int(sm.get_string(1)), ot])
		if out.score == 0:
			# value written below the label (vertical stat boxes)
			for o in items:
				if o.p == it.p and float(o.y) > float(it.y) and float(o.y) - float(it.y) < float(it.s) * 4 and float(o.x1) > float(it.x0) - 10 and float(o.x0) < float(it.x1) + 10 and num_re.search(str(o.t)):
					out.score = int(str(o.t))
					break
		if out.score > 0 and out.score <= 30:
			for sv in signed:
				if _re("(?i)comp|prof|★|●|✓").search(sv[1]):
					out.save_prof = true
			if signed.size() >= 2 and not out.save_prof:
				out.save_prof = int(signed[1][0]) > Rules.mod(out.score)
			return out
		out.score = 0
	# plain-text fallback: "FOR 8", "Forza: 8"
	var m := _re("(?i)(?:" + full + "|\\b(?:" + abbr + ")\\b)\\s*(?:\\((?:" + abbr + ")\\))?\\s*[:=]?\\s*(\\d{1,2})\\b").search(text)
	if m and int(m.get_string(1)) <= 30:
		out.score = int(m.get_string(1))
	if _re("(?i)(?:tiri? salvezza|saving throws?)[^\\n]{0,200}?(?:" + full + ")\\s*[+]").search(text):
		out.save_prof = true
	return out


func _attacks() -> Array:
	var out: Array = []
	var dice_re := _re("(\\d+d\\d+(?:\\s*[+-]\\s*\\d+)?)")
	var hit_re := _re("(?i)(?:attacc\\w*|attack|colpire|to hit)[^+\\-\\d]{0,25}([+-]\\d{1,2})")
	var bonus_re := _re("^([+-]\\d{1,2})$")
	var skip_re := _re("(?i)^(trucchetto|cantrip|\\d+°|livello|level|\\d+\\s*azion|azione|reazione|bonus|/)")
	var seen := {}
	for it in items:
		var t := str(it.t)
		var dm := dice_re.search(t)
		if not dm:
			continue
		var hm := hit_re.search(t)
		var row: Array = []
		for o in items:
			if o.p == it.p and o != it and absf(float(o.y) - float(it.y)) < float(it.s) * 0.6 and float(o.x1) <= float(it.x0) + 1:
				row.append(o)
		row.sort_custom(_sort_x)
		var bonus := 0
		if hm:
			bonus = int(hm.get_string(1))
		else:
			# weapon tables: "Spada lunga | +7 | 1d8+4 taglienti"
			var found_b := false
			for o in row:
				var bm := bonus_re.search(str(o.t))
				if bm:
					bonus = int(bm.get_string(1))
					found_b = true
			if not found_b:
				continue
		var name := ""
		for o in row:
			var ot := str(o.t)
			if skip_re.search(ot) or bonus_re.search(ot) or _re("\\d+\\s*m$").search(ot) or not _re("\\p{L}{3}").search(ot):
				continue
			name = ot
			break
		if name == "":
			var nm := _re("^([^:+\\d]{3,40}):").search(t)
			name = nm.get_string(1) if nm else "Attacco"
		name = _re("(?i)\\s*\\((?:inv|ev|abj|ill|nec|tra|div|con)\\.?\\)").sub(name, "", true).strip_edges()
		var key := name.to_lower()
		if seen.has(key):
			continue
		seen[key] = true
		out.append({"name": name.left(40), "bonus": clampi(bonus, -20, 30), "damage": dm.get_string(1).replace(" ", "").left(40)})
		if out.size() >= 12:
			break
	return out
