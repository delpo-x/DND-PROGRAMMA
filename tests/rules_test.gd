extends SceneTree
# Checks conditions, death saves, rests and XP on a throwaway state.

func _init() -> void:
	var st := GameState.new()
	st.persist = false
	st.new_campaign("Test")
	var a: Dictionary = st.add_character("Aria", "")
	var b: Dictionary = st.add_character("Bruno", "")
	st.toggle_condition(a.id, "Prono")
	st.toggle_condition(a.id, "Avvelenato")
	st.toggle_condition(a.id, "Prono")
	var ok := str(a.conditions) == "Avvelenato"
	st.change_hp(a.id, -10)  # 10 PF -> 0: a terra (non morte sul colpo)
	st.death_save(a.id, 12)
	st.death_save(a.id, 1)
	ok = ok and int(a.death_ok) == 1 and int(a.death_ko) == 2
	st.death_save(a.id, 20)
	ok = ok and int(a.hp) == 1
	st.award_xp(300, "test")
	ok = ok and int(b.xp) == 150 and int(st.data.xp_total) == 300
	st.rest(true)
	ok = ok and int(a.hp) == int(a.hp_max)
	var m: Dictionary = st.add_monster({"name": "Goblin"})
	st.toggle_condition(m.id, "Prono")
	ok = ok and str(m.conditions) == "Prono"
	var sk: Dictionary = st.add_monster({"name": "Scheletro", "hp": 13, "vuln": "Contundente", "immune": "Veleno", "resist": "Fuoco"})
	ok = ok and int(st.damage(sk.id, 4, "Contundente")[0]) == 8 and int(sk.hp) == 5
	ok = ok and int(st.damage(sk.id, 9, "Veleno")[0]) == 0 and int(st.damage(sk.id, 5, "Fuoco")[0]) == 2 and int(sk.hp) == 3
	st.give_temp_hp(sk.id, 5)
	st.give_temp_hp(sk.id, 3)
	st.change_hp(sk.id, -6)
	ok = ok and int(sk.hp_temp) == 0 and int(sk.hp) == 2
	st.update_character(b.id, {"resist": "Fuoco"})
	var hb := int(b.hp)
	ok = ok and int(st.damage(b.id, 7, "Fuoco")[0]) == 3 and int(b.hp) == hb - 3
	st.update_character(b.id, {"name": "Bruno"})
	ok = ok and str(b.resist) == "Fuoco"
	st.update_character(a.id, {"cls": "Maga", "level": 5})
	ok = ok and a.slots_max.slice(0, 3) == [4, 3, 2]
	st.use_slot(a.id, 3, 1)
	st.use_slot(a.id, 3, 1)
	st.use_slot(a.id, 3, 1)
	ok = ok and int(a.slots_used[2]) == 2
	st.update_character(b.id, {"cls": "Paladino", "level": 5})
	ok = ok and b.slots_max.slice(0, 2) == [4, 2]
	var w: Dictionary = st.add_character("Wren", "")
	st.update_character(w.id, {"cls": "Warlock", "level": 5})
	ok = ok and int(w.slots_max[2]) == 2
	st.use_slot(w.id, 3, 1)
	st.rest(false)
	ok = ok and int(w.slots_used[2]) == 0 and int(a.slots_used[2]) == 2
	st.rest(true)
	ok = ok and int(a.slots_used[2]) == 0
	st.update_character(a.id, {"spells": [{"name": "Palla di fuoco", "lvl": 3}, {"name": "Luce", "lvl": 0}, {"name": "", "lvl": 1}]})
	ok = ok and a.spells.size() == 2 and str(a.spells[0].name) == "Luce"
	ok = ok and st.cast_spell(a.id, 0).contains("trucchetto")
	ok = ok and st.cast_spell(a.id, 1) != "" and st.cast_spell(a.id, 1) != "" and st.cast_spell(a.id, 1) == ""
	ok = ok and int(Rules.spell_numbers(a)[0]) == 8 + int(a.prof) + Rules.mod(a.ab.INT) and int(a.prof) == Rules.prof_for(int(a.level))
	# 2024 rules: paladin slots from 1st level
	var c: Dictionary = st.add_character("Cleo", "")
	st.update_character(c.id, {"cls": "Paladino", "level": 1})
	ok = ok and int(c.slots_max[0]) == 2
	# damage at 0 PF = one failed death save, and it ends the stable state
	st.change_hp(c.id, -10)
	st.change_hp(c.id, -1)
	ok = ok and int(c.hp) == 0 and int(c.death_ko) == 1
	st.set_death(c.id, 3, 1)
	ok = ok and st.death_save(c.id, 15) == ""
	st.change_hp(c.id, -1)
	ok = ok and int(c.death_ok) == 0 and int(c.death_ko) == 2
	# long rest has no effect at 0 PF
	st.rest(true)
	ok = ok and int(c.hp) == 0 and int(c.death_ko) == 2
	# third failure: dead; no more death saves, no healing until reset
	st.change_hp(c.id, -1)
	ok = ok and st.is_dead(c) and st.death_save(c.id, 20) == ""
	st.change_hp(c.id, 5)
	ok = ok and int(c.hp) == 0
	st.set_death(c.id, 0, 0)
	st.change_hp(c.id, 5)
	ok = ok and int(c.hp) == 5 and int(c.death_ko) == 0
	# damage left after 0 PF >= PF maximum: instant death
	var dd: Dictionary = st.add_character("Dario", "")
	st.change_hp(dd.id, -(int(dd.hp) + int(dd.hp_max)))
	ok = ok and st.is_dead(dd)
	# initiative ties: same score keeps a fixed random order, highest score first
	var g1: Dictionary = st.add_monster({"name": "Goblin A"})
	var g2: Dictionary = st.add_monster({"name": "Goblin B"})
	st.combat_start([g1.id, g2.id, a.id])
	st.set_score_for_ref(g1.id, 12)
	st.set_score_for_ref(g2.id, 12)
	st.set_score_for_ref(a.id, 15)
	var order: Array = st.ini().combatants.map(func(x): return x.ref)
	st.sort_combatants()
	ok = ok and order[0] == a.id and order == st.ini().combatants.map(func(x): return x.ref)
	# encounter difficulty, 2024 rules: four level-5 characters have budgets
	# 2000 / 3000 / 4400; the monsters' XP is added without a multiplier
	var e := Rules.encounter_difficulty([5, 5, 5, 5], 1800 + 3 * 200)
	var e_ok: bool = e.budget == [2000, 3000, 4400] and e.name == "Moderata"
	e_ok = e_ok and Rules.encounter_difficulty([5, 5, 5, 5], 2000).name == "Bassa"
	e_ok = e_ok and Rules.encounter_difficulty([5, 5, 5, 5], 4401).name == "Oltre il limite"
	e_ok = e_ok and Rules.encounter_difficulty([1], 0).level == -1 and Rules.encounter_difficulty([], 500).level == -1
	e_ok = e_ok and Rules.encounter_difficulty([0, 25], 100).budget == [6450, 13275, 22100]
	e_ok = e_ok and Rules.fmt_thousands(155000) == "155.000" and Rules.fmt_thousands(900) == "900"
	# in the state: the ogre (450 PE) counts, the hand-made goblin (no PE) is
	# reported, a monster at 0 PF does not count
	var og: Dictionary = st.add_monster({"name": "Ogre", "hp": 68, "xp": 450})
	var dead: Dictionary = st.add_monster({"name": "Lupo", "hp": 11, "xp": 50})
	st.change_hp(dead.id, -20)
	var se: Dictionary = st.encounter([og.id, dead.id, m.id])
	e_ok = e_ok and int(se.xp) == 450 and int(se.unknown) == 1 and int(se.party) == st.characters().size()
	var ce: Dictionary = st.combat_encounter()
	e_ok = e_ok and int(ce.party) == 1 and int(ce.unknown) == 2
	print("encounter: ", "ok" if e_ok else "FAIL", " ", e, " ", se, " ", ce)
	ok = ok and e_ok
	# class resources: barbarian 3 rages at level 3, one back on a short rest,
	# all on a long rest; paladin pool 5 x level; custom resources by the master
	var bb: Dictionary = st.add_character("Brak", "")
	st.update_character(bb.id, {"cls": "Barbaro", "level": 3})
	var rr: Array = Rules.resources(bb)
	var r_ok: bool = rr.size() == 1 and rr[0].key == "rage" and int(rr[0].max) == 3
	r_ok = r_ok and st.use_resource(bb.id, "rage", 1) != "" and st.use_resource(bb.id, "rage", 1) != ""
	r_ok = r_ok and int(Rules.resources(bb)[0].used) == 2
	st.rest(false)
	r_ok = r_ok and int(Rules.resources(bb)[0].used) == 1
	st.set_custom_resources(bb.id, [{"name": "Bacchetta", "max": 7, "reset": "short"}, {"name": "", "max": 2}])
	r_ok = r_ok and Rules.resources(bb).size() == 2 and st.use_resource(bb.id, "c0", 9) != "" and int(Rules.resources(bb)[1].used) == 7
	st.rest(false)
	r_ok = r_ok and int(Rules.resources(bb)[1].used) == 0 and int(Rules.resources(bb)[0].used) == 0
	st.use_resource(bb.id, "rage", 3)
	st.rest(true)
	r_ok = r_ok and int(Rules.resources(bb)[0].used) == 0
	r_ok = r_ok and int(Rules.class_resources("Paladino", 4, {})[0].max) == 20
	r_ok = r_ok and int(Rules.class_resources("Bardo", 1, {"CAR": 16})[0].max) == 3
	r_ok = r_ok and Rules.class_resources("Guerriero", 9, {}).size() == 3 and Rules.class_resources("Ladro", 5, {}).is_empty()
	r_ok = r_ok and st.player_view(bb.id).me.resources.size() == 2 and not bb.has("resources")
	print("resources: ", "ok" if r_ok else "FAIL", " ", Rules.resources(bb))
	ok = ok and r_ok
	var v: Dictionary = st.player_view(a.id)
	ok = ok and v.chronicle.size() >= 4
	print("rules test: ", "OK" if ok else "FAIL", "  cond=", a.conditions, " chron=", v.chronicle.size())
	quit(0 if ok else 1)
