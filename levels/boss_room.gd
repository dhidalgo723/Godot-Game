extends Node2D
# Sala de jefe generica (igual que la del Chairman): al cruzar el trigger el
# jefe despierta, la puerta se cierra detras del jugador y la camara se fija
# encuadrando la sala. Al derrotarlo (o si el jugador muere) todo se reabre.
# El jefe necesita: activate(), reset_fight(), is_dead y la señal boss_defeated.

@export var boss_path : NodePath = ^"Boss"
@export var arena : Rect2 = Rect2(32, -64, 656, 224)   # ← limites de la sala

@onready var boss = get_node(boss_path)
@onready var trigger = $BossTrigger
@onready var gate = $Gate
@onready var gate_shape = $Gate/CollisionShape2D
var fight_started : bool = false
var player : Node = null

func _ready():
	player = get_tree().get_first_node_in_group("player")
	trigger.body_entered.connect(_on_trigger_body_entered)
	boss.boss_defeated.connect(_on_boss_defeated)
	if "arena" in boss:
		boss.arena = arena
	# Aqui el jefe solo despierta con el trigger, no por cercania
	if "activation_range" in boss:
		boss.activation_range = -1.0
	_open_gate()

func _process(_delta):
	# Si el jugador muere durante la pelea, la sala se reinicia
	if fight_started and player != null and is_instance_valid(player) \
			and player.get("is_dead") == true:
		fight_started = false
		_open_gate()
		GameManager.unlock_camera()
		if is_instance_valid(boss):
			boss.reset_fight()

func _on_trigger_body_entered(body : Node2D):
	if fight_started or not body.is_in_group("player"):
		return
	if not is_instance_valid(boss) or boss.is_dead:
		return
	fight_started = true
	boss.activate()
	_close_gate()
	GameManager.lock_camera_to_room(arena)

func _on_boss_defeated():
	fight_started = false
	_open_gate()
	GameManager.unlock_camera()

func _open_gate():
	gate.visible = false
	gate_shape.set_deferred("disabled", true)

func _close_gate():
	gate.visible = true
	gate_shape.set_deferred("disabled", false)
