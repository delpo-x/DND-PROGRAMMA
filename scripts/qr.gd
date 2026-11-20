class_name QR
extends RefCounted
## Minimal QR Code encoder (byte mode, error correction M, versions 1-10).
## Follows the public QR specification (ISO/IEC 18004).

const ECC_PER_BLOCK_M := [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26]
const BLOCKS_M := [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5]
const FORMAT_BITS_M := 0

var size := 0
var version := 1
var modules: Array = []  # [y][x] bool
var is_func: Array = []


static func encode(text: String) -> QR:
	var q := QR.new()
	q._build(text.to_utf8_buffer())
	return q


static func _raw_modules(ver: int) -> int:
	var result := (16 * ver + 128) * ver + 64
	if ver >= 2:
		var na := ver / 7 + 2
		result -= (25 * na - 10) * na - 55
		if ver >= 7:
			result -= 36
	return result


static func _data_codewords(ver: int) -> int:
	return _raw_modules(ver) / 8 - ECC_PER_BLOCK_M[ver] * BLOCKS_M[ver]


func _build(bytes: PackedByteArray) -> void:
	version = 0
	for v in range(1, 11):
		var cc_bits := 8 if v < 10 else 16
		if 4 + cc_bits + bytes.size() * 8 <= _data_codewords(v) * 8:
			version = v
			break
	if version == 0:
		version = 10
		bytes = bytes.slice(0, 200)
	var bits: Array = []
	_append_bits(bits, 4, 4)
	_append_bits(bits, bytes.size(), 8 if version < 10 else 16)
	for b in bytes:
		_append_bits(bits, b, 8)
	var cap := _data_codewords(version) * 8
	_append_bits(bits, 0, mini(4, cap - bits.size()))
	while bits.size() % 8 != 0:
		bits.append(0)
	var pad := 0xEC
	while bits.size() < cap:
		_append_bits(bits, pad, 8)
		pad = 0x11 if pad == 0xEC else 0xEC
	var data: Array = []
	for i in range(0, bits.size(), 8):
		var v := 0
		for j in 8:
			v = (v << 1) | int(bits[i + j])
		data.append(v)
	var all := _add_ecc(data)
	size = version * 4 + 17
	modules = []
	is_func = []
	for y in size:
		var row: Array = []
		var frow: Array = []
		row.resize(size)
		frow.resize(size)
		row.fill(false)
		frow.fill(false)
		modules.append(row)
		is_func.append(frow)
	_draw_function_patterns()
	_draw_codewords(all)
	var best := 0
	var best_pen := 1 << 30
	for m in 8:
		_apply_mask(m)
		_draw_format(m)
		var p := _penalty()
		if p < best_pen:
			best_pen = p
			best = m
		_apply_mask(m)
	_apply_mask(best)
	_draw_format(best)


func _append_bits(bits: Array, val: int, n: int) -> void:
	for i in range(n - 1, -1, -1):
		bits.append((val >> i) & 1)


func _set_func(x: int, y: int, dark: bool) -> void:
	modules[y][x] = dark
	is_func[y][x] = true


func _draw_function_patterns() -> void:
	for i in size:
		_set_func(6, i, i % 2 == 0)
		_set_func(i, 6, i % 2 == 0)
	_draw_finder(3, 3)
	_draw_finder(size - 4, 3)
	_draw_finder(3, size - 4)
	var pos := _align_positions()
	var n := pos.size()
	for i in n:
		for j in n:
			if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
				continue
			_draw_align(pos[i], pos[j])
	_draw_format(0)
	_draw_version()


func _draw_finder(x: int, y: int) -> void:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var dist := maxi(absi(dx), absi(dy))
			var xx := x + dx
			var yy := y + dy
			if xx >= 0 and xx < size and yy >= 0 and yy < size:
				_set_func(xx, yy, dist != 2 and dist != 4)


