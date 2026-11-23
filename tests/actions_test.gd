extends SceneTree
# Combat actions: monster attacks read from notes, character attacks and
# spells, hit vs AC, saves with half damage, conditions, slots, concentration.
# godot --headless --path . -s tests/actions_test.gd

var fails := 0


func check(name: String, ok: bool, info = "") -> void:
	print(("ok   " if ok else "FAIL ") + name + " " + str(info))
	if not ok:
		fails += 1


func names(list: Array) -> Array:
	return list.map(func(a): return a.name)


func _init() -> void:
	# parsing of every ready-made monster
	for mm in Rules.MONSTERS:
		var acts := Actions.parse_monster(str(mm[6]))
		print("     %s -> %s" % [mm[0], acts.map(func(a): return "%s[%s %s %s %s%s%s x%d]" % [a.name, a.mode, a.bonus if a.mode == "attack" else "CD%d %s" % [a.dc, a.save], a.dmg, a.type,
			(" +" + a.dmg2 + " " + a.type2) if a.dmg2 != "" else "", (" cond " + a.cond) if a.cond != "" else "", a.times])])
		check("parsed %s" % mm[0], not acts.is_empty())
	var gob := Actions.parse_monster("Scimitarra +4, 1d6+2; arco corto +4, 1d6+2; +1d4 se l'attacco aveva vantaggio")
	check("goblin: two attacks", names(gob) == ["Scimitarra", "Arco corto"] and gob[0].type == "Tagliente" and gob[1].ranged, names(gob))
	var drag := Actions.parse_monster("Due attacchi: squarcio +6, 1d10+4 + 1d6 fuoco. Soffio di fuoco (ricarica 5-6): cono 4,5 m, 7d6, TS Des CD 13")
	check("dragon claw x2 with fire", drag[0].times == 2 and drag[0].dmg2 == "1d6" and drag[0].type2 == "Fuoco")
	check("dragon breath", drag[1].name == "Soffio di fuoco" and drag[1].mode == "save" and drag[1].dc == 13 and drag[1].dmg == "7d6" and drag[1].type == "Fuoco" and drag[1].targets == 0, drag[1])
	var ghoul := Actions.parse_monster("Due morsi +4, 1d6+2 + 1d6 necrotici. Artigli +4, 1d4+2: TS Cos CD 10 o paralizzato fino alla fine del suo turno successivo")
	check("ghoul: two bites", ghoul[0].times == 2 and ghoul[0].type == "Perforante", ghoul[0])
	check("ghoul claws paralyse on a failed save", ghoul[1].hit_save.get("cond", "") == "Paralizzato" and int(ghoul[1].hit_save.dc) == 10, ghoul[1].hit_save)
	var mage := Actions.parse_monster("Tre attacchi: scarica arcana +6, 3d8+3 forza. Incantesimi CD 14: palla di fuoco e invisibilità (2/giorno)")
	check("mage casts fireball", names(mage).has("Palla di fuoco") and mage[0].type == "Forza" and mage[0].times == 3, names(mage))

	# spells
	check("find spell by Italian and English name", not Actions.find_spell("Palla di Fuoco").is_empty() and not Actions.find_spell("Magic Missile").is_empty())
	check("no false match on short names", Actions.find_spell("Scudo della fede").is_empty())
	check("upcast dice", Actions.add_dice("8d6", "1d6", 2) == "10d6" and Actions.add_dice("2d8+3", "2d8", 1) == "4d8+3")
	var fb := Actions.spell_action(Actions.find_spell("dardo di fuoco"), "Dardo di fuoco", 5, 7, 15, 4)
	check("cantrip grows at 5th level", fb.dmg == "2d10", fb.dmg)

	var st := GameState.new()
	st.persist = false
	st.new_campaign("Test azioni")
	st.rng.seed = 42
	var wiz: Dictionary = st.add_character("Mira", "")
	st.update_character(wiz.id, {"cls": "Mago", "level": 5, "ab": {"INT": 18, "DES": 14, "COS": 14}, "saves": ["INT", "SAG"],
		"hp_max": 30, "hp": 30, "prof": 3, "attacks": [{"name": "Pugnale", "bonus": 5, "damage": "1d4+2"}],
		"spells": [{"name": "Palla di fuoco", "lvl": 3, "prep": true}, {"name": "Dardo incantato", "lvl": 1, "prep": true},
			{"name": "Blocca persone", "lvl": 2, "prep": true}, {"name": "Teletrasporto inventato", "lvl": 1, "prep": true}]})
	var g1: Dictionary = st.add_monster({"name": "Goblin 1", "ac": 15, "hp": 40, "init_mod": 2, "notes": "Scimitarra +4, 1d6+2"})
	var g2: Dictionary = st.add_monster({"name": "Goblin 2", "ac": 15, "hp": 40, "init_mod": 2, "notes": "Scimitarra +4, 1d6+2"})
	var skel: Dictionary = st.add_monster({"name": "Scheletro", "ac": 14, "hp": 40, "immune": "Veleno", "notes": "Spada corta +5, 1d6+3"})
	var acts := Actions.list_for(st, wiz.id)
	var by_name := {}
	for x in acts:
		by_name[x.name] = x
	check("wizard actions", by_name.size() == 6 and acts[0].name == "Pugnale" and acts[-1].name == "Azione personalizzata", names(acts))
	check("unknown spell kept as manual effect", by_name["Teletrasporto inventato"].mode == "effect")
	var fireball: Dictionary = by_name["Palla di fuoco"]
	check("fireball numbers from the sheet (CD 8+3+4)", fireball.dc == 15 and fireball.mode == "save" and fireball.half, fireball.dc)
	var hp_before := [int(g1.hp), int(g2.hp)]
	var res := Actions.resolve(st, wiz.id, fireball, [g1.id, g2.id], {"slot": 3})
	print("\n".join(res.lines))
	check("fireball hits both, slot 3 spent, 8d6", res.ok and int(g1.hp) < hp_before[0] and int(g2.hp) < hp_before[1] and int(wiz.slots_used[2]) == 1 and str(res.lines).contains("8d6"))
	check("no 4th level slot at 5th level", not Actions.resolve(st, wiz.id, fireball, [g1.id], {"slot": 4}).ok)
	var log_n: int = st.data.log.size()
	check("rolls written to the log", log_n >= 3, log_n)
	# magic missile: 3 darts + 1 for a 2nd level slot, always hit
	var hp_g1 := int(g1.hp)
	res = Actions.resolve(st, wiz.id, by_name["Dardo incantato"], [g1.id], {"slot": 2})
	print("\n".join(res.lines))
	check("magic missile 4 darts", res.ok and str(res.lines).count("1d4+1 =") == 4 and int(g1.hp) < hp_g1)
	# hold person: concentration + paralysed on a failed save
	g2.hp = 40
	for i in 20:
		if Actions.has_cond(g2, "Paralizzato"):
			break
		st.use_slot(wiz.id, 2, -1)
		Actions.resolve(st, wiz.id, by_name["Blocca persone"], [g2.id], {"slot": 2})
	check("hold person paralyses and needs concentration", Actions.has_cond(g2, "Paralizzato") and str(wiz.get("concentration", "")) == "Blocca persone")
	check("advantage against a paralysed target", Actions.auto_adv(skel, g2, false)[0] == 1)
	# a melee hit on a paralysed target is a critical hit
	var crit_seen := false
	for i in 30:
		g2.hp = 40
		var r := Actions.resolve(st, skel.id, Actions.list_for(st, skel.id)[0], [g2.id])
		if str(r.lines).contains("CRITICO"):
			crit_seen = true
			break
	check("melee hit on paralysed = critical", crit_seen)
	# no slots left
	wiz.slots_used = wiz.slots_max.duplicate()
	res = Actions.resolve(st, wiz.id, fireball, [g1.id], {"slot": 3})
	check("refused without slots", not res.ok and str(res.error).contains("slot"), res.error)
	# immunity
	var poison := Actions.blank_action()
	poison.mode = "auto"
	poison.dmg = "10"
	poison.type = "Veleno"
	var hp_sk := int(skel.hp)
	Actions.resolve(st, g1.id, poison, [skel.id])
	check("immune to poison", int(skel.hp) == hp_sk)
	# concentration ends at 0 PF
	wiz.hp = 30
	wiz.concentration = "Blocca persone"
	var big := Actions.blank_action()
	big.mode = "auto"
	big.dmg = "60"
	Actions.resolve(st, g1.id, big, [wiz.id])
	check("concentration ends at 0 PF", str(wiz.concentration) == "" and int(wiz.hp) == 0)
	# healing
	var cleric: Dictionary = st.add_character("Teo", "")
	st.update_character(cleric.id, {"cls": "Chierico", "level": 3, "ab": {"SAG": 16}, "spells": [{"name": "Parola guaritrice", "lvl": 1, "prep": true}]})
	var heal: Dictionary = Actions.list_for(st, cleric.id)[0]
	check("healing word 2d4+3", heal.dmg == "2d4+3" and heal.mode == "heal", heal.dmg)
	wiz.death_ko = 0
	res = Actions.resolve(st, cleric.id, heal, [wiz.id])
	check("healed from 0", int(wiz.hp) > 0, res.lines)
	check("no target refused", not Actions.resolve(st, cleric.id, heal, []).ok)

	# phone turn panel
	var p2 := GameState.new()
	p2.persist = false
	p2.new_campaign("Test telefono")
	p2.rng.seed = 5
	var hero: Dictionary = p2.add_character("Ugo", "")
	p2.update_character(hero.id, {"cls": "Mago", "level": 3, "ab": {"INT": 16}, "hp_max": 20, "hp": 20,
		"attacks": [{"name": "Spada lunga", "bonus": 5, "damage": "1d8+3"}],
		"spells": [{"name": "Dardo incantato", "lvl": 1, "prep": true}, {"name": "Sonno", "lvl": 1, "prep": false}]})
	var orc: Dictionary = p2.add_monster({"name": "Orco", "ac": 13, "hp": 30, "revealed": true, "notes": "Ascia +5, 1d12+3"})
	var spy: Dictionary = p2.add_monster({"name": "Ombra", "ac": 12, "hp": 10, "revealed": false})
	p2.combat_start([hero.id, orc.id, spy.id])
	while str(p2.current_combatant().get("ref", "")) != orc.id:
		p2.next_turn()
	check("no panel when it's not my turn", Actions.phone_turn(p2, hero.id).is_empty() and p2.player_view(hero.id).turn.is_empty())
	check("refused off turn", not Actions.phone_act(p2, hero.id, {"i": 0, "name": "Spada lunga", "targets": [orc.id]}).ok)
	while str(p2.current_combatant().get("ref", "")) != hero.id:
		p2.next_turn()
	var tr: Dictionary = p2.player_view(hero.id).turn
	var tnames: Array = tr.targets.map(func(t): return t.name)
	check("my turn: attacks and prepared spells only", names(tr.actions) == ["Spada lunga", "Dardo incantato"], names(tr.actions))
	check("hidden monster not offered, no AC/HP sent", tnames.has("Orco") and not tnames.has("Ombra") and not tr.targets[0].has("hp") and not tr.targets[0].has("ac"), tnames)
	check("hidden monster can't be hit", not Actions.phone_act(p2, hero.id, {"i": 0, "name": "Spada lunga", "targets": [spy.id]}).ok)
	check("stale action refused", not Actions.phone_act(p2, hero.id, {"i": 0, "name": "Altro", "targets": [orc.id]}).ok)
	var hp_orc := int(orc.hp)
	res = Actions.phone_act(p2, hero.id, {"i": 1, "name": "Dardo incantato", "targets": [orc.id], "slot": 2})
	check("phone magic missile: slot 2, 4 darts", res.ok and int(hero.slots_used[1]) == 1 and int(orc.hp) < hp_orc and str(res.lines).count("1d4+1 =") == 4, res)
	var pub := Actions.public_lines(p2, res.lines)
	check("public lines hide monster HP", not str(pub).contains("PF ") and str(pub).contains("Orco subisce"), pub)
	var atk_pub := Actions.public_lines(p2, ["Spada lunga contro Orco: 17 (12+5) vs CA 13, colpito", "Orco - TS Destrezza: 9 (8+1) vs CD 13, fallito"])
	check("public lines hide AC and monster bonus", atk_pub == ["Spada lunga contro Orco: 17 (12+5), colpito", "Orco - TS Destrezza: 9 vs CD 13, fallito"], atk_pub)
	print("actions test: " + ("OK" if fails == 0 else "%d FAIL" % fails))
	quit()
