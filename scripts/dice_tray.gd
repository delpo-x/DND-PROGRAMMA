class_name DiceTray
extends Node3D
## 3D dice tray with real rigid-body physics (master device).
## roll([{"type": "d20"}, ...]) throws the dice; "finished" gives the values
## read from the face that ends up on top (d4: the top vertex).

signal finished(results: Array)

const TRAY_W := 16.0
const TRAY_D := 10.0
const SIZES := {4: 1.25, 6: 0.95, 8: 1.05, 10: 1.05, 12: 1.1, 20: 1.15}
const COLORS := {
	"d4": Color(0.18, 0.55, 0.34), "d6": Color(0.92, 0.88, 0.8), "d8": Color(0.23, 0.43, 0.82),
	"d10": Color(0.54, 0.25, 0.78), "d12": Color(0.82, 0.48, 0.12), "d20": Color(0.7, 0.12, 0.16),
	"d100t": Color(0.25, 0.25, 0.28), "d100u": Color(0.42, 0.42, 0.46),
}
const GRAVITY_SCALE := 2.6
const MAX_TIME := 8.0

var dice: Array = []
var rolling := false
var elapsed := 0.0
var still_time := 0.0
var nudges := 0
var travelled := 0.0
var _mesh_cache: Dictionary = {}
var cam: Camera3D


func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.035, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.56, 0.5)
	env.ambient_light_energy = 0.7
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 28, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-6, 8, 6)
	fill.omni_range = 30
	fill.light_energy = 0.5
	add_child(fill)
	cam = Camera3D.new()
	cam.fov = 52
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.position = Vector3(0, 19.0, 9.0)
	add_child(cam)
	cam.look_at(Vector3(0, 0, 1.2))
	# green baize with a faint nap, dark walnut frame with grain, brass trim
	var felt := StandardMaterial3D.new()
	felt.albedo_color = Color(0.1, 0.27, 0.17)
	felt.albedo_texture = _noise_tex(0.09, Vector2(1, 1), Color(0.8, 0.8, 0.8), Color(1, 1, 1))
	felt.uv1_scale = Vector3(3, 2, 1)
	felt.roughness = 1.0
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.16, 0.08)
	wood.albedo_texture = _noise_tex(0.02, Vector2(1, 14), Color(0.62, 0.5, 0.42), Color(1, 0.92, 0.82))
	wood.roughness = 0.55
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.72, 0.55, 0.26)
	brass.metallic = 0.8
	brass.roughness = 0.35
	_box(Vector3(TRAY_W + 1.2, 1.0, TRAY_D + 1.2), Vector3(0, -0.5, 0), felt)
	var h := 1.0
	var t := 0.6
	_box(Vector3(TRAY_W + 2 * t, h, t), Vector3(0, h / 2, -TRAY_D / 2 - t / 2), wood)
	_box(Vector3(TRAY_W + 2 * t, h, t), Vector3(0, h / 2, TRAY_D / 2 + t / 2), wood)
	_box(Vector3(t, h, TRAY_D), Vector3(-TRAY_W / 2 - t / 2, h / 2, 0), wood)
	_box(Vector3(t, h, TRAY_D), Vector3(TRAY_W / 2 + t / 2, h / 2, 0), wood)
	# thin brass strip along the inner top edge of the frame (visual only)
	for z in [-TRAY_D / 2 + 0.03, TRAY_D / 2 - 0.03]:
		_deco(Vector3(TRAY_W, 0.06, 0.06), Vector3(0, h + 0.01, z), brass)
	for x in [-TRAY_W / 2 + 0.03, TRAY_W / 2 - 0.03]:
		_deco(Vector3(0.06, 0.06, TRAY_D), Vector3(x, h + 0.01, 0), brass)
	# invisible tall walls and lid keep the dice inside
	_box(Vector3(TRAY_W + 4, 20, 1), Vector3(0, 10, -TRAY_D / 2 - 0.5), null)
	_box(Vector3(TRAY_W + 4, 20, 1), Vector3(0, 10, TRAY_D / 2 + 0.5), null)
	_box(Vector3(1, 20, TRAY_D + 4), Vector3(-TRAY_W / 2 - 0.5, 10, 0), null)
	_box(Vector3(1, 20, TRAY_D + 4), Vector3(TRAY_W / 2 + 0.5, 10, 0), null)
	_box(Vector3(TRAY_W + 4, 1, TRAY_D + 4), Vector3(0, 14, 0), null)


