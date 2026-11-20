extends SceneTree
## Rolls three dice in the master tray and checks that impact sounds play.
## Usage: godot --path app -s tests/sfx_test.gd

func _initialize() -> void:
	var tray := DiceTray.new()
	root.add_child(tray)
	await process_frame
	print("streams loaded: ", FileAccess.file_exists("res://web/sfx/tok1.wav"))
	tray.roll([{"type": "d20"}, {"type": "d6"}, {"type": "d8"}])
	var res: Array = await tray.finished
	print("results ", res, "  sounds played: ", Sfx.played, "  streams: ", Sfx._streams.size())
	quit(0 if Sfx.played > 0 and Sfx._streams.size() == 6 else 1)
