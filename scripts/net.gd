class_name NetServer
extends Node
## Local network server on the master device.
## HTTP (port P) serves the player and shared-screen pages from res://web/.
## WebSocket (port P+1) carries real-time messages. Every client only gets
## the view allowed by the visibility rules (GameState.player_view / screen_view).

signal clients_changed
signal player_message(text: String)

const WEB_DIR := "res://web/"
const MAX_UPLOAD := 40 * 1024 * 1024
const ROUTES := {
	"/": ["index.html", "text/html; charset=utf-8"],
	"/index.html": ["index.html", "text/html; charset=utf-8"],
	"/giocatore": ["player.html", "text/html; charset=utf-8"],
	"/schermo": ["screen.html", "text/html; charset=utf-8"],
	"/spettatore": ["screen.html", "text/html; charset=utf-8"],
	"/common.js": ["common.js", "application/javascript; charset=utf-8"],
	"/dice3d.js": ["dice3d.js", "application/javascript; charset=utf-8"],
	"/style.css": ["style.css", "text/css; charset=utf-8"],
	"/sfx/tok1.wav": ["sfx/tok1.wav", "audio/wav"],
	"/sfx/tok2.wav": ["sfx/tok2.wav", "audio/wav"],
	"/sfx/tok3.wav": ["sfx/tok3.wav", "audio/wav"],
	"/sfx/crit.wav": ["sfx/crit.wav", "audio/wav"],
	"/sfx/fumble.wav": ["sfx/fumble.wav", "audio/wav"],
	"/sfx/turn.wav": ["sfx/turn.wav", "audio/wav"],
}

var state: GameState
var _img_path := RegEx.create_from_string("^/img/(m/|p/)?[a-z0-9_]+[.](jpg|png)$")
var http := TCPServer.new()
var ws_server := TCPServer.new()
var http_port := 0
var bind_addr := "*"
var running := false
var http_conns: Array = []
var clients: Dictionary = {}  # peer id -> {ws, token, role, char_id, t, open}
var next_peer := 1
var file_cache: Dictionary = {}
var broadcast_pending := false


func setup(s: GameState) -> void:
	state = s
	state.changed.connect(func(): broadcast_pending = true)
	state.roll_added.connect(_on_roll_added)
	state.request_added.connect(_on_request_added)


func start(addr := "*") -> bool:
	stop()
	bind_addr = addr
	for p in [8080, 8090, 8180, 8280, 8380]:
		if http.listen(p, addr) == OK:
			if ws_server.listen(p + 1, addr) == OK:
				http_port = p
				running = true
				return true
			http.stop()
	return false


func stop() -> void:
	for id in clients.keys():
		clients[id].ws.close()
	clients.clear()
	http.stop()
	ws_server.stop()
	running = false


func ws_port() -> int:
	return http_port + 1


static func local_ips() -> Array:
	var good: Array = []
	for ip in IP.get_local_addresses():
		if ip.contains(":"):
			continue
		if ip.begins_with("192.168.") or ip.begins_with("10.") or _is_172(ip):
			good.append(ip)
	good.sort_custom(func(a, b): return int(a.begins_with("192.168.")) > int(b.begins_with("192.168.")))
	return good


static func _is_172(ip: String) -> bool:
	if not ip.begins_with("172."):
		return false
	var parts := ip.split(".")
	return parts.size() > 1 and int(parts[1]) >= 16 and int(parts[1]) <= 31


func base_url() -> String:
	var ips := local_ips()
	var host: String = ips[0] if ips.size() > 0 else "127.0.0.1"
	if bind_addr != "*":
		host = bind_addr
	return "http://%s:%d" % [host, http_port]


## Connected phones and screens shown to the master. Spectators are left out:
## they only watch the public view and the master has nothing to manage.
func client_list() -> Array:
	var out: Array = []
	for id in clients:
		var c: Dictionary = clients[id]
		if not c.open or c.role == "spectator":
			continue
		out.append({"peer": id, "role": c.role, "char_id": c.char_id})
	return out


func _process(delta: float) -> void:
	if not running:
		return
	_poll_http(delta)
	_poll_ws(delta)
	if broadcast_pending:
		broadcast_pending = false
		broadcast_state()


