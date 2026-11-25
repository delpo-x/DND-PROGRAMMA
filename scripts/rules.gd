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


## Exhaustion level 0-6 (PHB 2024), kept in the conditions text as
## "Indebolimento N".
static func exhaustion(e: Dictionary) -> int:
	var re := RegEx.create_from_string("(?i)indebolimento\\s*(\\d)")
	var m := re.search(str(e.get("conditions", "")))
	return clampi(int(m.get_string(1)), 0, 6) if m else 0


## Hit die of a class (d6-d12), 8 when the class is unknown.
const HIT_DIE := {"barbar": 12, "guerrier": 10, "fighter": 10, "paladin": 10, "ranger": 10,
	"mago": 6, "wizard": 6, "stregon": 6, "sorcerer": 6}


static func hit_die(cls: String) -> int:
	var c := cls.to_lower()
	for k in HIT_DIE:
		if c.contains(k):
			return int(HIT_DIE[k])
	return 8


static func skill_mod(ch: Dictionary, id: String) -> int:
	var s := skill_info(id)
	if s.is_empty():
		return 0
	var ab: Dictionary = ch.get("ab", {})
	var m := mod(ab.get(s[2], 10))
	var level := int(ch.get("skills", {}).get(id, 0))
	return m + int(ch.get("prof", 2)) * clampi(level, 0, 2) - 2 * exhaustion(ch)


static func save_mod(ch: Dictionary, ab_id: String) -> int:
	var ab: Dictionary = ch.get("ab", {})
	var m := mod(ab.get(ab_id, 10))
	if ch.get("saves", []).has(ab_id):
		m += int(ch.get("prof", 2))
	return m - 2 * exhaustion(ch)


static func init_mod(ch: Dictionary) -> int:
	var ab: Dictionary = ch.get("ab", {})
	return mod(ab.get("DES", 10)) + int(ch.get("init_bonus", 0)) - 2 * exhaustion(ch)


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
		"resist": "", "vuln": "", "immune": "", "portrait": "",
		"spells": [], "slots_auto": true, "slots_max": [0, 0, 0, 0, 0, 0, 0, 0, 0], "slots_used": [0, 0, 0, 0, 0, 0, 0, 0, 0],
		"res_used": {}, "res_custom": [],
	}


static func _to_int(v, fallback: int) -> int:
	var s := str(v).strip_edges()
	if s.is_valid_int():
		return int(s)
	if s.is_valid_float():
		return int(float(s))
	return fallback


## Copies only known sheet fields from src into ch, with type and range checks.
## Proficiency bonus by level (PHB): +2 at 1-4, +3 at 5-8 ... +6 at 17-20.
static func prof_for(level: int) -> int:
	return 2 + int((clampi(level, 1, 20) - 1) / 4)


static func merge_sheet(ch: Dictionary, src: Dictionary) -> void:
	# the proficiency bonus follows the level, unless it was changed by hand
	var old_level := int(ch.get("level", 1))
	var auto_prof := int(ch.get("prof", 2)) == prof_for(old_level)
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
	if auto_prof and int(ch.get("level", 1)) != old_level and (not src.has("prof") or int(src.prof) == prof_for(old_level)):
		ch["prof"] = prof_for(int(ch.level))
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
	["Indebolimento", "Ogni clic aggiunge un livello (1-6): -2 per livello a ogni tiro di d20, velocità -1,5 m per livello; al 6° muore. Il riposo lungo toglie 1 livello; Annulla toglie l'ultimo clic."],
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
	"13": 10000, "14": 11500, "15": 13000, "16": 15000, "17": 18000, "18": 20000, "19": 22000, "20": 25000,
	"21": 33000, "22": 41000, "23": 50000, "24": 62000, "25": 75000, "26": 90000, "27": 105000,
	"28": 120000, "29": 135000, "30": 155000}

## Encounter XP budget per character, 2024 rules: [low, moderate, high] for
## levels 1 to 20. The budgets of the characters are added up and compared
## with the XP of all the monsters (no multiplier for their number).
const ENCOUNTER_BUDGET: Array = [
	[50, 75, 100], [100, 150, 200], [150, 225, 400], [250, 375, 500], [500, 750, 1100],
	[600, 1000, 1400], [750, 1300, 1700], [1000, 1700, 2100], [1300, 2000, 2600], [1600, 2300, 3100],
	[1900, 2900, 4100], [2200, 3700, 4700], [2600, 4200, 5400], [2900, 4900, 6200], [3300, 5400, 7800],
	[3800, 6100, 9800], [4500, 7200, 11700], [5000, 8700, 14200], [5500, 10700, 17200], [6400, 13200, 22000],
]
const DIFFICULTY_NAMES: Array = ["Bassa", "Moderata", "Alta", "Oltre il limite"]

