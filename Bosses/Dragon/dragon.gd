extends CharacterBody2D
# Jefe Dragon. De momento solo la base: aparece cuando el jugador se acerca,
# lo persigue, recibe daño y muere. Tiene dos ataques preparados (attack1 y
# attack2) listos para rellenar cuando definamos que hace cada uno.
# Tocar su cuerpo tambien hace daño (BodyHitbox siempre activo).

signal boss_defeated

const GRAVITY = 1000
@export var max_hits : int = 14
@export var walk_speed : float = 55.0           # ← velocidad al acercarse
@export var attack_range : float = 90.0         # ← distancia a la que ataca
@export var attack_cooldown : float = 2.0       # ← segundos entre ataques
@export var activation_range : float = 260.0    # ← distancia a la que despierta

@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var hurtbox = $Hurtbox
@onready var attack_box_shape = $AttackBox/CollisionShape2D
@onready var boss_ui = $BossUI
@onready var health_bar = $BossUI/HealthBar

enum State { idle, run, attack, hurt, dead }
var current_state : State = State.idle
var current_hits : int = 0
var active : bool = false
var is_dead : bool = false
var player : Node = null
var start_position : Vector2
var facing : int = -1
var attack_cooldown_timer : float = 0.0
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
		# No despierta con el jugador muerto (si no, reiniciaria la pelea al instante)
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
			# TODO: activar el hitbox en los fotogramas que toquen de cada ataque
		_:
			_decide(delta)

	move_and_slide()

func _decide(_delta : float):
	if player == null or not is_instance_valid(player) or player.get("is_dead") == true:
		velocity.x = move_toward(velocity.x, 0, walk_speed)
		_play("idle")
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
		current_state = State.run
		_play("run")

func _face(dir : int):
	facing = dir
	# El sprite mira a la IZQUIERDA por defecto
	animated_sprite_2d.flip_h = dir > 0
	attack_box_shape.position.x = attack_offset * dir

func _play(anim : String):
	if animated_sprite_2d.animation != anim:
		animated_sprite_2d.play(anim)

func _start_attack():
	# De momento alterna los dos ataques; el comportamiento real va aparte
	current_state = State.attack
	attack_cooldown_timer = attack_cooldown
	velocity.x = 0
	animated_sprite_2d.stop()
	animated_sprite_2d.play("attack1" if randf() < 0.5 else "attack2")

func activate():
	if active or is_dead:
		return
	active = true
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
	current_state = State.hurt
	velocity.x = 0
	attack_box_shape.set_deferred("disabled", true)
	animated_sprite_2d.stop()
	animated_sprite_2d.play("hurt")

func die():
	is_dead = true
	active = false
	current_state = State.dead
	velocity.x = 0
	boss_ui.visible = false
	attack_box_shape.set_deferred("disabled", true)
	$BodyHitbox/CollisionShape2D.set_deferred("disabled", true)
	animated_sprite_2d.stop()
	animated_sprite_2d.play("death")
	boss_defeated.emit()

func _on_animation_finished():
	if current_state == State.attack:
		attack_box_shape.set_deferred("disabled", true)
		current_state = State.idle
	elif current_state == State.hurt:
		current_state = State.idle
	elif current_state == State.dead:
		# Se queda tumbado en el ultimo fotograma
		animated_sprite_2d.frame = animated_sprite_2d.sprite_frames.get_frame_count("death") - 1
