class_name Rules
extends RefCounted
## D&D 5e rules data (Italian names) shared by the master app.
## The same lists exist in web/common.js for the browser pages.

const ABILITIES: Array = ["FOR", "DES", "COS", "INT", "SAG", "CAR"]
const ABILITY_NAMES: Dictionary = {
	"FOR": "Forza", "DES": "Destrezza", "COS": "Costituzione",
	"INT": "Intelligenza", "SAG": "Saggezza", "CAR": "Carisma",
}
# [id, nome, caratteristica]
const SKILLS: Array = [
	["acrobazia", "Acrobazia", "DES"],
	["addestrare", "Addestrare Animali", "SAG"],
	["arcano", "Arcano", "INT"],
	["atletica", "Atletica", "FOR"],
	["furtivita", "Furtività", "DES"],
	["indagare", "Indagare", "INT"],
	["inganno", "Inganno", "CAR"],
	["intimidire", "Intimidire", "CAR"],
	["intrattenere", "Intrattenere", "CAR"],
	["intuizione", "Intuizione", "SAG"],
	["medicina", "Medicina", "SAG"],
	["natura", "Natura", "INT"],
	["percezione", "Percezione", "SAG"],
	["persuasione", "Persuasione", "CAR"],
	["rapidita", "Rapidità di Mano", "DES"],
	["religione", "Religione", "INT"],
	["sopravvivenza", "Sopravvivenza", "SAG"],
	["storia", "Storia", "INT"],
]
const KINDS: Array = ["Libero", "Attacco", "Danni", "Prova", "Tiro salvezza", "Iniziativa"]
const DIE_SIDES: Array = [4, 6, 8, 10, 12, 20, 100]
const NO_SCORE := -999


static func mod(score) -> int:
	return floori((int(score) - 10) / 2.0)


static func fmt_mod(m) -> String:
	var v := int(m)
	return ("+%d" % v) if v >= 0 else str(v)


static func skill_info(id: String) -> Array:
	for s in SKILLS:
		if s[0] == id:
			return s
	return []


static func skill_name(id: String) -> String:
	var s := skill_info(id)
	return s[1] if s.size() > 0 else id


static func skill_mod(ch: Dictionary, id: String) -> int:
	var s := skill_info(id)
	if s.is_empty():
		return 0
	var ab: Dictionary = ch.get("ab", {})
	var m := mod(ab.get(s[2], 10))
	var level := int(ch.get("skills", {}).get(id, 0))
	return m + int(ch.get("prof", 2)) * clampi(level, 0, 2)


static func save_mod(ch: Dictionary, ab_id: String) -> int:
	var ab: Dictionary = ch.get("ab", {})
	var m := mod(ab.get(ab_id, 10))
	if ch.get("saves", []).has(ab_id):
		m += int(ch.get("prof", 2))
	return m


static func init_mod(ch: Dictionary) -> int:
	var ab: Dictionary = ch.get("ab", {})
	return mod(ab.get("DES", 10)) + int(ch.get("init_bonus", 0))


## Generic health state shown to players instead of exact hit points.
static func status_text(hp, hp_max) -> String:
	var h := int(hp)
	var mx := maxi(1, int(hp_max))
	if h <= 0:
		return "A terra"
	if h >= mx:
		return "Illeso"
	if h * 2 > mx:
		return "Ferito"
	return "Gravemente ferito"


static func check_label(kind: String, param: String) -> String:
	match kind:
		"skill":
			return "Prova di %s" % skill_name(param)
		"save":
			return "Tiro salvezza su %s" % ABILITY_NAMES.get(param, param)
		"init":
			return "Iniziativa"
		"free":
			return "Tiro: %s" % param
	return param