## Ready-made creatures, 2024 rules (System Reference Document 5.2, CC BY 4.0;
## the Orc has no 2024 stat block and keeps its SRD 5.1 values).
## [name, type, CA, PF, init mod, CR, attack / notes]
const MONSTERS: Array = [
	["Ratto gigante (Giant Rat)", "Bestia", 13, 7, 3, "1/8", "Morso +5, 1d4+3 perforanti. Tattica di branco"],
	["Coboldo (Kobold Warrior)", "Drago", 14, 7, 2, "1/8", "Pugnale +4, 1d4+2 (anche da lancio). Tattica di branco; svantaggio alla luce del sole"],
	["Bandito (Bandit)", "Umanoide", 12, 11, 1, "1/8", "Scimitarra +3, 1d6+1; balestra leggera +3, 1d8+1"],
	["Guardia (Guard)", "Umanoide", 16, 11, 1, "1/8", "Lancia +3, 1d6+1 (anche da lancio)"],
	["Cultista (Cultist)", "Umanoide", 12, 9, 1, "1/8", "Falcetto rituale +3, 1d4+1 taglienti + 1 necrotico"],
	["Goblin (Goblin Warrior)", "Folletto", 15, 10, 2, "1/4", "Scimitarra +4, 1d6+2; arco corto +4, 1d6+2; +1d4 se l'attacco aveva vantaggio. Fuga agile (Disimpegno o Nascondersi come azione bonus)"],
	["Scheletro (Skeleton)", "Non morto", 14, 13, 3, "1/4", "Spada corta +5, 1d6+3; arco corto +5, 1d6+3. Immune al veleno"],
	["Zombi (Zombie)", "Non morto", 8, 15, -2, "1/4", "Schianto +3, 1d8+1. Tempra da non morto: a 0 PF TS Cos CD 5+danni per restare a 1 PF (non con radiosi o critici)"],
	["Lupo (Wolf)", "Bestia", 12, 11, 2, "1/4", "Morso +4, 1d6+2; un bersaglio Medio o più piccolo cade prono. Tattica di branco"],
	["Orco (Orc, valori 2014)", "Umanoide", 13, 15, 1, "1/2", "Valori 2014: nelle regole 2024 l'orco non ha una scheda da mostro. Ascia bipenne +5, 1d12+3; giavellotto +5, 1d6+3. Aggressivo: azione bonus per muoversi verso un nemico"],
	["Hobgoblin (Hobgoblin Warrior)", "Folletto", 18, 11, 3, "1/2", "Spada lunga +3, 2d10+1; arco lungo +3, 1d8+1 + 3d4 veleno. Tattica di branco"],
	["Gnoll (Gnoll Warrior)", "Immondo", 15, 27, 1, "1/2", "Squarcio +4, 1d6+2; arco d'osso +3, 1d10+1. Furia (azione bonus): dopo aver ferito un bersaglio sanguinante si muove di metà velocità e attacca di nuovo"],
	["Tagliagole (Tough)", "Umanoide", 12, 32, 1, "1/2", "Mazza +4, 1d6+2; balestra pesante +3, 1d10+1. Tattica di branco"],
	["Capo goblin (Goblin Boss)", "Folletto", 17, 21, 2, "1", "Due attacchi: scimitarra o arco corto +4, 1d6+2 (+1d4 con vantaggio). Fuga agile. Reazione: scambia posto con un alleato vicino, che diventa il bersaglio"],
	["Bugbear (Bugbear Warrior)", "Folletto", 14, 33, 2, "1", "Presa +4 (portata 3 m), 2d6+2 e afferrato (fuga CD 12); martello leggero +4, 3d4+2 (vantaggio se il bersaglio è afferrato)"],
	["Ghoul", "Non morto", 12, 22, 2, "1", "Due morsi +4, 1d6+2 + 1d6 necrotici. Artigli +4, 1d4+2: TS Cos CD 10 o paralizzato fino alla fine del suo turno successivo (non elfi né non morti)"],
	["Lupo crudele (Dire Wolf)", "Bestia", 14, 22, 2, "1", "Morso +5, 1d10+3; un bersaglio Grande o più piccolo cade prono. Tattica di branco"],
	["Ragno gigante (Giant Spider)", "Bestia", 14, 26, 3, "1", "Morso +5, 1d8+3 + 2d6 veleno. Ragnatela (ricarica 5-6): TS Des CD 13 o trattenuto. Cammina sulle pareti"],
	["Ogre", "Gigante", 11, 68, -1, "2", "Randello pesante +6, 2d8+4; giavellotto +6, 2d6+4"],
	["Capitano dei banditi (Bandit Captain)", "Umanoide", 15, 52, 3, "2", "Due attacchi: scimitarra +5, 1d6+3 o pistola +5, 1d10+3. Reazione: Parata +2 CA"],
	["Mimic", "Mostruosità", 12, 58, 3, "2", "Pseudopodo +5, 1d8+3 + 1d8 acido e afferrato (fuga CD 13); morso +5, 1d8+3 (2d8+3 e vantaggio se afferrato) + 1d8 acido. Sembra un oggetto"],
	["Cubo gelatinoso (Gelatinous Cube)", "Melma", 6, 63, -4, "2", "Pseudopodo +4, 3d6+2 acido. Inglobare: TS Des CD 12, 3d6 acido e inglobato. Trasparente"],
	["Wight", "Non morto", 14, 82, 4, "3", "Due attacchi: spada o arco necrotico +4, 1d8+2 + 1d8 necrotici; uno può essere Risucchio vitale (TS Cos CD 13, 1d8+2 necrotici, riduce i PF max). Svantaggio alla luce del sole"],
	["Gufoorso (Owlbear)", "Mostruosità", 13, 59, 1, "3", "Due attacchi: squarcio +7, 2d8+5"],
	["Veterano (Warrior Veteran)", "Umanoide", 17, 65, 3, "3", "Due attacchi: spadone +5, 2d6+3 o balestra pesante +3, 2d10+1. Reazione: Parata +2 CA"],
	["Cucciolo di drago rosso (Red Dragon Wyrmling)", "Drago", 17, 75, 2, "4", "Due attacchi: squarcio +6, 1d10+4 + 1d6 fuoco. Soffio di fuoco (ricarica 5-6): cono 4,5 m, 7d6, TS Des CD 13"],
	["Troll", "Gigante", 15, 94, 1, "5", "Tre attacchi: squarcio +7 (portata 3 m), 2d6+4. Rigenera 15 PF a inizio turno se non ha subito acido o fuoco. Carica (azione bonus)"],
	["Mago (Mage)", "Umanoide", 15, 81, 2, "6", "Tre attacchi: scarica arcana +6, 3d8+3 forza. Incantesimi CD 14: palla di fuoco e invisibilità (2/giorno), cono di freddo e volare (1/giorno). Passo velato; Controincantesimo o Scudo"],
	["Giovane drago rosso (Young Red Dragon)", "Drago", 18, 178, 4, "10", "Tre attacchi: squarcio +10 (portata 3 m), 2d6+6 + 1d6 fuoco. Soffio di fuoco (ricarica 5-6): cono 9 m, 16d6, TS Des CD 17"],
]


