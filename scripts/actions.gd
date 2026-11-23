class_name Actions
extends RefCounted
## Combat actions: what a combatant can do on its turn (weapon attacks, spells,
## special abilities) and their resolution with real dice and every effect:
## hit against AC, critical hits, saving throws, half damage, damage defenses,
## conditions, spell slots, concentration (and the check when hurt), healing.
##
## An action is a Dictionary:
##   name, group ("Attacchi", "Incantesimi", "Speciali", "Personalizzata")
##   mode: "attack" (d20 + bonus vs AC), "save" (targets roll vs dc),
##         "auto" (always hits, e.g. Magic Missile, Divine Smite),
##         "heal", "effect" (only a condition or a note)
##   bonus, dc, save (ability id: FOR DES COS INT SAG CAR)
##   dmg ("2d6+3"), type (damage type), dmg2, type2 (second damage)
##   half (half damage on a successful save), cond ("Prono, Incapacitato")
##   times (attack rolls, darts or rays), targets (how many; 0 = area)
##   lvl (-1 not a spell, 0 cantrip, 1-9), upcast (dice per higher slot level)
##   up_times / up_targets (a higher slot adds a ray / a target)
##   conc (concentration), ranged, drain (heals half the damage dealt)
##   hit_save {save, dc, cond} (a hit also forces a save), note

const ABILITY_NAMES := {"FOR": "Forza", "DES": "Destrezza", "COS": "Costituzione",
	"INT": "Intelligenza", "SAG": "Saggezza", "CAR": "Carisma"}