static func blank_character(cname: String) -> Dictionary:
	return {
		"id": "", "name": cname, "player": "", "cls": "", "race": "", "level": 1,
		"hp": 10, "hp_max": 10, "hp_temp": 0, "ac": 10, "speed": 9, "prof": 2,
		"ab": {"FOR": 10, "DES": 10, "COS": 10, "INT": 10, "SAG": 10, "CAR": 10},
		"saves": [], "skills": {}, "init_bonus": 0, "attacks": [], "notes": "", "conditions": "",
		"resist": "", "vuln": "", "immune": "",
		"spells": [], "slots_auto": true, "slots_max": [0, 0, 0, 0, 0, 0, 0, 0, 0], "slots_used": [0, 0, 0, 0, 0, 0, 0, 0, 0],
	}


static func _to_int(v, fallback: int) -> int:
	var s := str(v).strip_edges()
	if s.is_valid_int():
		return int(s)
	if s.is_valid_float():
		return int(float(s))
	return fallback


## Copies only known sheet fields from src into ch, with type and range checks.
static func merge_sheet(ch: Dictionary, src: Dictionary) -> void:
	var str_fields := {"name": 40, "player": 40, "cls": 40, "race": 40, "notes": 4000, "conditions": 200,
		"resist": 200, "vuln": 200, "immune": 200}
	for k in str_fields:
		if src.has(k):
			var s := str(src[k]).strip_edges().left(str_fields[k])
			if k == "name" and s == "":
				continue
			ch[k] = s
	var int_fields := {
		"level": [1, 20], "hp": [0, 999], "hp_max": [1, 999], "hp_temp": [0, 999], "ac": [0, 40],
		"speed": [0, 60], "prof": [0, 9], "init_bonus": [-20, 20],
	}
	for k in int_fields:
		if src.has(k):
			ch[k] = clampi(_to_int(src[k], int(ch.get(k, 0))), int_fields[k][0], int_fields[k][1])
	ch["hp"] = clampi(int(ch.get("hp", 0)), 0, int(ch.get("hp_max", 1)))
	sync_slots(ch)
	if src.get("ab") is Dictionary:
		var ab: Dictionary = ch.get("ab", {}).duplicate()
		var sab: Dictionary = src["ab"]
		for a in ABILITIES:
			if sab.has(a):
				ab[a] = clampi(_to_int(sab[a], 10), 1, 30)
		ch["ab"] = ab
	if src.get("saves") is Array:
		var sv: Array = []
		for a in src["saves"]:
			if ABILITIES.has(str(a)) and not sv.has(str(a)):
				sv.append(str(a))
		ch["saves"] = sv
	if src.get("skills") is Dictionary:
		var sk := {}
		var ssk: Dictionary = src["skills"]
		for s in SKILLS:
			if ssk.has(s[0]):
				var lv := clampi(_to_int(ssk[s[0]], 0), 0, 2)
				if lv > 0:
					sk[s[0]] = lv
		ch["skills"] = sk
	if src.get("attacks") is Array:
		var at: Array = []
		for a in src["attacks"]:
			if a is Dictionary and at.size() < 12:
				at.append({
					"name": str(a.get("name", "Attacco")).left(40),
					"bonus": clampi(_to_int(a.get("bonus", 0), 0), -20, 30),
					"damage": str(a.get("damage", "1d6")).left(40),
				})
		ch["attacks"] = at
	if src.get("spells") is Array:
		var sp: Array = []
		for a in src["spells"]:
			if a is Dictionary and sp.size() < 60 and str(a.get("name", "")).strip_edges() != "":
				sp.append({
					"name": str(a.get("name", "")).strip_edges().left(50),
					"lvl": clampi(_to_int(a.get("lvl", 0), 0), 0, 9),
					"prep": bool(a.get("prep", true)),
				})
		sp.sort_custom(func(x, y): return x.lvl < y.lvl or (x.lvl == y.lvl and str(x.name) < str(y.name)))
		ch["spells"] = sp


