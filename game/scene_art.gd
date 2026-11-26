class_name SceneArt
extends RefCounted
## Battle map pictures drawn by code for the place of the fight (cellar,
## tavern, cave, crypt, forest, beach, road). Everything is drawn square by
## square on a 48 px grid, so floor seams, walls and props line up with the
## squares the phones draw on top. The middle of the map stays free of props:
## that is where the heroes and the monsters are placed.

const CELL := 48

## Place words, the last one in the text wins (like Ambience.detect).
const PLACES := {
	"cantina": ["cantina", "botti", "dispensa", "magazzino", "scantinato"],
	"locanda": ["locanda", "taverna", "osteria", "bancone", "sala comune"],
	"grotta": ["grotta", "caverna", "miniera", "galleria", "tunnel", "cunicol", "stalattit"],
	"cripta": ["cripta", "tomba", "sotterrane", "catacomb", "tempio", "sepolcr", "mausole", "dungeon", "prigion"],
	"bosco": ["bosco", "foresta", "alberi", "radura", "boschi", "sottobosco", "palude"],
	"mare": ["mare", "spiaggia", "porto", "molo", "scogli", "costa", "riva"],
	"strada": ["strada", "sentiero", "villaggio", "piazza", "accampamento", "bivacco", "campo", "pianura", "collina"],
}
const TITLES := {"cantina": "Cantina", "locanda": "Locanda", "grotta": "Grotta", "cripta": "Cripta",
	"bosco": "Bosco", "mare": "Spiaggia", "strada": "Strada"}

var img: Image
var r := RandomNumberGenerator.new()
var cols := 24
var rows := 16
var night := false


static func detect(text: String) -> String:
	var t := text.to_lower()
	var best := ""
	var best_at := -1
	for place in PLACES:
		for w in PLACES[place]:
			var at := t.rfind(w)
			while at > 0 and Ambience._letter(t.unicode_at(at - 1)):
				at = t.rfind(w, at - 1)
			if at > best_at:
				best_at = at
				best = place
	return best if best != "" else "strada"


static func title(place: String) -> String:
	return str(TITLES.get(place, "Strada"))


## The picture of a place, cols x rows squares of CELL pixels.
static func make(place: String, c := 24, rw := 16, is_night := false) -> Image:
	var a := SceneArt.new()
	a.cols = c
	a.rows = rw
	a.night = is_night
	a.r.seed = hash(place) & 0x7fffffff
	a.img = Image.create(c * CELL, rw * CELL, false, Image.FORMAT_RGB8)
	match place:
		"cantina": a._cellar()
		"locanda": a._tavern()
		"grotta": a._cave()
		"cripta": a._crypt()
		"bosco": a._forest()
		"mare": a._beach()
		_: a._road()
	return a.img


# ------------------------------------------------------------------ places
func _cellar() -> void:
	_floor_each(_flag.bind(Color(0.36, 0.33, 0.29)))
	_walls(Color(0.30, 0.26, 0.22))
	for p in _spots(16):
		match r.randi() % 4:
			0, 1: _barrel(p)
			2: _crate(p)
			_: _sacks(p)
	# a row of barrels against the back wall
	for x in range(2, cols - 2, 3):
		if r.randf() < 0.7:
			_barrel(Vector2i(x, 1))


func _tavern() -> void:
	_floor_each(_plank.bind(Color(0.46, 0.31, 0.18)))
	_walls(Color(0.33, 0.24, 0.17))
	# the counter along the left, the hearth on the back wall
	_box(Vector2i(2, 3), Vector2i(1, rows - 6), Color(0.33, 0.2, 0.1), 3)
	_hearth(Vector2i(cols / 2 - 1, 0))
	for p in _spots(7, 2):
		_table(p)


func _cave() -> void:
	_floor_each(_rock.bind(Color(0.34, 0.33, 0.33)))
	# rough walls: the border and a few bites into the floor
	for y in rows:
		for x in cols:
			var edge := mini(mini(x, cols - 1 - x), mini(y, rows - 1 - y))
			if edge == 0 or (edge == 1 and r.randf() < 0.35):
				_rock_wall(Vector2i(x, y))
	for p in _spots(14):
		match r.randi() % 3:
			0: _boulder(p)
			1: _stalagmite(p)
			_: _puddle(p)