## Spells of the Player's Handbook 2024 that matter in a fight (SRD 5.2).
## [names (Italian first, then aliases), level, mode, save, damage, type,
##  half, condition, targets (0 = area), concentration, upcast, flags, note]
## flags: scale (cantrip dice grow at 5/11/17), beams (cantrip rays grow),
##        times3 (three darts/rays), upt (+1 dart/ray per level), upn (+1
##        target per level), mod (adds the spell ability modifier), drain,
##        touch (melee spell attack), d2=<dice> <type> (second damage)
const SPELLS: Array = [
	["Dardo di fuoco|fire bolt", 0, "attack", "", "1d10", "Fuoco", false, "", 1, false, "", "scale", "Accende gli oggetti infiammabili non indossati"],
	["Raggio di gelo|ray of frost", 0, "attack", "", "1d8", "Freddo", false, "", 1, false, "", "scale", "Se colpisce, velocità -3 m fino al tuo prossimo turno"],
	["Stretta folgorante|shocking grasp", 0, "attack", "", "1d8", "Fulmine", false, "", 1, false, "", "scale touch", "Se colpisce, niente attacchi di opportunità fino al suo prossimo turno"],
	["Tocco gelido|chill touch", 0, "attack", "", "1d10", "Necrotico", false, "", 1, false, "", "scale touch", "Se colpisce, non recupera PF fino alla fine del tuo prossimo turno"],
	["Spruzzo velenoso|poison spray", 0, "attack", "", "1d12", "Veleno", false, "", 1, false, "", "scale", ""],
	["Produrre fiamma|produce flame", 0, "attack", "", "1d8", "Fuoco", false, "", 1, false, "", "scale", ""],
	["Frusta di spine|thorn whip", 0, "attack", "", "1d6", "Perforante", false, "", 1, false, "", "scale", "Se colpisce, lo tiri di 3 m verso di te"],
	["Deflagrazione occulta|scarica occulta|eldritch blast", 0, "attack", "", "1d10", "Forza", false, "", 1, false, "", "beams", "Un raggio in più al 5°, 11° e 17° livello"],
	["Fiamma sacra|sacred flame", 0, "save", "DES", "1d8", "Radioso", false, "", 1, false, "", "scale", "La copertura non aiuta"],
	["Fiotto acido|spruzzo acido|acid splash", 0, "save", "DES", "1d6", "Acido", false, "", 2, false, "", "scale", ""],
	["Beffa crudele|scherno crudele|vicious mockery", 0, "save", "SAG", "1d6", "Psichico", false, "", 1, false, "", "scale", "Se fallisce, svantaggio al suo prossimo tiro per colpire"],
	["Rintocco dei morti|toll the dead", 0, "save", "SAG", "1d8", "Necrotico", false, "", 1, false, "", "scale", "d12 invece di d8 se il bersaglio è già ferito"],
	["Parola del radioso|word of radiance", 0, "save", "COS", "1d6", "Radioso", false, "", 0, false, "", "scale", ""],
	["Dardo incantato|missile magico|magic missile", 1, "auto", "", "1d4+1", "Forza", false, "", 0, false, "", "times3 upt", "Colpisce sempre: i dardi vanno ai bersagli scelti, a turno"],
	["Mani brucianti|burning hands", 1, "save", "DES", "3d6", "Fuoco", true, "", 0, false, "1d6", "", "Cono di 4,5 m"],
	["Onda tonante|thunderwave", 1, "save", "COS", "2d8", "Tuono", true, "", 0, false, "1d8", "", "Cubo di 4,5 m; chi fallisce è spinto di 3 m"],
	["Cura ferite|cure wounds", 1, "heal", "", "2d8", "", false, "", 1, false, "2d8", "mod", "Contatto"],
	["Parola guaritrice|healing word", 1, "heal", "", "2d4", "", false, "", 1, false, "2d4", "mod", "Azione bonus, gittata 18 m"],
	["Dardo tracciante|guiding bolt", 1, "attack", "", "4d6", "Radioso", false, "", 1, false, "1d6", "", "Il prossimo attacco contro il bersaglio ha vantaggio"],
	["Intimorire infernale|rimprovero infernale|hellish rebuke", 1, "save", "DES", "2d10", "Fuoco", true, "", 1, false, "1d10", "", "Reazione quando subisci danni"],
	["Dardo stregato|witch bolt", 1, "attack", "", "2d12", "Fulmine", false, "", 1, true, "1d12", "", "Nei turni seguenti, con un'azione bonus: 1d12 fulmine automatico"],
	["Infliggi ferite|infliggere ferite|inflict wounds", 1, "save", "COS", "2d10", "Necrotico", true, "", 1, false, "1d10", "touch", ""],
	["Raggio di malattia|ray of sickness", 1, "attack", "", "2d8", "Veleno", false, "Avvelenato", 1, false, "1d8", "", "Avvelenato fino alla fine del tuo prossimo turno"],
	["Sonno|sleep", 1, "save", "SAG", "", "", false, "Incapacitato", 0, true, "", "", "Se fallisce di nuovo alla fine del suo turno cade Privo di sensi"],
	["Charme su persone|ammaliare persone|charm person", 1, "save", "SAG", "", "", false, "Affascinato", 1, false, "", "upn", "Vantaggio al TS se lo state combattendo"],
	["Comando|command", 1, "save", "SAG", "", "", false, "", 1, false, "", "upn", "Ordine: Avvicinati, Lascia cadere, Fuggi, A terra (Prono) o Fermo"],
	["Intralciare|entangle", 1, "save", "FOR", "", "", false, "Trattenuto", 0, true, "", "", "Quadrato di 6 m"],
	["Fuoco fatato|faerie fire", 1, "save", "DES", "", "", false, "", 0, true, "", "", "Chi fallisce brilla: gli attacchi contro di lui hanno vantaggio"],
	["Risata incontrollabile|risata orribile di tasha|tasha's hideous laughter", 1, "save", "SAG", "", "", false, "Prono, Incapacitato", 1, true, "", "", "Ripete il TS alla fine di ogni suo turno e quando subisce danni"],
	["Benedizione|bless", 1, "effect", "", "", "", false, "", 3, true, "", "upn", "+1d4 ai tiri per colpire e ai tiri salvezza"],
	["Anatema|bane", 1, "save", "CAR", "", "", false, "", 3, true, "", "upn", "Chi fallisce: -1d4 ai tiri per colpire e ai tiri salvezza"],
	["Scudo|shield", 1, "effect", "", "", "", false, "", 1, false, "", "", "Reazione: +5 CA fino al tuo prossimo turno"],
	["Armatura magica|mage armor", 1, "effect", "", "", "", false, "", 1, false, "", "", "CA 13 + Destrezza per 8 ore"],
	["Marchio del cacciatore|hunter's mark", 1, "effect", "", "", "", false, "", 1, true, "", "", "+1d6 forza ai tuoi colpi contro il bersaglio"],
	["Punizione divina|divine smite", 1, "auto", "", "2d8", "Radioso", false, "", 1, false, "1d8", "", "Dopo un colpo in mischia; +1d8 contro immondi e non morti"],
	["Punizione tonante|thunderous smite", 1, "auto", "", "2d6", "Tuono", false, "", 1, false, "1d6", "", "Dopo un colpo in mischia; TS For o spinto di 3 m e Prono"],
	["Raggio rovente|scorching ray", 2, "attack", "", "2d6", "Fuoco", false, "", 0, false, "", "times3 upt", "Tre raggi, anche su bersagli diversi"],
	["Frantumare|shatter", 2, "save", "COS", "3d8", "Tuono", true, "", 0, false, "1d8", "", "Sfera di 3 m"],
	["Blocca persone|immobilizzare persone|hold person", 2, "save", "SAG", "", "", false, "Paralizzato", 1, true, "", "upn", "Solo umanoidi; ripete il TS alla fine di ogni suo turno"],
	["Arma spirituale|spiritual weapon", 2, "attack", "", "1d8", "Forza", false, "", 1, true, "1d8", "mod touch", "Azione bonus per muoverla e attaccare di nuovo"],
	["Invisibilità|invisibility", 2, "effect", "", "", "", false, "Invisibile", 1, true, "", "upn", "Finisce se attacca, infligge danni o lancia un incantesimo"],
	["Raggio di luna|raggio lunare|moonbeam", 2, "save", "COS", "2d10", "Radioso", true, "", 0, true, "1d10", "", "Cilindro di 1,5 m"],
	["Sfera infuocata|flaming sphere", 2, "save", "DES", "2d6", "Fuoco", true, "", 1, true, "1d6", "", ""],
	["Ragnatela|web", 2, "save", "DES", "", "", false, "Trattenuto", 0, true, "", "", "Cubo di 6 m"],
	["Freccia acida|freccia acida di melf|acid arrow", 2, "attack", "", "4d4", "Acido", false, "", 1, false, "1d4", "", "Se colpisce, altri 2d4 acido alla fine del suo prossimo turno"],
	["Preghiera di guarigione|prayer of healing", 2, "heal", "", "2d8", "", false, "", 5, false, "1d8", "mod", "Richiede 10 minuti: fuori dal combattimento"],
	["Palla di fuoco|fireball", 3, "save", "DES", "8d6", "Fuoco", true, "", 0, false, "1d6", "", "Sfera di 6 m"],
	["Fulmine|lightning bolt", 3, "save", "DES", "8d6", "Fulmine", true, "", 0, false, "1d6", "", "Linea di 30 m"],
	["Guardiani spirituali|spiriti guardiani|spirit guardians", 3, "save", "SAG", "3d8", "Radioso", true, "", 0, true, "1d8", "", "Emanazione di 4,5 m; velocità dimezzata nell'area"],
	["Parola guaritrice di massa|mass healing word", 3, "heal", "", "2d4", "", false, "", 6, false, "1d4", "mod", "Azione bonus"],
	["Paura|fear", 3, "save", "SAG", "", "", false, "Spaventato", 0, true, "", "", "Cono di 9 m; chi fallisce lascia cadere ciò che tiene e fugge"],
	["Trama ipnotica|schema ipnotico|hypnotic pattern", 3, "save", "SAG", "", "", false, "Affascinato, Incapacitato", 0, true, "", "", "Cubo di 9 m"],
	["Lentezza|slow", 3, "save", "SAG", "", "", false, "", 6, true, "", "", "-2 CA e TS Des, velocità dimezzata, niente reazioni"],
	["Tocco del vampiro|tocco vampirico|vampiric touch", 3, "attack", "", "3d6", "Necrotico", false, "", 1, true, "1d6", "drain touch", "Recuperi PF pari a metà dei danni"],
	["Velocità|haste", 3, "effect", "", "", "", false, "", 1, true, "", "", "+2 CA, velocità doppia, vantaggio TS Des, un'azione in più"],
	["Controincantesimo|counterspell", 3, "effect", "", "", "", false, "", 1, false, "", "", "Reazione: il nemico fa un TS Cos o l'incantesimo fallisce"],
	["Tempesta di ghiaccio|ice storm", 4, "save", "DES", "2d10", "Contundente", true, "", 0, false, "1d10", "d2=4d6 Freddo", "Cilindro di 6 m; terreno difficile"],
	["Muro di fuoco|wall of fire", 4, "save", "DES", "5d8", "Fuoco", true, "", 0, true, "1d8", "", ""],
	["Esilio|banishment", 4, "save", "CAR", "", "", false, "Incapacitato", 1, true, "", "upn", "Bandito in un semipiano"],
	["Cono di freddo|cone of cold", 5, "save", "COS", "8d8", "Freddo", true, "", 0, false, "1d8", "", "Cono di 18 m"],
	["Colpo infuocato|colpo di fiamma|flame strike", 5, "save", "DES", "5d6", "Fuoco", true, "", 0, false, "1d6", "d2=5d6 Radioso", "Cilindro di 3 m"],
	["Cura ferite di massa|mass cure wounds", 5, "heal", "", "5d8", "", false, "", 6, false, "1d8", "mod", ""],
	["Blocca mostri|hold monster", 5, "save", "SAG", "", "", false, "Paralizzato", 1, true, "", "upn", "Ripete il TS alla fine di ogni suo turno"],
]

