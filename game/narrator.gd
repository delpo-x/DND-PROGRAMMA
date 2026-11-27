class_name Narrator
extends Node
## Local storyteller of Dnd The Game: streams replies from a model that runs
## on this PC through Ollama (http://127.0.0.1:11434). If Ollama is not
## running, it is started once ("ollama serve").
## A request with opts.cloud goes to Google Gemini instead (only when a key is
## set and today's calls are under the cap): used for the revision pass. The
## caller falls back to the local model when it fails.

signal chunk(text: String)
signal finished(full: String, ok: bool, tag: String)
signal status_changed(text: String)

const HOST := "127.0.0.1"
const PORT := 11434
const LOAD_TIMEOUT := 400.0  # seconds: the first reply also loads the model

## Chosen with tests/llm_bench.gd (see tests/llm_results/storico.csv).
const DEFAULT_MODEL := "gemma4:e4b-it-q4_K_M"

var model := DEFAULT_MODEL
var busy := false

# --- Gemini (optional, see ask with opts.cloud)
const GEMINI_HOST := "generativelanguage.googleapis.com"
const GEMINI_MODEL := "gemini-4-hydrogen"  # with thinking LOW: quick and careful
const GEMINI_CAP := 300  # calls per day: well under the free daily limit
const GEMINI_TIMEOUT := 25.0  # seconds without the first words: give up
const USAGE := "user://the_game/gemini_uso.json"
var gemini_key := ""
var gemini_model := GEMINI_MODEL
var gemini_cap := GEMINI_CAP
var gemini_used := 0  # calls today
var gemini_day := ""
var gemini_blocked := ""  # why Gemini is off until tomorrow ("" = usable)
var persist_usage := true
var last_cloud := false  # the last request went to Gemini
var _cloud := false
var _cloud_retry := 0  # 1: asked again with "low", 2: without thinking settings
var _cloud_msgs: Array = []
var _cloud_opts := {}
var status := "Narratore non ancora usato"

var _http: HTTPClient
var _phase := 0  # 0 idle, 1 connecting, 2 waiting for the reply, 3 reading, 4 waiting before a retry
var _body := ""
var _buf := PackedByteArray()
var _full := ""
var _tag := ""
var _clock := 0.0
var _tried_start := false
var _err_body := ""
## Numbers Ollama gives at the end of the last reply: prompt_eval_count,
## eval_count, eval_duration (ns), load_duration (ns)...
var last_stats := {}


## Sends a chat. messages: [{role, content}]. opts: {max: tokens, tag, temp}.
## Returns false when a reply is still being written.
func ask(messages: Array, opts := {}) -> bool:
	if busy:
		return false
	busy = true
	_full = ""
	_tag = str(opts.get("tag", ""))
	_buf = PackedByteArray()
	_err_body = ""
	last_stats = {}
	_cloud = bool(opts.get("cloud", false)) and cloud_ready()
	last_cloud = _cloud
	if _cloud:
		_cloud_msgs = messages
		_cloud_opts = opts
		_cloud_retry = 0
		_body = JSON.stringify(gemini_body(messages, opts, gemini_model, 0))
		_count_call()
		_connect()
		return true
	var options := {"temperature": float(opts.get("temp", 0.8)), "num_ctx": 4096,
		"num_predict": int(opts.get("max", 170)), "repeat_penalty": 1.1}
	# think false: models that reason before answering (qwen3.5, gemma4...)
	# would spend most of the time on hidden thoughts; the others ignore it
	var body := {"model": model, "messages": messages, "stream": true,
		"think": false, "keep_alive": "60m", "options": options}
	# a JSON schema: Ollama makes the model answer only with JSON of that shape
	if opts.has("format"):
		body["format"] = opts.format
	_body = JSON.stringify(body)
	_connect()
	return true


## Tag of the request being written ("" when idle).
func current_tag() -> String:
	return _tag if busy else ""


## Drops the request being written, without the finished signal. Closing the
## connection also stops Ollama, so the model is free at once.
func cancel() -> void:
	if not busy:
		return
	_phase = 0
	if _http:
		_http.close()
	busy = false


## Loads the model in memory, so the first real reply is not slow.
func warm_up() -> void:
	ask([{"role": "user", "content": "Rispondi solo: pronto"}], {"max": 2, "tag": "warm"})


func _connect() -> void:
	_http = HTTPClient.new()
	_clock = 0.0
	if _cloud:
		if _http.connect_to_host(GEMINI_HOST, 443, TLSOptions.client()) != OK:
			_done(false, "Gemini non raggiungibile")
			return
		_phase = 1
		return
	if _http.connect_to_host(HOST, PORT) != OK:
		_connect_failed()
		return
	_phase = 1


func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)


func _connect_failed() -> void:
	if _cloud:
		_done(false, "Gemini non raggiungibile (internet?)")
		return
	if not _tried_start:
		_tried_start = true
		var pid := OS.create_process("ollama", ["serve"])
		if pid > 0:
			_set_status("Avvio di Ollama...")
			_phase = 4
			_clock = 0.0
			return
	_done(false, "Narratore spento: Ollama non risponde. Installalo da ollama.com e scarica il modello con: ollama pull " + model)


