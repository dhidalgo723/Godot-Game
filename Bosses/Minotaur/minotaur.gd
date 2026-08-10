extends CharacterBody2D
# Jefe Minotauro: persigue al jugador andando, embiste cada cierto tiempo y
# golpea con el hacha cuando lo tiene cerca. Tocar su cuerpo tambien hace daño
# (el BodyHitbox esta siempre activo y en el grupo "enemy_attack").

signal boss_defeated

const GRAVITY = 1000
@export var max_hits : int = 10
@export var walk_speed : float = 45.0           # ← velocidad al acercarse andando
@export var attack_range : float = 62.0         # ← distancia a la que da el hachazo
@export var attack_cooldown : float = 1.8       # ← segundos entre hachazos
@export var activation_range : float = 220.0    # ← distancia a la que despierta

@export_group("Embestida")
@export var charge_enabled : bool = true
@export var charge_interval : float = 5.0       # ← cada cuanto embiste al jugador
@export var charge_telegraph : float = 0.6      # ← aviso quieto antes de arrancar
@export var charge_speed : float = 260.0        # ← velocidad de la embestida
@export var charge_duration : float = 1.1       # ← cuanto dura la embestida

@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var hurtbox = $Hurtbox
@onready var attack_box_shape = $AttackBox/CollisionShape2D
@onready var boss_ui = $BossUI
@onready var health_bar = $BossUI/HealthBar

enum State { idle, walk, attack, charge_warn, charge, hurt, dead }
var current_state : State = State.idle
var current_hits : int = 0
var active : bool = false
var is_dead : bool = false
var player : Node = null
var start_position : Vector2
var facing : int = -1
var attack_cooldown_timer : float = 0.0
var charge_timer : float = 0.0
var state_timer : float = 0.0
var attack_offset : float = 0.0

func _ready():
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	player = get_tree().get_first_node_in_group("player")
	start_position = global_position
	attack_offset = abs(attack_box_shape.position.x)
	attack_box_shape.disabled = true
	boss_ui.visible = false
	health_bar.max_value = max_hits
	health_bar.value = max_hits
	animated_sprite_2d.play("idle")

func _physics_process(delta : float):
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if is_dead:
		velocity.x = 0
		move_and_slide()
		return

	if not active:
		velocity.x = 0
		# No despierta ante un jugador muerto: si no, al morir a su lado volveria
		# a empezar la pelea al instante y la camara no llegaria a soltarse.
		if player != null and is_instance_valid(player) \
				and player.get("is_dead") != true \
				and global_position.distance_to(player.global_position) <= activation_range:
			activate()
		move_and_slide()
		return

	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta

	match current_state:
		State.hurt:
			velocity.x = move_toward(velocity.x, 0, walk_speed)
		State.attack:
			velocity.x = 0
			# El hacha solo hace daño en los fotogramas centrales del golpe
			var f = animated_sprite_2d.frame
			attack_box_shape.set_deferred("disabled", f < 2 or f > 3)
		State.charge_warn:
			velocity.x = 0
			state_timer -= delta
			if state_timer <= 0:
				_start_charge()
		State.charge:
			state_timer -= delta
			velocity.x = facing * charge_speed
			# Termina al agotarse el tiempo o al chocar contra una pared
			if state_timer <= 0 or is_on_wall():
				_end_charge()
		_:
			_decide(delta)

	move_and_slide()

func _decide(delta : float):
	if player == null or not is_instance_valid(player) or player.get("is_dead") == true:
		velocity.x = move_toward(velocity.x, 0, walk_speed)
		_play("idle")
		return

	if charge_enabled:
		charge_timer -= delta
		if charge_timer <= 0:
			_start_charge_warn()
			return

	var diff_x = player.global_position.x - global_position.x
	_face(1 if diff_x > 0 else -1)

	if abs(diff_x) <= attack_range:
		if attack_cooldown_timer <= 0:
			_start_attack()
		else:
			velocity.x = move_toward(velocity.x, 0, walk_speed)
			current_state = State.idle
			_play("idle")
	else:
		velocity.x = facing * walk_speed
		current_state = State.walk
		_play("walk")

func _face(dir : int):
	facing = dir
	animated_sprite_2d.flip_h = dir < 0
	attack_box_shape.position.x = attack_offset * dir

func _play(anim : String):
	if animated_sprite_2d.animation != anim:
		animated_sprite_2d.play(anim)

func _start_attack():
	current_state = State.attack
	attack_cooldown_timer = attack_cooldown
	velocity.x = 0
	animated_sprite_2d.stop()
	animated_sprite_2d.play("attack")

func _start_charge_warn():
	# Se planta y resopla: aviso para que el jugador pueda apartarse
	current_state = State.charge_warn
	state_timer = charge_telegraph
	charge_timer = charge_interval
	velocity.x = 0
	if player != null and is_instance_valid(player):
		_face(1 if player.global_position.x > global_position.x else -1)
	animated_sprite_2d.stop()
	animated_sprite_2d.play("idle")

func _start_charge():
	current_state = State.charge
	state_timer = charge_duration
	animated_sprite_2d.stop()
	animated_sprite_2d.play("walk")
	animated_sprite_2d.speed_scale = 2.0   # patas rapidas durante la embestida

func _end_charge():
	animated_sprite_2d.speed_scale = 1.0
	current_state = State.idle
	velocity.x = 0
	_play("idle")

func activate():
	if active or is_dead:
		return
	active = true
	charge_timer = charge_interval
	boss_ui.visible = true

func reset_fight():
	# Vuelve a su estado inicial (p. ej. si el jugador muere)
	if is_dead:
		return
	active = false
	current_hits = 0
	current_state = State.idle
	health_bar.value = max_hits
	boss_ui.visible = false
	velocity = Vector2.ZERO
	global_position = start_position
	animated_sprite_2d.speed_scale = 1.0
	attack_box_shape.set_deferred("disabled", true)
	_play("idle")

func _on_hurtbox_area_entered(area : Area2D):
	if area.name == "AttackBox" and active and not is_dead:
		receive_hit()

func receive_hit():
	current_hits += 1
	health_bar.value = max_hits - current_hits
	if current_hits >= max_hits:
		die()
		return
	# La embestida no se interrumpe: una vez lanzado no hay quien lo pare
	if current_state == State.charge:
		_flash()
		return
	current_state = State.hurt
	velocity.x = 0
	attack_box_shape.set_deferred("disabled", true)
	animated_sprite_2d.speed_scale = 1.0
	animated_sprite_2d.stop()
	animated_sprite_2d.play("hurt")

func _flash():
	animated_sprite_2d.modulate = Color(1, 0.4, 0.4)
	var tween = create_tween()
	tween.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.25)

func die():
	is_dead = true
	active = false
	current_state = State.dead
	velocity.x = 0
	boss_ui.visible = false
	attack_box_shape.set_deferred("disabled", true)
	$BodyHitbox/CollisionShape2D.set_deferred("disabled", true)
	animated_sprite_2d.speed_scale = 1.0
	animated_sprite_2d.stop()
	animated_sprite_2d.play("dead")
	boss_defeated.emit()

func _on_animation_finished():
	if current_state == State.attack:
		attack_box_shape.set_deferred("disabled", true)
		current_state = State.idle
	elif current_state == State.hurt:
		current_state = State.idle
	elif current_state == State.dead:
		# Se queda tumbado en el ultimo fotograma
		animated_sprite_2d.frame = animated_sprite_2d.sprite_frames.get_frame_count("dead") - 1