## Words of the damage types as they appear in stat blocks (plural too).
const TYPE_WORDS := [["acid", "Acido"], ["contundent", "Contundente"], ["forza", "Forza"], ["fredd", "Freddo"],
	["fulmin", "Fulmine"], ["fuoc", "Fuoco"], ["necrotic", "Necrotico"], ["perforant", "Perforante"],
	["psichic", "Psichico"], ["radios", "Radioso"], ["taglient", "Tagliente"], ["tuon", "Tuono"], ["velen", "Veleno"]]

## Damage type of a weapon from its name.
const WEAPON_TYPES := [
	["Tagliente", ["spad", "scimitarr", "ascia", "falc", "alabard", "squarci", "artigl", "lama", "frust", "sciabol"]],
	["Perforante", ["mors", "lancia", "pugnal", "arco", "balestr", "frecc", "dard", "giavellott", "stocc", "tridente", "picc", "corno", "pungigl", "zanne", "pistol", "moschett"]],
	["Contundente", ["presa", "pseudopod", "mazz", "randell", "martell", "schiant", "bastone", "pugno", "fionda", "clava", "maglio", "coda", "senz'armi", "calci"]]]

const RANGED_WORDS := ["arco", "balestr", "fionda", "pistol", "moschett", "giavellott", "dard", "lancio", "rete"]

## Conditions that a hit or a failed save can impose, by the word used in stat blocks.
const COND_WORDS := [["paralizzat", "Paralizzato"], ["trattenut", "Trattenuto"], ["pron", "Prono"], ["afferrat", "Afferrato"],
	["avvelenat", "Avvelenato"], ["spaventat", "Spaventato"], ["accecat", "Accecato"], ["stordit", "Stordito"],
	["affascinat", "Affascinato"], ["incapacitat", "Incapacitato"], ["assordat", "Assordato"], ["pietrificat", "Pietrificato"]]

static var _re_attack := RegEx.create_from_string("(?i)([a-zà-ù' ]+?)\\s*\\+(\\d+)\\s*(?:\\([^)]*\\))?\\s*,\\s*(\\d+d\\d+(?:\\s*[+-]\\s*\\d+)?)(?:\\s+(acid\\w*|contundent\\w*|forza|fredd\\w*|fulmin\\w*|fuoco|necrotic\\w*|perforant\\w*|psichic\\w*|radios\\w*|taglient\\w*|tuono|velen\\w*))?(?:\\s*\\+\\s*(\\d+d\\d+)\\s+([a-zà-ù]+))?")
static var _re_save := RegEx.create_from_string("TS (For|Des|Cos|Int|Sag|Car) CD (\\d+)(?!\\s*\\+)")
static var _re_dice := RegEx.create_from_string("(\\d+)d(\\d+)(?:\\s*([+-])\\s*(\\d+))?")
static var _re_multi := RegEx.create_from_string("(?i)\\b(due|tre|quattro) attacchi")
static var _re_spell_dc := RegEx.create_from_string("(?i)incantesimi[^.]*?CD (\\d+)")
static var _re_terms := RegEx.create_from_string("([+-]?)(\\d+)(?:d(\\d+))?")
static var _re_cap := RegEx.create_from_string("([A-ZÀ-Ù][a-zà-ù' ]*)\\s*$")
static var _re_recharge := RegEx.create_from_string("\\(([^)]*ricarica[^)]*)\\)")


