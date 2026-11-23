class_name PdfImages
extends PdfText
## Finds the pictures inside a PDF (battle maps are almost always one big
## image on a page) and decodes the one the master picks.
##
## Supported: JPEG (DCTDecode) and Flate-compressed RGB / gray / indexed
## pictures, 8 bits per component. JPEG 2000 and other filters are skipped.
## Vector maps (lines drawn by the PDF itself) are not pictures: for those the
## master can import a screenshot instead.

const MIN_SIDE := 300  # smaller pictures are icons and ornaments, not maps


## List of the big pictures: [{page (1-based), ref, w, h}], biggest first.
## Nothing is decoded yet, so this is quick even on long adventures.
static func list(bytes: PackedByteArray) -> Dictionary:
	var p := new()
	return p._list(bytes)


## Decodes the picture `ref` (from list) of the same PDF. Returns null if the
## format is not supported.
static func decode(bytes: PackedByteArray, ref: Vector2i) -> Image:
	var p := new()
	if not p._open(bytes):
		return null
	return p._decode_image(ref)


func _open(bytes: PackedByteArray) -> bool:
	buf = bytes
	src = bytes
	if buf.size() < 16 or buf.slice(0, 5).get_string_from_ascii() != "%PDF-":
		error = "Il file non è un PDF"
		return false
	if not _read_xref_chain():
		_scan_objects()
	var root = _get(trailer.get(&"Root"))
	if not root is Dictionary:
		_scan_objects()
		root = _get(trailer.get(&"Root"))
	if not root is Dictionary:
		error = "Struttura del PDF non riconosciuta"
		return false
	if trailer.has(&"Encrypt"):
		error = "Il PDF è protetto da password o cifrato"
		return false
	return true


func _list(bytes: PackedByteArray) -> Dictionary:
	if not _open(bytes):
		return {"images": [], "error": error}
	var pages: Array = []
	_collect_pages(_get(_get(trailer.get(&"Root")).get(&"Pages")), {}, pages, 0)
	var out: Array = []
	var seen := {}
	for i in pages.size():
		var res = _get(pages[i].get(&"Resources", {}))
		_walk_resources(res, i + 1, out, seen, 0)
	out.sort_custom(func(a, b): return int(a.w) * int(a.h) > int(b.w) * int(b.h))
	return {"images": out, "pages": pages.size(), "error": ""}


func _walk_resources(res, page: int, out: Array, seen: Dictionary, depth: int) -> void:
	if not res is Dictionary or depth > 6:
		return
	var xobjs = _get(res.get(&"XObject", {}))
	if not xobjs is Dictionary:
		return
	for k in xobjs:
		var ref = xobjs[k]
		if not ref is Vector2i or seen.has(ref):
			continue
		seen[ref] = true
		var xo = _get(ref)
		if not xo is Dictionary:
			continue
		var sub := str(xo.get(&"Subtype", ""))
		if sub == "Form":
			_walk_resources(_get(xo.get(&"Resources", {})), page, out, seen, depth + 1)
		elif sub == "Image":
			var w := int(_num(xo.get(&"Width")))
			var h := int(_num(xo.get(&"Height")))
			if mini(w, h) >= MIN_SIDE and _supported(xo):
				out.append({"page": page, "ref": ref, "w": w, "h": h})


func _filters(xo: Dictionary) -> Array:
	var f = _get(xo.get(&"Filter"))
	if f == null:
		return []
	if not f is Array:
		return [str(f)]
	var out: Array = []
	for x in f:
		out.append(str(_get(x)))
	return out


func _supported(xo: Dictionary) -> bool:
	var f := _filters(xo)
	if f.has("DCTDecode") or f.has("DCT"):
		return true
	for x in f:
		if not x in ["FlateDecode", "Fl"]:
			return false
	return int(_num(xo.get(&"BitsPerComponent", 8))) == 8


