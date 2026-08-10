extends CharacterBody2D
@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var attack_box = $AttackBox
@onready var attack_shape = $AttackBox/CollisionShape2D          # ← shape derecha
@onready var attack_shape_left = $AttackBox/CollisionShape2DLeft # ← shape izquierda
@onready var hurtbox = $HurtBox
@onready var health_bar = $PlayerUI/HealthBar
const GRAVITY = 1000
@export var speed: int = 300
@export var jump: int = -400
@export var jump_horizontal: int = 100
@export var roll_speed: int = 250
@export var max_health: int = 5
enum State { idle, run, jump, attack, roll, hurt, dead, turnaround, wall_hang }
var current_state : State
var character_sprite: Sprite2D
var jump_count: int = 0
const MAX_JUMPS: int = 2
var is_attacking: bool = false
var is_rolling: bool = false
var roll_direction: float = 1.0
var facing_dir: int = 0            # ← ultima direccion de carrera (para TurnAround)
var health: int
var is_hurt: bool = false
var is_dead: bool = false
var invulnerable_timer: float = 0.0
var hurt_timer: float = 0.0
var respawn_timer: float = 0.0
var respawn_default: Vector2
const INVULNERABLE_TIME: float = 1.0   # segundos sin poder recibir daño tras un golpe
const HURT_TIME: float = 0.35          # segundos sin control tras un golpe
const RESPAWN_DELAY: float = 0.8       # segundos hasta reaparecer tras morir

func _ready():
	add_to_group("player")
	health = max_health
	respawn_default = global_position   # si no hay checkpoint, reaparece donde empezó
	current_state = State.idle
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	attack_shape.disabled = true
	attack_shape_left.disabled = true   # ← ambos empiezan desactivados
	update_health_bar()

func _physics_process(delta : float):
	if is_dead:
		respawn_timer -= delta
		velocity.x = 0
		player_faling(delta)
		move_and_slide()
		if respawn_timer <= 0:
			respawn()
		return
	if invulnerable_timer > 0:
		invulnerable_timer -= delta
		animated_sprite_2d.visible = int(invulnerable_timer * 10) % 2 == 0  # parpadeo
		if invulnerable_timer <= 0:
			animated_sprite_2d.visible = true
	if is_hurt:
		hurt_timer -= delta
		player_faling(delta)
		move_and_slide()
		if hurt_timer <= 0:
			is_hurt = false
			current_state = State.idle
		return
	check_contact_damage()
	if not is_attacking and not is_rolling and handle_wall(delta):
		return
	player_faling(delta)
	player_attack()
	player_roll()
	if not is_attacking and not is_rolling:
		player_idle(delta)
		player_run(delta)
		player_jump(delta)
	move_and_slide()
	player_animation()

func player_faling(delta : float):
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		jump_count = 0

func player_idle(delta : float):
	if is_on_floor() and current_state != State.turnaround:
		current_state = State.idle

func player_run(delta : float):
	var direction = Input.get_axis("move_left", "move_right")
	if direction:
		velocity.x = direction * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
	if direction != 0 and is_on_floor():
		var new_dir = 1 if direction > 0 else -1
		# TurnAround: gira de golpe mientras corre
		if facing_dir != 0 and new_dir != facing_dir and current_state != State.turnaround:
			current_state = State.turnaround
			animated_sprite_2d.stop()
			animated_sprite_2d.play("turnaround")
		elif current_state != State.turnaround:
			current_state = State.run
		facing_dir = new_dir
		animated_sprite_2d.flip_h = new_dir < 0

func player_jump(delta : float):
	if Input.is_action_just_pressed("jump") and jump_count < MAX_JUMPS:
		velocity.y = jump
		current_state = State.jump
		jump_count += 1
	if not is_on_floor() and current_state == State.jump:
		var direction = Input.get_axis("move_left", "move_right")
		velocity.x += direction * jump_horizontal * delta

# ---------- Movimiento en paredes (agarre estatico, sin trepar) ----------

func handle_wall(delta : float) -> bool:
	var was_on_wall = current_state == State.wall_hang
	if not is_on_wall_only():
		if was_on_wall:
			current_state = State.idle if is_on_floor() else State.jump
		return false
	var direction = Input.get_axis("move_left", "move_right")
	var wall_normal = get_wall_normal()
	# Hay que empujar hacia la pared para mantenerse agarrado
	if direction == 0 or sign(direction) == sign(wall_normal.x):
		if was_on_wall:
			current_state = State.jump
		return false
	jump_count = 0
	animated_sprite_2d.flip_h = wall_normal.x > 0   # pared a la izquierda → mira izquierda
	# Salto de pared: se impulsa en diagonal alejandose de la pared
	if Input.is_action_just_pressed("jump"):
		velocity = Vector2(wall_normal.x * speed * 0.8, jump * 0.9)
		current_state = State.jump
		animated_sprite_2d.play("jump")
		move_and_slide()
		return true
	current_state = State.wall_hang
	velocity.y = 0
	play_wall_anim("wallclimbnomove")
	velocity.x = -wall_normal.x * 30    # presion contra la pared para no soltarse
	move_and_slide()
	return true