## Tileable noise used as a subtle texture (baize nap, wood grain).
func _noise_tex(freq: float, stretch: Vector2, dark: Color, light: Color) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = int(256 * stretch.x) if stretch.x > 1 else 256
	tex.height = int(64 * stretch.y) if stretch.y > 1 else 256
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	g.set_color(0, dark)
	g.set_color(1, light)
	tex.color_ramp = g
	return tex


func _deco(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.7
	body.physics_material_override = pm
	if mat:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		body.add_child(mi)
	add_child(body)


static func sides_of(type: String) -> int:
	if type.begins_with("d100"):
		return 10
	return int(type.substr(1))


## Text and value shown on face i (or vertex i for d4).
static func label_for(type: String, base_value: int) -> Array:
	match type:
		"d10":
			return ["0" if base_value == 10 else str(base_value), base_value]
		"d100t":
			var v := (base_value - 1) * 10
			return ["00" if v == 0 else str(v), v]
		"d100u":
			var u := base_value - 1
			return [str(u), u]
	var txt := str(base_value)
	if (type == "d12" or type == "d20") and (base_value == 6 or base_value == 9):
		txt += "."
	return [txt, base_value]


func clear() -> void:
	for d in dice:
		d.body.queue_free()
	dice.clear()
	rolling = false


func roll(spec: Array) -> void:
	clear()
	elapsed = 0.0
	still_time = 0.0
	nudges = 0
	travelled = 0.0
	var n := spec.size()
	for i in n:
		var type: String = spec[i].type
		dice.append(_make_die(type, i, n))
	rolling = true


func _make_die(type: String, i: int, n: int) -> Dictionary:
	var sides := sides_of(type)
	var g := Poly.geometry(sides)
	var r: float = SIZES[sides]
	var body := RigidBody3D.new()
	body.mass = 1.0
	body.gravity_scale = GRAVITY_SCALE
	body.continuous_cd = true
	body.linear_damp = 0.15
	body.angular_damp = 0.8
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.32
	pm.friction = 0.55
	body.physics_material_override = pm
	var pts := PackedVector3Array()
	for v in g.verts:
		pts.append(v * r)
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(type, sides, r)
	body.add_child(mi)
	var labels: Array = []
	var text_col := Color(0.08, 0.06, 0.05) if type == "d6" else Color(1.0, 0.93, 0.72)
	if sides == 4:
		for vi in g.verts.size():
			labels.append(label_for(type, vi + 1))
		for f in g.faces:
			for vi in f.idx:
				var corner: Vector3 = g.verts[vi] * r
				var c: Vector3 = f.c * r
				_label(body, str(labels[vi][0]), c + (corner - c) * 0.52, f.n, (corner - c).normalized(), r * 0.30, text_col)
	else:
		for fi in g.faces.size():
			var f: Dictionary = g.faces[fi]
			labels.append(label_for(type, int(g.values[fi])))
			var c: Vector3 = f.c * r
			var up := _face_up(g, f, sides)
			var fs := {6: 0.62, 8: 0.42, 10: 0.38, 12: 0.42, 20: 0.32}
			var size: float = fs.get(sides, 0.4) * r
			if type == "d100t":
				size *= 0.8
			_label(body, str(labels[fi][0]), c, f.n, up, size, text_col)
	add_child(body)
	var lane := (float(i) + 0.5) / float(n) - 0.5
	body.position = Vector3(randf_range(-TRAY_W / 2 + 1.6, -TRAY_W / 2 + 3.0), randf_range(3.0, 5.0), lane * (TRAY_D - 3.0) + randf_range(-0.6, 0.6))
	body.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	body.linear_velocity = Vector3(randf_range(13.0, 19.0), randf_range(-2.0, 1.5), randf_range(-3.5, 3.5))
	body.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(14.0, 24.0)
	return {"type": type, "sides": sides, "body": body, "labels": labels, "geo": g, "start": body.position, "prev_v": Vector3.ZERO, "last_hit": -1.0}


static func _face_up(g: Dictionary, f: Dictionary, sides: int) -> Vector3:
	var c: Vector3 = f.c
	var idx: Array = f.idx
	if idx.size() == 3:
		return (g.verts[idx[0]] - c).normalized()
	if sides == 10:
		var far: Vector3 = g.verts[idx[0]]
		for vi in idx:
			if (g.verts[vi] - c).length() > (far - c).length():
				far = g.verts[vi]
		return (far - c).normalized()
	var mid: Vector3 = (g.verts[idx[0]] + g.verts[idx[1]]) * 0.5
	return (mid - c).normalized()


func _label(body: Node3D, text: String, pos: Vector3, nor: Vector3, up: Vector3, height: float, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.outline_size = 10
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.85) if col.v > 0.5 else Color(1, 1, 1, 0.25)
	l.pixel_size = height / 64.0
	l.double_sided = false
	l.shaded = false
	var z := nor.normalized()
	var y := (up - z * up.dot(z)).normalized()
	var x := y.cross(z)
	l.transform = Transform3D(Basis(x, y, z), pos + z * 0.012)
	body.add_child(l)


func _mesh(type: String, sides: int, r: float) -> Mesh:
	if _mesh_cache.has(type):
		return _mesh_cache[type]
	var g := Poly.geometry(sides)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in g.faces:
		var idx: Array = f.idx
		for k in range(1, idx.size() - 1):
			st.set_normal(f.n)
			st.add_vertex(g.verts[idx[0]] * r)
			st.set_normal(f.n)
			st.add_vertex(g.verts[idx[k + 1]] * r)
			st.set_normal(f.n)
			st.add_vertex(g.verts[idx[k]] * r)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS.get(type, Color(0.6, 0.6, 0.6))
	mat.roughness = 0.35
	mat.metallic = 0.05
	mesh.surface_set_material(0, mat)
	_mesh_cache[type] = mesh
	return mesh


func _read(d: Dictionary) -> Dictionary:
	var b: Basis = d.body.global_transform.basis
	var g: Dictionary = d.geo
	if d.sides == 4:
		var best := 0
		var by := -INF
		for vi in g.verts.size():
			var y: float = (b * g.verts[vi]).y
			if y > by:
				by = y
				best = vi
		var flat := false
		for f in g.faces:
			if (b * f.n).y < -0.95:
				flat = true
		return {"value": d.labels[best][1], "flat": flat}
	var bi := 0
	var bd := -INF
	for fi in g.faces.size():
		var y: float = (b * g.faces[fi].n).y
		if y > bd:
			bd = y
			bi = fi
	return {"value": d.labels[bi][1], "flat": bd > 0.95}


func _physics_process(delta: float) -> void:
	if not rolling:
		return
	elapsed += delta
	var all_still := true
	for d in dice:
		var body: RigidBody3D = d.body
		travelled = maxf(travelled, body.position.distance_to(d.start))
		# a sudden loss of speed means the die hit the table, a wall or another die
		var lost: float = (d.prev_v - body.linear_velocity).length()
		d.prev_v = body.linear_velocity
		if lost > 2.2 and elapsed - float(d.last_hit) > 0.09:
			d.last_hit = elapsed
			Sfx.tok(self, lost)
		if not body.sleeping and (body.linear_velocity.length() > 0.08 or body.angular_velocity.length() > 0.15):
			all_still = false
	still_time = still_time + delta if all_still else 0.0
	if (still_time > 0.35 and elapsed > 0.6) or elapsed > MAX_TIME:
		var results: Array = []
		var cocked := false
		for d in dice:
			var r := _read(d)
			if not r.flat:
				cocked = true
				if elapsed <= MAX_TIME and nudges < 4:
					var body: RigidBody3D = d.body
					body.sleeping = false
					body.apply_central_impulse(Vector3(randf_range(-1, 1), 3.5, randf_range(-1, 1)))
					body.apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 1.5)
			results.append({"type": d.type, "value": r.value})
		if cocked and elapsed <= MAX_TIME and nudges < 4:
			nudges += 1
			still_time = 0.0
			return
		rolling = false
		finished.emit(results)


## Screen position of each die (for the result badges).
func die_screen_positions() -> Array:
	var out: Array = []
	if cam == null:
		return out
	for d in dice:
		var p: Vector3 = d.body.global_position + Vector3(0, 1.4, 0)
		out.append(cam.unproject_position(p))
	return out
