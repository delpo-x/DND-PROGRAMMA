extends SceneTree
## godot --headless --path app --script res://tests/pdf_cli.gd -- <in.pdf> <out.txt> [sheet|story]

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	var bytes := FileAccess.get_file_as_bytes(a[0])
	var doc := PdfText.extract(bytes)
	var ms := Time.get_ticks_msec() - t0
	var out := "pages=%d error=%s ms=%d\n" % [doc.pages.size(), doc.error, ms]
	for i in doc.pages.size():
		out += "=== page %d\n" % (i + 1)
		for c in doc.pages[i].chunks:
			out += "[%.0f,%.0f s%.1f] %s\n" % [c.x0, c.y, c.s, c.t]
	if a.size() > 2 and a[2] == "sheet":
		out = JSON.stringify(SheetImport.parse(doc), "  ") + "

" + out
	if a.size() > 2 and a[2] == "story":
		var st: Dictionary = StoryImport.parse(doc, a[0])
		var o2: String = "TITLE " + st.title + "
"
		for c in st.chapters:
			o2 += "
##### " + c.title + " (" + str(c.text.length()) + ")
" + c.text.left(600) + "
"
		out = o2 + "

" + out
	var f := FileAccess.open(a[1], FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("done ", ms, " ms")
	quit()
