## NetworkManager.gd — Autoload singleton
## Add this as an Autoload in Project → Project Settings → Autoload
## Name it exactly "NetworkManager"
##
## It bridges Godot's GDScript to the Socket.io JS client running in the
## HTML page. All other scripts talk to the server through this one node.

extends Node

# ── Signals (other nodes connect to these) ────────────────────────────────────
signal room_updated(data)        # lobby: player list changed
signal game_starting(data)       # countdown before first round
signal round_started(data)       # new round: question + platform positions
signal state_updated(players)    # 20×/sec: everyone's positions
signal knockback_received(dir)   # server confirmed a hit on local player
signal tick_received(time_left)  # countdown each second
signal round_result(data)        # round ended: correct answer + scores
signal game_over(data)           # match finished

# ── Public state ──────────────────────────────────────────────────────────────
var my_id: String = ""

# ── Internal ──────────────────────────────────────────────────────────────────
const SERVER_URL := "http://localhost:3000"   # change to Railway URL before deploy


func _ready() -> void:
	if OS.get_name() == "Web":
		_inject_socket()
		# Grab our own socket id once connected
		JavaScriptBridge.eval("""
			window._socket.on('connect', function() {
				window._mySocketId = window._socket.id;
			});
		""")
	else:
		push_warning("NetworkManager: not running in browser — network disabled.")


# ── Inject Socket.io JS into the page and set up all listeners ────────────────
func _inject_socket() -> void:
	JavaScriptBridge.eval("""
		(function() {
			// Queues for GDScript to poll every frame
			window._gdEvent  = '';
			window._gdState  = '';
			window._gdKnock  = '';
			window._gdTick   = '';

			var s = window._socket;

			s.on('room_update',    function(d){ window._gdEvent = JSON.stringify({t:'room_update',    d:d}); });
			s.on('game_starting',  function(d){ window._gdEvent = JSON.stringify({t:'game_starting',  d:d}); });
			s.on('round_start',    function(d){ window._gdEvent = JSON.stringify({t:'round_start',    d:d}); });
			s.on('round_result',   function(d){ window._gdEvent = JSON.stringify({t:'round_result',   d:d}); });
			s.on('game_over',      function(d){ window._gdEvent = JSON.stringify({t:'game_over',      d:d}); });
			s.on('state_update',   function(d){ window._gdState = JSON.stringify(d); });
			s.on('apply_knockback',function(d){ window._gdKnock = JSON.stringify(d); });
			s.on('tick',           function(d){ window._gdTick  = JSON.stringify(d); });
		})();
	""")


# ── Poll JS queues every frame ─────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if OS.get_name() != "Web":
		return

	# Grab latest socket id (cheap string read)
	if my_id.is_empty():
		my_id = JavaScriptBridge.eval("window._mySocketId || ''")

	_poll_event()
	_poll_state()
	_poll_knockback()
	_poll_tick()


func _poll_event() -> void:
	var raw: String = JavaScriptBridge.eval("window._gdEvent || ''")
	if raw.is_empty():
		return
	JavaScriptBridge.eval("window._gdEvent = ''")
	var obj = JSON.parse_string(raw)
	if not obj:
		return
	match obj.t:
		"room_update":   room_updated.emit(obj.d)
		"game_starting": game_starting.emit(obj.d)
		"round_start":   round_started.emit(obj.d)
		"round_result":  round_result.emit(obj.d)
		"game_over":     game_over.emit(obj.d)


func _poll_state() -> void:
	var raw: String = JavaScriptBridge.eval("window._gdState || ''")
	if raw.is_empty():
		return
	JavaScriptBridge.eval("window._gdState = ''")
	var obj = JSON.parse_string(raw)
	if obj and obj.has("players"):
		state_updated.emit(obj.players)


func _poll_knockback() -> void:
	var raw: String = JavaScriptBridge.eval("window._gdKnock || ''")
	if raw.is_empty():
		return
	JavaScriptBridge.eval("window._gdKnock = ''")
	var obj = JSON.parse_string(raw)
	if obj:
		knockback_received.emit(obj.direction)


func _poll_tick() -> void:
	var raw: String = JavaScriptBridge.eval("window._gdTick || ''")
	if raw.is_empty():
		return
	JavaScriptBridge.eval("window._gdTick = ''")
	var obj = JSON.parse_string(raw)
	if obj:
		tick_received.emit(obj.timeLeft)


# ── Emit helpers (call these from any script) ─────────────────────────────────
func join_room(room_code: String, player_name: String) -> void:
	_emit("join_room", {"roomCode": room_code, "playerName": player_name})


func send_position(pos: Vector2, vel_y: float, facing: int) -> void:
	_emit("player_move", {"x": pos.x, "y": pos.y, "vy": vel_y, "facing": facing})


func send_attack(facing: int) -> void:
	_emit("player_attack", {"facing": facing})


func claim_point() -> void:
	_emit("claim_point", {})


func _emit(event: String, data: Dictionary) -> void:
	if OS.get_name() != "Web":
		return
	var json := JSON.stringify(data)
	JavaScriptBridge.eval("window._socket.emit('%s', %s)" % [event, json])
