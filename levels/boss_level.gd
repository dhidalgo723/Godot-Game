extends Node2D
# Sala del jefe: al cruzar el trigger, el ChairmanBoss aparece y la puerta
# se cierra detras del jugador. Al derrotarlo (o morir), la puerta se abre.

@onready var boss = $ChairmanBoss
@onready var trigger = $BossTrigger
@onready var gate = $Gate
@onready var gate_shape = $Gate/CollisionShape2D
var fight_started : bool = false
var player : Node = null

func _ready():
	player = get_tree().get_first_node_in_group("player")
	trigger.body_entered.connect(_on_trigger_body_entered)
	boss.boss_defeated.connect(_on_boss_defeated)
	# Limites de la sala para los ataques del jefe (de pared a pared, techo a suelo)
	boss.arena = Rect2(247, -74, 640, 240)
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
	GameManager.lock_camera_to_room(boss.arena)   # camara fija encuadrando la sala

func _on_boss_defeated():
	fight_started = false
	_open_gate()
	GameManager.unlock_camera()                   # la camara vuelve a la normalidad

func _open_gate():
	gate.visible = false
	gate_shape.set_deferred("disabled", true)

func _close_gate():
	gate.visible = true
	gate_shape.set_deferred("disabled", false)