# ------------------------------------------------------------------- HTTP
func _poll_http(delta: float) -> void:
	while http.is_connection_available():
		var tcp := http.take_connection()
		if tcp:
			http_conns.append({"tcp": tcp, "buf": PackedByteArray(), "t": 0.0, "done": false})
	for c in http_conns.duplicate():
		var tcp: StreamPeerTCP = c.tcp
		tcp.poll()
		c.t += delta
		var st := tcp.get_status()
		if st != StreamPeerTCP.STATUS_CONNECTED or c.t > (1.5 if c.done else 10.0):
			tcp.disconnect_from_host()
			http_conns.erase(c)
			continue
		if c.done:
			continue
		var n := tcp.get_available_bytes()
		if n > 0:
			var r := tcp.get_partial_data(n)
			if r[0] == OK:
				c.buf.append_array(r[1])
		if c.has("need"):
			# POST upload: wait for the whole body (keep alive while data arrives)
			if n > 0:
				c.t = 0.0
			if c.buf.size() >= int(c.need):
				c.done = true
				_respond_post(tcp, str(c.head), c.buf.slice(int(c.hlen), int(c.need)))
			continue
		var hend := _header_end(c.buf)
		if hend < 0:
			if c.buf.size() > 16384:
				c.done = true
			continue
		var head: String = c.buf.slice(0, hend).get_string_from_utf8()
		if head.begins_with("POST "):
			var m := RegEx.create_from_string("(?im)^content-length:\\s*(\\d+)").search(head)
			var ln := int(m.get_string(1)) if m else 0
			if ln <= 0 or ln > MAX_UPLOAD:
				c.done = true
				_send(tcp, "413 Payload Too Large", "application/json", JSON.stringify({"ok": false, "error": "File troppo grande o vuoto"}).to_utf8_buffer())
				continue
			c.head = head
			c.hlen = hend + 4
			c.need = hend + 4 + ln
			if c.buf.size() >= int(c.need):
				c.done = true
				_respond_post(tcp, head, c.buf.slice(int(c.hlen), int(c.need)))
			continue
		c.done = true
		_respond(tcp, head + "\r\n\r\n")


static func _header_end(b: PackedByteArray) -> int:
	var i := b.find(13)
	while i >= 0 and i + 3 < b.size():
		if b[i + 1] == 10 and b[i + 2] == 13 and b[i + 3] == 10:
			return i
		i = b.find(13, i + 1)
	return -1


func _send(tcp: StreamPeerTCP, code: String, ctype: String, body: PackedByteArray) -> void:
	var header := "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [code, ctype, body.size()]
	var out := header.to_utf8_buffer()
	out.append_array(body)
	tcp.put_data(out)


static func _query(path: String) -> Dictionary:
	var out := {}
	var q := path.find("?")
	if q < 0:
		return out
	for kv in path.substr(q + 1).split("&", false):
		var p := kv.split("=")
		out[p[0].uri_decode()] = (p[1].replace("+", " ").uri_decode() if p.size() > 1 else "")
	return out


## POST /importa-scheda?token=..&player=..  body = PDF bytes.
func _respond_post(tcp: StreamPeerTCP, head: String, body: PackedByteArray) -> void:
	var first := head.split("\r\n")[0].split(" ")
	var path := first[1] if first.size() > 1 else "/"
	var q := _query(path)
	var res := {"ok": false, "error": "Richiesta non valida"}
	if path.begins_with("/importa-scheda"):
		res = import_sheet_for(str(q.get("token", "")), body, str(q.get("player", "")).left(40))
	_send(tcp, "200 OK" if res.ok else "400 Bad Request", "application/json; charset=utf-8", JSON.stringify(res).to_utf8_buffer())


## Creates the character from a PDF sheet and gives it to the phone that sent it.
func import_sheet_for(token: String, bytes: PackedByteArray, player: String) -> Dictionary:
	var peer := -1
	for id in clients:
		if token.length() >= 8 and clients[id].token == token and clients[id].role == "player":
			peer = id
	if peer < 0:
		return {"ok": false, "error": "Telefono non collegato al tavolo: ricarica la pagina"}
	var doc := PdfText.extract(bytes)
	var count := 0
	for pg in doc.pages:
		count += pg.chunks.size()
	if count == 0:
		return {"ok": false, "error": str(doc.error) if str(doc.error) != "" else "Nel PDF non c'è testo leggibile (forse è una scansione)"}
	var res := SheetImport.parse(doc)
	var ch := state.import_character(res.char, player)
	var c: Dictionary = clients[peer]
	for tk in state.char_claimed_by(ch.id):
		state.data.claims.erase(tk)
	state.data.claims[c.token] = ch.id
	c.char_id = ch.id
	player_message.emit("Scheda PDF importata: %s" % ch.name)
	send(peer, {"t": "welcome", "token": c.token, "char_id": ch.id, "chars": state.char_choices(c.token)})
	_update_online()
	state.touch()
	return {"ok": true, "name": ch.name, "found": res.found}


