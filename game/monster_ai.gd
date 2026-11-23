class_name MonsterAI
## Rule-based monster turns for Dnd The Game: no AI model, works offline.
## Picks the action with the best expected damage, the target (wounded
## characters first, concentrating casters next), recharge abilities such as
## a dragon's breath, and when to run away.

const SKIP_CONDS := ["Paralizzato", "Pietrificato", "Privo di sensi", "Stordito", "Incapacitato"]
## Creatures that never flee: no mind, or no fear.
const FEARLESS := ["non morto", "zombi", "scheletr", "costrutto", "golem", "melma", "gelatina", "elementale",
	"demone", "diavolo", "drag", "capo", "boss", "re ", "regina"]

## Recharge state per monster and ability: "m12|Soffio di fuoco" -> true when spent.
static var spent: Dictionary = {}


static func reset() -> void:
	spent.clear()


## Average of a dice formula ("2d6+3" -> 10).
static func avg(formula: String) -> float:
	if formula.strip_edges() == "":
		return 0.0
	var p := Actions.parse_dice(formula)
	var tot := float(p.get("mod", 0))
	for d in p.get("dice", []):
		tot += float(d[0]) * (float(d[1]) + 1.0) / 2.0
	return maxf(0.0, tot)


## Chance that +bonus hits armour class ac (natural 1 misses, 20 hits).
static func hit_chance(bonus: int, ac: int) -> float:
	return clampf((21.0 + bonus - ac) / 20.0, 0.05, 0.95)


## "ricarica 5-6" in the ability text -> 5; 0 when the ability has no recharge.
static func recharge_min(a: Dictionary) -> int:
	var txt := Actions.norm(str(a.get("note", "")) + " " + str(a.get("name", "")))
	var m := RegEx.create_from_string("ricarica ([1-6])").search(txt)
	return int(m.get_string(1)) if m else 0


static func fearless(m: Dictionary) -> bool:
	var txt := " " + Actions.norm(str(m.get("name", "")) + " " + str(m.get("kind", "")) + " " + str(m.get("notes", ""))) + " "
	for w in FEARLESS:
		if txt.contains(w):
			return true
	return false


## Characters the monster can fight: in combat and still standing.
static func foes(st) -> Array:
	var out: Array = []
	for c in st.ini().combatants:
		if c.type != "pc":
			continue
		var e: Dictionary = st.find_entity(str(c.ref))
		if not e.is_empty() and int(e.hp) > 0:
			out.append(str(c.ref))
	return out


## Monsters in combat still standing.
static func allies_up(st) -> int:
	var n := 0
	for c in st.ini().combatants:
		if c.type == "monster":
			var e: Dictionary = st.find_entity(str(c.ref))
			if not e.is_empty() and int(e.hp) > 0:
				n += 1
	return n


## Usable actions: attacks and damaging or hindering abilities.
static func usable(st, mid: String) -> Array:
	var out: Array = []
	for a in Actions.list_for(st, mid):
		if a.group == "Personalizzata":
			continue
		if not str(a.mode) in ["attack", "save"]:
			continue
		if recharge_min(a) > 0 and spent.get(mid + "|" + str(a.name), false):
			continue
		out.append(a)
	return out


## Improvised attack for monsters whose notes list no attacks.
static func fallback_attack(m: Dictionary) -> Dictionary:
	var a := Actions.blank_action()
	a.name = "Attacco"
	a.group = "Attacchi"
	var hp := int(m.get("hp_max", 7))
	a.bonus = 3 + int(hp >= 30) + int(hp >= 80)
	a.dmg = "1d6+1" if hp < 30 else ("2d6+3" if hp < 80 else "2d10+4")
	return a


## Expected damage of an action against the chosen targets.
static func value_of(st, a: Dictionary, targets: Array) -> float:
	var v := 0.0
	var base := avg(str(a.get("dmg", ""))) + avg(str(a.get("dmg2", "")))
	if str(a.mode) == "attack":
		for i in maxi(1, int(a.times)):
			var t: Dictionary = st.find_entity(str(targets[i % targets.size()]))
			v += base * hit_chance(int(a.bonus), int(t.get("ac", 12)))
		if not a.get("hit_save", {}).is_empty() or str(a.get("cond", "")) != "":
			v += 2.0
	else:
		var half := 0.75 if bool(a.get("half", true)) else 0.5
		v = base * half * targets.size()
		if str(a.get("cond", "")) != "":
			v += 4.0 * targets.size()
	return v


## Order of preference among the characters: wounded ones first (finish them),
## then casters holding concentration, then lower armour; a pinch of chance.
static func rank_targets(st, rng: RandomNumberGenerator, ids: Array) -> Array:
	var scored: Array = []
	for id in ids:
		var e: Dictionary = st.find_entity(id)
		var s := 2.0 * (1.0 - float(e.hp) / maxf(1.0, float(e.hp_max)))
		if str(e.get("concentration", "")) != "":
			s += 0.8
		s -= float(e.get("ac", 12)) / 25.0
		s += rng.randf() * 0.9
		scored.append([s, id])
	scored.sort_custom(func(x, y): return x[0] > y[0])
	return scored.map(func(x): return x[1])


## Decides the monster's turn. Returns one of:
##   {kind: "skip", why}
##   {kind: "flee", why}
##   {kind: "act", action, targets, why}
static func choose(st, mid: String, rng: RandomNumberGenerator) -> Dictionary:
	var m: Dictionary = st.find_entity(mid)
	if m.is_empty() or int(m.get("hp", 0)) <= 0:
		return {"kind": "skip", "why": "a terra"}
	for c in SKIP_CONDS:
		if Actions.has_cond(m, c):
			return {"kind": "skip", "why": c.to_lower()}
	var ids := foes(st)
	if ids.is_empty():
		return {"kind": "skip", "why": "nessun nemico in piedi"}
	# recharge rolls at the start of the turn (d6)
	for a in Actions.list_for(st, mid):
		var key := mid + "|" + str(a.name)
		var rmin := recharge_min(a)
		if rmin > 0 and spent.get(key, false) and rng.randi_range(1, 6) >= rmin:
			spent[key] = false
	var ratio := float(m.hp) / maxf(1.0, float(m.hp_max))
	if ratio <= 0.25 and not fearless(m):
		var chance := 0.35 + (0.35 if allies_up(st) <= 1 else 0.0)
		if rng.randf() < chance:
			return {"kind": "flee", "why": "ferito gravemente"}
	var acts := usable(st, mid)
	if acts.is_empty():
		acts = [fallback_attack(m)]
	var order := rank_targets(st, rng, ids)
	var best: Dictionary = {}
	var best_t: Array = []
	var best_v := -1.0
	for a in acts:
		var t: Array
		if str(a.mode) == "save" and int(a.targets) == 0:
			# area: the characters are assumed close together, up to three caught
			t = order.slice(0, mini(3, order.size()))
		else:
			var n := maxi(1, int(a.targets)) if str(a.mode) == "save" else 1
			t = order.slice(0, mini(n, order.size()))
		var v := value_of(st, a, t) * (0.9 + rng.randf() * 0.2)
		if v > best_v:
			best_v = v
			best = a
			best_t = t
	if recharge_min(best) > 0:
		spent[mid + "|" + str(best.name)] = true
	var why := "colpisce chi è più ferito" if best_t.size() == 1 else "prende più bersagli possibile"
	return {"kind": "act", "action": best, "targets": best_t, "why": why}
