extends SceneTree
# Import of a fillable character sheet: the values are only in the form
# fields (AcroForm), not in the page text. Builds a small PDF in memory with
# the field names of a typical fillable 5e sheet and checks the character.

var ok := true


func check(name: String, cond: bool, info = "") -> void:
	print("ok   " if cond else "FAIL ", name, " ", info)
	ok = ok and cond


## PDF string with a UTF-16 byte order mark, as form fields often store text.
func u16(s: String) -> String:
	var h := "<FEFF"
	for c in s:
		h += "%04X" % c.unicode_at(0)
	return h + ">"


func build_pdf(fields: Array, annots_only := false) -> PackedByteArray:
	# fields: [name, value_pdf_token]; one terminal field each, plus a
	# parent "Extra" with a kid to test hierarchical names. annots_only: no
	# /AcroForm, the fields are only widget annotations of the page (what
	# some PDF merging tools leave)
	var objs: Array = []
	objs.append("<< /Type /Catalog /Pages 2 0 R >>" if annots_only else "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [%s] >> >>")
	objs.append("<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
	objs.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << >> /Annots [%s] >>")
	objs.append("<< /Length 0 >>\nstream\n\nendstream")
	var refs := PackedStringArray()
	for f in fields:
		objs.append("<< /Type /Annot /Subtype /Widget /FT /Tx /T (%s) /V %s >>" % [f[0], f[1]])
		refs.append("%d 0 R" % objs.size())
	objs.append("<< /T (Extra) /Kids [%d 0 R] >>" % (objs.size() + 2))
	refs.append("%d 0 R" % objs.size())
	objs.append("<< /Type /Annot /Subtype /Widget /FT /Tx /T (Notes) /V (Darkvision, Second Wind, Action Surge and a long list of other features of the class) /Parent %d 0 R >>" % objs.size())
	var notes_ref := "%d 0 R" % objs.size()
	objs.append("<< /Type /Annot /Subtype /Widget /FT /Btn /T (Box) /V /Off >>")
	refs.append("%d 0 R" % objs.size())
	if not annots_only:
		objs[0] = objs[0] % " ".join(refs)
	var widgets := refs.slice(0, refs.size() - 2)
	widgets.append(notes_ref)
	widgets.append(refs[refs.size() - 1])
	objs[2] = objs[2] % " ".join(widgets)
	var out := "%PDF-1.7\n"
	var offs: Array = []
	for i in objs.size():
		offs.append(out.to_utf8_buffer().size())
		out += "%d 0 obj\n%s\nendobj\n" % [i + 1, objs[i]]
	var xref := out.to_utf8_buffer().size()
	out += "xref\n0 %d\n0000000000 65535 f \n" % (objs.size() + 1)
	for o in offs:
		out += "%010d 00000 n \n" % o
	out += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % [objs.size() + 1, xref]
	return out.to_utf8_buffer()


func _init() -> void:
	var pdf := build_pdf([
		["CharacterName", u16("Thorin Scudodiquercia")], ["ClassLevel", "(Fighter 3 / Wizard 2)"], ["Race ", "(Dwarf)"],
		["PlayerName", "(Luca)"], ["ProfBonus", "(+3)"], ["AC", "(18)"], ["Initiative", "(+1)"], ["Speed", "(25 ft.)"],
		["HPMax", "(44)"], ["HPCurrent", "(30)"],
		["STR", "(16)"], ["STRmod", "(+3)"], ["DEX", "(12)"], ["CON", "(15)"], ["INT", "(13)"], ["WIS", "(10)"], ["CHA", "(8)"],
		["ST Strength", "(+6)"], ["ST Dexterity", "(+1)"], ["ST Constitution", "(+5)"],
		["Athletics", "(+9)"], ["Perception ", "(+3)"], ["Stealth ", "(+1)"], ["Animal", "(+0)"],
		["Wpn Name", "(Ascia da battaglia)"], ["Wpn1 AtkBonus", "(+6)"], ["Wpn1 Damage", "(1d8+3 Slashing)"],
		["Wpn Name 2", "(Balestra leggera)"], ["Wpn2 AtkBonus ", "(+4)"], ["Wpn2 Damage ", "(1d8 + 1 Piercing)"],
		["CharacterName 2", "(Altro nome)"],
	])
	var doc := PdfText.extract(pdf)
	check("fields read", doc.get("fields", {}).size() >= 30, doc.get("fields", {}).size())
	check("hierarchical name", doc.fields.has("Extra.Notes"))
	check("check box off left out", not doc.fields.has("Box"))
	check("utf-16 value", str(doc.fields.get("CharacterName", "")) == "Thorin Scudodiquercia")
	var res := SheetImport.parse(doc)
	var ch: Dictionary = res.char
	check("name", ch.name == "Thorin Scudodiquercia", ch.name)
	check("class and levels", ch.cls == "Fighter" and int(ch.level) == 5, [ch.cls, ch.level])
	check("race, player", ch.race == "Dwarf" and ch.player == "Luca")
	check("numbers", int(ch.prof) == 3 and int(ch.ac) == 18 and int(ch.hp_max) == 44 and int(ch.hp) == 30 and int(ch.speed) == 8,
		[ch.prof, ch.ac, ch.hp_max, ch.hp, ch.speed])
	check("initiative from DEX", int(ch.init_bonus) == 0, ch.init_bonus)
	check("abilities", ch.ab.FOR == 16 and ch.ab.DES == 12 and ch.ab.CAR == 8, ch.ab)
	check("saves", ch.saves.has("FOR") and ch.saves.has("COS") and not ch.saves.has("DES"), ch.saves)
	check("skills", int(ch.skills.get("atletica", 0)) == 2 and int(ch.skills.get("percezione", 0)) == 1 and not ch.skills.has("furtivita"), ch.skills)
	check("attacks", ch.attacks.size() == 2 and ch.attacks[0].name == "Ascia da battaglia" and int(ch.attacks[0].bonus) == 6
		and ch.attacks[0].damage == "1d8+3" and ch.attacks[1].damage == "1d8+1", ch.attacks)
	check("notes from long fields", str(ch.notes).contains("Second Wind"))
	# the whole flow: merge into a real character
	var st := GameState.new()
	st.persist = false
	st.new_campaign("T")
	var c: Dictionary = st.add_character("x", "")
	st.update_character(c.id, ch)
	check("merged", c.name == "Thorin Scudodiquercia" and int(c.level) == 5 and c.attacks.size() == 2)
	# a PDF with only the notes field still works
	check("small form", PdfText.extract(build_pdf([])).fields.size() == 1)
	# fields only as page widgets, with proficiency marks, a flat damage and
	# an equipment table (the shape of a D&D Beyond export)
	var doc2 := PdfText.extract(build_pdf([
		["CharacterName", "(Bobby)"], ["CLASS  LEVEL", "(Barbarian 1)"], ["ProfBonus", "(+2)"],
		["STR", "(14)"], ["DEX", "(14)"], ["CON", "(14)"], ["WIS", "(9)"],
		["StrProf", u16("•")], ["ST Strength", "(+4)"], ["ST Dexterity", "(+9)"], ["ConProf", u16("•")], ["ST Constitution", "(+4)"],
		["AthleticsProf", "(P)"], ["Athletics", "(+4)"], ["Stealth ", "(+9)"], ["PerceptionProf", "(E)"], ["Perception", "(+3)"],
		["Wpn Name 3", "(Unarmed Strike)"], ["Wpn3 AtkBonus", "(+4)"], ["Wpn3 Damage", "(3 Bludgeoning)"],
		["Wpn Notes 3", "(Simple, Light, Thrown, Vex, Range \\(20/60\\) and more)"],
		["BACKGROUND", "(Farmer)"], ["GP", "(15)"], ["Eq Name0", "(Handaxe)"], ["Eq Qty0", "(1)"], ["Eq Name1", "(Handaxe)"],
		["Eq Qty1", "(3)"], ["Eq Name2", "(Rope)"], ["Eq Qty2", "(1)"],
		["spellHeader0", "(=== CANTRIPS ===)"], ["spellPrepared0", "(O)"], ["spellName0", "(Guidance)"],
		["spellDuration0", "(Concentration, up to 1 minute, and a long note)"],
		["spellPrepared1", "(O)"], ["spellName1", "(Guidance)"],
		["spellHeader1", "(=== 1st LEVEL ===)"], ["spellPrepared2", "(P)"], ["spellName2", "(Hunter's Mark)"],
		["spellHeader2", "(=== 2nd LEVEL ===)"], ["spellName3", "(Pass without Trace)"],
	], true))
	check("widget fields without /AcroForm", doc2.fields.size() >= 28 and doc2.fields.has("Extra.Notes"), doc2.fields.size())
	var ch2: Dictionary = SheetImport.parse(doc2).char
	check("marks win over totals", ch2.saves == ["FOR", "COS"] and int(ch2.skills.get("atletica", 0)) == 1
		and int(ch2.skills.get("percezione", 0)) == 2 and not ch2.skills.has("furtivita"), [ch2.saves, ch2.skills])
	check("flat damage", ch2.attacks.size() == 1 and ch2.attacks[0].damage == "3", ch2.attacks)
	check("equipment and background in the notes", str(ch2.notes).contains("Handaxe (4), Rope; monete: 15 mo")
		and str(ch2.notes).contains("Background: Farmer") and not str(ch2.notes).contains("Thrown"), ch2.notes)
	check("spells by level, duplicates dropped", ch2.spells.size() == 3 and ch2.spells[0].name == "Guidance"
		and int(ch2.spells[0].lvl) == 0 and ch2.spells[1].name == "Hunter's Mark" and int(ch2.spells[1].lvl) == 1
		and bool(ch2.spells[1].prep) and int(ch2.spells[2].lvl) == 2 and not bool(ch2.spells[2].prep), ch2.spells)
	check("spell fields not in the notes", not str(ch2.notes).contains("Concentration"), ch2.notes)
	print("sheet form test: ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)