func _process(delta: float) -> void:
	if _phase == 0:
		return
	_clock += delta
	if _phase == 4:
		if _clock > 5.0:
			_connect()
		return
	_http.poll()
	var s := _http.get_status()
	var broken := s in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE,
		HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]
	match _phase:
		1:
			if s == HTTPClient.STATUS_CONNECTED and _cloud:
				_http.request(HTTPClient.METHOD_POST, "/v1beta/models/%s:streamGenerateContent?alt=sse" % gemini_model.uri_encode(),
					["Content-Type: application/json", "x-goog-api-key: " + gemini_key], _body)
				_phase = 2
				_clock = 0.0
				_set_status("Gemini rilegge la bozza (%d di %d oggi)..." % [gemini_used, gemini_cap])
			elif s == HTTPClient.STATUS_CONNECTED:
				_http.request(HTTPClient.METHOD_POST, "/api/chat", ["Content-Type: application/json"], _body)
				_phase = 2
				_clock = 0.0
				if _tag == "secret" or _tag == "prep":
					pass  # silent work: the table must not see it
				elif _tag != "warm":
					_set_status("Il narratore pensa...")
				else:
					_set_status("Carico il modello %s (la prima volta serve un minuto)..." % model)
			elif broken or s == HTTPClient.STATUS_DISCONNECTED or _clock > (10.0 if _cloud else 6.0):
				_connect_failed()
		2:
			if s == HTTPClient.STATUS_BODY:
				_phase = 3
			elif s == HTTPClient.STATUS_CONNECTED and _http.has_response():
				_phase = 3
			elif broken or s == HTTPClient.STATUS_DISCONNECTED:
				_done(false, "Collegamento con Gemini interrotto" if _cloud else "Collegamento con Ollama interrotto")
			elif _cloud and _clock > GEMINI_TIMEOUT:
				_done(false, "Gemini non risponde da troppo tempo")
			elif _clock > LOAD_TIMEOUT:
				_done(false, "Il modello non risponde da troppo tempo")
		3:
			if s == HTTPClient.STATUS_BODY:
				var part := _http.read_response_body_chunk()
				if part.size() > 0:
					_buf.append_array(part)
					_drain()
			else:
				_drain()
				if _phase == 3:
					if _http.get_response_code() != 200:
						if _cloud:
							_cloud_failed()
						else:
							_done(false, _error_text())
					else:
						_done(true, "")
			if _cloud and _phase == 3 and _full == "" and _clock > GEMINI_TIMEOUT:
				_done(false, "Gemini non risponde da troppo tempo")


func _error_text() -> String:
	var txt := _err_body + _buf.get_string_from_utf8()
	if txt.contains("not found"):
		return "Modello %s non trovato: aprilo con  ollama pull %s" % [model, model]
	return "Errore del narratore (%d): %s" % [_http.get_response_code(), txt.strip_edges().left(160)]


## Reads the complete lines of the reply (one JSON object per line).
func _drain() -> void:
	if _cloud:
		_drain_cloud()
		return
	while _phase == 3:
		var nl := _buf.find(10)
		if nl < 0:
			return
		var line := _buf.slice(0, nl).get_string_from_utf8()
		_buf = _buf.slice(nl + 1)
		if line.strip_edges() == "":
			continue
		var j = JSON.parse_string(line)
		if not (j is Dictionary):
			continue
		if j.has("error"):
			_err_body = str(j.error)
			continue
		var piece := str(j.get("message", {}).get("content", ""))
		if piece != "":
			_full += piece
			if _tag != "warm":
				chunk.emit(piece)
		if bool(j.get("done", false)):
			last_stats = j
			_done(true, "")


func _done(ok: bool, why: String) -> void:
	_phase = 0
	if _http:
		_http.close()
	busy = false
	if ok:
		if _cloud:
			_set_status("Narratore pronto (%s; revisione Gemini %d di %d oggi)" % [model, gemini_used, gemini_cap])
		elif _tag != "secret":
			_set_status("Narratore pronto (%s, su questo PC)" % model)
	else:
		_set_status(why)
	# copies: GDScript passes members by reference, and the first listener may
	# start the next request (new _full and _tag) before the others hear this one
	var full := _full
	var tag := _tag
	finished.emit(full, ok, tag)


# -------------------------------------------------------------------- Gemini
## Gemini can be used now: a key, under today's cap, not blocked by Google.
func cloud_ready() -> bool:
	_roll_day()
	return gemini_key.strip_edges() != "" and gemini_blocked == "" and gemini_used < gemini_cap


## Short text for the settings: how many calls are left today.
func cloud_text() -> String:
	_roll_day()
	if gemini_key.strip_edges() == "":
		return "Gemini: manca la chiave"
	if gemini_blocked != "":
		return "Gemini fermo fino a domani: " + gemini_blocked
	return "Gemini: %d chiamate su %d oggi" % [gemini_used, gemini_cap]


