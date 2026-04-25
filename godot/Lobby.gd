extends CanvasLayer

# ── Node references ────────────────────────────────────────────────────────────
@onready var main_panel      = $Panel/VBox/MainMenu
@onready var host_panel      = $Panel/VBox/HostMenu
@onready var host_code_label = $Panel/VBox/HostMenu/GeneratedCode
@onready var join_panel      = $Panel/VBox/JoinMenu
@onready var code_input      = $Panel/VBox/JoinMenu/CodeInput
@onready var name_input      = $Panel/VBox/NameInput
@onready var error_label     = $Panel/VBox/ErrorLabel
@onready var bg_rect         = $ColorRect  # the full-screen dark background

# Full-screen waiting panel (used by joiners only)
@onready var waiting_panel   = $WaitingPanel
@onready var waiting_label   = $WaitingPanel/Label

# Small corner HUD shown to the host while they wait in-game
# Add a Panel or Label called "HostHUD" as a direct child of the CanvasLayer
@onready var host_hud        = $HostHUD
@onready var host_hud_label  = $HostHUD/Label

var _generated_code := ""
var _is_hosting     := false


func _ready():
	error_label.text   = ""
	waiting_panel.visible = false
	host_panel.visible = false
	join_panel.visible = false
	host_hud.visible   = false

	NetworkManager.room_updated.connect(_on_room_updated)
	NetworkManager.game_starting.connect(_on_game_starting)

	$Panel/VBox/MainMenu/HostButton.pressed.connect(_on_host_pressed)
	$Panel/VBox/MainMenu/JoinButton.pressed.connect(_on_join_menu_pressed)
	$Panel/VBox/HostMenu/StartButton.pressed.connect(_on_start_host)
	$Panel/VBox/JoinMenu/JoinButton.pressed.connect(_on_join_pressed)
	$Panel/VBox/HostMenu/BackButton.pressed.connect(_show_main_menu)
	$Panel/VBox/JoinMenu/BackButton.pressed.connect(_show_main_menu)


# ── Main menu ──────────────────────────────────────────────────────────────────

func _on_host_pressed():
	_generated_code = _generate_code()
	host_code_label.text = _generated_code
	main_panel.visible = false
	host_panel.visible = true


func _on_join_menu_pressed():
	main_panel.visible = false
	join_panel.visible = true


func _show_main_menu():
	host_panel.visible = false
	join_panel.visible = false
	main_panel.visible = true
	error_label.text   = ""


# ── Host flow ──────────────────────────────────────────────────────────────────

func _on_start_host():
	var player_name = name_input.text.strip_edges()
	if player_name == "":
		error_label.text = "Enter your name."
		return
	error_label.text = ""
	_is_hosting = true
	NetworkManager.join_room(_generated_code, player_name)
	# Hide the form panel AND the dark background so the game world is visible
	$Panel.visible  = false
	bg_rect.visible = false


# ── Join flow ──────────────────────────────────────────────────────────────────

func _on_join_pressed():
	var player_name = name_input.text.strip_edges()
	var room_code   = code_input.text.strip_edges().to_upper()

	if player_name == "":
		error_label.text = "Enter your name."
		return
	if room_code.length() != 4:
		error_label.text = "Room code must be 4 letters."
		return

	error_label.text = ""
	NetworkManager.join_room(room_code, player_name)


# ── Server responses ───────────────────────────────────────────────────────────

func _on_room_updated(players: Array, your_id: String, player_count: int):
	# yourId is only sent once — when we first join.
	# Subsequent updates (other players joining) omit it, so guard against overwriting with "".
	if your_id != "":
		get_parent().my_id = your_id

	var names = []
	for p in players:
		names.append(p.get("name", "?"))

	if _is_hosting:
		# Host is already in the game world — just update the small corner HUD
		host_hud.visible = true
		host_hud_label.text = (
			"Room: %s  |  Players: %d\n%s"
			% [_generated_code, player_count, "  ".join(names)]
		)
	else:
		# Joiner sees a full-screen waiting screen until the game starts
		$Panel.visible = false
		waiting_panel.visible = true
		var code = code_input.text.to_upper()
		waiting_label.text = (
			"Room Code: %s\n\nWaiting for players... (%d)\n\n%s"
			% [code, player_count, "\n".join(names)]
		)


func _on_game_starting(countdown: int):
	# Hide everything — both host HUD and joiner waiting screen
	host_hud.visible   = false
	waiting_panel.visible = false

	if not _is_hosting:
		# Joiner needs a brief countdown overlay before the game reveals
		waiting_panel.visible = true
		waiting_label.text = "Game starting in %d..." % countdown
		await get_tree().create_timer(float(countdown)).timeout
		waiting_panel.visible = false

	self.visible = false


# ── Helpers ────────────────────────────────────────────────────────────────────

func _generate_code() -> String:
	var letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
	var code = ""
	for i in 4:
		code += letters[randi() % letters.length()]
	return code