func _respond(tcp: StreamPeerTCP, head: String) -> void:
	var first := head.split("\r\n")[0]
	var parts := first.split(" ")
	var path := "/"
	if parts.size() >= 2:
		path = parts[1]
	var q := path.find("?")
	if q >= 0:
		path = path.substr(0, q)
	var body := PackedByteArray()
	var ctype := "text/plain; charset=utf-8"
	var code := "200 OK"
	var extra := ""
	if ROUTES.has(path):
		var r: Array = ROUTES[path]
		body = _file(r[0])
		ctype = r[1]
		if body.is_empty():
			code = "500 Internal Server Error"
			body = "File mancante".to_utf8_buffer()
	elif path.begins_with("/csv/") and path.substr(5) == str(state.data.get("csv_token", "-")) + ".csv":
		body = PackedByteArray([0xEF, 0xBB, 0xBF])
		body.append_array(state.log_csv().to_utf8_buffer())
		ctype = "text/csv; charset=utf-8"
		extra = "Content-Disposition: attachment; filename=\"registro_tiri.csv\"\r\n"
	elif _img_path.search(path):
		body = _file(path.substr(1))
		ctype = "image/png" if path.ends_with(".png") else "image/jpeg"
		if body.is_empty():
			code = "404 Not Found"
			body = "Immagine mancante".to_utf8_buffer()
	elif path == "/favicon.ico":
		body = _file("img/icona.png")
		ctype = "image/png"
	else:
		code = "404 Not Found"
		body = "Pagina non trovata".to_utf8_buffer()
	var header := "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\n%sConnection: close\r\n\r\n" % [code, ctype, body.size(), extra]
	var out := header.to_utf8_buffer()
	out.append_array(body)
	tcp.put_data(out)


func _file(fname: String) -> PackedByteArray:
	if file_cache.has(fname):
		return file_cache[fname]
	var b := FileAccess.get_file_as_bytes(WEB_DIR + fname)
	if not b.is_empty():
		file_cache[fname] = b
	return b


# -------------------------------------------------------------- WebSocket
func _poll_ws(delta: float) -> void:
	while ws_server.is_connection_available():
		var tcp := ws_server.take_connection()
		if tcp == null:
			continue
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = 1 << 20
		ws.outbound_buffer_size = 1 << 21
		ws.max_queued_packets = 4096
		if ws.accept_stream(tcp) != OK:
			continue
		clients[next_peer] = {"ws": ws, "token": "", "role": "", "char_id": "", "t": 0.0, "open": false}
		next_peer += 1
	var changed := false
	for id in clients.keys():
		var c: Dictionary = clients[id]
		var ws: WebSocketPeer = c.ws
		ws.poll()
		c.t += delta
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_OPEN:
			c.open = true
			while ws.get_available_packet_count() > 0:
				var pkt := ws.get_packet().get_string_from_utf8()
				var msg = JSON.parse_string(pkt)
				if msg is Dictionary:
					if _on_message(id, msg):
						changed = true
		elif st == WebSocketPeer.STATE_CLOSED or (st == WebSocketPeer.STATE_CONNECTING and c.t > 15.0):
			clients.erase(id)
			changed = true
	if changed:
		_update_online()


func _update_online() -> void:
	var on := {}
	for id in clients:
		var c: Dictionary = clients[id]
		if c.open and c.char_id != "":
			on[c.char_id] = true
	if on != state.online_chars:
		state.online_chars = on
		broadcast_pending = true
	clients_changed.emit()


func send(id: int, obj: Dictionary) -> void:
	if not clients.has(id):
		return
	var ws: WebSocketPeer = clients[id].ws
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(obj))


func view_for(id: int) -> Dictionary:
	var c: Dictionary = clients[id]
	if c.role == "screen" or c.role == "spectator":
		return state.screen_view()
	return state.player_view(c.char_id)


func broadcast_state() -> void:
	for id in clients:
		var c: Dictionary = clients[id]
		if c.open and c.role != "":
			if c.role == "player" and c.char_id != "" and state.find_entity(c.char_id).is_empty():
				c.char_id = ""
				send(id, {"t": "welcome", "token": c.token, "char_id": "", "chars": state.char_choices(c.token)})
			send(id, {"t": "state", "s": view_for(id)})


func _on_roll_added(entry: Dictionary) -> void:
	if bool(entry.secret):
		return
	var pub := state.public_entry(entry)
	for id in clients:
		var c: Dictionary = clients[id]
		if c.open and c.role != "":
			send(id, {"t": "roll", "e": pub})


func _on_request_added(req: Dictionary) -> void:
	for id in clients:
		var c: Dictionary = clients[id]
		if c.open and c.role == "player" and req.chars.has(c.char_id):
			send(id, {"t": "request", "r": {"id": req.id, "type": req.type, "param": req.param,
				"label": state.request_label(req), "reason": req.reason}})


