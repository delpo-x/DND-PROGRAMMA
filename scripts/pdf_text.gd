class_name PdfText
extends RefCounted
## Minimal PDF text extractor written in plain GDScript (no external tools),
## so it works the same in the Windows build and on Android.
##
## Supports: classic xref tables and xref streams, object streams, FlateDecode
## (with PNG predictors), page trees with inherited resources, Form XObjects,
## simple / Type3 / Type0 (CID) fonts with ToUnicode maps.
## Output: per page, a list of "chunks" = pieces of text on one baseline
## separated by large gaps (table cells), with position and font size:
##   {pages: [{w, h, chunks: [{t, x0, x1, y, s}]}], error: ""}
## y grows downward from the top of the page, units are PDF points.

const WS := [0, 9, 10, 12, 13, 32]

var buf: PackedByteArray
var src: PackedByteArray  # the whole file (buf may point at a stream)
var offsets: Dictionary = {}     # obj num -> byte offset
var in_stream: Dictionary = {}   # obj num -> [stream obj num, index]
var cache: Dictionary = {}
var trailer: Dictionary = {}
var font_cache: Dictionary = {}
var pos := 0
var error := ""

# page assembly state
var chunks: Array = []
var cur: Dictionary = {}
var page_h := 842.0


static func extract(bytes: PackedByteArray) -> Dictionary:
	var p := new()
	return p._run(bytes)


## Convenience: plain text of the whole document; chunks on one baseline are
## joined with a tab, one line per baseline.
static func plain_text(doc: Dictionary) -> String:
	var out := PackedStringArray()
	for pg in doc.get("pages", []):
		var last_y := -1e9
		var line := ""
		for c in pg.chunks:
			if absf(float(c.y) - last_y) < float(c.s) * 0.5:
				line += "\t" + str(c.t)
			else:
				if line != "":
					out.append(line)
				line = str(c.t)
			last_y = float(c.y)
		if line != "":
			out.append(line)
	return "\n".join(out)


func _run(bytes: PackedByteArray) -> Dictionary:
	buf = bytes
	src = bytes
	var pages_out: Array = []
	if buf.size() < 16 or buf.slice(0, 5).get_string_from_ascii() != "%PDF-":
		return {"pages": [], "error": "Il file non è un PDF"}
	if not _read_xref_chain():
		_scan_objects()
	var root = _get(trailer.get(&"Root"))
	if not root is Dictionary:
		_scan_objects()
		root = _get(trailer.get(&"Root"))
	if not root is Dictionary:
		return {"pages": [], "error": "Struttura del PDF non riconosciuta"}
	if trailer.has(&"Encrypt"):
		return {"pages": [], "error": "Il PDF è protetto da password o cifrato"}
	var pages: Array = []
	_collect_pages(_get(root.get(&"Pages")), {}, pages, 0)
	for pg in pages:
		pages_out.append(_page_text(pg))
	return {"pages": pages_out, "error": error}


# ------------------------------------------------------------------ objects
func _read_xref_chain() -> bool:
	var tail_start := maxi(0, buf.size() - 2048)
	var tail := _ascii(buf.slice(tail_start))
	var k := tail.rfind("startxref")
	if k < 0:
		return false
	var num := ""
	for ch in tail.substr(k + 9):
		if ch >= "0" and ch <= "9":
			num += ch
		elif num != "":
			break
	if num == "":
		return false
	var off := int(num)
	var seen := {}
	var first := true
	while off > 0 and off < buf.size() and not seen.has(off):
		seen[off] = true
		var d = _read_xref_at(off)
		if not d is Dictionary:
			return not first
		if first:
			trailer = d
			first = false
		else:
			for key in d:
				if not trailer.has(key):
					trailer[key] = d[key]
		if d.has(&"XRefStm"):
			_read_xref_at(int(d[&"XRefStm"]))
		off = int(d.get(&"Prev", 0))
	return not offsets.is_empty() or not in_stream.is_empty()


static func _ascii(b: PackedByteArray) -> String:
	# byte-for-byte latin-1 view (get_string_from_ascii stops at NUL bytes)
	var s := PackedStringArray()
	for x in b:
		s.append(char(x if x > 0 else 32))
	return "".join(s)