# ----------------------------------------------------------------- helpers
static func norm(s: String) -> String:
	var t := s.to_lower().strip_edges()
	for p in [["à", "a"], ["è", "e"], ["é", "e"], ["ì", "i"], ["ò", "o"], ["ù", "u"], ["’", "'"]]:
		t = t.replace(p[0], p[1])
	return t


static func type_of_word(w: String) -> String:
	var t := norm(w)
	if t == "":
		return ""
	for p in TYPE_WORDS:
		if t.begins_with(p[0]):
			return p[1]
	return ""


static func weapon_type(name: String) -> String:
	var t := norm(name)
	for g in WEAPON_TYPES:
		for w in g[1]:
			if t.contains(w):
				return g[0]
	return ""


static func is_ranged(name: String) -> bool:
	var t := norm(name)
	for w in RANGED_WORDS:
		if t.contains(w):
			return true
	return false


static func cond_of_word(text: String) -> String:
	var t := norm(text)
	for p in COND_WORDS:
		if t.contains(p[0]):
			return p[1]
	return ""


static func has_cond(e: Dictionary, cond: String) -> bool:
	for p in str(e.get("conditions", "")).split(","):
		if p.strip_edges().to_lower() == cond.to_lower():
			return true
	return false


## "2d6+3" -> {dice: [[2, 6]], mod: 3}. Several terms are allowed ("1d8+1d6+2").
static func parse_dice(s: String) -> Dictionary:
	var out := {"dice": [], "mod": 0}
	var txt := s.replace(" ", "").to_lower()
	for m in _re_terms.search_all(txt):
		var sign := -1 if m.get_string(1) == "-" else 1
		if m.get_string(3) != "":
			out.dice.append([mini(int(m.get_string(2)), 100), maxi(1, int(m.get_string(3)))])
		else:
			out.mod += sign * int(m.get_string(2))
	return out


## Adds `extra` dice (e.g. "1d6") `times` times to `base` ("8d6" + 2x"1d6" = "10d6").
static func add_dice(base: String, extra: String, times: int) -> String:
	if extra == "" or times <= 0:
		return base
	var b := parse_dice(base)
	var e := parse_dice(extra)
	for d in e.dice:
		var merged := false
		for bd in b.dice:
			if int(bd[1]) == int(d[1]):
				bd[0] = int(bd[0]) + int(d[0]) * times
				merged = true
		if not merged:
			b.dice.append([int(d[0]) * times, int(d[1])])
	b.mod += int(e.mod) * times
	return dice_text(b)


static func dice_text(p: Dictionary) -> String:
	var parts: Array = []
	for d in p.dice:
		parts.append("%dd%d" % [int(d[0]), int(d[1])])
	var s := "+".join(parts)
	if int(p.mod) != 0 or s == "":
		s += ("%+d" % int(p.mod)) if s != "" else str(int(p.mod))
	return s


## Rolls a formula; `crit` doubles the dice. Returns {total, dice: [{s, v}], mod}.
static func roll(rng: RandomNumberGenerator, formula: String, crit := false) -> Dictionary:
	var p := parse_dice(formula)
	var dice: Array = []
	var total := int(p.mod)
	for d in p.dice:
		var n := int(d[0]) * (2 if crit else 1)
		for i in n:
			var v := rng.randi_range(1, int(d[1]))
			dice.append({"s": int(d[1]), "v": v})
			total += v
	return {"total": maxi(0, total), "dice": dice, "mod": int(p.mod)}


# ----------------------------------------------------------- action lists
static func blank_action() -> Dictionary:
	return {"name": "Azione personalizzata", "group": "Personalizzata", "mode": "attack", "bonus": 4, "dc": 13,
		"save": "DES", "dmg": "1d6+2", "type": "", "dmg2": "", "type2": "", "half": true, "cond": "",
		"times": 1, "targets": 1, "lvl": -1, "upcast": "", "up_times": false, "up_targets": false,
		"conc": false, "ranged": false, "drain": false, "hit_save": {}, "note": "", "spell_idx": -1}


static func find_spell(name: String) -> Array:
	var n := norm(name)
	if n == "":
		return []
	for sp in SPELLS:
		for alias in str(sp[0]).split("|"):
			if norm(alias) == n:
				return sp
	if n.length() < 8:
		return []
	for sp in SPELLS:
		for alias in str(sp[0]).split("|"):
			var a := norm(alias)
			if a.length() >= 8 and (n.contains(a) or a.contains(n)):
				return sp
	return []