func _draw_align(x: int, y: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_set_func(x + dx, y + dy, maxi(absi(dx), absi(dy)) != 1)


func _align_positions() -> Array:
	if version == 1:
		return []
	var na := version / 7 + 2
	var step := (version * 8 + na * 3 + 5) / (na * 4 - 4) * 2
	var result: Array = []
	result.resize(na)
	result[0] = 6
	var p := size - 7
	for i in range(na - 1, 0, -1):
		result[i] = p
		p -= step
	return result


func _draw_format(mask: int) -> void:
	var d := (FORMAT_BITS_M << 3) | mask
	var rem := d
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((d << 10) | rem) ^ 0x5412
	for i in range(0, 6):
		_set_func(8, i, _bit(bits, i))
	_set_func(8, 7, _bit(bits, 6))
	_set_func(8, 8, _bit(bits, 7))
	_set_func(7, 8, _bit(bits, 8))
	for i in range(9, 15):
		_set_func(14 - i, 8, _bit(bits, i))
	for i in range(0, 8):
		_set_func(size - 1 - i, 8, _bit(bits, i))
	for i in range(8, 15):
		_set_func(8, size - 15 + i, _bit(bits, i))
	_set_func(8, size - 8, true)


func _draw_version() -> void:
	if version < 7:
		return
	var rem := version
	for i in 12:
		rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
	var bits := (version << 12) | rem
	for i in 18:
		var b := _bit(bits, i)
		var a := size - 11 + i % 3
		var c := i / 3
		_set_func(a, c, b)
		_set_func(c, a, b)


func _bit(x: int, i: int) -> bool:
	return ((x >> i) & 1) != 0


func _draw_codewords(data: Array) -> void:
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := (size - 1 - vert) if upward else vert
				if not is_func[y][x] and i < data.size() * 8:
					modules[y][x] = _bit(data[i >> 3], 7 - (i & 7))
					i += 1
		right -= 2


func _apply_mask(m: int) -> void:
	for y in size:
		for x in size:
			if is_func[y][x]:
				continue
			var inv := false
			match m:
				0: inv = (x + y) % 2 == 0
				1: inv = y % 2 == 0
				2: inv = x % 3 == 0
				3: inv = (x + y) % 3 == 0
				4: inv = (x / 3 + y / 2) % 2 == 0
				5: inv = x * y % 2 + x * y % 3 == 0
				6: inv = (x * y % 2 + x * y % 3) % 2 == 0
				7: inv = ((x + y) % 2 + x * y % 3) % 2 == 0
			if inv:
				modules[y][x] = not modules[y][x]


## Simplified penalty (runs, 2x2 blocks, balance) to pick a readable mask.
func _penalty() -> int:
	var p := 0
	var dark := 0
	for y in size:
		var run := 1
		for x in size:
			if modules[y][x]:
				dark += 1
			if x > 0:
				if modules[y][x] == modules[y][x - 1]:
					run += 1
					if run == 5:
						p += 3
					elif run > 5:
						p += 1
				else:
					run = 1
	for x in size:
		var run := 1
		for y in range(1, size):
			if modules[y][x] == modules[y - 1][x]:
				run += 1
				if run == 5:
					p += 3
				elif run > 5:
					p += 1
			else:
				run = 1
	for y in size - 1:
		for x in size - 1:
			var c: bool = modules[y][x]
			if c == modules[y][x + 1] and c == modules[y + 1][x] and c == modules[y + 1][x + 1]:
				p += 3
	var total := size * size
	var k := int(abs(dark * 20 - total * 10) / total)
	p += k * 10
	return p


func _gf_mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z


func _rs_divisor(degree: int) -> Array:
	var result: Array = []
	result.resize(degree)
	result.fill(0)
	result[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			result[j] = _gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _gf_mul(root, 0x02)
	return result


func _rs_remainder(data: Array, div: Array) -> Array:
	var result: Array = []
	result.resize(div.size())
	result.fill(0)
	for b in data:
		var factor: int = b ^ result.pop_front()
		result.append(0)
		for i in div.size():
			result[i] ^= _gf_mul(div[i], factor)
	return result


func _add_ecc(data: Array) -> Array:
	var nb: int = BLOCKS_M[version]
	var ecc_len: int = ECC_PER_BLOCK_M[version]
	var raw := _raw_modules(version) / 8
	var num_short := nb - raw % nb
	var short_len := raw / nb
	var div := _rs_divisor(ecc_len)
	var blocks: Array = []
	var k := 0
	for i in nb:
		var dl := short_len - ecc_len + (0 if i < num_short else 1)
		var dat: Array = data.slice(k, k + dl)
		k += dl
		var ecc := _rs_remainder(dat, div)
		if i < num_short:
			dat.append(0)
		dat.append_array(ecc)
		blocks.append(dat)
	var result: Array = []
	for i in blocks[0].size():
		for j in blocks.size():
			if i != short_len - ecc_len or j >= num_short:
				result.append(blocks[j][i])
	return result


func get_module(x: int, y: int) -> bool:
	return modules[y][x]
