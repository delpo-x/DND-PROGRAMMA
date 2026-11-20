class_name Sfx
extends Node
## Sound effects for the master app. The WAV files live in web/sfx/ (shared with
## the phone pages) and are exported as-is, so they are loaded from bytes.

const NAMES := ["tok1", "tok2", "tok3", "crit", "fumble", "turn"]
const VOICES := 8

static var _streams: Dictionary = {}
static var _players: Array = []
static var _next := 0
static var played := 0  # how many sounds started (used by the tests)


static func _ensure(host: Node) -> void:
	if _streams.is_empty():
		for n in NAMES:
			var b := FileAccess.get_file_as_bytes("res://web/sfx/%s.wav" % n)
			if not b.is_empty():
				var s := AudioStreamWAV.load_from_buffer(b)
				if s:
					_streams[n] = s
	_players = _players.filter(func(p): return is_instance_valid(p))
	if _players.is_empty():
		var tree := host.get_tree()
		if tree == null:
			return
		for i in VOICES:
			var p := AudioStreamPlayer.new()
			tree.root.add_child.call_deferred(p)
			_players.append(p)


## Plays a sound; volume 0..1, pitch 1 = original.
static func play(host: Node, sound: String, volume := 1.0, pitch := 1.0) -> void:
	_ensure(host)
	if not _streams.has(sound) or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_next % _players.size()]
	_next += 1
	if not p.is_inside_tree():
		return
	p.stream = _streams[sound]
	p.volume_db = linear_to_db(clampf(volume, 0.01, 1.0))
	p.pitch_scale = pitch
	p.play()
	played += 1


## A die hitting the table or another die; speed is the velocity lost in the hit.
static func tok(host: Node, speed: float) -> void:
	play(host, "tok%d" % randi_range(1, 3), clampf(0.12 + speed / 16.0, 0.0, 1.0), randf_range(0.9, 1.15))