## Action of a spell, for a caster of `level` with spell attack bonus `atk`,
## save DC `dc` and spellcasting ability modifier `ab_mod`.
static func spell_action(sp: Array, shown_name: String, level: int, atk: int, dc: int, ab_mod: int) -> Dictionary:
	var a := blank_action()
	var flags := str(sp[11])
	a.name = shown_name
	a.group = "Incantesimi"
	a.lvl = int(sp[1])
	a.mode = str(sp[2])
	a.save = str(sp[3]) if str(sp[3]) != "" else "DES"
	a.dmg = str(sp[4])
	a.type = str(sp[5])
	a.half = bool(sp[6])
	a.cond = str(sp[7])
	a.targets = int(sp[8])
	a.conc = bool(sp[9])
	a.upcast = str(sp[10])
	a.note = str(sp[12])
	a.bonus = atk
	a.dc = dc
	a.ranged = not flags.contains("touch")
	a.drain = flags.contains("drain")
	a.up_times = flags.contains("upt")
	a.up_targets = flags.contains("upn")
	if flags.contains("times3"):
		a.times = 3
	var tier := 1 + int(level >= 5) + int(level >= 11) + int(level >= 17)
	if flags.contains("scale") and str(a.dmg) != "":
		var p := parse_dice(a.dmg)
		for d in p.dice:
			d[0] = int(d[0]) * tier
		a.dmg = dice_text(p)
	if flags.contains("beams"):
		a.times = tier
		a.targets = 0
	if flags.contains("mod") and ab_mod != 0:
		a.dmg = str(a.dmg) + ("%+d" % ab_mod)
	var d2 := flags.find("d2=")
	if d2 >= 0:
		var rest := flags.substr(d2 + 3).split(" ")
		a.dmg2 = rest[0]
		a.type2 = rest[1] if rest.size() > 1 else ""
	return a


## Everything a combatant can do: weapon attacks and spells of a character,
## attacks and special abilities read from a monster's notes. A blank custom
## action is always last.
static func list_for(st, id: String) -> Array:
	var e: Dictionary = st.find_entity(id)
	var out: Array = []
	if e.is_empty():
		return [blank_action()]
	if st.is_pc(id):
		for at in e.get("attacks", []):
			var a := blank_action()
			a.name = str(at.name)
			a.group = "Attacchi"
			a.bonus = int(at.bonus)
			a.dmg = str(at.damage)
			a.type = weapon_type(a.name)
			a.ranged = is_ranged(a.name)
			out.append(a)
		var nums: Array = Rules.spell_numbers(e)
		var atk := int(nums[1]) if nums.size() > 0 else int(e.get("prof", 2))
		var dc := int(nums[0]) if nums.size() > 0 else 8 + int(e.get("prof", 2))
		var ab_mod := atk - int(e.get("prof", 2))
		var spells: Array = e.get("spells", [])
		for i in spells.size():
			var s: Dictionary = spells[i]
			var sp := find_spell(str(s.name))
			var a: Dictionary
			if sp.is_empty():
				a = blank_action()
				a.name = str(s.name)
				a.group = "Incantesimi"
				a.mode = "effect"
				a.lvl = int(s.lvl)
				a.note = "Incantesimo non in archivio: gli effetti vanno applicati a mano (lo slot viene speso)"
			else:
				a = spell_action(sp, str(s.name), int(e.get("level", 1)), atk, dc, ab_mod)
				a.lvl = maxi(int(s.lvl), int(sp[1])) if int(sp[1]) > 0 else 0
			a.spell_idx = i
			out.append(a)
	else:
		out.append_array(parse_monster(str(e.get("notes", ""))))
	out.append(blank_action())
	return out


## Attacks and abilities written in a monster's notes, in the style of the
## ready-made stat blocks: "Scimitarra +4, 1d6+2; arco corto +4, 1d6+2",
## "Soffio di fuoco (ricarica 5-6): cono 4,5 m, 7d6, TS Des CD 13",
## "Artigli +4, 1d4+2: TS Cos CD 10 o paralizzato".
static func parse_monster(notes: String) -> Array:
	var out: Array = []
	var multi := 1
	var mm := _re_multi.search(notes)
	if mm:
		multi = int({"due": 2, "tre": 3, "quattro": 4}[mm.get_string(1).to_lower()])
	for seg in notes.replace("\n", ". ").split(";"):
		for sent in seg.split(". "):
			var am := _re_attack.search(sent)
			if am:
				var a := blank_action()
				var nm := am.get_string(1).strip_edges()
				var times := multi
				# "Due morsi +4, ..." = two attacks of that kind
				var cnt := RegEx.create_from_string("(?i)^(due|tre|quattro) ").search(nm)
				if cnt:
					times = int({"due": 2, "tre": 3, "quattro": 4}[cnt.get_string(1).to_lower()])
				a.name = (nm.left(1).to_upper() + nm.substr(1)) if nm != "" else "Attacco"
				a.group = "Attacchi"
				a.bonus = int(am.get_string(2))
				a.dmg = am.get_string(3).replace(" ", "")
				a.type = type_of_word(am.get_string(4))
				if a.type == "":
					a.type = weapon_type(nm)
				if am.get_string(5) != "":
					a.dmg2 = am.get_string(5)
					a.type2 = type_of_word(am.get_string(6))
				a.ranged = is_ranged(nm) and not norm(nm).contains(" o ")
				a.times = times
				var tail := sent.substr(am.get_end())
				var sm := _re_save.search(tail)
				if sm:
					var c := cond_of_word(tail.substr(sm.get_end()))
					a.hit_save = {"save": sm.get_string(1).to_upper(), "dc": int(sm.get_string(2)), "cond": c}
				else:
					var c2 := cond_of_word(tail)
					if c2 in ["Prono", "Afferrato", "Trattenuto", "Avvelenato"]:
						a.cond = c2
						a.note = tail.strip_edges().trim_prefix(",").strip_edges().left(120)
				out.append(a)
				continue
			var sm2 := _re_save.search(sent)
			if sm2 and not sent.contains("0 PF"):
				var a := blank_action()
				var cut := sent.find("(")
				if cut < 0:
					cut = sent.find(":")
				var head := sent.left(cut) if cut >= 0 else sent
				var words := _re_cap.search(head.strip_edges())
				a.name = words.get_string(1).strip_edges() if words else head.strip_edges().left(30)
				if a.name == "":
					a.name = "Capacità speciale"
				a.group = "Speciali"
				a.mode = "save"
				a.save = sm2.get_string(1).to_upper()
				a.dc = int(sm2.get_string(2))
				var dm := _re_dice.search(sent)
				a.dmg = dm.get_string(0).replace(" ", "") if dm else ""
				a.type = ""
				for w in sent.replace(",", " ").replace(")", " ").replace(":", " ").split(" "):
					var t := type_of_word(w)
					if t != "" and t != "Forza":
						a.type = t
						break
				a.half = a.dmg != ""
				a.cond = cond_of_word(sent.substr(sm2.get_end()))
				var low := norm(sent)
				a.targets = 0 if (low.contains("cono") or low.contains("linea") or low.contains("sfera") or low.contains("cubo")) else 1
				var rec := _re_recharge.search(sent)
				a.note = (rec.get_string(1).left(1).to_upper() + rec.get_string(1).substr(1)) if rec else ""
				out.append(a)
	# monsters that cast spells: "Incantesimi CD 14: palla di fuoco e invisibilità"
	var sdc := _re_spell_dc.search(notes)
	if sdc:
		var dc := int(sdc.get_string(1))
		var low := norm(notes)
		for sp in SPELLS:
			for alias in str(sp[0]).split("|"):
				var al := norm(alias)
				if al.length() >= 5 and low.contains(al):
					var a := spell_action(sp, str(sp[0]).get_slice("|", 0), 5, dc - 8, dc, 0)
					a.lvl = -1  # no slots: uses per day are tracked by the master
					out.append(a)
					break
	return out


