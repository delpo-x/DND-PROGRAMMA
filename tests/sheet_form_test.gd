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


func build_pdf(fields: Array) -> PackedByteArray:
	# fields: [name, value_pdf_token]; one terminal field each, plus a
	# parent "Extra" with a kid to test hierarchical names
	var objs: Array = []
	objs.append("<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [%s] >> >>")
	objs.append("<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
	objs.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << >> >>")
	objs.append("<< /Length 0 >>\nstream\n\nendstream")
	var refs := PackedStringArray()
	for f in fields:
		objs.append("<< /FT /Tx /T (%s) /V %s >>" % [f[0], f[1]])
		refs.append("%d 0 R" % objs.size())
	objs.append("<< /T (Extra) /Kids [%d 0 R] >>" % (objs.size() + 2))
	refs.append("%d 0 R" % objs.size())
	objs.append("<< /FT /Tx /T (Notes) /V (Darkvision, Second Wind, Action Surge and a long list of other features of the class) /Parent %d 0 R >>" % objs.size())
	objs.append("<< /FT /Btn /T (Box) /V /Off >>")
	refs.append("%d 0 R" % objs.size())
	objs[0] = objs[0] % " ".join(refs)
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
	print("sheet form test: ", "OK" if ok else "FAIL")
	quit(0 if ok else 1)
