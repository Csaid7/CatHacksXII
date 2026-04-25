extends CanvasLayer

# ── Node references ────────────────────────────────────────────────────────────
@onready var main_panel      = $Panel/VBox/MainMenu
@onready var host_panel      = $Panel/VBox/HostMenu
@onready var host_code_label = $Panel/VBox/HostMenu/GeneratedCode
@onready var join_panel      = $Panel/VBox/JoinMenu
@onready var code_input      = $Panel/VBox/JoinMenu/CodeInput
@onready var name_input      = $Panel/VBox/NameInput
@onready var error_label     = $Panel/VBox/ErrorLabel
@onready var bg_rect         = $ColorRect
@onready var waiting_panel   = $WaitingPanel
@onready var waiting_label   = $WaitingPanel/Label
@onready var host_hud        = $HostHUD
@onready var host_hud_label  = $HostHUD/Label

var _generated_code  := ""
var _is_hosting      := false
var _in_game_world   := false  # true once Panel+bg are hidden

# Created dynamically — host only
var _start_game_btn: Button = null


func _ready():
	error_label.text      = ""
	waiting_panel.visible = false
	host_panel.visible    = false
	join_panel.visible    = false
	host_hud.visible      = false

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
	_generated_code      = _generate_code()
	host_code_label.text = _generated_code
	main_panel.visible   = false
	host_panel.visible   = true


func _on_join_menu_pressed():
	main_panel.visible = false
	join_panel.visible = true


func _show_main_menu():
	host_panel.visible = false
	join_panel.visible = false
	main_panel.visible = true
	error_label.text   = ""


# ── Shared: enter game world ───────────────────────────────────────────────────

func _enter_game_world():
	$Panel.visible  = false
	bg_rect.visible = false
	_in_game_world  = true


# ── Host flow ──────────────────────────────────────────────────────────────────

func _on_start_host():
	var player_name = name_input.text.strip_edges()
	if player_name == "":
		error_label.text = "Enter your name."
		return
	error_label.text = ""
	_is_hosting = true
	NetworkManager.join_room(_generated_code, player_name)
	_enter_game_world()

	# Build the Start Game button as a sibling of the HostHUD panel,
	# NOT inside it — avoids Panel clipping issues.
	_start_game_btn              = Button.new()
	_start_game_btn.text         = "▶  Start Game"
	_start_game_btn.custom_minimum_size = Vector2(200, 40)
	# Anchor to top-left, just below the HostHUD (which has min-size 300×60)
	_start_game_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_start_game_btn.position     = Vector2(8, 72)
	_start_game_btn.pressed.connect(_on_start_game_pressed)
	add_child(_start_game_btn)   # child of CanvasLayer, not of HostHUD


func _on_start_game_pressed():
	if _start_game_btn:
		_start_game_btn.disabled = true
	NetworkManager.request_start_game()


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
	# Server confirmation arrives in _on_room_updated; enter game world there


# ── Server responses ───────────────────────────────────────────────────────────

func _on_room_updated(players: Array, your_id: String, player_count: int):
	# yourId is only sent once — on subsequent updates guard against overwriting with "".
	if your_id != "":
		get_parent().my_id = your_id

	# Enter the game world on first confirmed join (host already did this, but safe to repeat)
	if not _in_game_world:
		_enter_game_world()

	var names = []
	for p in players:
		names.append(p.get("name", "?"))

	# Everyone sees the same small corner HUD while in the lobby
	host_hud.visible    = true
	var room_label       = _generated_code if _is_hosting else code_input.text.to_upper()
	var waiting_line     = "" if _is_hosting else "\nWaiting for host to start..."
	host_hud_label.text  = (
		"Room: %s  |  Players: %d\n%s%s"
		% [room_label, player_count, "  ".join(names), waiting_line]
	)


func _on_game_starting(countdown: int):
	# Hide the lobby HUD for everyone
	host_hud.visible = false
	if _start_game_btn:
		_start_game_btn.visible = false

	if not _is_hosting:
		# Joiners get a brief countdown overlay
		waiting_panel.visible = true
		waiting_label.text    = "Game starting in %d..." % countdown
		await get_tree().create_timer(float(countdown)).timeout
		waiting_panel.visible = false

	self.visible = false


# ── Helpers ────────────────────────────────────────────────────────────────────

func _generate_code() -> String:
	var letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
	var code    = ""
	for i in 4:
		code += letters[randi() % letters.length()]
	return code