func _read_xref_at(off: int):
	pos = off
	_skip_ws()
	if _peek_word("xref"):
		pos += 4
		while true:
			_skip_ws()
			if _peek_word("trailer"):
				pos += 7
				var d = _parse_value()
				return d if d is Dictionary else null
			var start = _parse_value()
			var count = _parse_value()
			if not (start is int and count is int):
				return null
			for i in count:
				_skip_ws()
				if pos + 18 > buf.size():
					return null
				var line := buf.slice(pos, pos + 18).get_string_from_ascii()
				pos += 18
				var parts := line.split(" ", false)
				if parts.size() >= 3 and parts[2].begins_with("n"):
					var n: int = start + i
					if not offsets.has(n) and not in_stream.has(n):
						offsets[n] = int(parts[0])
		return null
	# cross-reference stream
	var obj = _parse_indirect_at(off)
	if not (obj is Dictionary and obj.has("__stream") and str(obj.get(&"Type", "")) == "XRef"):
		return null
	var data := _decode_stream(obj)
	var w: Array = obj.get(&"W", [1, 2, 1])
	var size := int(obj.get(&"Size", 0))
	var index: Array = obj.get(&"Index", [0, size])
	var rec := int(w[0]) + int(w[1]) + int(w[2])
	var p := 0
	var i := 0
	while i + 1 < index.size():
		var n0 := int(index[i])
		var cnt := int(index[i + 1])
		for j in cnt:
			if p + rec > data.size():
				break
			var f := [0, 0, 0]
			var q := p
			for fi in 3:
				var v := 0
				for b in int(w[fi]):
					v = (v << 8) | data[q]
					q += 1
				f[fi] = v
			if int(w[0]) == 0:
				f[0] = 1
			p += rec
			var n := n0 + j
			if offsets.has(n) or in_stream.has(n):
				continue
			if f[0] == 1:
				offsets[n] = f[1]
			elif f[0] == 2:
				in_stream[n] = [f[1], f[2]]
		i += 2
	return obj


## Fallback when the xref is missing or broken: find "N G obj" everywhere.
func _scan_objects() -> void:
	var n := buf.size()
	var i := buf.find(111)  # 'o'
	while i >= 0 and i < n - 3:
		if buf[i + 1] == 98 and buf[i + 2] == 106 and i > 3:  # "obj"
			var j := i - 1
			while j > 0 and WS.has(buf[j]):
				j -= 1
			var g_end := j
			while j > 0 and buf[j] >= 48 and buf[j] <= 57:
				j -= 1
			if j < g_end and WS.has(buf[j]):
				var k := j
				while k > 0 and WS.has(buf[k]):
					k -= 1
				var n_end := k
				while k >= 0 and buf[k] >= 48 and buf[k] <= 57:
					k -= 1
				if k < n_end:
					var num := int(buf.slice(k + 1, n_end + 1).get_string_from_ascii())
					offsets[num] = k + 1
		i = buf.find(111, i + 1)
	var t := _find_last("trailer".to_ascii_buffer())
	if t >= 0:
		pos = t + 7
		var d = _parse_value()
		if d is Dictionary and d.has(&"Root"):
			trailer = d
	if not trailer.has(&"Root"):
		for num in offsets:
			var o = _get(Vector2i(num, 0))
			if o is Dictionary and str(o.get(&"Type", "")) == "Catalog":
				trailer[&"Root"] = Vector2i(num, 0)
				break


func _find_last(needle: PackedByteArray) -> int:
	var best := -1
	var i := _find_bytes(needle, 0)
	while i >= 0:
		best = i
		i = _find_bytes(needle, i + 1)
	return best


func _get(v):
	if v is Vector2i:
		var num: int = v.x
		if cache.has(num):
			return cache[num]
		cache[num] = null  # guards against reference loops
		var o = null
		if offsets.has(num):
			var save := pos
			var save_buf := buf
			buf = src
			o = _parse_indirect_at(offsets[num])
			buf = save_buf
			pos = save
		elif in_stream.has(num):
			o = _from_obj_stream(in_stream[num][0], in_stream[num][1], num)
		cache[num] = o
		return o
	return v


func _parse_indirect_at(off: int):
	pos = off
	var a = _parse_value()
	var b = _parse_value()
	_skip_ws()
	if not (a is int and b is int and _peek_word("obj")):
		return null
	pos += 3
	var v = _parse_value()
	_skip_ws()
	if v is Dictionary and _peek_word("stream"):
		pos += 6
		if pos < buf.size() and buf[pos] == 13:
			pos += 1
		if pos < buf.size() and buf[pos] == 10:
			pos += 1
		var start := pos
		var length = v.get(&"Length", 0)
		if length is Vector2i:
			var save := pos
			length = _get(length)
			pos = save
		var ln := int(length) if (length is int or length is float) else -1
		var endpos := start + ln
		var ok := ln >= 0 and endpos <= buf.size()
		if ok:
			var tail := _ascii(buf.slice(endpos, mini(endpos + 20, buf.size())))
			ok = tail.strip_edges().begins_with("endstream")
		if not ok:
			endpos = _find_bytes("endstream".to_ascii_buffer(), start)
			if endpos < 0:
				endpos = buf.size()
			while endpos > start and WS.has(buf[endpos - 1]):
				endpos -= 1
		v["__stream"] = buf.slice(start, endpos)
		pos = endpos
	return v