# -------------------------------------------------------------- resolution
## Advantage from conditions (PHB 2024). Returns [state, reasons]:
## state 1 = advantage, -1 = disadvantage, 0 = normal.
static func auto_adv(attacker: Dictionary, target: Dictionary, ranged: bool) -> Array:
	var adv := false
	var dis := false
	var why: Array = []
	for c in ["Accecato", "Avvelenato", "Prono", "Spaventato", "Trattenuto"]:
		if has_cond(attacker, c):
			dis = true
			why.append("attaccante %s" % c.to_lower())
	if has_cond(attacker, "Invisibile"):
		adv = true
		why.append("attaccante invisibile")
	for c in ["Accecato", "Paralizzato", "Pietrificato", "Privo di sensi", "Stordito", "Trattenuto"]:
		if has_cond(target, c):
			adv = true
			why.append("bersaglio %s" % c.to_lower())
	if has_cond(target, "Prono"):
		if ranged:
			dis = true
			why.append("bersaglio prono, a distanza")
		else:
			adv = true
			why.append("bersaglio prono")
	if has_cond(target, "Invisibile"):
		dis = true
		why.append("bersaglio invisibile")
	var s := 0
	if adv and not dis:
		s = 1
	elif dis and not adv:
		s = -1
	return [s, why]


## Saving throw bonus. Monsters have no ability scores in this app: Dexterity
## uses the initiative modifier, the rest +0.
static func save_bonus(st, id: String, ab: String) -> int:
	var e: Dictionary = st.find_entity(id)
	if st.is_pc(id):
		return Rules.save_mod(e, ab)
	return int(e.get("init_mod", 0)) if ab == "DES" else 0


static func _auto_fail(e: Dictionary, ab: String) -> bool:
	if ab != "FOR" and ab != "DES":
		return false
	for c in ["Paralizzato", "Pietrificato", "Privo di sensi", "Stordito"]:
		if has_cond(e, c):
			return true
	return false


## Returns [kept d20, dice for the log].
static func _d20(rng: RandomNumberGenerator, adv: int) -> Array:
	var a := rng.randi_range(1, 20)
	if adv == 0:
		return [a, [{"s": 20, "v": a}]]
	var b := rng.randi_range(1, 20)
	var keep := maxi(a, b) if adv > 0 else mini(a, b)
	var drop_a := a != keep
	return [keep, [{"s": 20, "v": a, "drop": drop_a}, {"s": 20, "v": b, "drop": not drop_a}]]


static func _adv_name(adv: int) -> String:
	return "adv" if adv > 0 else ("dis" if adv < 0 else "none")


static func _who_type(st, id: String) -> String:
	return "pc" if st.is_pc(id) else "monster"


