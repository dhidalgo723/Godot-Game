extends CharacterBody2D
# Jefa Chitsu (sprites de Shaia): espadachina de escudo y espada.
#   - Ataques de espada: un combo fijo (ver combo_attacks / combo_waits)
#     y, al terminarlo, espera combo_cooldown antes de repetirlo.
#   - Ataque de salto: si el jugador se aleja, salta y le cae con una patada.
#   - Ataque de patada: si el jugador la toca, le da un rodillazo.
# El hitbox solo esta activo en los fotogramas del golpe, el salto avisa con
# un destello, y a veces bloquea con el escudo.
# Los sprites miran a la DERECHA por defecto.

signal boss_defeated

const GRAVITY = 1000
@export var max_hits : int = 24
@export var walk_speed : float = 70.0         # ← velocidad andando
@export var run_speed : float = 125.0         # ← velocidad corriendo (si el jugador esta lejos)
@export var close_range : float = 58.0        # ← distancia a la que lanza los golpes del combo
@export var guard_chance : float = 0.2        # ← probabilidad de bloquear un golpe
@export var poise : int = 4                   # ← golpes que aguanta antes de tambalearse
@export var activation_range : float = 220.0  # ← despierta por cercania (la sala lo desactiva)

@export_group("Combo de espada")
# Golpe a golpe y la espera que hay DESPUES de cada uno (0 = encadena al instante)
@export var combo_attacks : PackedStringArray = ["slash", "slash", "knee", "sweep", "spin", "spin", "slash"]
@export var combo_waits : PackedFloat32Array = [0.5, 1.0, 0.5, 0.7, 1.0, 0.0, 0.0]
@export var combo_cooldown : float = 2.4      # ← tras el combo, tiempo hasta el siguiente
@export_group("Salto con patada")
@export var jump_enabled : bool = true
@export var jump_range : float = 170.0        # ← distancia a partir de la cual salta
@export var jump_cooldown : float = 4.0
@export var jump_telegraph : float = 0.4      # ← aviso (destello) antes de saltar
@export var jump_air_time : float = 0.75      # ← lo que tarda en caer sobre el jugador
@export_group("Rodillazo al tocarla")
@export var knee_enabled : bool = true
@export var touch_range : float = 34.0        # ← distancia a la que cuenta como "tocarla"
@export var knee_cooldown : float = 1.2       # ← para que no lo encadene sin parar

# Ataques cuerpo a cuerpo: fotogramas activos, tamaño y posicion del hitbox
# (mirando a la derecha) y un pequeño avance durante el golpe.
const MELEE = {
	"slash": {"frames": [[2, 3]], "size": Vector2(62, 40), "off": Vector2(34, -34), "lunge": 40.0},
	"spin":  {"frames": [[3, 6]], "size": Vector2(84, 42), "off": Vector2(32, -34), "lunge": 55.0},
	"knee":  {"frames": [[2, 3]], "size": Vector2(34, 32), "off": Vector2(20, -30), "lunge": 90.0},
	"sweep": {"frames": [[3, 5], [10, 12]], "size": Vector2(70, 22), "off": Vector2(34, -11), "lunge": 30.0},
}

@onready var sprite = $AnimatedSprite2D
@onready var hurtbox = $Hurtbox
@onready var attack_box_shape = $AttackBox/CollisionShape2D
@onready var boss_ui = $BossUI
@onready var health_bar = $BossUI/HealthBar

enum State { idle, walk, attack, jump_windup, jump, landing, hurt, guard, dead }
var state : State = State.idle
var current_attack : String = ""
var current_hits : int = 0
var poise_left : int = 0
var active : bool = false
var is_dead : bool = false
var player : Node = null
var start_position : Vector2
var arena : Rect2 = Rect2()
var facing : int = 1
var jump_timer : float = 0.0
var knee_timer : float = 0.0
var state_timer : float = 0.0
var combo_index : int = -1          # ← golpe del combo que toca (-1 = sin combo en marcha)
var combo_wait : float = 0.0        # ← espera entre golpes del combo
var combo_timer : float = 0.0       # ← enfriamiento entre combos
var attack_in_combo : bool = false  # ← el golpe actual es del combo o un rodillazo por contacto