func _from_obj_stream(snum: int, idx: int, num: int):
	var s = _get(Vector2i(snum, 0))
	if not (s is Dictionary and s.has("__stream")):
		return null
	if not s.has("__decoded"):
		s["__decoded"] = _decode_stream(s)
	var data: PackedByteArray = s["__decoded"]
	var n := int(s.get(&"N", 0))
	var first := int(s.get(&"First", 0))
	var save_buf := buf
	var save_pos := pos
	buf = data
	pos = 0
	var table: Array = []
	for i in n:
		var a = _parse_value()
		var b = _parse_value()
		table.append([int(a), int(b)])
	var result = null
	var pick := idx if idx < table.size() and table[idx][0] == num else -1
	if pick < 0:
		for t in table.size():
			if table[t][0] == num:
				pick = t
				break
	if pick >= 0:
		pos = first + table[pick][1]
		result = _parse_value()
	buf = save_buf
	pos = save_pos
	return result


func _find_bytes(needle: PackedByteArray, from: int) -> int:
	var n := buf.size() - needle.size()
	var first := needle[0]
	var i := buf.find(first, from)
	while i >= 0 and i <= n:
		var ok := true
		for k in range(1, needle.size()):
			if buf[i + k] != needle[k]:
				ok = false
				break
		if ok:
			return i
		i = buf.find(first, i + 1)
	return -1


# ------------------------------------------------------------------ lexer
func _skip_ws() -> void:
	var n := buf.size()
	while pos < n:
		var c := buf[pos]
		if c == 37:  # % comment
			while pos < n and buf[pos] != 10 and buf[pos] != 13:
				pos += 1
		elif c == 0 or c == 9 or c == 10 or c == 12 or c == 13 or c == 32:
			pos += 1
		else:
			return


func _peek_word(w: String) -> bool:
	var n := w.length()
	if pos + n > buf.size():
		return false
	for i in n:
		if buf[pos + i] != w.unicode_at(i):
			return false
	return true


static func _is_regular(c: int) -> bool:
	if c == 0 or c == 9 or c == 10 or c == 12 or c == 13 or c == 32:
		return false
	return not (c == 40 or c == 41 or c == 60 or c == 62 or c == 91 or c == 93 or c == 123 or c == 125 or c == 47 or c == 37)


## Returns: int/float, StringName (PDF name), PackedByteArray (string),
## Array, Dictionary, Vector2i (reference), bool, null,
## or a String for bare keywords (operators in content streams).
func _parse_value():
	_skip_ws()
	var n := buf.size()
	if pos >= n:
		return null
	var c := buf[pos]
	if c == 47:  # /Name
		pos += 1
		var s := pos
		while pos < n and _is_regular(buf[pos]):
			pos += 1
		var name := buf.slice(s, pos).get_string_from_ascii()
		if name.contains("#"):
			name = _unhash(name)
		return StringName(name)
	if c == 40:  # (string)
		return _parse_lit_string()
	if c == 60:
		if pos + 1 < n and buf[pos + 1] == 60:
			pos += 2
			var d := {}
			while true:
				_skip_ws()
				if pos >= n:
					break
				if buf[pos] == 62 and pos + 1 < n and buf[pos + 1] == 62:
					pos += 2
					break
				var k = _parse_value()
				if not k is StringName:
					if k == null and pos >= n:
						break
					continue
				d[k] = _parse_value()
			return d
		return _parse_hex_string()
	if c == 91:  # [
		pos += 1
		var arr: Array = []
		while true:
			_skip_ws()
			if pos >= n:
				break
			if buf[pos] == 93:
				pos += 1
				break
			arr.append(_parse_value())
		return arr
	if (c >= 48 and c <= 57) or c == 43 or c == 45 or c == 46:
		var s := pos
		pos += 1
		while pos < n and ((buf[pos] >= 48 and buf[pos] <= 57) or buf[pos] == 46):
			pos += 1
		var txt := buf.slice(s, pos).get_string_from_ascii()
		if txt.contains("."):
			return float(txt)
		var num := int(txt)
		# reference "n g R"?
		if c != 43 and c != 45:
			var save := pos
			_skip_ws()
			if pos < n and buf[pos] >= 48 and buf[pos] <= 57:
				var s2 := pos
				while pos < n and buf[pos] >= 48 and buf[pos] <= 57:
					pos += 1
				var g := int(buf.slice(s2, pos).get_string_from_ascii())
				_skip_ws()
				if pos < n and buf[pos] == 82 and (pos + 1 >= n or not _is_regular(buf[pos + 1])):
					pos += 1
					return Vector2i(num, g)
			pos = save
		return num
	if c == 93 or c == 62 or c == 41 or c == 123 or c == 125:
		pos += 1
		return "?"
	var s := pos
	while pos < n and _is_regular(buf[pos]):
		pos += 1
	if pos == s:
		pos += 1
		return "?"
	var word := buf.slice(s, pos).get_string_from_ascii()
	match word:
		"true":
			return true
		"false":
			return false
		"null":
			return null
	return word


