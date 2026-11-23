extends SceneTree
## godot --headless --path app -s tests/pdf_images_cli.gd -- <in.pdf> <out_dir>
## Lists the big pictures of a PDF and saves the first three as PNG.

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var bytes := FileAccess.get_file_as_bytes(a[0])
	var t0 := Time.get_ticks_msec()
	var r := PdfImages.list(bytes)
	print("pages=%s images=%d error=%s ms=%d" % [r.get("pages", 0), r.images.size(), r.error, Time.get_ticks_msec() - t0])
	for i in r.images.size():
		var it: Dictionary = r.images[i]
		print("  p%d %dx%d %s" % [it.page, it.w, it.h, it.ref])
		if i < 3:
			var img := PdfImages.decode(bytes, it.ref)
			print("    decoded: ", img != null)
			if img:
				img.save_png("%s/img_%d.png" % [a[1], i])
	quit()
