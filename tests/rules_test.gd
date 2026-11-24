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
	var v: Dictionary = st.player_view(a.id)
	ok = ok and v.chronicle.size() >= 4
	print("rules test: ", "OK" if ok else "FAIL", "  cond=", a.conditions, " chron=", v.chronicle.size())
	quit(0 if ok else 1)
