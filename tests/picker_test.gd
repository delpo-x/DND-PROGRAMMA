extends SceneTree
# Import buttons: every picker goes through main.open_file_dialog; the
# picked file is read and checked before the callback runs.
# godot --headless --path . -s tests/picker_test.gd

var fails := 0


func check(name: String, ok: bool, info = "") -> void:
	print(("ok   " if ok else "FAIL ") + name + " " + str(info))
	if not ok:
		fails += 1


## Picks `path` in the dialog the last call opened.
func choose(app, path: String) -> bool:
	for c in app.get_children():
		if c is FileDialog and not c.is_queued_for_deletion():
			c.file_selected.emit(path)
			return true
	return false


func _init() -> void:
	var app = load("res://scripts/main.gd").new()
	app.screenshot_path = "x"  # test mode: nothing is saved
	root.add_child(app)
	for i in 10:
		await process_frame
	var png := ProjectSettings.globalize_path("res://web/img/icona.png")
	var got: Array = []
	app.pick_image("img", func(img: Image, fname: String): got.append([img.get_width(), fname]))
	check("image dialog opened", choose(app, png))
	check("image read and decoded", got.size() == 1 and int(got[0][0]) > 0 and got[0][1] == "icona.png", got)
	got.clear()
	app.pick_pdf("pdf", func(bytes, fname): got.append(fname))
	choose(app, png)
	check("not a PDF: refused", got.is_empty())
	var tmp := OS.get_user_data_dir() + "/picker_test.pdf"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_buffer("\n%PDF-1.4\n%%EOF\n".to_utf8_buffer())
	f.close()
	app.pick_pdf("pdf", func(bytes, fname): got.append(fname))
	choose(app, tmp)
	check("PDF header after a junk byte accepted", got == ["picker_test.pdf"], got)
	got.clear()
	app.pick_pdf("pdf", func(bytes, fname): got.append(fname))
	choose(app, OS.get_user_data_dir() + "/manca.pdf")
	check("missing file: no callback", got.is_empty())
	var js := OS.get_user_data_dir() + "/picker_test.json"
	f = FileAccess.open(js, FileAccess.WRITE)
	f.store_string("{\"name\": \"Prova è\"}")
	f.close()
	app.pick_text_file("json", "*.json ; x", func(t): got.append(t))
	choose(app, js)
	check("text file read as UTF-8", got.size() == 1 and str(got[0]).contains("Prova è"), got)
	var out := OS.get_user_data_dir() + "/picker_out.txt"
	app.save_text_file("save", "a.txt", "*.txt ; x", "ciao")
	choose(app, out)
	check("save writes the file", FileAccess.get_file_as_string(out) == "ciao")
	for p in [tmp, js, out]:
		DirAccess.remove_absolute(p)
	await process_frame
	var left := 0
	for c in app.get_children():
		if c is FileDialog and not c.is_queued_for_deletion():
			left += 1
	check("dialogs freed", left == 0, left)
	print("picker test: " + ("OK" if fails == 0 else "%d FAIL" % fails))
	quit()