## Loads today's count (the cap holds across restarts of the app).
func load_usage() -> void:
	if not persist_usage or not FileAccess.file_exists(USAGE):
		return
	var j = JSON.parse_string(FileAccess.get_file_as_string(USAGE))
	if j is Dictionary:
		gemini_day = str(j.get("day", ""))
		gemini_used = int(j.get("used", 0))
		gemini_blocked = str(j.get("blocked", ""))
	_roll_day()


func _roll_day() -> void:
	var today := Time.get_date_string_from_system()
	if gemini_day != today:
		gemini_day = today
		gemini_used = 0
		gemini_blocked = ""


func _count_call() -> void:
	_roll_day()
	gemini_used += 1
	_save_usage()


func _save_usage() -> void:
	if not persist_usage:
		return
	DirAccess.make_dir_recursive_absolute("user://the_game")
	var f := FileAccess.open(USAGE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"day": gemini_day, "used": gemini_used, "blocked": gemini_blocked}))


## The request for Gemini: the system lines become the system instruction,
## "assistant" becomes "model", and turns of the same role are joined.
## step: 0 the shortest thinking the model knows (the first word must come
## quickly), 1 "low" (when the model refused the first), 2 no thinking settings.
static func gemini_body(messages: Array, opts: Dictionary, model_name: String, step := 0) -> Dictionary:
	var sys := PackedStringArray()
	var contents: Array = []
	for m in messages:
		var role := str(m.get("role", "user"))
		var text := str(m.get("content", ""))
		if role == "system":
			sys.append(text)
			continue
		role = "model" if role == "assistant" else "user"
		if not contents.is_empty() and contents.back().role == role:
			contents.back().parts[0].text += "\n\n" + text
		else:
			contents.append({"role": role, "parts": [{"text": text}]})
	var config := {"temperature": float(opts.get("temp", 0.8)),
		"maxOutputTokens": int(opts.get("max", 170)) + 600}  # thinking counts as output
	if step == 1:
		config["thinkingConfig"] = {"thinkingLevel": "low"}
	elif step == 0:
		if model_name.contains("2.5"):
			config["thinkingConfig"] = {"thinkingBudget": 128 if model_name.contains("pro") else 0}
		elif model_name.begins_with("gemini-4") or model_name.contains("hydrogen"):
			# Gemini 4: LOW is the lowest level (MINIMAL and budgets are refused)
			config["thinkingConfig"] = {"thinkingLevel": "LOW"}
		else:
			config["thinkingConfig"] = {"thinkingLevel": "minimal"}
	var body := {"contents": contents, "generationConfig": config}
	if not sys.is_empty():
		body["systemInstruction"] = {"parts": [{"text": "\n\n".join(sys)}]}
	return body


## Text of one line of the Gemini stream ("data: {...}"); the hidden
## thoughts are skipped.
static func gemini_piece(line: String) -> String:
	var l := line.strip_edges()
	if not l.begins_with("data:"):
		return ""
	var parser := JSON.new()  # quiet: a broken line is only skipped
	if parser.parse(l.substr(5).strip_edges()) != OK or not parser.data is Dictionary:
		return ""
	var j: Dictionary = parser.data
	var out := ""
	for c in j.get("candidates", []):
		for p in c.get("content", {}).get("parts", []):
			if not bool(p.get("thought", false)):
				out += str(p.get("text", ""))
		break
	return out


func _drain_cloud() -> void:
	while _phase == 3:
		var nl := _buf.find(10)
		if nl < 0:
			return
		var line := _buf.slice(0, nl).get_string_from_utf8()
		_buf = _buf.slice(nl + 1)
		if _http.get_response_code() != 200:
			_err_body += line + "\n"
			continue
		var piece := gemini_piece(line)
		if piece != "":
			_full += piece
			chunk.emit(piece)


## Gemini answered with an error: thinking settings the model does not know
## are dropped once; a used-up quota or a wrong key stops Gemini for today.
func _cloud_failed() -> void:
	var code := _http.get_response_code()
	var txt := _err_body + _buf.get_string_from_utf8()
	if code == 400 and _cloud_retry < 2 and txt.to_lower().contains("think"):
		_cloud_retry += 1
		_buf = PackedByteArray()
		_err_body = ""
		_body = JSON.stringify(gemini_body(_cloud_msgs, _cloud_opts, gemini_model, _cloud_retry))
		_http.close()
		_connect()
		return
	if code == 429:
		gemini_blocked = "limite di uso raggiunto"
	elif code in [401, 403]:
		gemini_blocked = "chiave non valida"
	elif code == 404:
		gemini_blocked = "modello %s non trovato" % gemini_model
	if gemini_blocked != "":
		_save_usage()
	var msg := ""
	var j = JSON.parse_string(txt.strip_edges())
	if j is Dictionary and j.has("error"):
		msg = str(j.error.get("message", ""))
	_done(false, "Gemini (%d): %s" % [code, (gemini_blocked if gemini_blocked != "" else msg).left(140)])
