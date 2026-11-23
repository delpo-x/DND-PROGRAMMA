class_name Voice
extends RefCounted
## Spoken master: the system's own text-to-speech (Windows and Android
## voices), free and offline. Streamed text is spoken one sentence at a
## time, so the voice starts before the whole reply is written.

var enabled := true
var available := false
var voice_id := ""
var voice_name := ""
var rate := 1.0
var volume := 90

var _buf := ""
var _muted_rest := false  # set by stop(): the rest of the reply stays silent
var _in_tag := false  # inside a [[TAG]], which is never read aloud


func setup(wanted_id := "") -> void:
	available = false
	if DisplayServer.get_name() == "headless":
		return
	if not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		return
	var all: Array = DisplayServer.tts_get_voices()
	var it: Array = all.filter(func(v): return str(v.get("language", "")).to_lower().begins_with("it"))
	var pool: Array = it if not it.is_empty() else all
	if pool.is_empty():
		return
	var pick: Dictionary = pool[0]
	for v in pool:
		if str(v.get("id", "")) == wanted_id:
			pick = v
	voice_id = str(pick.get("id", ""))
	voice_name = str(pick.get("name", voice_id))
	available = true


func voices() -> Array:
	if not available:
		return []
	return DisplayServer.tts_get_voices()


## Text as it should be read aloud: no tags, markdown or stage symbols.
static func clean(t: String) -> String:
	var s := RegEx.create_from_string("\\[\\[[^\\]]*\\]\\]").sub(t, " ", true)
	var cut := s.find("[[")
	if cut >= 0:
		s = s.left(cut)
	for ch in ["*", "#", "_", "`", "→", "»", "«"]:
		s = s.replace(ch, " ")
	s = RegEx.create_from_string("\\([^)]*\\)").sub(s, "", true)
	s = RegEx.create_from_string("\\s+").sub(s, " ", true)
	return s.strip_edges()


func say(text: String) -> void:
	if not enabled or not available:
		return
	var t := clean(text)
	if t == "":
		return
	DisplayServer.tts_speak(t, voice_id, volume, 1.0, rate, 0, false)


func stop() -> void:
	_buf = ""
	_muted_rest = true
	if available:
		DisplayServer.tts_stop()


func speaking() -> bool:
	return available and DisplayServer.tts_is_speaking()


## Start of a streamed reply.
func begin() -> void:
	_buf = ""
	_muted_rest = false
	_in_tag = false


## A new piece of the reply: every finished sentence is spoken right away.
func feed(piece: String) -> void:
	if _muted_rest:
		return
	_buf += piece
	# markers are skipped, the text after them (often "Cosa fate?") is read
	while true:
		if _in_tag:
			var close := _buf.find("]]")
			if close < 0:
				return
			_buf = _buf.substr(close + 2)
			_in_tag = false
		var tag := _buf.find("[[")
		if tag < 0:
			break
		say(_buf.left(tag))
		_buf = _buf.substr(tag + 2)
		_in_tag = true
	while true:
		var best := -1
		for mark in [". ", "! ", "? ", "… ", ".\n", "!\n", "?\n", "\n\n"]:
			var i := _buf.find(mark)
			if i >= 0 and (best < 0 or i < best):
				best = i
		if best < 0:
			return
		say(_buf.left(best + 1))
		_buf = _buf.substr(best + 1)


## End of the reply: what is left is spoken.
func end() -> void:
	if not _muted_rest and not _in_tag:
		say(_buf)
	_buf = ""