# ------------------------------------------- from the Player's Handbook 2024
## Conditions (Rules Glossary, 2024 rules), with a one-line reminder of their effect.
const CONDITIONS: Array = [
	["Accecato", "Non vede: fallisce le prove che richiedono la vista. Attacca con svantaggio, chi lo attacca ha vantaggio."],
	["Affascinato", "Non può attaccare chi lo ha affascinato né colpirlo con effetti dannosi; questi ha vantaggio nelle prove sociali contro di lui."],
	["Afferrato", "Velocità 0. Svantaggio agli attacchi contro chiunque non sia chi lo afferra, che può trascinarlo."],
	["Assordato", "Non sente e fallisce le prove che richiedono l'udito."],
	["Avvelenato", "Svantaggio ai tiri per colpire e alle prove di caratteristica."],
	["Incapacitato", "Niente azioni, azioni bonus né reazioni; non parla; perde la concentrazione; svantaggio all'iniziativa."],
	["Invisibile", "Vantaggio all'iniziativa. Attacca con vantaggio, chi lo attacca ha svantaggio (se non lo vede)."],
	["Paralizzato", "Incapacitato, velocità 0. Fallisce TS di For e Des. Chi lo attacca ha vantaggio; colpito entro 1,5 m = critico."],
	["Pietrificato", "Pietra: incapacitato, velocità 0. Fallisce TS di For e Des, chi lo attacca ha vantaggio. Resistenza a tutti i danni, immune ad Avvelenato."],
	["Privo di sensi", "Incapacitato e prono, velocità 0. Fallisce TS di For e Des. Chi lo attacca ha vantaggio; colpito entro 1,5 m = critico."],
	["Prono", "Si muove strisciando (alzarsi costa metà velocità). Attacca con svantaggio; contro di lui vantaggio entro 1,5 m, altrimenti svantaggio."],
	["Spaventato", "Svantaggio a prove e attacchi finché vede la fonte della paura; non può avvicinarsi a essa."],
	["Stordito", "Incapacitato. Fallisce TS di For e Des; chi lo attacca ha vantaggio."],
	["Trattenuto", "Velocità 0. Attacca con svantaggio, chi lo attacca ha vantaggio. Svantaggio ai TS di Des."],
	["Indebolimento", "Livelli cumulativi 1-6: -2 per livello a ogni tiro di d20, velocità -1,5 m per livello; al 6° muore. Il riposo lungo toglie 1 livello."],
]


static func condition_info(name: String) -> String:
	for c in CONDITIONS:
		if c[0] == name:
			return c[1]
	return ""


# --------------------------------------------------- from the Monster Manual
## Experience points by challenge rating.
const CR_XP := {"0": 10, "1/8": 25, "1/4": 50, "1/2": 100, "1": 200, "2": 450, "3": 700, "4": 1100,
	"5": 1800, "6": 2300, "7": 2900, "8": 3900, "9": 5000, "10": 5900, "11": 7200, "12": 8400,
	"13": 10000, "14": 11500, "15": 13000, "16": 15000, "17": 18000, "18": 20000, "19": 22000, "20": 25000}