## Performs the action. opts: {adv: "auto"|"adv"|"none"|"dis", slot: int}.
## Returns {ok, error, lines: [String]}. Everything is applied to the state
## and written to the roll log, so phones and the shared screen see it.
static func resolve(st, actor_id: String, a: Dictionary, targets: Array, opts := {}) -> Dictionary:
	var actor: Dictionary = st.find_entity(actor_id)
	if actor.is_empty():
		return {"ok": false, "error": "Chi agisce non esiste più", "lines": []}
	var tg: Array = []
	for t in targets:
		if not st.find_entity(str(t)).is_empty():
			tg.append(str(t))
	if tg.is_empty():
		return {"ok": false, "error": "Scegli almeno un bersaglio", "lines": []}
	var mode := str(a.get("mode", "attack"))
	var lines: Array = []
	var aname := str(actor.name)
	var title := str(a.name)
	var dmg := str(a.get("dmg", ""))
	var dmg2 := str(a.get("dmg2", ""))
	var times := maxi(1, int(a.get("times", 1)))
	# spell slot
	var lvl := int(a.get("lvl", -1))
	if lvl >= 1 and st.is_pc(actor_id):
		var slot := clampi(int(opts.get("slot", lvl)), lvl, 9)
		Rules.sync_slots(actor)
		if int(actor.slots_used[slot - 1]) >= int(actor.slots_max[slot - 1]):
			return {"ok": false, "error": "%s non ha slot di %d° livello liberi" % [aname, slot], "lines": []}
		st.use_slot(actor_id, slot, 1)
		var extra := slot - lvl
		dmg = add_dice(dmg, str(a.get("upcast", "")), extra)
		if bool(a.get("up_times", false)):
			times += extra
		lines.append("%s lancia %s con uno slot di %d° livello" % [aname, title, slot])
	elif lvl == 0:
		lines.append("%s lancia %s (trucchetto)" % [aname, title])
	else:
		lines.append("%s usa %s" % [aname, title])
	if bool(a.get("conc", false)):
		var old := str(actor.get("concentration", ""))
		if old != "":
			lines.append("%s smette di concentrarsi su %s" % [aname, old])
		actor["concentration"] = title
	var forced: int = int({"adv": 1, "dis": -1, "none": 0}.get(str(opts.get("adv", "auto")), 99))
	match mode:
		"attack":
			var ranged := bool(a.get("ranged", false))
			for i in times:
				var tid: String = tg[i % tg.size()]
				var t: Dictionary = st.find_entity(tid)
				var aa := auto_adv(actor, t, ranged)
				var adv: int = int(aa[0]) if forced == 99 else forced
				var r := _d20(st.rng, adv)
				var nat: int = r[0]
				var total: int = nat + int(a.bonus)
				var ac := int(t.get("ac", 10))
				var hit := nat == 20 or (nat != 1 and total >= ac)
				var crit := nat == 20
				if hit and not ranged and (has_cond(t, "Paralizzato") or has_cond(t, "Privo di sensi")):
					crit = true
				var res_txt := "CRITICO" if crit else ("colpito" if hit else "mancato")
				st.add_roll({"who": aname, "who_id": actor_id, "who_type": _who_type(st, actor_id),
					"kind": "Attacco", "dice": r[1], "mod": int(a.bonus), "adv": _adv_name(adv),
					"reason": "%s contro %s: %s" % [title, t.name, res_txt], "formula": "1d20%+d" % int(a.bonus)}, false)
				var line := "%s%s contro %s: %d (%d%+d) vs CA %d, %s" % [title, (" #%d" % (i + 1)) if times > 1 else "", t.name, total, nat, int(a.bonus), ac, res_txt]
				if nat == 1:
					line += " (1 naturale)"
				if adv != 0:
					line += " - %s" % ("vantaggio" if adv > 0 else "svantaggio")
					if forced == 99 and not aa[1].is_empty():
						line += " (%s)" % ", ".join(aa[1])
				lines.append(line)
				if not hit:
					continue
				var dealt := _deal(st, actor_id, tid, dmg, str(a.get("type", "")), crit, lines, title)
				if dmg2 != "":
					dealt += _deal(st, actor_id, tid, dmg2, str(a.get("type2", "")), crit, lines, title)
				if bool(a.get("drain", false)) and dealt > 0:
					st.change_hp(actor_id, int(dealt / 2))
					lines.append("   %s recupera %d PF" % [aname, int(dealt / 2)])
				if str(a.get("cond", "")) != "":
					_apply_conds(st, tid, str(a.cond), lines)
				var hs: Dictionary = a.get("hit_save", {})
				if not hs.is_empty():
					_save(st, tid, str(hs.save), int(hs.dc), "", false, str(hs.get("cond", "")), title, lines, 0)
		"save":
			var shared: Dictionary = roll(st.rng, dmg) if dmg != "" else {}
			var shared2: Dictionary = roll(st.rng, dmg2) if dmg2 != "" else {}
			if dmg != "":
				var all_dice: Array = shared.dice.duplicate()
				if dmg2 != "":
					all_dice.append_array(shared2.dice)
				st.add_roll({"who": aname, "who_id": actor_id, "who_type": _who_type(st, actor_id), "kind": "Danni",
					"dice": all_dice, "mod": int(shared.mod) + int(shared2.get("mod", 0)), "reason": title,
					"formula": dmg + ((" + " + dmg2) if dmg2 != "" else "")}, false)
				var dl := "Danni tirati: %d (%s%s)" % [int(shared.total), dmg, (" " + str(a.type).to_lower()) if str(a.get("type", "")) != "" else ""]
				if dmg2 != "":
					dl += " + %d (%s %s)" % [int(shared2.total), dmg2, str(a.get("type2", "")).to_lower()]
				if bool(a.get("half", false)):
					dl += ", metà a chi supera il TS"
				lines.append(dl)
			for tid in tg:
				_save(st, tid, str(a.save), int(a.dc), str(a.get("type", "")), bool(a.get("half", false)), str(a.get("cond", "")),
					title, lines, int(shared.get("total", 0)), str(a.get("type2", "")), int(shared2.get("total", 0)))
		"auto":
			for i in times:
				var tid: String = tg[i % tg.size()]
				_deal(st, actor_id, tid, dmg, str(a.get("type", "")), false, lines, title + ((" #%d" % (i + 1)) if times > 1 else ""))
				if dmg2 != "":
					_deal(st, actor_id, tid, dmg2, str(a.get("type2", "")), false, lines, title)
				if str(a.get("cond", "")) != "":
					_apply_conds(st, tid, str(a.cond), lines)
		"heal":
			for tid in tg:
				var t: Dictionary = st.find_entity(tid)
				var r := roll(st.rng, dmg)
				var before := int(t.hp)
				st.change_hp(tid, int(r.total))
				st.add_roll({"who": aname, "who_id": actor_id, "who_type": _who_type(st, actor_id), "kind": "Libero",
					"dice": r.dice, "mod": int(r.mod), "reason": "%s su %s" % [title, t.name], "formula": dmg}, false)
				lines.append("%s recupera %d PF (%s): %d → %d" % [t.name, int(r.total), dmg, before, int(t.hp)])
		_:
			for tid in tg:
				if str(a.get("cond", "")) != "":
					_apply_conds(st, tid, str(a.cond), lines)
				else:
					lines.append("   Bersaglio: %s" % st.find_entity(tid).name)
	if str(a.get("note", "")) != "":
		lines.append("Nota: " + str(a.note))
	st.touch()
	return {"ok": true, "error": "", "lines": lines}