func _crypt() -> void:
	_floor_each(_tile.bind(Color(0.40, 0.40, 0.42)))
	_walls(Color(0.24, 0.24, 0.27))
	for x in [3, cols - 4]:
		for y in range(3, rows - 2, 3):
			_pillar(Vector2i(x, y))
	for p in _spots(5, 2):
		_sarcophagus(p)


func _forest() -> void:
	_floor_each(_grass.bind(Color(0.27, 0.40, 0.19)))
	_path(Color(0.42, 0.34, 0.22))
	for p in _spots(26):
		if r.randf() < 0.65:
			_tree(p)
		else:
			_bush(p)


func _beach() -> void:
	_floor_each(_sand.bind(Color(0.76, 0.67, 0.47)))
	for x in cols:
		var deep := 2 + int(r.randf() < 0.4)
		for y in deep:
			_water(Vector2i(x, y), y < deep - 1)
	for p in _spots(10):
		if p.y <= 3:
			continue
		if r.randf() < 0.6:
			_boulder(p)
		else:
			_driftwood(p)


func _road() -> void:
	_floor_each(_grass.bind(Color(0.33, 0.42, 0.21)))
	_path(Color(0.47, 0.39, 0.27))
	for p in _spots(14):
		match r.randi() % 3:
			0: _boulder(p)
			1: _bush(p)
			_: _tree(p)


# ------------------------------------------------------------- floors
func _floor_each(f: Callable) -> void:
	for y in rows:
		for x in cols:
			f.call(Vector2i(x, y))


func _jit(c: Color, amount := 0.06) -> Color:
	var k := r.randf_range(-amount, amount)
	var o := Color(clampf(c.r + k, 0, 1), clampf(c.g + k, 0, 1), clampf(c.b + k * 0.8, 0, 1))
	return o.darkened(0.35) if night else o


func _px(cell: Vector2i) -> Vector2i:
	return cell * CELL


func _rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	var rc := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if rc.size.x > 0 and rc.size.y > 0:
		img.fill_rect(rc, c)


func _specks(cell: Vector2i, c: Color, n: int, size := 3) -> void:
	var o := _px(cell)
	for i in n:
		_rect(o.x + r.randi_range(0, CELL - size), o.y + r.randi_range(0, CELL - size), r.randi_range(1, size), r.randi_range(1, size), _jit(c, 0.08))


## Flagstone: one stone per square, mortar around it.
func _flag(cell: Vector2i, base: Color) -> void:
	var o := _px(cell)
	_rect(o.x, o.y, CELL, CELL, base.darkened(0.45))
	_rect(o.x + 2, o.y + 2, CELL - 4, CELL - 4, _jit(base))
	_specks(cell, base.darkened(0.15), 10)
	_rect(o.x + 2, o.y + 2, CELL - 4, 2, base.lightened(0.08))


## Wooden floor: three planks per square, the seams fall on the square edges.
func _plank(cell: Vector2i, base: Color) -> void:
	var o := _px(cell)
	for i in 3:
		var y := o.y + i * 16
		_rect(o.x, y, CELL, 16, _jit(base, 0.05))
		_rect(o.x, y + 15, CELL, 1, base.darkened(0.5))
		for k in 3:  # grain
			_rect(o.x + r.randi_range(0, 30), y + r.randi_range(3, 12), r.randi_range(8, 18), 1, base.darkened(0.18))
		_rect(o.x + 4, y + 7, 2, 2, base.darkened(0.55))
	_rect(o.x + CELL - 1, o.y, 1, CELL, base.darkened(0.5))


func _rock(cell: Vector2i, base: Color) -> void:
	var o := _px(cell)
	_rect(o.x, o.y, CELL, CELL, _jit(base, 0.04))
	_specks(cell, base.darkened(0.2), 14, 6)
	_specks(cell, base.lightened(0.1), 6, 3)