## Ready-made creatures (SRD 5.1 values): [name, type, CA, PF, init mod, CR, attack / notes]
const MONSTERS: Array = [
	["Ratto gigante (Giant Rat)", "Bestia", 12, 7, 2, "1/8", "Morso +4, 1d4+2 perforanti"],
	["Coboldo (Kobold)", "Umanoide", 12, 5, 2, "1/8", "Pugnale +4, 1d4+2. Tattica di branco; svantaggio alla luce del sole"],
	["Bandito (Bandit)", "Umanoide", 12, 11, 1, "1/8", "Scimitarra +3, 1d6+1; balestra leggera +3, 1d8+1"],
	["Guardia (Guard)", "Umanoide", 16, 11, 1, "1/8", "Lancia +3, 1d6+1"],
	["Cultista (Cultist)", "Umanoide", 12, 9, 1, "1/8", "Scimitarra +3, 1d6+1. Vantaggio ai TS contro paura e charme"],
	["Goblin", "Umanoide", 15, 7, 2, "1/4", "Scimitarra +4, 1d6+2; arco corto +4, 1d6+2. Fuga agile (Disimpegno o Nascondersi come azione bonus)"],
	["Scheletro (Skeleton)", "Non morto", 13, 13, 2, "1/4", "Spada corta +4, 1d6+2; arco corto +4, 1d6+2. Vulnerabile ai danni contundenti"],
	["Zombi (Zombie)", "Non morto", 8, 22, -2, "1/4", "Schianto +3, 1d6+1. Tempra da non morto: a 0 PF TS Cos CD 5+danni per restare a 1 PF (non con radiosi o critici)"],
	["Lupo (Wolf)", "Bestia", 13, 11, 2, "1/4", "Morso +4, 2d4+2; TS For CD 11 o prono. Tattica di branco"],
	["Orco (Orc)", "Umanoide", 13, 15, 1, "1/2", "Ascia bipenne +5, 1d12+3; giavellotto +5, 1d6+3. Aggressivo: azione bonus per muoversi verso un nemico"],
	["Hobgoblin", "Umanoide", 18, 11, 1, "1/2", "Spada lunga +3, 1d8+1 (+2d6 con Vantaggio marziale)"],
	["Gnoll", "Umanoide", 15, 22, 1, "1/2", "Lancia +4, 1d6+2; arco lungo +3, 1d8+1. Furia: attacco di morso extra quando riduce a 0 PF"],
	["Tagliagole (Thug)", "Umanoide", 11, 32, 0, "1/2", "Due attacchi: mazza +4, 1d6+2. Tattica di branco"],
	["Capo goblin (Goblin Boss)", "Umanoide", 17, 21, 2, "1", "Due attacchi: scimitarra +4, 1d6+2. Reazione: dirotta l'attacco su un goblin vicino"],
	["Bugbear", "Umanoide", 16, 27, 2, "1", "Morning star +4, 2d8+2. Attacco a sorpresa +2d6 nel primo round"],
	["Ghoul", "Non morto", 12, 22, 2, "1", "Artigli +4, 2d4+2; TS Cos CD 10 o paralizzato 1 minuto (non elfi né non morti)"],
	["Lupo crudele (Dire Wolf)", "Bestia", 14, 37, 2, "1", "Morso +5, 2d6+3; TS For CD 13 o prono. Tattica di branco"],
	["Ragno gigante (Giant Spider)", "Bestia", 14, 26, 3, "1", "Morso +5, 1d8+3 + 2d8 veleno (TS Cos CD 11 dimezza). Ragnatela (ricarica 5-6)"],
	["Ogre", "Gigante", 11, 59, -1, "2", "Randello pesante +6, 2d8+4; giavellotto +6, 2d6+4"],
	["Capitano dei banditi (Bandit Captain)", "Umanoide", 15, 65, 3, "2", "Tre attacchi: scimitarra +5, 1d6+3 (x2) e pugnale +5, 1d4+3. Reazione: Parata +2 CA"],
	["Mimic", "Mostruosità", 12, 58, 1, "2", "Pseudopodo +5, 1d8+3 (adesivo); morso +5, 1d8+3 + 1d8 acido. Sembra un oggetto"],
	["Cubo gelatinoso (Gelatinous Cube)", "Melma", 6, 84, -4, "2", "Pseudopodo +4, 3d6 acido. Inglobare: TS Des CD 12. Trasparente"],
	["Wight", "Non morto", 14, 45, 2, "3", "Due attacchi con spada lunga +4, 1d8+2. Risucchio vitale +4, 1d6+2 necrotici (riduce i PF max)"],
	["Gufoorso (Owlbear)", "Mostruosità", 13, 59, 1, "3", "Becco +7, 1d10+5 e artigli +7, 2d8+5"],
	["Veterano (Veteran)", "Umanoide", 17, 58, 1, "3", "Due attacchi con spada lunga +5, 1d8+3 e uno con spada corta +5, 1d6+3"],
	["Cucciolo di drago rosso (Red Dragon Wyrmling)", "Drago", 17, 75, 0, "4", "Morso +6, 1d10+4 + 1d6 fuoco. Soffio di fuoco (ricarica 5-6): cono 4,5 m, 7d6, TS Des CD 13"],
	["Troll", "Gigante", 15, 84, 1, "5", "Morso +7, 1d6+4; due artigli +7, 2d6+4. Rigenera 10 PF a turno se non subisce fuoco o acido"],
	["Mago (Mage)", "Umanoide", 12, 40, 2, "6", "Incantatore di 9° livello: palla di fuoco, cono di freddo, scudo, invisibilità superiore"],
	["Giovane drago rosso (Young Red Dragon)", "Drago", 18, 178, 0, "10", "Morso +10, 2d10+6 + 1d6 fuoco; due artigli +10, 2d6+6. Soffio di fuoco (ricarica 5-6): cono 9 m, 16d6, TS Des CD 17"],
]


