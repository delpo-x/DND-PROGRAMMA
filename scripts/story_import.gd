class_name StoryImport
extends RefCounted
## Turns an adventure PDF (see PdfText) into chapters for the campaign:
##   {title, source, chapters: [{title, text}]}
## Chapters start at the biggest headings; smaller headings become "## " lines
## inside the text. Repeated page headers/footers are dropped.


static func _re(p: String) -> RegEx:
	var r := RegEx.new()
	r.compile(p)
	return r


static func parse(doc: Dictionary, source: String) -> Dictionary:
	var pages: Array = doc.get("pages", [])
	# body size = the size carrying most characters
	var weight := {}
	for pg in pages:
		for c in pg.chunks:
			var k := snappedf(float(c.s), 0.5)
			weight[k] = int(weight.get(k, 0)) + str(c.t).length()
	var body := 10.0
	var bw := -1
	for k in weight:
		if int(weight[k]) > bw:
			bw = int(weight[k])
			body = float(k)
	# repeated headers / footers (same text, digits ignored, on many pages)
	var digits := _re("\\d+")
	var rep := {}
	for pg in pages:
		var seen := {}
		for c in pg.chunks:
			var key := digits.sub(str(c.t), "#", true)
			if not seen.has(key):
				seen[key] = true
				rep[key] = int(rep.get(key, 0)) + 1
	var min_rep := maxi(3, int(pages.size() * 0.4))
	# heading levels
	var h_sizes := {}
	for pg in pages:
		for c in pg.chunks:
			if float(c.s) >= body * 2.0 and str(c.t).length() <= 90 and str(c.t).length() >= 3:
				var hk := snappedf(float(c.s), 0.5)
				if not h_sizes.has(hk):
					h_sizes[hk] = {}
				h_sizes[hk][str(c.t)] = true
	var sizes := h_sizes.keys()
	sizes.sort()
	sizes.reverse()
	# document title = biggest text on page 1
	var title := source.get_basename().replace("_", " ")
	if pages.size() > 0:
		var big := 0.0
		for c in pages[0].chunks:
			if float(c.s) > big and str(c.t).length() > 2:
				big = float(c.s)
				title = str(c.t)
	# chapter size: the big heading size used by the most different titles
	var chap_size := body * 2.0
	var best_n := 1
	for s in sizes:
		if h_sizes[s].size() > best_n:
			best_n = h_sizes[s].size()
			chap_size = float(s)
	var chapters: Array = []
	var cur := {"title": "Introduzione", "lines": PackedStringArray()}
	var para := ""
	var last: Dictionary = {}
	for pi in pages.size():
		for c in pages[pi].chunks:
			var t := str(c.t).strip_edges()
			if t == "" or int(rep.get(digits.sub(t, "#", true), 0)) >= min_rep:
				continue
			var s := float(c.s)
			if absf(snappedf(s, 0.5) - chap_size) < 0.01 and t.length() <= 90 and not (pi == 0 and t == title):
				if t == str(cur.title):
					continue
				if para != "":
					cur.lines.append(para)
					para = ""
				if cur.lines.size() > 0:
					chapters.append(cur)
				cur = {"title": t, "lines": PackedStringArray()}
				last = {"p": pi, "y": c.y, "s": s, "x0": c.x0, "head": true}
				continue
			if s >= body * 1.3 and t.length() <= 90:
				if para != "":
					cur.lines.append(para)
					para = ""
				cur.lines.append("## " + t)
				last = {"p": pi, "y": c.y, "s": s, "x0": c.x0, "head": false, "sub": true}
				continue
			var cont := false
			if para != "" and not last.is_empty() and not last.get("sub", false) and int(last.p) == pi:
				var dy := float(c.y) - float(last.y)
				cont = dy > 0 and dy < s * 1.75 and absf(float(c.x0) - float(last.x0)) < s * 3 and absf(s - float(last.s)) < 1.0
			elif para != "" and not last.is_empty() and int(last.p) != pi:
				cont = not _re("[.!?:»\"]$").search(para)
			if cont:
				if para.ends_with("-") and not para.ends_with(" -"):
					para = para.substr(0, para.length() - 1) + t
				else:
					para += " " + t
			else:
				if para != "":
					cur.lines.append(para)
				para = t
			last = {"p": pi, "y": c.y, "s": s, "x0": c.x0, "head": false}
	if para != "":
		cur.lines.append(para)
	if cur.lines.size() > 0:
		chapters.append(cur)
	var out: Array = []
	for ch in chapters:
		var txt := "\n\n".join(ch.lines).replace("\n\n## ", "\n\n## ")
		out.append({"title": str(ch.title).left(90), "text": txt})
	return {"title": title.left(90), "source": source.get_file(), "chapters": out, "pcs": find_pcs(pages)}


## Ready-made characters listed in the adventure: a name followed (just below)
## by "race, class" (e.g. "Aelyra" / "elfa, maga"). Stats mentioned in the text
## as "Name (CA 20, 84 PF ...)" are picked up too.
static func find_pcs(pages: Array) -> Array:
	var cls_re := _re("(?i)\\b(" + "|".join(SheetImport.CLASSES) + ")\\b")
	var all_text := ""
	for pg in pages:
		for c in pg.chunks:
			all_text += str(c.t) + "\n"
	var lvl_m := _re("(?i)\\b(?:pg|personaggi)\\s+di\\s+(?:livello\\s+)?(\\d{1,2})|livello\\s+(\\d{1,2})").search(all_text)
	var level := 1
	if lvl_m:
		level = int(lvl_m.get_string(1) if lvl_m.get_string(1) != "" else lvl_m.get_string(2))
	var out: Array = []
	var seen := {}
	for pi in mini(pages.size(), 4):
		var ch: Array = pages[pi].chunks
		for i in ch.size():
			var name := str(ch[i].t).strip_edges()
			if name.length() < 2 or name.length() > 30 or not _re("^\\p{Lu}[\\p{L}' -]+$").search(name) or seen.has(name):
				continue
			for j in range(i + 1, mini(i + 4, ch.size())):
				var d: Dictionary = ch[j]
				var dy := float(d.y) - float(ch[i].y)
				if dy <= 0 or dy > float(ch[i].s) * 2.0 or absf((float(d.x0) + float(d.x1)) / 2.0 - (float(ch[i].x0) + float(ch[i].x1)) / 2.0) > 60:
					continue
				var desc := str(d.t).strip_edges()
				var parts := desc.split(",")
				var cm := cls_re.search(desc)
				if parts.size() >= 2 and cm and desc.length() <= 40:
					seen[name] = true
					var pc := {"name": name, "race": parts[0].strip_edges().capitalize(), "cls": cm.get_string(1).capitalize(), "level": clampi(level, 1, 20)}
					var sm := _re("(?i)" + SheetImport._esc(name) + "\\s*\\(\\s*CA\\s*(\\d{1,2})\\s*,\\s*(\\d{1,3})\\s*PF(?:[^)]*?attacchi?\\s*a\\s*([+-]\\d{1,2}))?").search(all_text)
					if sm:
						pc.ac = int(sm.get_string(1))
						pc.hp_max = int(sm.get_string(2))
						pc.hp = pc.hp_max
						if sm.get_string(3) != "":
							pc.attacks = [{"name": "Attacco", "bonus": int(sm.get_string(3)), "damage": "1d8"}]
					out.append(pc)
					break
	return out