static func _unhash(s: String) -> String:
	var out := PackedByteArray()
	var i := 0
	while i < s.length():
		if s[i] == "#" and i + 2 < s.length() and s.substr(i + 1, 2).is_valid_hex_number():
			out.append(s.substr(i + 1, 2).hex_to_int())
			i += 3
		else:
			out.append(s.unicode_at(i) & 255)
			i += 1
	var u := out.get_string_from_utf8()
	return u if u != "" else out.get_string_from_ascii()


func _parse_lit_string() -> PackedByteArray:
	var out := PackedByteArray()
	var n := buf.size()
	pos += 1
	var depth := 1
	while pos < n:
		var c := buf[pos]
		pos += 1
		if c == 92:  # backslash
			if pos >= n:
				break
			var e := buf[pos]
			pos += 1
			if e == 110:
				out.append(10)
			elif e == 114:
				out.append(13)
			elif e == 116:
				out.append(9)
			elif e == 98:
				out.append(8)
			elif e == 102:
				out.append(12)
			elif e == 13:
				if pos < n and buf[pos] == 10:
					pos += 1
			elif e == 10:
				pass
			elif e >= 48 and e <= 55:
				var v := e - 48
				for k in 2:
					if pos < n and buf[pos] >= 48 and buf[pos] <= 55:
						v = v * 8 + buf[pos] - 48
						pos += 1
				out.append(v & 255)
			else:
				out.append(e)
		elif c == 40:
			depth += 1
			out.append(c)
		elif c == 41:
			depth -= 1
			if depth == 0:
				break
			out.append(c)
		else:
			out.append(c)
	return out


func _parse_hex_string() -> PackedByteArray:
	var out := PackedByteArray()
	var n := buf.size()
	pos += 1
	var hi := -1
	while pos < n:
		var c := buf[pos]
		pos += 1
		if c == 62:
			break
		var v := -1
		if c >= 48 and c <= 57:
			v = c - 48
		elif c >= 65 and c <= 70:
			v = c - 55
		elif c >= 97 and c <= 102:
			v = c - 87
		if v < 0:
			continue
		if hi < 0:
			hi = v
		else:
			out.append(hi * 16 + v)
			hi = -1
	if hi >= 0:
		out.append(hi * 16)
	return out


# ------------------------------------------------------------------ streams
func _decode_stream(obj: Dictionary) -> PackedByteArray:
	var data: PackedByteArray = obj.get("__stream", PackedByteArray())
	var filters = _get(obj.get(&"Filter"))
	var parms = _get(obj.get(&"DecodeParms"))
	if filters == null:
		return data
	if not filters is Array:
		filters = [filters]
		parms = [parms]
	if not parms is Array:
		parms = [parms]
	for i in filters.size():
		var f := str(filters[i])
		var pr = _get(parms[i]) if i < parms.size() else null
		match f:
			"FlateDecode", "Fl":
				data = _inflate(data)
				if pr is Dictionary and int(pr.get(&"Predictor", 1)) >= 10:
					data = _unpredict(data, int(pr.get(&"Columns", 1)), int(pr.get(&"Colors", 1)) * int(pr.get(&"BitsPerComponent", 8)))
			"ASCIIHexDecode", "AHx":
				var save_buf := buf
				var save_pos := pos
				buf = PackedByteArray([60]) + data
				pos = 0
				data = _parse_hex_string()
				buf = save_buf
				pos = save_pos
			"ASCII85Decode", "A85":
				data = _a85(data)
			_:
				return PackedByteArray()  # images and other filters: not text
	return data