func _tile(cell: Vector2i, base: Color) -> void:
	var o := _px(cell)
	_rect(o.x, o.y, CELL, CELL, base.darkened(0.5))
	for q in [Vector2i(1, 1), Vector2i(25, 1), Vector2i(1, 25), Vector2i(25, 25)]:
		_rect(o.x + q.x, o.y + q.y, 22, 22, _jit(base, 0.05))
	_specks(cell, base.darkened(0.12), 6)


func _grass(cell: Vector2i, base: Color) -> void:
	var o := _px(cell)
	_rect(o.x, o.y, CELL, CELL, _jit(base, 0.03))
	for i in 18:  # tufts
		var c := base.darkened(r.randf_range(0.05, 0.25)) if r.randf() < 0.7 else base.lightened(0.12)
		_rect(o.x + r.randi_range(0, CELL - 2), o.y + r.randi_range(0, CELL - 5), 1 + r.randi() % 2, r.randi_range(2, 5), c.darkened(0.35) if night else c)


func _sand(cell: Vector2i, base: Color) -> void:
	var o := _px(cell)
	_rect(o.x, o.y, CELL, CELL, _jit(base, 0.03))
	_specks(cell, base.darkened(0.12), 12, 2)


func _water(cell: Vector2i, deep: bool) -> void:
	var o := _px(cell)
	var base := Color(0.14, 0.32, 0.45) if deep else Color(0.22, 0.45, 0.55)
	_rect(o.x, o.y, CELL, CELL, _jit(base, 0.03))
	for i in 3:
		_rect(o.x + r.randi_range(2, 24), o.y + 8 + i * 14, r.randi_range(10, 20), 2, base.lightened(0.25))


## A dirt path across the map, through the middle where the pieces stand.
func _path(c: Color) -> void:
	var y := rows / 2 - 1
	for x in cols:
		for dy in [0, 1]:
			var cell := Vector2i(x, clampi(y + dy, 0, rows - 1))
			var o := _px(cell)
			_rect(o.x, o.y, CELL, CELL, _jit(c, 0.04))
			_specks(cell, c.darkened(0.2), 10, 4)
		if r.randf() < 0.3:
			y = clampi(y + (1 if r.randf() < 0.5 else -1), rows / 2 - 2, rows / 2)


func _walls(c: Color) -> void:
	for y in rows:
		for x in cols:
			if x == 0 or y == 0 or x == cols - 1 or y == rows - 1:
				_bricks(Vector2i(x, y), c)


func _bricks(cell: Vector2i, c: Color) -> void:
	var o := _px(cell)
	_rect(o.x, o.y, CELL, CELL, c.darkened(0.5))
	for i in 4:
		var off := 0 if i % 2 == 0 else 12
		for k in range(-1, 2):
			var b := Rect2i(o.x + off + k * 24 + 1, o.y + i * 12 + 1, 22, 10).intersection(Rect2i(o, Vector2i(CELL, CELL)))
			if b.size.x > 0:
				_rect(b.position.x, b.position.y, b.size.x, b.size.y, _jit(c, 0.05))


func _rock_wall(cell: Vector2i) -> void:
	var o := _px(cell)
	var c := Color(0.2, 0.19, 0.19)
	_rect(o.x, o.y, CELL, CELL, _jit(c, 0.03))
	for i in 5:
		_disc(o + Vector2i(r.randi_range(8, 40), r.randi_range(8, 40)), r.randi_range(8, 16), _jit(c.lightened(0.08), 0.04))


# -------------------------------------------------------------- props
## Squares for props, away from the middle where the pieces stand
## (heroes on column 6, monsters on column 12). w = width in squares.
func _spots(n: int, w := 1) -> Array:
	var out: Array = []
	var used := {}
	var tries := 0
	while out.size() < n and tries < n * 40:
		tries += 1
		var p := Vector2i(r.randi_range(1, cols - 1 - w), r.randi_range(1, rows - 2))
		if p.x + w > 4 and p.x < 15 and p.y >= 4 and p.y <= rows - 5:
			continue
		var free := true
		for k in w:
			if used.has(p + Vector2i(k, 0)):
				free = false
		if not free:
			continue
		for k in w:
			used[p + Vector2i(k, 0)] = true
		out.append(p)
	return out