func _ready():
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	sprite.animation_finished.connect(_on_animation_finished)
	player = get_tree().get_first_node_in_group("player")
	start_position = global_position
	poise_left = poise
	attack_box_shape.disabled = true
	boss_ui.visible = false
	health_bar.max_value = max_hits
	health_bar.value = max_hits
	sprite.play("idle")

func _physics_process(delta : float):
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if is_dead:
		velocity.x = move_toward(velocity.x, 0, 400 * delta)
		move_and_slide()
		return

	if not active:
		velocity.x = 0
		if player != null and is_instance_valid(player) and player.get("is_dead") != true \
				and global_position.distance_to(player.global_position) <= activation_range:
			activate()
		move_and_slide()
		return

	jump_timer -= delta
	knee_timer -= delta
	combo_timer -= delta
	combo_wait -= delta

	match state:
		State.attack:
			_update_melee()
		State.landing:
			velocity.x = move_toward(velocity.x, 0, 600 * delta)
		State.jump_windup:
			velocity.x = 0
			state_timer -= delta
			if state_timer <= 0:
				_launch_jump()
		State.jump:
			# Patada activa durante todo el vuelo
			_set_hitbox(true)
			if is_on_floor() and velocity.y >= 0 and state_timer <= 0:
				_land()
			state_timer -= delta
		State.hurt, State.guard:
			velocity.x = move_toward(velocity.x, 0, 500 * delta)
			state_timer -= delta
			if state_timer <= 0:
				_back_to_idle()
		_:
			_decide()

	move_and_slide()

# ---------- Decision ----------

func _decide():
	if player == null or not is_instance_valid(player) or player.get("is_dead") == true:
		velocity.x = 0
		_play("idle")
		return
	var diff = player.global_position.x - global_position.x
	var dist = abs(diff)
	_face(1 if diff > 0 else -1)

	# 1) Si el jugador la esta tocando: rodillazo
	if knee_enabled and knee_timer <= 0 and dist <= touch_range:
		knee_timer = knee_cooldown
		_start_melee("knee", false)
		return
	# 2) Si el jugador se aleja bastante: salto con patada
	if jump_enabled and jump_timer <= 0 and dist >= jump_range:
		_start_jump_windup()
		return
	# 3) Combo de espada
	if combo_index < 0 and combo_timer <= 0 and dist <= close_range and not combo_attacks.is_empty():
		combo_index = 0
		combo_wait = 0.0
	if combo_index >= 0 and combo_wait <= 0 and dist <= close_range:
		_start_melee(combo_attacks[combo_index], true)
		return

	# Si no toca atacar, se acerca al jugador (tambien durante las esperas del combo)
	if dist > close_range * 0.8:
		var spd = run_speed if dist > 200 else walk_speed
		velocity.x = facing * spd
		state = State.walk
		_play("run" if dist > 200 else "walk")
	else:
		velocity.x = 0
		state = State.idle
		_play("idle")

func _advance_combo():
	# Pasa al siguiente golpe del combo con su espera; al acabar, enfriamiento
	var wait = combo_waits[combo_index] if combo_index < combo_waits.size() else 0.0
	combo_index += 1
	if combo_index >= combo_attacks.size():
		combo_index = -1
		combo_timer = combo_cooldown
		_back_to_idle()
		return
	if wait <= 0.0:
		_start_melee(combo_attacks[combo_index], true)   # encadena al instante
	else:
		combo_wait = wait
		_back_to_idle()

# ---------- Ataques cuerpo a cuerpo ----------

func _start_melee(atk : String, from_combo : bool):
	attack_in_combo = from_combo
	current_attack = atk
	state = State.attack
	velocity.x = 0
	var data = MELEE[atk]
	var shape = RectangleShape2D.new()
	shape.size = data["size"]
	attack_box_shape.shape = shape
	attack_box_shape.position = Vector2(data["off"].x * facing, data["off"].y)
	sprite.stop()
	sprite.play(atk)

func _update_melee():
	var data = MELEE[current_attack]
	var on := false
	for r in data["frames"]:
		if sprite.frame >= r[0] and sprite.frame <= r[1]:
			on = true
	_set_hitbox(on)
	# Pequeño paso adelante mientras golpea
	velocity.x = facing * data["lunge"] if on else move_toward(velocity.x, 0, 20)