static func _inflate(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return data
	var out := data.decompress_dynamic(256 * 1024 * 1024, FileAccess.COMPRESSION_DEFLATE)
	if out.is_empty() and data.size() > 2:
		# some writers emit raw deflate without the zlib header: add one
		var fixed := PackedByteArray([0x78, 0x9C]) + data
		out = fixed.decompress_dynamic(256 * 1024 * 1024, FileAccess.COMPRESSION_DEFLATE)
	return out


static func _unpredict(data: PackedByteArray, columns: int, bits_per_px: int) -> PackedByteArray:
	var bpp := maxi(1, bits_per_px / 8)
	var row := maxi(1, columns * bits_per_px / 8)
	var out := PackedByteArray()
	var prev := PackedByteArray()
	prev.resize(row)
	prev.fill(0)
	var i := 0
	while i < data.size():
		var ft := data[i]
		var line := data.slice(i + 1, i + 1 + row)
		line.resize(row)
		for x in row:
			var a := line[x - bpp] if x >= bpp else 0
			var b := prev[x]
			var c := prev[x - bpp] if x >= bpp else 0
			var v := line[x]
			if ft == 1:
				v = (v + a) & 255
			elif ft == 2:
				v = (v + b) & 255
			elif ft == 3:
				v = (v + ((a + b) >> 1)) & 255
			elif ft == 4:
				var p := a + b - c
				var pa := absi(p - a)
				var pb := absi(p - b)
				var pc := absi(p - c)
				var pred := a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
				v = (v + pred) & 255
			line[x] = v
		out.append_array(line)
		prev = line
		i += row + 1
	return out


static func _a85(data: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var group: Array = []
	for c in data:
		if c == 126:
			break
		if c == 122 and group.is_empty():
			out.append_array([0, 0, 0, 0])
			continue
		if c < 33 or c > 117:
			continue
		group.append(c - 33)
		if group.size() == 5:
			var v := 0
			for g in group:
				v = v * 85 + g
			out.append_array([(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255])
			group.clear()
	if group.size() > 1:
		var k := group.size()
		while group.size() < 5:
			group.append(84)
		var v := 0
		for g in group:
			v = v * 85 + g
		var bytes := [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]
		for b in k - 1:
			out.append(bytes[b])
	return out


# ------------------------------------------------------------------ pages
func _collect_pages(node, inherited: Dictionary, out: Array, depth: int) -> void:
	if not node is Dictionary or depth > 40:
		return
	var inh := inherited.duplicate()
	for k in [&"Resources", &"MediaBox", &"CropBox"]:
		if node.has(k):
			inh[k] = node[k]
	var kids = _get(node.get(&"Kids"))
	if kids is Array and str(node.get(&"Type", "")) != "Page":
		for k in kids:
			_collect_pages(_get(k), inh, out, depth + 1)
	else:
		var pg: Dictionary = node.duplicate()
		for k in inh:
			pg[k] = inh[k]
		out.append(pg)


func _num(v) -> float:
	v = _get(v)
	return float(v) if (v is int or v is float) else 0.0


func _page_text(pg: Dictionary) -> Dictionary:
	var box = _get(pg.get(&"CropBox", pg.get(&"MediaBox", [0, 0, 595, 842])))
	var w := 595.0
	page_h = 842.0
	var y0 := 0.0
	if box is Array and box.size() == 4:
		w = _num(box[2]) - _num(box[0])
		page_h = _num(box[3]) - _num(box[1])
		y0 = _num(box[1])
	chunks = []
	cur = {}
	var contents = _get(pg.get(&"Contents"))
	var data := PackedByteArray()
	if contents is Array:
		for c in contents:
			var s = _get(c)
			if s is Dictionary:
				data.append_array(_decode_stream(s))
				data.append(10)
	elif contents is Dictionary:
		data = _decode_stream(contents)
	var res = _get(pg.get(&"Resources", {}))
	var ctm := Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(0, -y0))
	_run_content(data, res if res is Dictionary else {}, ctm, 0)
	_flush()
	return {"w": w, "h": page_h, "chunks": chunks}


func _flush() -> void:
	if cur.is_empty():
		return
	var t := str(cur.t).strip_edges()
	if t != "":
		chunks.append({"t": t, "x0": snappedf(cur.x0, 0.1), "x1": snappedf(cur.x1, 0.1), "y": snappedf(page_h - cur.y, 0.1), "s": snappedf(cur.s, 0.1)})
	cur = {}


## Adds a decoded text piece at user-space position (x, y), with advance.
func _emit(text: String, x: float, y: float, adv: float, size: float) -> void:
	if text == "":
		return
	if not cur.is_empty():
		var same_line := absf(y - cur.y) < maxf(size, cur.s) * 0.35
		var gap := x - float(cur.x1)
		if same_line and gap > -size * 0.6 and gap < size * 1.2:
			var space := gap > size * 0.15 and not str(cur.t).ends_with(" ") and not text.begins_with(" ")
			cur.t = str(cur.t) + (" " if space else "") + text
			cur.x1 = maxf(float(cur.x1), x + adv)
			cur.s = maxf(float(cur.s), size)
			return
		_flush()
	cur = {"t": text, "x0": x, "x1": x + adv, "y": y, "s": size}


static func _mat(o: Array, i := 0) -> Transform2D:
	return Transform2D(Vector2(float(o[i]), float(o[i + 1])), Vector2(float(o[i + 2]), float(o[i + 3])), Vector2(float(o[i + 4]), float(o[i + 5])))


static func _is_num(v) -> bool:
	return v is int or v is float


func _run_content(data: PackedByteArray, res: Dictionary, ctm0: Transform2D, depth: int) -> void:
	if data.is_empty() or depth > 8:
		return
	var save_buf := buf
	var save_pos := pos
	buf = data
	pos = 0
	var ctm := ctm0
	var gstack: Array = []
	var tm := Transform2D.IDENTITY
	var tlm := Transform2D.IDENTITY
	var font: Dictionary = {}
	var fsize := 1.0
	var leading := 0.0
	var tc := 0.0
	var tw := 0.0
	var th := 1.0
	var rise := 0.0
	var ops: Array = []
	var fonts = _get(res.get(&"Font", {}))
	var xobjs = _get(res.get(&"XObject", {}))
	var n := buf.size()
	while pos < n:
		var v = _parse_value()
		if v == null and pos >= n:
			break
		if not v is String:
			ops.append(v)
			continue
		var op: String = v
		var k := ops.size()
		match op:
			"q":
				gstack.append(ctm)
			"Q":
				if not gstack.is_empty():
					ctm = gstack.pop_back()
			"cm":
				if k >= 6 and _is_num(ops[k - 6]):
					ctm = ctm * _mat(ops, k - 6)
			"BT":
				tm = Transform2D.IDENTITY
				tlm = Transform2D.IDENTITY
			"Tf":
				if k >= 2:
					font = _font(fonts, ops[k - 2])
					fsize = float(ops[k - 1]) if _is_num(ops[k - 1]) else 1.0
			"TL":
				if k >= 1 and _is_num(ops[k - 1]):
					leading = float(ops[k - 1])
			"Tc":
				if k >= 1 and _is_num(ops[k - 1]):
					tc = float(ops[k - 1])
			"Tw":
				if k >= 1 and _is_num(ops[k - 1]):
					tw = float(ops[k - 1])
			"Tz":
				if k >= 1 and _is_num(ops[k - 1]):
					th = float(ops[k - 1]) / 100.0
			"Ts":
				if k >= 1 and _is_num(ops[k - 1]):
					rise = float(ops[k - 1])
			"Tm":
				if k >= 6 and _is_num(ops[k - 6]):
					tlm = _mat(ops, k - 6)
					tm = tlm
			"Td", "TD":
				if k >= 2 and _is_num(ops[k - 2]) and _is_num(ops[k - 1]):
					if op == "TD":
						leading = -float(ops[k - 1])
					tlm = tlm * Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(float(ops[k - 2]), float(ops[k - 1])))
					tm = tlm
			"T*":
				tlm = tlm * Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(0, -leading))
				tm = tlm
			"Tj", "'", "\"", "TJ":
				if op == "'" or op == "\"":
					if op == "\"" and k >= 3:
						tw = float(ops[k - 3])
						tc = float(ops[k - 2])
					tlm = tlm * Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(0, -leading))
					tm = tlm
				var items: Array = []
				if k >= 1:
					if ops[k - 1] is Array:
						items = ops[k - 1]
					else:
						items = [ops[k - 1]]
				for it in items:
					if it is PackedByteArray:
						var r := _show(it, font, fsize, tc, tw, th)
						var adv_w: float = r[1]
						var trm := ctm * tm * Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(0, rise))
						var p0: Vector2 = trm.origin
						var p1: Vector2 = (trm * Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(adv_w, 0))).origin
						var size := trm.y.length() * fsize * float(font.get("vscale", 1.0))
						_emit(r[0], p0.x, p0.y, maxf(0.0, p1.x - p0.x), size)
						tm = tm * Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(adv_w, 0))
					elif _is_num(it):
						var dx := -float(it) / 1000.0 * fsize * th
						tm = tm * Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(dx, 0))
			"Do":
				if k >= 1 and xobjs is Dictionary:
					var xo = _get(xobjs.get(ops[k - 1]))
					if xo is Dictionary and str(xo.get(&"Subtype", "")) == "Form":
						var m := Transform2D.IDENTITY
						var mm = _get(xo.get(&"Matrix"))
						if mm is Array and mm.size() == 6:
							m = _mat(mm)
						var xres = _get(xo.get(&"Resources", res))
						var sub := _decode_stream(xo)
						_run_content(sub, xres if xres is Dictionary else res, ctm * m, depth + 1)
			"BI":
				# inline image: skip to "EI"
				var j := pos
				while j < n - 2:
					if buf[j] == 69 and buf[j + 1] == 73 and WS.has(buf[j - 1]) and (j + 2 >= n or WS.has(buf[j + 2])):
						break
					j += 1
				pos = j + 2
		ops.clear()
	buf = save_buf
	pos = save_pos