func _disc(c: Vector2i, rad: int, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(maxi(0, c.y - rad), mini(h, c.y + rad + 1)):
		var dy := y - c.y
		var half := int(sqrt(float(rad * rad - dy * dy)))
		var x0 := maxi(0, c.x - half)
		var x1 := mini(w - 1, c.x + half)
		if x1 >= x0:
			img.fill_rect(Rect2i(x0, y, x1 - x0 + 1, 1), col)


func _ring(c: Vector2i, rad: int, wid: int, col: Color, inner: Color) -> void:
	_disc(c, rad, col)
	_disc(c, rad - wid, inner)


func _mid(cell: Vector2i) -> Vector2i:
	return cell * CELL + Vector2i(CELL / 2, CELL / 2)


func _shadow(cell: Vector2i, rad: int) -> void:
	_disc(_mid(cell) + Vector2i(3, 4), rad, Color(0, 0, 0).lerp(_floor_at(cell), 0.55))


func _floor_at(cell: Vector2i) -> Color:
	return img.get_pixel(cell.x * CELL + 3, cell.y * CELL + 3)


func _barrel(cell: Vector2i) -> void:
	var m := _mid(cell)
	var wood := _jit(Color(0.45, 0.28, 0.13), 0.04)
	_shadow(cell, 20)
	_ring(m, 20, 3, Color(0.18, 0.13, 0.1), wood)
	_ring(m, 14, 2, Color(0.25, 0.2, 0.16), wood.lightened(0.08))
	_ring(m, 7, 2, wood.darkened(0.3), wood.lightened(0.12))


func _crate(cell: Vector2i) -> void:
	var o := _px(cell)
	var wood := _jit(Color(0.55, 0.4, 0.22), 0.04)
	_rect(o.x + 7, o.y + 8, 37, 37, Color(0, 0, 0).lerp(_floor_at(cell), 0.5))
	_rect(o.x + 4, o.y + 4, 38, 38, wood.darkened(0.4))
	_rect(o.x + 7, o.y + 7, 32, 32, wood)
	for i in 32:
		_rect(o.x + 7 + i, o.y + 7 + i, 3, 3, wood.darkened(0.3))
		_rect(o.x + 37 - i, o.y + 7 + i, 3, 3, wood.darkened(0.3))


func _sacks(cell: Vector2i) -> void:
	var m := _mid(cell)
	var c := _jit(Color(0.66, 0.58, 0.42), 0.04)
	for d in [Vector2i(-8, -6), Vector2i(8, -4), Vector2i(0, 9)]:
		_disc(m + d + Vector2i(2, 3), 11, Color(0, 0, 0).lerp(_floor_at(cell), 0.5))
		_disc(m + d, 11, c)
		_disc(m + d + Vector2i(-3, -3), 4, c.lightened(0.15))


func _box(cell: Vector2i, size: Vector2i, c: Color, edge: int) -> void:
	var o := _px(cell)
	var w := size.x * CELL
	var h := size.y * CELL
	_rect(o.x + 4, o.y + 4, w - 4, h - 4, c.darkened(0.45))
	_rect(o.x + 4 + edge, o.y + 4 + edge, w - 4 - 2 * edge, h - 4 - 2 * edge, _jit(c, 0.03))


func _table(cell: Vector2i) -> void:
	var o := _px(cell)
	var wood := Color(0.5, 0.33, 0.17)
	_rect(o.x + 9, o.y + 12, CELL * 2 - 14, CELL - 18, Color(0, 0, 0).lerp(_floor_at(cell), 0.5))
	_rect(o.x + 6, o.y + 9, CELL * 2 - 12, CELL - 18, wood.darkened(0.45))
	_rect(o.x + 8, o.y + 11, CELL * 2 - 16, CELL - 22, _jit(wood, 0.04))
	for k in 2:  # stools above and below
		_disc(Vector2i(o.x + 24 + k * CELL, o.y + 3), 6, wood.darkened(0.3))
		_disc(Vector2i(o.x + 24 + k * CELL, o.y + CELL - 3), 6, wood.darkened(0.3))
	_disc(Vector2i(o.x + 30, o.y + 24), 4, Color(0.8, 0.75, 0.6))  # a mug


func _hearth(cell: Vector2i) -> void:
	var o := _px(cell)
	_rect(o.x, o.y, CELL * 2, CELL, Color(0.22, 0.2, 0.19))
	_rect(o.x + 8, o.y + 10, CELL * 2 - 16, CELL - 16, Color(0.1, 0.07, 0.05))
	_disc(Vector2i(o.x + CELL, o.y + CELL / 2 + 4), 13, Color(0.85, 0.35, 0.08))
	_disc(Vector2i(o.x + CELL, o.y + CELL / 2 + 6), 7, Color(1.0, 0.78, 0.3))


func _boulder(cell: Vector2i) -> void:
	var m := _mid(cell)
	var c := _jit(Color(0.47, 0.46, 0.44), 0.05)
	_shadow(cell, 19)
	_disc(m, 18, c.darkened(0.35))
	_disc(m + Vector2i(-2, -2), 15, c)
	_disc(m + Vector2i(-6, -6), 6, c.lightened(0.15))


func _stalagmite(cell: Vector2i) -> void:
	var m := _mid(cell)
	var c := Color(0.5, 0.47, 0.43)
	_shadow(cell, 12)
	_ring(m, 12, 3, c.darkened(0.4), c)
	_disc(m + Vector2i(-2, -2), 4, c.lightened(0.25))


func _puddle(cell: Vector2i) -> void:
	var m := _mid(cell)
	_disc(m, 17, Color(0.16, 0.2, 0.24))
	_disc(m + Vector2i(-4, -3), 6, Color(0.3, 0.37, 0.42))


func _pillar(cell: Vector2i) -> void:
	var o := _px(cell)
	var m := _mid(cell)
	_rect(o.x + 3, o.y + 3, CELL - 6, CELL - 6, Color(0.28, 0.28, 0.3))
	_shadow(cell, 19)
	_ring(m, 19, 3, Color(0.25, 0.25, 0.28), Color(0.55, 0.55, 0.57))
	_disc(m + Vector2i(-5, -5), 6, Color(0.66, 0.66, 0.68))


func _sarcophagus(cell: Vector2i) -> void:
	var o := _px(cell)
	var c := Color(0.5, 0.48, 0.45)
	_rect(o.x + 8, o.y + 10, CELL * 2 - 10, CELL - 12, Color(0, 0, 0).lerp(_floor_at(cell), 0.5))
	_rect(o.x + 5, o.y + 7, CELL * 2 - 10, CELL - 14, c.darkened(0.45))
	_rect(o.x + 8, o.y + 10, CELL * 2 - 16, CELL - 20, _jit(c, 0.03))
	_rect(o.x + CELL - 2, o.y + 12, 4, CELL - 24, c.darkened(0.3))
	_rect(o.x + CELL - 10, o.y + CELL / 2 - 2, 20, 4, c.darkened(0.3))


func _tree(cell: Vector2i) -> void:
	var m := _mid(cell)
	var g := _jit(Color(0.16, 0.3, 0.12), 0.04)
	_disc(m + Vector2i(4, 5), 22, Color(0, 0, 0).lerp(_floor_at(cell), 0.45))
	_disc(m, 22, g.darkened(0.3))
	for d in [Vector2i(-7, -6), Vector2i(6, -4), Vector2i(-2, 7)]:
		_disc(m + d, 11, g)
	_disc(m + Vector2i(-8, -9), 6, g.lightened(0.15))


func _bush(cell: Vector2i) -> void:
	var m := _mid(cell)
	var g := _jit(Color(0.22, 0.36, 0.15), 0.04)
	_disc(m + Vector2i(3, 3), 14, Color(0, 0, 0).lerp(_floor_at(cell), 0.45))
	_disc(m, 14, g.darkened(0.25))
	_disc(m + Vector2i(-4, -4), 8, g)


func _driftwood(cell: Vector2i) -> void:
	var o := _px(cell)
	var c := Color(0.55, 0.47, 0.37)
	for i in 34:
		_rect(o.x + 7 + i, o.y + 14 + i / 2, 5, 6, c.darkened(0.2) if i % 9 == 0 else c)