func _decode_image(ref: Vector2i) -> Image:
	var xo = _get(ref)
	if not xo is Dictionary:
		return null
	var raw: PackedByteArray = xo.get("__stream", PackedByteArray())
	var f := _filters(xo)
	var w := int(_num(xo.get(&"Width")))
	var h := int(_num(xo.get(&"Height")))
	var cs = _get(xo.get(&"ColorSpace"))
	if f.has("DCTDecode") or f.has("DCT"):
		if f.size() > 1 and (f[0] == "FlateDecode" or f[0] == "Fl"):
			raw = _inflate(raw)
		var img := Image.new()
		if img.load_jpg_from_buffer(raw) != OK:
			return null
		# Adobe CMYK JPEGs are often stored inverted (light becomes dark)
		if str(cs) == "DeviceCMYK" and _mean_luma(img) < 0.25:
			_invert(img)
		return img
	# Flate: raw pixels, optionally with a PNG predictor
	var comps := 3
	var palette := PackedByteArray()
	if cs is Array and cs.size() > 0:
		var kind := str(_get(cs[0]))
		if kind == "ICCBased" and cs.size() > 1:
			var icc = _get(cs[1])
			comps = int(_num(icc.get(&"N", 3))) if icc is Dictionary else 3
		elif kind == "Indexed" and cs.size() >= 4:
			comps = 1
			var base = _get(cs[1])
			var lookup = _get(cs[3])
			var base_n := 3
			if str(base) == "DeviceGray":
				base_n = 1
			elif base is Array and str(_get(base[0])) == "ICCBased":
				var icc2 = _get(base[1])
				base_n = int(_num(icc2.get(&"N", 3))) if icc2 is Dictionary else 3
			if lookup is Dictionary:
				lookup = _decode_stream(lookup)
			if not lookup is PackedByteArray or base_n == 4:
				return null
			palette = _palette_rgb(lookup, base_n)
		elif kind == "DeviceGray" or kind == "CalGray":
			comps = 1
		elif kind == "DeviceCMYK":
			comps = 4
	else:
		var cname := str(cs)
		comps = 1 if cname in ["DeviceGray", "CalGray"] else (4 if cname == "DeviceCMYK" else 3)
	var data := _inflate(raw)
	var parms = _get(xo.get(&"DecodeParms"))
	if parms is Array:
		parms = _get(parms[0]) if parms.size() > 0 else null
	if parms is Dictionary and int(_num(parms.get(&"Predictor", 1))) >= 10:
		data = _unpredict(data, w, comps * 8)
	if data.size() < w * h * comps:
		return null
	data = data.slice(0, w * h * comps)
	if not palette.is_empty():
		var rgb := PackedByteArray()
		rgb.resize(w * h * 3)
		var n_col := palette.size() / 3
		for i in w * h:
			var c := mini(data[i], n_col - 1) * 3
			rgb[i * 3] = palette[c]
			rgb[i * 3 + 1] = palette[c + 1]
			rgb[i * 3 + 2] = palette[c + 2]
		return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, rgb)
	if comps == 1:
		return Image.create_from_data(w, h, false, Image.FORMAT_L8, data)
	if comps == 4:
		var rgb2 := PackedByteArray()
		rgb2.resize(w * h * 3)
		for i in w * h:
			var k := 255 - data[i * 4 + 3]
			rgb2[i * 3] = (255 - data[i * 4]) * k / 255
			rgb2[i * 3 + 1] = (255 - data[i * 4 + 1]) * k / 255
			rgb2[i * 3 + 2] = (255 - data[i * 4 + 2]) * k / 255
		return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, rgb2)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, data)


static func _palette_rgb(lookup: PackedByteArray, base_n: int) -> PackedByteArray:
	if base_n == 3:
		return lookup
	var out := PackedByteArray()
	for v in lookup:
		out.append_array([v, v, v])
	return out


static func _mean_luma(img: Image) -> float:
	var s: Image = img.duplicate()
	s.resize(16, 16, Image.INTERPOLATE_BILINEAR)
	var t := 0.0
	for y in 16:
		for x in 16:
			t += s.get_pixel(x, y).get_luminance()
	return t / 256.0


static func _invert(img: Image) -> void:
	img.convert(Image.FORMAT_RGB8)
	var d := img.get_data()
	for i in d.size():
		d[i] = 255 - d[i]
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8, d)