## Decodes a shown string. Returns [text, advance in text space units].
func _show(s: PackedByteArray, font: Dictionary, fsize: float, tc: float, tw: float, th: float) -> Array:
	var text := ""
	var adv := 0.0
	var two: bool = font.get("two", false)
	var map: Dictionary = font.get("map", {})
	var widths: Dictionary = font.get("widths", {})
	var dw: float = font.get("dw", 500.0)
	var wscale: float = font.get("wscale", 0.001)
	var i := 0
	while i < s.size():
		var code := 0
		if two and i + 1 < s.size():
			code = (s[i] << 8) | s[i + 1]
			i += 2
		else:
			code = s[i]
			i += 1
		var ch := ""
		if map.has(code):
			ch = map[code]
		elif not two:
			ch = _win_ansi(code)
		var w := float(widths.get(code, dw)) * wscale * fsize
		adv += (w + tc + (tw if ch == " " else 0.0)) * th
		text += ch
	return [text, adv]


static func _win_ansi(code: int) -> String:
	if code < 32:
		return ""
	if code >= 128 and code < 160:
		const HI := {128: "€", 130: "‚", 132: "„", 133: "…", 145: "'", 146: "'", 147: "\"", 148: "\"", 149: "•", 150: "–", 151: "—", 153: "™"}
		return HI.get(code, "")
	return char(code)