## One saving throw of a target. `rolled` = damage already rolled (shared by
## all targets of an area); half of it on a success when `half`.
static func _save(st, tid: String, ab: String, dc: int, dtype: String, half: bool, cond: String, title: String,
		lines: Array, rolled: int, dtype2 := "", rolled2 := 0) -> void:
	var t: Dictionary = st.find_entity(tid)
	if t.is_empty():
		return
	var ok := false
	var txt := ""
	if _auto_fail(t, ab):
		txt = "fallito in automatico (condizione)"
	else:
		var adv := -1 if (ab == "DES" and has_cond(t, "Trattenuto")) else 0
		var r := _d20(st.rng, adv)
		var bonus := save_bonus(st, tid, ab)
		var total: int = int(r[0]) + bonus
		ok = total >= dc
		st.add_roll({"who": t.name, "who_id": tid, "who_type": _who_type(st, tid), "kind": "Tiro salvezza",
			"dice": r[1], "mod": bonus, "dc": dc, "adv": _adv_name(adv), "reason": "%s contro %s" % [ABILITY_NAMES.get(ab, ab), title],
			"formula": "1d20%+d" % bonus}, false)
		txt = "%d (%d%+d) vs CD %d, %s" % [total, int(r[0]), bonus, dc, "riuscito" if ok else "fallito"]
	lines.append("%s - TS %s: %s" % [t.name, ABILITY_NAMES.get(ab, ab), txt])
	var amount := rolled
	var amount2 := rolled2
	if ok:
		amount = int(amount / 2) if half else 0
		amount2 = int(amount2 / 2) if half else 0
	if amount > 0:
		_apply_damage(st, tid, amount, dtype, lines)
	if amount2 > 0:
		_apply_damage(st, tid, amount2, dtype2, lines)
	if not ok and cond != "":
		_apply_conds(st, tid, cond, lines)


## Rolls and applies damage to one target. Returns the damage really dealt.
static func _deal(st, actor_id: String, tid: String, formula: String, dtype: String, crit: bool, lines: Array, title: String) -> int:
	if formula == "":
		return 0
	var t: Dictionary = st.find_entity(tid)
	var r := roll(st.rng, formula, crit)
	st.add_roll({"who": st.find_entity(actor_id).get("name", "?"), "who_id": actor_id, "who_type": _who_type(st, actor_id),
		"kind": "Danni", "dice": r.dice, "mod": int(r.mod), "reason": "%s su %s%s" % [title, t.name, " (critico)" if crit else ""],
		"formula": formula}, false)
	return _apply_damage(st, tid, int(r.total), dtype, lines, formula + (", dadi raddoppiati" if crit else ""))


static func _apply_damage(st, tid: String, amount: int, dtype: String, lines: Array, formula := "") -> int:
	var t: Dictionary = st.find_entity(tid)
	var before := int(t.hp)
	var r: Array = st.damage(tid, amount, dtype)
	var dealt := int(r[0])
	var txt := "   %s subisce %d danni%s" % [t.name, dealt, (" " + dtype.to_lower()) if dtype != "" else ""]
	if formula != "":
		txt += " (%s = %d)" % [formula, amount]
	if str(r[1]) != "":
		txt += ", %s" % r[1]
	txt += ": PF %d → %d" % [before, int(t.hp)]
	if int(t.hp) <= 0 and before > 0:
		txt += "  A TERRA!" if st.is_pc(tid) else "  SCONFITTO!"
	lines.append(txt)
	if dealt > 0:
		_concentration_check(st, tid, dealt, lines)
	return dealt


## Damage breaks concentration unless a Constitution save succeeds
## (DC 10 or half the damage, max 30); at 0 PF it ends anyway.
static func _concentration_check(st, tid: String, dealt: int, lines: Array) -> void:
	var t: Dictionary = st.find_entity(tid)
	var spell := str(t.get("concentration", ""))
	if spell == "":
		return
	if int(t.hp) <= 0:
		t.concentration = ""
		lines.append("   %s perde la concentrazione su %s (0 PF)" % [t.name, spell])
		return
	var dc := mini(30, maxi(10, int(dealt / 2)))
	var r := _d20(st.rng, 0)
	var bonus := save_bonus(st, tid, "COS")
	var total: int = int(r[0]) + bonus
	st.add_roll({"who": t.name, "who_id": tid, "who_type": _who_type(st, tid), "kind": "Tiro salvezza",
		"dice": r[1], "mod": bonus, "dc": dc, "reason": "Concentrazione su %s" % spell, "formula": "1d20%+d" % bonus}, false)
	if total >= dc:
		lines.append("   %s mantiene la concentrazione su %s (TS Cos %d vs CD %d)" % [t.name, spell, total, dc])
	else:
		t.concentration = ""
		lines.append("   %s perde la concentrazione su %s (TS Cos %d vs CD %d)" % [t.name, spell, total, dc])


static func _apply_conds(st, tid: String, conds: String, lines: Array) -> void:
	var t: Dictionary = st.find_entity(tid)
	for c in conds.split(","):
		var cc := c.strip_edges()
		if cc == "" or has_cond(t, cc):
			continue
		st.toggle_condition(tid, cc)
		lines.append("   %s ora è %s" % [t.name, cc.to_lower()])
