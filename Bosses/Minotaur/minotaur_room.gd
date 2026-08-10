extends Node2D
# Sala del Minotauro: la camara se amolda a la sala mientras dura la pelea y
# si el jugador muere el jefe vuelve a su sitio con toda su vida.

@export var camera_room : Rect2 = Rect2(128, -32, 880, 208)   # ← encuadre de la sala

@onready var boss = $Minotaur
var player : Node = null
var fight_started : bool = false

func _ready():
	player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(boss):
		boss.boss_defeated.connect(_on_boss_defeated)

func _process(_delta):
	if not is_instance_valid(boss):
		return
	# El Minotauro despierta por cercania: en cuanto lo hace, se fija la camara
	if boss.active and not fight_started:
		fight_started = true
		GameManager.lock_camera_to_room(camera_room)
	if fight_started and player != null and is_instance_valid(player) \
			and player.get("is_dead") == true:
		fight_started = false
		GameManager.unlock_camera()
		boss.reset_fight()

func _on_boss_defeated():
	fight_started = false
	GameManager.unlock_camera()
