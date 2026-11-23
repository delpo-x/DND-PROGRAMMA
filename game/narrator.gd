class_name Narrator
extends Node
## Local storyteller of Dnd The Game: streams replies from a model that runs
## on this PC through Ollama (http://127.0.0.1:11434). Nothing goes on the
## internet. If Ollama is not running, it is started once ("ollama serve").

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
	var options := {"temperature": float(opts.get("temp", 0.8)), "num_ctx": 4096,
		"num_predict": int(opts.get("max", 170)), "repeat_penalty": 1.1}
	# think false: models that reason before answering (qwen3.5, gemma4...)
	# would spend most of the time on hidden thoughts; the others ignore it
	_body = JSON.stringify({"model": model, "messages": messages, "stream": true,
		"think": false, "keep_alive": "60m", "options": options})
	_connect()
	return true


## Loads the model in memory, so the first real reply is not slow.
func warm_up() -> void:
	ask([{"role": "user", "content": "Rispondi solo: pronto"}], {"max": 2, "tag": "warm"})


func _connect() -> void:
	_http = HTTPClient.new()
	_clock = 0.0
	if _http.connect_to_host(HOST, PORT) != OK:
		_connect_failed()
		return
	_phase = 1


func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)


func _connect_failed() -> void:
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
			if s == HTTPClient.STATUS_CONNECTED:
				_http.request(HTTPClient.METHOD_POST, "/api/chat", ["Content-Type: application/json"], _body)
				_phase = 2
				_clock = 0.0
				if _tag != "warm":
					_set_status("Il narratore pensa...")
				else:
					_set_status("Carico il modello %s (la prima volta serve un minuto)..." % model)
			elif broken or s == HTTPClient.STATUS_DISCONNECTED or _clock > 6.0:
				_connect_failed()
		2:
			if s == HTTPClient.STATUS_BODY:
				_phase = 3
			elif s == HTTPClient.STATUS_CONNECTED and _http.has_response():
				_phase = 3
			elif broken or s == HTTPClient.STATUS_DISCONNECTED:
				_done(false, "Collegamento con Ollama interrotto")
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
						_done(false, _error_text())
					else:
						_done(true, "")


func _error_text() -> String:
	var txt := _err_body + _buf.get_string_from_utf8()
	if txt.contains("not found"):
		return "Modello %s non trovato: aprilo con  ollama pull %s" % [model, model]
	return "Errore del narratore (%d): %s" % [_http.get_response_code(), txt.strip_edges().left(160)]


## Reads the complete lines of the reply (one JSON object per line).
func _drain() -> void:
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
		_set_status("Narratore pronto (%s, su questo PC)" % model)
	else:
		_set_status(why)
	finished.emit(_full, ok, _tag)