func play_wall_anim(anim_name : String):
	if animated_sprite_2d.animation != anim_name:
		animated_sprite_2d.play(anim_name)

func disable_all_attack_shapes():
	attack_shape.set_deferred("disabled", true)
	attack_shape_left.set_deferred("disabled", true)

func player_attack():
	if Input.is_action_just_pressed("attack") and is_on_floor() and not is_rolling:
		is_attacking = true
		current_state = State.attack
		velocity.x = 0
		animated_sprite_2d.stop()
		animated_sprite_2d.play("attack")
		# Activa solo el shape del lado que mira el jugador
		if animated_sprite_2d.flip_h:
			attack_shape_left.disabled = false  # ← mira izquierda
			attack_shape.disabled = true
		else:
			attack_shape.disabled = false       # ← mira derecha
			attack_shape_left.disabled = true

func player_roll():
	if Input.is_action_just_pressed("roll") and is_on_floor() and not is_attacking:
		is_rolling = true
		current_state = State.roll
		roll_direction = -1.0 if animated_sprite_2d.flip_h else 1.0
		velocity.x = roll_direction * roll_speed
		animated_sprite_2d.stop()
		animated_sprite_2d.play("roll")

func check_contact_damage():
	# area_entered solo salta al entrar, asi que estar pegado a un enemigo
	# (p. ej. el cuerpo del Minotauro) no volveria a hacer daño. Aqui se
	# vuelve a comprobar el solape en cuanto se acaba la invulnerabilidad.
	if invulnerable_timer > 0 or is_rolling:
		return
	for area in hurtbox.get_overlapping_areas():
		if area.is_in_group("enemy_attack"):
			take_damage(area.global_position.x)
			return

func update_health_bar():
	# La barra tiene 8 fotogramas de 112x32: 0 = llena, 7 = vacia
	var ratio = clampf(float(health) / float(max_health), 0.0, 1.0)
	var frame = int(round((1.0 - ratio) * 7.0))
	health_bar.texture.region = Rect2(frame * 112, 0, 112, 32)

func take_damage(from_x : float):
	# Cualquier ataque (de jefe o de enemigo) quita exactamente 1 hit.
	# Rodar esquiva el golpe; los i-frames evitan daño en cadena.
	if is_dead or is_rolling or invulnerable_timer > 0:
		return
	health -= 1
	update_health_bar()
	invulnerable_timer = INVULNERABLE_TIME
	is_attacking = false
	disable_all_attack_shapes()
	if health <= 0:
		die()
		return
	is_hurt = true
	hurt_timer = HURT_TIME
	current_state = State.hurt
	var knock_dir = 1.0 if global_position.x >= from_x else -1.0
	velocity = Vector2(knock_dir * 180, -120)   # empujón al recibir daño
	animated_sprite_2d.stop()
	animated_sprite_2d.play("hit")

func die():
	is_dead = true
	is_hurt = false
	is_rolling = false
	current_state = State.dead
	respawn_timer = RESPAWN_DELAY
	velocity = Vector2.ZERO
	update_health_bar()
	animated_sprite_2d.stop()
	animated_sprite_2d.play("hit")

func respawn():
	global_position = GameManager.get_respawn(respawn_default)
	velocity = Vector2.ZERO
	health = max_health
	update_health_bar()
	is_dead = false
	is_hurt = false
	invulnerable_timer = INVULNERABLE_TIME
	current_state = State.idle
	animated_sprite_2d.visible = true
	animated_sprite_2d.play("idle")

func _on_hurtbox_area_entered(area : Area2D):
	if area.is_in_group("enemy_attack"):
		take_damage(area.global_position.x)

func _on_attack_box_area_entered(area : Area2D):
	pass

func _on_animation_finished():
	if current_state == State.attack:
		is_attacking = false
		current_state = State.idle
		disable_all_attack_shapes()     # ← desactiva ambos al terminar
	elif current_state == State.roll:
		is_rolling = false
		current_state = State.idle
		velocity.x = 0
	elif current_state == State.turnaround:
		current_state = State.idle

func player_animation():
	if current_state == State.attack:
		if not animated_sprite_2d.is_playing():
			is_attacking = false
			current_state = State.idle
			disable_all_attack_shapes() # ← desactiva ambos si termina por aquí
		elif animated_sprite_2d.animation != "attack":
			animated_sprite_2d.play("attack")
	elif current_state == State.roll:
		if not animated_sprite_2d.is_playing():
			is_rolling = false
			current_state = State.idle
			velocity.x = 0
		elif animated_sprite_2d.animation != "roll":
			animated_sprite_2d.play("roll")
	elif current_state == State.turnaround:
		if not animated_sprite_2d.is_playing():
			current_state = State.idle
		elif animated_sprite_2d.animation != "turnaround":
			animated_sprite_2d.play("turnaround")
	elif current_state == State.idle:
		animated_sprite_2d.play("idle")
	elif current_state == State.run and is_on_floor():
		animated_sprite_2d.play("run")
	elif current_state == State.jump:
		animated_sprite_2d.play("jump")

func input_moviment():
	var direction : float = Input.get_axis("move_left", "move_right")
	return direction
