extends Control

@onready var name_input = $VBoxContainer/NameInput
@onready var room_input = $VBoxContainer/RoomInput
@onready var join_button = $VBoxContainer/JoinButton

func _ready():
	print("Lobby _ready called")
	print("join_button: ", join_button)
	join_button.pressed.connect(_on_join_button_pressed)

func _on_join_button_pressed():
	var player_name = name_input.text.strip_edges()
	var room_code = room_input.text.strip_edges().to_upper()
	if player_name == "" or room_code == "":
		return
	join_button.disabled = true
	NetworkManager.join_room(room_code, player_name)
	NetworkManager.on_room_update.connect(_on_room_update)

func _on_room_update(_data):
	NetworkManager.on_room_update.disconnect(_on_room_update)
	get_tree().change_scene_to_file("res://main.tscn")
