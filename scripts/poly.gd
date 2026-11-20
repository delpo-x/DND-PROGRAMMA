class_name Poly
extends RefCounted
## Dice geometry: vertices of each polyhedron and its faces found as the
## convex hull planes. Same algorithm as web/dice3d.js (there with Z up).

const PHI := 1.6180339887

static var _cache: Dictionary = {}


static func base_verts(sides: int) -> Array:
	var v: Array = []
	match sides:
		4:
			v = [Vector3(1, 1, 1), Vector3(1, -1, -1), Vector3(-1, 1, -1), Vector3(-1, -1, 1)]
		6:
			for x in [-1, 1]:
				for y in [-1, 1]:
					for z in [-1, 1]:
						v.append(Vector3(x, y, z))
		8:
			v = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
		10:
			var a := 0.105
			var h := a * (1.0 + cos(PI / 5.0)) / (1.0 - cos(PI / 5.0))
			v.append(Vector3(0, h, 0))
			v.append(Vector3(0, -h, 0))
			for i in 10:
				var g := i * PI / 5.0
				v.append(Vector3(cos(g), a if i % 2 == 0 else -a, sin(g)))
		12:
			for x in [-1, 1]:
				for y in [-1, 1]:
					for z in [-1, 1]:
						v.append(Vector3(x, y, z))
			var p := PHI
			var q := 1.0 / PHI
			for a in [-1, 1]:
				for b in [-1, 1]:
					v.append(Vector3(0, a * q, b * p))
					v.append(Vector3(a * q, b * p, 0))
					v.append(Vector3(a * p, 0, b * q))
		_:
			var p := PHI
			for a in [-1, 1]:
				for b in [-1, 1]:
					v.append(Vector3(0, a, b * p))
					v.append(Vector3(a, b * p, 0))
					v.append(Vector3(a * p, 0, b))
	var m := 0.0
	for x in v:
		m = maxf(m, x.length())
	var out: Array = []
	for x in v:
		out.append(x / m)
	return out


static func find_faces(verts: Array) -> Array:
	var result: Array = []
	var n := verts.size()
	var seen := {}
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var nor: Vector3 = (verts[j] - verts[i]).cross(verts[k] - verts[i])
				if nor.length() < 1e-6:
					continue
				nor = nor.normalized()
				var d: float = nor.dot(verts[i])
				if d < 0:
					nor = -nor
					d = -d
				if d < 1e-4:
					continue
				var ok := true
				var on: Array = []
				for m in n:
					var s: float = nor.dot(verts[m]) - d
					if s > 1e-4:
						ok = false
						break
					if absf(s) < 1e-4:
						on.append(m)
				if not ok:
					continue
				var key := "%d,%d,%d" % [roundi(nor.x * 1000), roundi(nor.y * 1000), roundi(nor.z * 1000)]
				if seen.has(key):
					continue
				seen[key] = true
				var c := Vector3.ZERO
				for m in on:
					c += verts[m]
				c /= on.size()
				var u: Vector3 = (verts[on[0]] - c).normalized()
				var w: Vector3 = nor.cross(u)
				var ang := {}
				for m in on:
					var pv: Vector3 = verts[m] - c
					ang[m] = atan2(pv.dot(w), pv.dot(u))
				on.sort_custom(func(a, b): return ang[a] < ang[b])
				result.append({"idx": on, "n": nor, "c": c})
	return result


## Face values: opposite faces add up to sides + 1 (d4 uses vertex values).
static func assign_values(faces: Array, count: int) -> Array:
	var vals: Array = []
	vals.resize(faces.size())
	vals.fill(0)
	var low := 1
	for i in faces.size():
		if vals[i] != 0:
			continue
		var best := -1
		var bd := 2.0
		for j in faces.size():
			if j == i or vals[j] != 0:
				continue
			var d: float = faces[i].n.dot(faces[j].n)
			if d < bd:
				bd = d
				best = j
		vals[i] = low
		if best >= 0 and bd < -0.99:
			vals[best] = count + 1 - low
		low += 1
		while vals.has(low) and low <= count:
			low += 1
	return vals


static func geometry(sides: int) -> Dictionary:
	if _cache.has(sides):
		return _cache[sides]
	var verts := base_verts(sides)
	var faces := find_faces(verts)
	var g := {"verts": verts, "faces": faces, "values": assign_values(faces, faces.size())}
	_cache[sides] = g
	return g