static func cr_xp(cr: String) -> int:
	return int(CR_XP.get(cr, 0))


## The 13 damage types of the Player's Handbook.
const DAMAGE_TYPES: Array = ["Acido", "Contundente", "Forza", "Freddo", "Fulmine", "Fuoco", "Necrotico",
	"Perforante", "Psichico", "Radioso", "Tagliente", "Tuono", "Veleno"]

## Damage defenses of the ready-made creatures, keyed by the start of their
## name: {resist, vuln, immune}, comma-separated damage types.
const MONSTER_DEFENSES := {
	"Scheletro": {"vuln": "Contundente", "immune": "Veleno"},
	"Zombi": {"immune": "Veleno"},
	"Ghoul": {"immune": "Veleno"},
	"Wight": {"resist": "Necrotico", "immune": "Veleno"},
	"Mimic": {"immune": "Acido"},
	"Cucciolo di drago rosso": {"immune": "Fuoco"},
	"Giovane drago rosso": {"immune": "Fuoco"},
}


static func monster_defenses(name: String) -> Dictionary:
	for k in MONSTER_DEFENSES:
		if name.begins_with(k):
			return MONSTER_DEFENSES[k]
	return {}


static func _has_type(list: String, dtype: String) -> bool:
	for p in list.split(","):
		if p.strip_edges().to_lower() == dtype.to_lower():
			return true
	return false


## Damage after immunity (0), resistance (half, rounded down) and
## vulnerability (double). Returns [amount, note].
static func apply_defenses(e: Dictionary, amount: int, dtype: String) -> Array:
	if dtype == "":
		return [amount, ""]
	if _has_type(str(e.get("immune", "")), dtype):
		return [0, "immune"]
	var out := amount
	var note := ""
	if _has_type(str(e.get("resist", "")), dtype):
		out = int(out / 2)
		note = "resistenza"
	if _has_type(str(e.get("vuln", "")), dtype):
		out *= 2
		note = "vulnerabile" if note == "" else "resistenza e vulnerabilità"
	return [out, note]


static func defenses_text(e: Dictionary) -> String:
	var parts: Array = []
	for k in [["resist", "Resistenze"], ["vuln", "Vulnerabilità"], ["immune", "Immunità"]]:
		var v := str(e.get(k[0], "")).strip_edges()
		if v != "":
			parts.append("%s: %s" % [k[1], v])
	return "   ".join(parts)