## Returns true when the online list may have changed.
func _on_message(id: int, msg: Dictionary) -> bool:
	var c: Dictionary = clients[id]
	var t := str(msg.get("t", ""))
	match t:
		"hello":
			var token := str(msg.get("token", "")).left(64)
			if token.length() < 8:
				token = "%08x%08x%08x" % [state.rng.randi(), state.rng.randi(), state.rng.randi()]
			c.token = token
			# "spectator" = a phone that only watches: same public view as the
			# shared screen, and every action message is refused (role != player)
			var r := str(msg.get("role", ""))
			c.role = r if r in ["screen", "spectator"] else "player"
			if c.role == "player":
				var cid := str(state.data.claims.get(token, ""))
				if cid != "" and state.find_entity(cid).is_empty():
					cid = ""
					state.data.claims.erase(token)
				c.char_id = cid
				send(id, {"t": "welcome", "token": token, "char_id": cid, "chars": state.char_choices(token),
					"campaign": state.data.get("name", "")})
			else:
				send(id, {"t": "welcome", "token": token, "char_id": "", "chars": []})
			send(id, {"t": "state", "s": view_for(id)})
			return true
		"claim":
			if c.role != "player":
				return false
			var cid := str(msg.get("char_id", ""))
			var ch := state.find_entity(cid)
			if ch.is_empty() or not state.is_pc(cid):
				send(id, {"t": "error", "text": "Personaggio non trovato"})
				return false
			for other in clients:
				if other != id and clients[other].char_id == cid and clients[other].open:
					send(id, {"t": "error", "text": "%s è già in uso su un altro dispositivo" % ch.name})
					return false
			for tk in state.char_claimed_by(cid):
				state.data.claims.erase(tk)
			state.data.claims[c.token] = cid
			c.char_id = cid
			player_message.emit("%s si è collegato" % ch.name)
			send(id, {"t": "welcome", "token": c.token, "char_id": cid, "chars": state.char_choices(c.token)})
			state.touch()
			return true
		"create_char":
			if c.role != "player":
				return false
			var ch := state.add_character(str(msg.get("name", "")), str(msg.get("player", "")))
			for tk in state.char_claimed_by(ch.id):
				state.data.claims.erase(tk)
			state.data.claims[c.token] = ch.id
			c.char_id = ch.id
			player_message.emit("Nuovo personaggio: %s" % ch.name)
			send(id, {"t": "welcome", "token": c.token, "char_id": ch.id, "chars": state.char_choices(c.token)})
			state.touch()
			return true
		"release":
			if c.char_id != "":
				state.data.claims.erase(c.token)
				c.char_id = ""
				send(id, {"t": "welcome", "token": c.token, "char_id": "", "chars": state.char_choices(c.token)})
				state.touch()
				return true
		"update_char":
			if c.role == "player" and c.char_id != "" and msg.get("char") is Dictionary:
				state.update_character(c.char_id, msg.char)
		"roll":
			if c.role == "player" and c.char_id != "":
				state.player_roll(c.char_id, msg)
		"hp":
			# -/+ buttons of the phone: same rules as the master's damage and healing
			if c.role == "player" and c.char_id != "":
				state.change_hp(c.char_id, clampi(int(msg.get("d", 0)), -999, 999))
		"slot":
			if c.role == "player" and c.char_id != "":
				state.use_slot(c.char_id, int(msg.get("lvl", 0)), clampi(int(msg.get("d", 0)), -1, 1))
		"cast":
			if c.role == "player" and c.char_id != "":
				var res := state.cast_spell(c.char_id, int(msg.get("i", -1)))
				if res == "":
					send(id, {"t": "toast", "text": "Nessuno slot libero per questo incantesimo"})
				else:
					send(id, {"t": "toast", "text": res})
					player_message.emit(res)
		"death_save":
			if c.role == "player" and c.char_id != "":
				# "v" = value of a real d20 typed in on the phone; otherwise the app rolls
				var typed := int(msg.get("v", 0))
				var real := typed >= 1 and typed <= 20
				var r := typed if real else state.rng.randi_range(1, 20)
				var res := state.death_save(c.char_id, r)
				if res != "":
					var how := " (dado vero)" if real else ""
					send(id, {"t": "toast", "text": "TS contro la morte: %d%s. %s" % [r, how, res]})
					player_message.emit("%s - TS contro la morte: %d%s. %s" % [state.find_entity(c.char_id).get("name", "?"), r, how, res])
		"ping":
			send(id, {"t": "pong"})
	return false


## Master action: free a character from its device.
func release_char(char_id: String) -> void:
	for tk in state.char_claimed_by(char_id):
		state.data.claims.erase(tk)
	for id in clients:
		var c: Dictionary = clients[id]
		if c.char_id == char_id:
			c.char_id = ""
			send(id, {"t": "welcome", "token": c.token, "char_id": "", "chars": state.char_choices(c.token)})
	_update_online()
	state.touch()
