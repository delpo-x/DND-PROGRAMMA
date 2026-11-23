class_name Art
extends RefCounted
## Pictures for monsters and characters. The files live in web/img/ (shared
## with the phone pages, exported as-is) and are matched by name:
##   monsters  -> web/img/m/<key>.jpg  (key from a word in the name, e.g. "Goblin 2" -> goblin)
##   characters -> the portrait chosen in the app (user://ritratti, key "r/<file>"),
##                 else web/img/p/<first name>.jpg  (e.g. "Aelyra, Figlia delle Stelle" -> aelyra)

## Ordered: the first match wins, so specific names come before generic ones.
const MONSTER_WORDS := [
	["capo_goblin", ["capo goblin", "goblin capo", "boss goblin", "goblin boss", "re goblin"]],
	["goblin", ["goblin", "hobgoblin"]],
	["coboldo", ["coboldo", "coboldi", "kobold"]],
	["orco", ["orco", "orchi", "orc"]],
	["scheletro", ["scheletro", "scheletri", "skeleton"]],
	["zombi", ["zombi", "zombie", "non morto", "morto vivente"]],
	["lupo", ["lupo", "lupi", "wolf", "warg", "worg"]],
	["drago", ["drago", "draghi", "dragon", "viverna", "wyrm"]],
	["bandito", ["bandito", "banditi", "brigante", "predone", "bandit", "ladro", "tagliagole"]],
]

static var _tex: Dictionary = {}


static var _file_re := RegEx.create_from_string("^[a-z0-9_]+$")


## Path of a picture key: "r/..." are portraits saved by the app, the rest
## ship with it.
static func path_of(key: String) -> String:
	if key.begins_with("r/"):
		return "user://ritratti/%s.jpg" % key.substr(2)
	return "res://web/img/%s.jpg" % key


static func valid_file(file: String) -> bool:
	return _file_re.search(file) != null


static func _exists(key: String) -> bool:
	return FileAccess.file_exists(path_of(key))


## Picture key for a monster or character dictionary, "" if none.
static func key_for(e: Dictionary, type: String) -> String:
	var name := str(e.get("name", "")).to_lower()
	if type == "pc":
		var own := str(e.get("portrait", ""))
		if own != "" and valid_file(own) and _exists("r/" + own):
			return "r/" + own
		var first := name.split(",")[0].strip_edges().split(" ")[0]
		first = first.replace("'", "").replace("à", "a").replace("è", "e").replace("é", "e").replace("ì", "i").replace("ò", "o").replace("ù", "u")
		return "p/" + first if first != "" and _exists("p/" + first) else ""
	var text := name + " " + str(e.get("kind", "")).to_lower()
	for pair in MONSTER_WORDS:
		for w in pair[1]:
			if text.contains(w):
				return "m/" + pair[0] if _exists("m/" + pair[0]) else ""
	return ""


## Texture for a key ("" or missing -> null). Cached.
static func texture(key: String) -> Texture2D:
	if key == "":
		return null
	if _tex.has(key):
		return _tex[key]
	var tex: Texture2D = null
	var b := FileAccess.get_file_as_bytes(path_of(key))
	if not b.is_empty():
		var img := Image.new()
		if img.load_jpg_from_buffer(b) == OK:
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex


## Any PNG/JPG from web/img/ (logo, textures) as a texture. Cached.
static func file_texture(fname: String) -> Texture2D:
	if _tex.has(fname):
		return _tex[fname]
	var tex: Texture2D = null
	var b := FileAccess.get_file_as_bytes("res://web/img/" + fname)
	if not b.is_empty():
		var img := Image.new()
		var err := img.load_png_from_buffer(b) if fname.ends_with(".png") else img.load_jpg_from_buffer(b)
		if err == OK:
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_tex[fname] = tex
	return tex


## Small framed picture (gold rim) for lists; empty spacer if there is none.
static func avatar(key: String, size := 56) -> Control:
	var tex := texture(key)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(size, size)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.035, 0.03)
	sb.border_color = UI.GOLD_DIM
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", sb)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.custom_minimum_size = Vector2(size - 4, size - 4)
		frame.add_child(tr)
	else:
		frame.modulate.a = 0.0
	return frame