# ------------------------------------------------------------ spell slots
## Spell slots of a full caster (bard, cleric, druid, sorcerer, wizard) by
## level, from the Player's Handbook 2024: slots of 1st..9th level.
const FULL_CASTER_SLOTS: Array = [
	[2, 0, 0, 0, 0, 0, 0, 0, 0], [3, 0, 0, 0, 0, 0, 0, 0, 0], [4, 2, 0, 0, 0, 0, 0, 0, 0],
	[4, 3, 0, 0, 0, 0, 0, 0, 0], [4, 3, 2, 0, 0, 0, 0, 0, 0], [4, 3, 3, 0, 0, 0, 0, 0, 0],
	[4, 3, 3, 1, 0, 0, 0, 0, 0], [4, 3, 3, 2, 0, 0, 0, 0, 0], [4, 3, 3, 3, 1, 0, 0, 0, 0],
	[4, 3, 3, 3, 2, 0, 0, 0, 0], [4, 3, 3, 3, 2, 1, 0, 0, 0], [4, 3, 3, 3, 2, 1, 0, 0, 0],
	[4, 3, 3, 3, 2, 1, 1, 0, 0], [4, 3, 3, 3, 2, 1, 1, 0, 0], [4, 3, 3, 3, 2, 1, 1, 1, 0],
	[4, 3, 3, 3, 2, 1, 1, 1, 0], [4, 3, 3, 3, 2, 1, 1, 1, 1], [4, 3, 3, 3, 3, 1, 1, 1, 1],
	[4, 3, 3, 3, 3, 2, 1, 1, 1], [4, 3, 3, 3, 3, 2, 2, 1, 1],
]


## "full", "half" (paladin, ranger), "pact" (warlock) or "" (no slots).
static func caster_kind(cls: String) -> String:
	var c := cls.to_lower()
	for p in ["bard", "chieric", "druid", "mag", "stregon", "cleric", "wizard", "sorcer"]:
		if c.begins_with(p):
			return "full"
	for p in ["paladin", "ranger"]:
		if c.begins_with(p):
			return "half"
	if c.begins_with("warlock"):
		return "pact"
	return ""


## Maximum slots per spell level (9 numbers) for a single-class character.
static func default_slots(cls: String, level: int) -> Array:
	var out: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0]
	var lv := clampi(level, 1, 20)
	match caster_kind(cls):
		"full":
			out = FULL_CASTER_SLOTS[lv - 1].duplicate()
		"half":
			# 2024 rules: paladin and ranger cast spells from 1st level
			# (2 slots), then follow the full-caster table at half their level.
			out = FULL_CASTER_SLOTS[int(ceil(lv / 2.0)) - 1].duplicate()
		"pact":
			# Pact Magic: few slots, all of the same level, back on a short rest.
			var n := 1 if lv == 1 else (2 if lv <= 10 else (3 if lv <= 16 else 4))
			out[mini(5, int(ceil(lv / 2.0))) - 1] = n
	return out


## Keeps slots_max / slots_used valid; while slots_auto is on the maximum
## follows class and level.
static func sync_slots(ch: Dictionary) -> void:
	if not ch.has("slots_auto"):
		ch["slots_auto"] = true
	var mx: Array = ch.get("slots_max", [])
	if bool(ch.slots_auto) or mx.size() != 9:
		mx = default_slots(str(ch.get("cls", "")), int(ch.get("level", 1)))
	var used: Array = ch.get("slots_used", [])
	var u2: Array = []
	for i in 9:
		var m := clampi(int(mx[i]), 0, 9)
		mx[i] = m
		u2.append(clampi(int(used[i]) if i < used.size() else 0, 0, m))
	ch["slots_max"] = mx
	ch["slots_used"] = u2



## Spellcasting ability of a class (PHB): Intelligence for the wizard, Wisdom
## for cleric, druid and ranger, Charisma for bard, paladin, sorcerer, warlock.
static func spell_ability(cls: String) -> String:
	var c := cls.to_lower()
	if c.begins_with("mag") or c.begins_with("wizard"):
		return "INT"
	for p in ["chieric", "druid", "ranger", "cleric"]:
		if c.begins_with(p):
			return "SAG"
	for p in ["bard", "paladin", "stregon", "warlock", "sorcer"]:
		if c.begins_with(p):
			return "CAR"
	return ""


## [save DC, spell attack bonus, ability] = 8 + prof + mod, prof + mod.
static func spell_numbers(ch: Dictionary) -> Array:
	var ab := spell_ability(str(ch.get("cls", "")))
	if ab == "":
		return []
	var m := mod(ch.get("ab", {}).get(ab, 10)) + int(ch.get("prof", 2))
	return [8 + m, m, ab]