func _font(fonts, name) -> Dictionary:
	if not fonts is Dictionary:
		return {}
	var ref = fonts.get(name)
	var key = ref if ref is Vector2i else "inline:" + str(name) + ":" + str(fonts.size())
	if font_cache.has(key):
		return font_cache[key]
	var f = _get(ref)
	var out := {"map": {}, "widths": {}, "two": false, "dw": 500.0, "wscale": 0.001, "vscale": 1.0}
	if f is Dictionary:
		var sub := str(f.get(&"Subtype", ""))
		if sub == "Type0":
			out.two = true
			out.dw = 1000.0
			var desc = _get(f.get(&"DescendantFonts"))
			if desc is Array and desc.size() > 0:
				var d = _get(desc[0])
				if d is Dictionary:
					out.dw = _num(d.get(&"DW", 1000))
					var warr = _get(d.get(&"W"))
					if warr is Array:
						var i := 0
						while i + 1 < warr.size():
							var c0 := int(_num(warr[i]))
							var nxt = _get(warr[i + 1])
							if nxt is Array:
								for j in nxt.size():
									out.widths[c0 + j] = _num(nxt[j])
								i += 2
							elif i + 2 < warr.size():
								var c1 := int(_num(nxt))
								var wv := _num(warr[i + 2])
								for c in range(c0, mini(c1, c0 + 65535) + 1):
									out.widths[c] = wv
								i += 3
							else:
								break
		else:
			var fc := int(_num(f.get(&"FirstChar", 0)))
			var wa = _get(f.get(&"Widths"))
			if wa is Array:
				for j in wa.size():
					out.widths[fc + j] = _num(wa[j])
			if sub == "Type3":
				var fm = _get(f.get(&"FontMatrix"))
				if fm is Array and fm.size() >= 4:
					out.wscale = _num(fm[0])
					out.vscale = absf(_num(fm[3])) / 0.001
			var enc = _get(f.get(&"Encoding"))
			if enc is Dictionary:
				var diffs = _get(enc.get(&"Differences"))
				if diffs is Array:
					var code := 0
					for d in diffs:
						if d is int:
							code = d
						elif d is StringName:
							var u := _glyph_name(str(d))
							if u != "":
								out.map[code] = u
							code += 1
		var tu = _get(f.get(&"ToUnicode"))
		if tu is Dictionary and tu.has("__stream"):
			var cmap := _parse_cmap(_decode_stream(tu))
			for c in cmap.map:
				out.map[c] = cmap.map[c]
			if sub == "Type0" and cmap.bytes == 1:
				out.two = false
	font_cache[key] = out
	return out