static func cr_xp(cr: String) -> int:
	return int(CR_XP.get(cr, 0))


## Encounter difficulty (2024 rules) of monsters worth xp experience points
## against a party with the given levels. Returns {xp, budget: [low,
## moderate, high], level: 0-3 (index in DIFFICULTY_NAMES, -1 = no monsters
## or no characters), name}.
static func encounter_difficulty(levels: Array, xp: int) -> Dictionary:
	var budget := [0, 0, 0]
	for l in levels:
		var row: Array = ENCOUNTER_BUDGET[clampi(int(l), 1, 20) - 1]
		for i in 3:
			budget[i] += int(row[i])
	var level := -1
	if xp > 0 and not levels.is_empty():
		level = 3
		for i in 3:
			if xp <= int(budget[i]):
				level = i
				break
	return {"xp": xp, "budget": budget, "level": level, "name": DIFFICULTY_NAMES[level] if level >= 0 else ""}


## Thousands with a dot, as written in Italian (12000 -> "12.000").
static func fmt_thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## The 13 damage types of the Player's Handbook.
const DAMAGE_TYPES: Array = ["Acido", "Contundente", "Forza", "Freddo", "Fulmine", "Fuoco", "Necrotico",
	"Perforante", "Psichico", "Radioso", "Tagliente", "Tuono", "Veleno"]