# ---------- Salto con patada ----------

func _start_jump_windup():
	state = State.jump_windup
	state_timer = jump_telegraph
	jump_timer = jump_cooldown
	velocity.x = 0
	sprite.stop()
	sprite.play("crouch")
	_telegraph_flash(jump_telegraph)

func _launch_jump():
	# Salto parabolico que cae justo donde esta el jugador ahora mismo
	var target_x = player.global_position.x if is_instance_valid(player) else global_position.x
	if arena.size.x > 0:
		target_x = clamp(target_x, arena.position.x + 24, arena.end.x - 24)
	var t = max(jump_air_time, 0.3)
	velocity.x = (target_x - global_position.x) / t
	velocity.y = -GRAVITY * t / 2.0
	_face(1 if velocity.x >= 0 else -1)
	var shape = RectangleShape2D.new()
	shape.size = Vector2(42, 30)
	attack_box_shape.shape = shape
	attack_box_shape.position = Vector2(24 * facing, -30)
	state = State.jump
	state_timer = 0.1
	sprite.play("kick")              # patada voladora

func _land():
	_set_hitbox(false)
	velocity.x = 0
	state = State.landing
	sprite.play("landing")

# ---------- Utilidades ----------

func _face(dir : int):
	facing = dir
	sprite.flip_h = dir < 0

func _play(anim : String):
	if sprite.animation != anim:
		sprite.play(anim)

func _set_hitbox(on : bool):
	attack_box_shape.set_deferred("disabled", not on)

func _telegraph_flash(duration : float):
	# Destello amarillo: aviso para que el jugador pueda reaccionar
	var tw = create_tween()
	tw.tween_property(sprite, "modulate", Color(1.8, 1.6, 0.6), duration * 0.5)
	tw.tween_property(sprite, "modulate", Color.WHITE, duration * 0.5)

func _back_to_idle():
	_set_hitbox(false)
	state = State.idle
	current_attack = ""
	_play("idle")

func _on_animation_finished():
	match state:
		State.attack:
			if attack_in_combo:
				_advance_combo()
			else:
				_back_to_idle()
		State.landing:
			_back_to_idle()
		State.dead:
			sprite.frame = sprite.sprite_frames.get_frame_count("dead") - 1

# ---------- Vida ----------

func activate():
	if active or is_dead:
		return
	active = true
	boss_ui.visible = true
	combo_index = -1
	combo_timer = 0.8
	jump_timer = 2.5
	knee_timer = 0.0

func reset_fight():
	if is_dead:
		return
	active = false
	current_hits = 0
	poise_left = poise
	combo_index = -1
	health_bar.value = max_hits
	boss_ui.visible = false
	velocity = Vector2.ZERO
	global_position = start_position
	sprite.modulate = Color.WHITE
	_face(1)
	_back_to_idle()

func _on_hurtbox_area_entered(area : Area2D):
	if area.name == "AttackBox" and active and not is_dead:
		receive_hit()

func receive_hit():
	# Bloqueo con el escudo si esta quieta o andando
	if (state == State.idle or state == State.walk) and randf() < guard_chance:
		state = State.guard
		state_timer = 0.35
		velocity.x = 0
		sprite.play("guard")
		_flash(Color(0.6, 0.8, 1.6))
		return
	current_hits += 1
	health_bar.value = max_hits - current_hits
	if current_hits >= max_hits:
		die()
		return
	_flash(Color(1.6, 0.5, 0.5))
	# Solo se tambalea cuando se le acaba la postura, y nunca en mitad de un salto
	poise_left -= 1
	if poise_left <= 0 and state != State.jump:
		poise_left = poise
		_set_hitbox(false)
		state = State.hurt
		state_timer = 0.4
		velocity.x = -facing * 80
		sprite.stop()
		sprite.play("hurt")

func _flash(col : Color):
	sprite.modulate = col
	var tw = create_tween()
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.2)

func die():
	is_dead = true
	active = false
	state = State.dead
	_set_hitbox(false)
	$BodyHitbox/CollisionShape2D.set_deferred("disabled", true)
	boss_ui.visible = false
	velocity.x = -facing * 120       # sale despedida hacia atras
	sprite.stop()
	sprite.play("dead")
	boss_defeated.emit()