static func _glyph_name(g: String) -> String:
	const NAMES := {"space": " ", "agrave": "à", "egrave": "è", "eacute": "é", "igrave": "ì", "ograve": "ò", "ugrave": "ù",
		"Agrave": "À", "Egrave": "È", "Eacute": "É", "quoteright": "'", "quoteleft": "'", "quotesingle": "'", "quotedblleft": "\"", "quotedblright": "\"",
		"endash": "–", "emdash": "—", "bullet": "•", "hyphen": "-", "period": ".", "comma": ",", "colon": ":", "semicolon": ";",
		"plus": "+", "minus": "-", "parenleft": "(", "parenright": ")", "slash": "/", "percent": "%", "degree": "°",
		"guillemotleft": "«", "guillemotright": "»", "ellipsis": "…", "fi": "fi", "fl": "fl", "exclam": "!", "question": "?",
		"bracketleft": "[", "bracketright": "]", "equal": "=", "ampersand": "&", "asterisk": "*", "numbersign": "#"}
	if NAMES.has(g):
		return NAMES[g]
	if g.length() == 1:
		return g
	if g.begins_with("uni") and g.length() == 7 and g.substr(3).is_valid_hex_number():
		return char(g.substr(3).hex_to_int())
	const DIGITS := ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
	var di := DIGITS.find(g)
	if di >= 0:
		return str(di)
	return ""


func _parse_cmap(data: PackedByteArray) -> Dictionary:
	var out := {"map": {}, "bytes": 2}
	var save_buf := buf
	var save_pos := pos
	buf = data
	pos = 0
	var ops: Array = []
	var mode := ""
	var n := buf.size()
	while pos < n:
		var v = _parse_value()
		if v == null and pos >= n:
			break
		if v is String and v.begins_with("begin") or v is String and v.begins_with("end"):
			match v:
				"begincodespacerange", "beginbfchar", "beginbfrange":
					mode = v
				"endcodespacerange":
					if ops.size() >= 1 and ops[0] is PackedByteArray:
						out.bytes = maxi(1, ops[0].size())
				"endbfchar":
					var i := 0
					while i + 1 < ops.size():
						if ops[i] is PackedByteArray and ops[i + 1] is PackedByteArray:
							out.map[_code(ops[i])] = _utf16(ops[i + 1])
						i += 2
				"endbfrange":
					var i := 0
					while i + 2 < ops.size():
						var a = ops[i]
						var b = ops[i + 1]
						var d = ops[i + 2]
						if a is PackedByteArray and b is PackedByteArray:
							var c0 := _code(a)
							var c1 := mini(_code(b), c0 + 65535)
							if d is PackedByteArray:
								var base := _utf16(d)
								if base != "":
									var prefix := base.substr(0, base.length() - 1)
									var last := base.unicode_at(base.length() - 1)
									for c in range(c0, c1 + 1):
										out.map[c] = prefix + char(last + c - c0)
							elif d is Array:
								for j in d.size():
									if d[j] is PackedByteArray:
										out.map[c0 + j] = _utf16(d[j])
						i += 3
			if v.begins_with("end"):
				mode = ""
			ops.clear()
			continue
		if mode != "":
			ops.append(v)
	buf = save_buf
	pos = save_pos
	return out


static func _code(b: PackedByteArray) -> int:
	var v := 0
	for x in b:
		v = (v << 8) | x
	return v


static func _utf16(b: PackedByteArray) -> String:
	if b.size() == 1:
		return char(b[0])
	var s := ""
	var i := 0
	while i + 1 < b.size():
		var u := (b[i] << 8) | b[i + 1]
		i += 2
		if u >= 0xD800 and u <= 0xDBFF and i + 1 < b.size():
			var lo := (b[i] << 8) | b[i + 1]
			i += 2
			u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)
		if u == 0:
			continue
		s += char(u)
	return s
