class_name Ambience
extends Node
## Background sound of the place the party is in (cave drips, tavern chatter,
## wind...). The loops live in web/amb/ and are made by tools/make_ambience.py.
## The place is guessed from the words of the narrator: the last place word in a
## reply wins. Two players crossfade when the place changes, and the sound
## gets quieter while the master's voice is speaking.

const PLACES := {
	"grotta": ["grotta", "caverna", "miniera", "galleria", "tunnel", "cunicol", "stalattit"],
	"cripta": ["cripta", "tomba", "sotterrane", "catacomb", "tempio", "sepolcr", "mausole"],
	"bosco": ["bosco", "foresta", "alberi", "radura", "sentiero", "boschi", "sottobosco"],
	"locanda": ["locanda", "taverna", "osteria", "bancone"],
	"pioggia": ["pioggia", "piove", "temporale", "tempesta", "acquazzone"],
	"notte": ["notte", "stelle", "luna", "notturn"],
	"vento": ["vento", "montagna", "vetta", "rupe", "valico"],
	"mare": ["mare", "spiaggia", "porto", "onde", "nave", "molo", "scogli"],
	"fuoco": ["fuoco", "falò", "accampamento", "bivacco"],
}
const FADE := 2.5      # seconds of crossfade between two places
const LEVEL := 0.35    # loudness of the loop, 0..1
const DUCK := 0.45     # share of LEVEL kept while the voice speaks

var enabled := true
var current := ""      # place being played ("" = silence)
var voice: Voice       # optional: ducked while speaking

var _streams := {}
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _fade := 1.0       # 0..1 progress of the running crossfade (1 = done)
var _duck := 1.0


func _ready() -> void:
	_a = AudioStreamPlayer.new()
	_b = AudioStreamPlayer.new()
	for p in [_a, _b]:
		p.volume_db = -80.0
		add_child(p)


## Which place a piece of text talks about: the place word that comes last.
## Words must start at a word boundary ("mare" does not match "amare").
static func detect(text: String) -> String:
	var t := text.to_lower()
	var best := ""
	var best_at := -1
	for place in PLACES:
		for w in PLACES[place]:
			var at := t.rfind(w)
			while at > 0 and _letter(t.unicode_at(at - 1)):
				at = t.rfind(w, at - 1)
			if at > best_at:
				best_at = at
				best = place
	return best


static func _letter(c: int) -> bool:
	return (c >= 97 and c <= 122) or c >= 192


## Switches to the place named in the text, if any. Returns the place found.
func follow(text: String) -> String:
	var p := detect(text)
	if p != "":
		play(p)
	return p


func play(place: String) -> void:
	if place == current:
		return
	current = place
	if not enabled or not is_inside_tree():
		return
	var s := _stream(place)
	# the old loop fades out on _b, the new one fades in on _a
	var t := _a
	_a = _b
	_b = t
	_a.stream = s
	_a.volume_db = -80.0
	if s:
		_a.play()
	_fade = 0.0


func set_enabled(on: bool) -> void:
	enabled = on
	if not is_inside_tree():
		return
	if on:
		var p := current
		current = ""
		if p != "":
			play(p)
	else:
		_a.stop()
		_b.stop()


func playing() -> bool:
	return _a != null and _a.playing


func _stream(place: String) -> AudioStreamWAV:
	if _streams.has(place):
		return _streams[place]
	var s: AudioStreamWAV = null
	var b := FileAccess.get_file_as_bytes("res://web/amb/%s.wav" % place)
	if not b.is_empty():
		s = AudioStreamWAV.load_from_buffer(b)
		if s:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
	_streams[place] = s
	return s


func _process(delta: float) -> void:
	if not enabled or _a == null:
		return
	var speaking := voice != null and voice.speaking()
	_duck = move_toward(_duck, DUCK if speaking else 1.0, delta * 1.5)
	_fade = minf(1.0, _fade + delta / FADE)
	var lvl := LEVEL * _duck
	_a.volume_db = linear_to_db(maxf(lvl * _fade, 0.0001))
	_b.volume_db = linear_to_db(maxf(lvl * (1.0 - _fade), 0.0001))
	if _fade >= 1.0 and _b.playing:
		_b.stop()
