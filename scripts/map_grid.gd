class_name MapGrid
extends RefCounted
## Finds the square grid printed on a battle map: the size of one square and
## where the first line starts, in pixels of the original picture.
## Method: grid lines are sharp edges repeating at a fixed step, so the edge
## strength of every column (and row) is folded on candidate steps; the step
## where the folded profile has the sharpest peak wins.


## Returns {cell, ox, oy, score} or {} when no clear grid is found.
static func detect(img: Image) -> Dictionary:
	if img == null or img.get_width() < 64 or img.get_height() < 64:
		return {}
	var g: Image = img.duplicate()
	g.convert(Image.FORMAT_L8)
	var scale := minf(1.0, 900.0 / maxf(g.get_width(), g.get_height()))
	if scale < 1.0:
		g.resize(int(g.get_width() * scale), int(g.get_height() * scale), Image.INTERPOLATE_BILINEAR)
	var w := g.get_width()
	var h := g.get_height()
	var d := g.get_data()
	var col := PackedFloat32Array()
	col.resize(w)
	col.fill(0)
	var row := PackedFloat32Array()
	row.resize(h)
	row.fill(0)
	for y in range(1, h):
		var o := y * w
		for x in range(1, w):
			var v := int(d[o + x])
			col[x] += absi(v - int(d[o + x - 1]))
			row[y] += absi(v - int(d[o + x - w]))
	col = _highpass(col)
	row = _highpass(row)
	var best_p := 0.0
	var best_s := 0.0
	var p := 8.0
	var max_p := minf(w, h) / 3.0
	while p <= max_p:
		var s: float = _fold(col, p)[0] + _fold(row, p)[0]
		if s > best_s:
			best_s = s
			best_p = p
		p += 0.5
	if best_p == 0.0:
		return {}
	var top: Array = _refine(col, row, best_p)
	var fine: float = top[0]
	best_s = top[1]
	# a grid also scores at 2x, 3x its step (and the coarse search can miss a
	# small step by a fraction of a pixel): try the fractions of the best step
	# and keep the smallest one that scores nearly as well
	for k in [4, 3, 2]:
		var q: float = fine / k
		if q < 8.0:
			continue
		var r: Array = _refine(col, row, q)
		if float(r[1]) >= best_s * 0.7:
			fine = r[0]
			best_s = r[1]
			break
	if best_s < 1.2:
		return {}
	var fx: Array = _fold(col, fine)
	var fy: Array = _fold(row, fine)
	return {"cell": fine / scale, "ox": float(fx[1]) / scale, "oy": float(fy[1]) / scale, "score": best_s}


## Best step within ±0.75 px of p. Returns [step, score].
static func _refine(col: PackedFloat32Array, row: PackedFloat32Array, p: float) -> Array:
	var best := [p, 0.0]
	var t := p - 0.75
	while t <= p + 0.75:
		var s: float = _fold(col, t)[0] + _fold(row, t)[0]
		if s > float(best[1]):
			best = [t, s]
		t += 0.02
	return best


## Removes slow changes (big dark or light areas), keeps only sharp lines.
static func _highpass(a: PackedFloat32Array) -> PackedFloat32Array:
	var n := a.size()
	var out := PackedFloat32Array()
	out.resize(n)
	var r := 6
	var mean := 0.0
	for i in n:
		mean += a[i]
	mean = maxf(1.0, mean / n)
	for i in n:
		var s := 0.0
		var c := 0
		for j in range(maxi(0, i - r), mini(n, i + r + 1)):
			s += a[j]
			c += 1
		out[i] = maxf(0.0, a[i] - s / c) / mean
	return out


## Folds the profile on step p. Returns [peak sharpness, phase in pixels].
static func _fold(a: PackedFloat32Array, p: float) -> Array:
	var bins := clampi(int(p / 1.5), 4, 24)
	var sum := PackedFloat32Array()
	sum.resize(bins)
	sum.fill(0)
	var cnt := PackedInt32Array()
	cnt.resize(bins)
	cnt.fill(0)
	for i in a.size():
		var b := int(fmod(float(i), p) / p * bins) % bins
		sum[b] += a[i]
		cnt[b] += 1
	var best := 0.0
	var bi := 0
	var tot := 0.0
	for b in bins:
		var m := sum[b] / maxf(1.0, cnt[b])
		tot += m
		if m > best:
			best = m
			bi = b
	var avg := tot / bins
	if avg <= 0.0:
		return [0.0, 0.0]
	return [best / avg - 1.0, (bi + 0.5) * p / bins]