## Damage defenses of the ready-made creatures, keyed by the start of their
## name: {resist, vuln, immune}, comma-separated damage types.
const MONSTER_DEFENSES := {
	"Scheletro": {"immune": "Veleno"},
	"Zombi": {"immune": "Veleno"},
	"Ghoul": {"immune": "Veleno"},
	"Wight": {"resist": "Necrotico", "immune": "Veleno"},
	"Mimic": {"immune": "Acido"},
	"Cubo gelatinoso": {"immune": "Acido"},
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



# --------------------------------------------------------- class resources
## How a resource comes back: "short" = all on a short or long rest, "long" =
## all on a long rest, "short1" = one use on a short rest, all on a long rest.
const RESET_NAMES := {"short": "riposo breve", "long": "riposo lungo", "short1": "1 al riposo breve, tutte al lungo"}


## Value of a level table [[from_level, value], ...]: the last row reached.
static func _by_level(level: int, rows: Array) -> int:
	var v := 0
	for r in rows:
		if level >= int(r[0]):
			v = int(r[1])
	return v


## Limited-use class features of a single-class character (2024 rules, SRD
## 5.2): [{key, name, max, reset, note}], only those with max > 0.
static func class_resources(cls: String, level: int, ab: Dictionary) -> Array:
	var c := cls.to_lower()
	var lv := clampi(level, 1, 20)
	var out: Array = []
	var add := func(key: String, name: String, mx: int, reset: String, note: String):
		if mx > 0:
			out.append({"key": key, "name": name, "max": mx, "reset": reset, "note": note})
	if c.begins_with("barbar"):
		add.call("rage", "Ira", _by_level(lv, [[1, 2], [3, 3], [6, 4], [12, 5], [17, 6]]), "short1", "Azione bonus, dura fino alla fine del tuo prossimo turno e si può prolungare")
	elif c.begins_with("bard"):
		add.call("bardic", "Ispirazione bardica", maxi(1, mod(ab.get("CAR", 10))), "short" if lv >= 5 else "long",
			"Azione bonus: un alleato entro 18 m prende un d%d da aggiungere a un tiro" % _by_level(lv, [[1, 6], [5, 8], [10, 10], [15, 12]]))
	elif c.begins_with("chieric") or c.begins_with("cleric"):
		add.call("channel", "Incanalare divinità", _by_level(lv, [[2, 2], [6, 3], [18, 4]]), "short1", "")
	elif c.begins_with("druid"):
		add.call("wildshape", "Forma selvatica", _by_level(lv, [[2, 2], [6, 3], [17, 4]]), "short1", "Azione bonus")
	elif c.begins_with("guerrier") or c.begins_with("fighter"):
		add.call("secondwind", "Recuperare energie", _by_level(lv, [[1, 2], [4, 3], [10, 4]]), "short1", "Azione bonus: recuperi 1d10 + %d PF" % lv)
		add.call("surge", "Azione impetuosa", _by_level(lv, [[2, 1], [17, 2]]), "short", "Un'azione in più nel turno (non per Magia)")
		add.call("indomitable", "Indomabile", _by_level(lv, [[9, 1], [13, 2], [17, 3]]), "long", "Ritira un tiro salvezza fallito con +%d" % lv)
	elif c.begins_with("monac") or c.begins_with("monk"):
		add.call("focus", "Punti focus", lv if lv >= 2 else 0, "short", "Raffica di colpi, Difesa paziente, Passo del vento")
	elif c.begins_with("paladin"):
		add.call("layhands", "Imposizione delle mani", 5 * lv, "long", "Azione bonus: cura i PF spesi dalla riserva (5 PF tolgono anche il veleno)")
		add.call("channel", "Incanalare divinità", _by_level(lv, [[3, 2], [11, 3]]), "short1", "")
	elif c.begins_with("ranger"):
		add.call("favored", "Nemico prescelto", _by_level(lv, [[1, 2], [5, 3], [9, 4], [13, 5], [17, 6]]), "long", "Marchio del cacciatore senza spendere uno slot")
	elif c.begins_with("stregon") or c.begins_with("sorcer"):
		add.call("innate", "Stregoneria innata", 2, "long", "Azione bonus, 1 minuto: CD +1 e vantaggio agli attacchi con incantesimi da stregone")
		add.call("sorcery", "Punti stregoneria", lv if lv >= 2 else 0, "long", "Metamagia o slot incantesimo")
	elif c.begins_with("mag") or c.begins_with("wizard"):
		add.call("arcane", "Recupero arcano", 1, "long", "Dopo un riposo breve: slot recuperati fino a %d livelli totali (massimo 5° livello)" % int(ceil(lv / 2.0)))
	elif c.begins_with("warlock"):
		add.call("cunning", "Astuzia magica", 1 if lv >= 2 else 0, "long", "1 minuto: recuperi metà degli slot del Patto")
	return out


## Every resource of a character: the class ones plus those added by the
## master (res_custom), each with "used" from res_used. Custom keys are "c0",
## "c1"...
static func resources(ch: Dictionary) -> Array:
	var out: Array = class_resources(str(ch.get("cls", "")), int(ch.get("level", 1)), ch.get("ab", {}))
	var custom: Array = ch.get("res_custom", [])
	for i in custom.size():
		var r: Dictionary = custom[i]
		out.append({"key": "c%d" % i, "name": str(r.get("name", "")), "max": clampi(int(r.get("max", 1)), 1, 999),
			"reset": str(r.get("reset", "long")), "note": ""})
	var used: Dictionary = ch.get("res_used", {})
	for r in out:
		r.used = clampi(int(used.get(r.key, 0)), 0, int(r.max))
	return out


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
