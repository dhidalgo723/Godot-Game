extends CharacterBody2D
# Jefe Hanma ("The Heart Hoarder").
# FASE 1 (vida > 75 %): ataques magicos mientras persigue despacio.
#   - Explosion cada 9,2 s: se para, carga 2 s y lanza una fila de explosiones a
#     ras de suelo desde donde esta hacia las dos paredes (se esquiva saltando).
#   - Atomic cada 7,3 s (quita 2) y Spines cada 5 s (quita 1): aviso sin daño
#     sobre el jugador y luego el golpe real en el mismo sitio.
#   - Moon si el jugador se acerca demasiado (quita 2), con un destello de aviso.
# FASE 2 (vida <= 75 %): deja la magia suelta y hace uno de los 5 combos al azar
#   cuando el jugador le da 2 golpes seguidos o cuando pasan 3 s sin recibir
#   ninguno. Entre combos persigue al jugador.
# Los golpes fisicos (attack, move_attack, air_slam) quitan 1 y solo hacen daño
# en sus fotogramas de golpe (tabla HITBOXES).
# Los sprites miran a la DERECHA por defecto.

signal boss_defeated

const EXPLOSION_SCENE = preload("res://Bosses/Hanma/Attacks/explosion_wave.tscn")
const ATOMIC_SCENE = preload("res://Bosses/Hanma/Attacks/atomic.tscn")
const SPINES_SCENE = preload("res://Bosses/Hanma/Attacks/spines.tscn")
const MOON_SCENE = preload("res://Bosses/Hanma/Attacks/moon.tscn")
const DARKNESS_SCENE = preload("res://Bosses/Hanma/Attacks/darkness.tscn")
const ICE_SCENE = preload("res://Bosses/Hanma/Attacks/ice_shard.tscn")

const GRAVITY = 1000
@export var max_hits : int = 18
@export var walk_speed : float = 45.0
@export var activation_range : float = 260.0     # ← despierta por cercania (la sala lo desactiva)
@export var poise : int = 4                      # ← golpes que aguanta antes de tambalearse
@export var stop_range : float = 55.0            # ← a esta distancia deja de andar
@export var wall_margin : float = 48.0           # ← grosor de las paredes dentro de la arena

@export_group("Fase 1: Explosion")
@export var explosion_interval : float = 9.2
@export var explosion_charge : float = 2.6
@export var explosion_step : float = 25.0        # ← distancia entre explosiones
@export var explosion_delay : float = 0.03       # ← tiempo entre explosiones (velocidad de la ola)
@export_group("Fase 1: Atomic")
@export var atomic_interval : float = 7.3
@export var atomic_gap : float = 0.7             # ← pausa entre el aviso y el golpe real
@export_group("Fase 1: Spines")
@export var spines_interval : float = 5.0
@export var spines_gap : float = 0.4
@export_group("Fase 1: Moon")
@export var moon_range : float = 50.0            # ← "demasiado cerca"
@export var moon_windup : float = 0.25           # ← destello de aviso antes del golpe
@export var moon_cooldown : float = 1.6

@export_group("Fase 2: Combos")
@export_range(0.0, 1.0) var phase2_life : float = 0.75   # ← vida restante a la que cambia de fase
@export var combo_hits_trigger : int = 2         # ← golpes seguidos que provocan un combo
@export var combo_idle_time : float = 3.0        # ← segundos sin recibir golpes que provocan un combo
@export var speed_fast : float = 1.6            # ← combo 2
@export var speed_medium : float = 1.25          # ← combos 3, 4 y 5
@export var speed_slow : float = 0.85            # ← combo 1
@export var attack_gap_slow : float = 0.8        # ← pausa entre los 2 attack del combo 3
@export var move_attack_speed : float = 110.0    # ← avance durante move_attack
@export var cast_pause : float = 0.35            # ← pausa tras lanzar una magia dentro de un combo
@export var combo_explosion_charge : float = 1.5 # ← carga de la Explosion dentro de un combo
@export var ice_speed : float = 170.0
@export var darkness_warn : float = 1.5          # ← tiempo para esquivar Darkness

# Fotogramas con daño de cada golpe fisico: [desde, hasta, tamaño, posicion]
# (x de la posicion hacia delante; se multiplica por la direccion en la que mira).
const HITBOXES = {
	"attack": [[1, 3, Vector2(200, 20), Vector2(0, -10)]],
	"move_attack": [[2, 3, Vector2(70, 34), Vector2(14, -17)], [9, 10, Vector2(70, 34), Vector2(14, -17)]],
	"air_slam": [[6, 8, Vector2(110, 40), Vector2(0, -20)], [17, 23, Vector2(240, 22), Vector2(0, -11)]],
}

# Pasos de cada combo. "anim": golpe fisico (n = repeticiones, tp = se teletransporta
# al jugador antes, gap = pausa attack_gap_slow entre repeticiones); "cast": magias
# que lanza a la vez. "speed" de un paso sustituye a la del combo.
const COMBOS = [
	{"speed": "slow", "steps": [
		{"anim": "attack", "n": 2},
		{"cast": ["spines", "explosion"]},
		{"anim": "air_slam"},
		{"cast": ["spines", "explosion"]},
		{"anim": "attack"},
	]},
	{"speed": "fast", "steps": [
		{"anim": "air_slam"},
		{"cast": ["atomic"]},
		{"anim": "move_attack", "n": 6},
		{"anim": "air_slam"},
	]},
	{"speed": "medium", "steps": [
		{"anim": "move_attack", "n": 3},
		{"anim": "attack", "n": 2, "gap": true},
		{"anim": "move_attack", "n": 2},
		{"anim": "air_slam", "n": 2},
	]},
	{"speed": "medium", "steps": [
		{"cast": ["explosion"]},
		{"anim": "air_slam", "tp": true},
		{"anim": "air_slam", "tp": true},
		{"anim": "move_attack", "n": 2},
		{"cast": ["atomic"]},
	]},
	{"speed": "medium", "steps": [
		{"cast": ["darkness"]},
		{"cast": ["ice"]},
		{"anim": "air_slam", "tp": true},
		{"anim": "air_slam", "tp": true},
		{"anim": "move_attack", "n": 2},
		{"cast": ["atomic"]},
	]},
]

@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var hurtbox = $Hurtbox
@onready var attack_box_shape = $AttackBox/CollisionShape2D
@onready var body_hitbox_shape = $BodyHitbox/CollisionShape2D
@onready var boss_ui = $BossUI
@onready var health_bar = $BossUI/HealthBar

enum State { idle, start_move, move, stop_move, hurt, charge, moon_windup, combo, recover, dead }
enum Sub { anim, prep, vanish, gap, pause }
var current_state : State = State.idle
var current_hits : int = 0
var poise_left : int = 0
var active : bool = false
var is_dead : bool = false
var player : Node = null
var start_position : Vector2
var arena : Rect2 = Rect2()
var facing : int = -1
var state_timer : float = 0.0

var phase : int = 1
var explosion_timer : float = 0.0
var atomic_timer : float = 0.0
var spines_timer : float = 0.0
var moon_timer : float = 0.0

var hit_streak : int = 0
var no_hit_timer : float = 0.0
var want_combo : bool = false
var combo : Dictionary = {}
var step_i : int = 0
var rep : int = 0
var sub : Sub = Sub.anim
var step_speed : float = 1.0
var last_anim : String = ""

func _ready():
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	player = get_tree().get_first_node_in_group("player")
	start_position = global_position
	poise_left = poise
	attack_box_shape.disabled = true
	boss_ui.visible = false
	health_bar.max_value = max_hits
	health_bar.value = max_hits
	_face(-1)
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
		if _player_ok() and global_position.distance_to(player.global_position) <= activation_range:
			activate()
		move_and_slide()
		return

	if phase == 1:
		_update_magic(delta)
	elif current_state != State.combo and current_state != State.recover:
		no_hit_timer += delta
		if no_hit_timer >= combo_idle_time:
			want_combo = true

	match current_state:
		State.start_move, State.stop_move, State.hurt, State.recover:
			velocity.x = 0
		State.move:
			_update_move()
		State.charge:
			velocity.x = 0
			state_timer -= delta
			if state_timer <= 0:
				_back_to_idle()
		State.moon_windup:
			velocity.x = 0
			state_timer -= delta
			if state_timer <= 0:
				_cast_moon()
		State.combo:
			_update_combo(delta)
		_:
			_decide()

	move_and_slide()

# ---------- Movimiento ----------

func _player_ok() -> bool:
	return player != null and is_instance_valid(player) and player.get("is_dead") != true

func _decide():
	velocity.x = 0
	if not _player_ok():
		_play("idle")
		return
	var diff_x = player.global_position.x - global_position.x
	_face(1 if diff_x > 0 else -1)
	if phase == 2 and want_combo:
		_start_combo()
		return
	if phase == 1 and _try_phase1_attack(diff_x):
		return
	if abs(diff_x) > stop_range:
		current_state = State.start_move
		_play("start_move")
	else:
		_play("idle")

func _update_move():
	if not _player_ok():
		_stop_moving()
		return
	var diff_x = player.global_position.x - global_position.x
	var dir = 1 if diff_x > 0 else -1
	if phase == 1 and _try_phase1_attack(diff_x):
		return
	if phase == 2 and want_combo:
		_start_combo()
		return
	# Si el jugador se pone detras, frena en vez de darse la vuelta en seco
	if abs(diff_x) <= stop_range or dir != facing or is_on_wall():
		_stop_moving()
		return
	velocity.x = facing * walk_speed

func _stop_moving():
	velocity.x = 0
	current_state = State.stop_move
	_play("stop_move")

# ---------- Fase 1: magia ----------

func _update_magic(delta : float):
	explosion_timer -= delta
	moon_timer -= delta
	if not _player_ok():
		return
	atomic_timer -= delta
	if atomic_timer <= 0:
		atomic_timer = atomic_interval
		_cast("atomic")
	spines_timer -= delta
	if spines_timer <= 0:
		spines_timer = spines_interval
		_cast("spines")

func _try_phase1_attack(diff_x : float) -> bool:
	# Explosion y Moon paran al jefe; Atomic y Spines se lanzan sin pararse
	if explosion_timer <= 0:
		explosion_timer = explosion_interval
		current_state = State.charge
		state_timer = explosion_charge
		velocity.x = 0
		_play("idle")
		_spawn_explosion(explosion_charge)
		var tw = create_tween().set_loops(maxi(1, int(explosion_charge / 0.4)))
		tw.tween_property(animated_sprite_2d, "modulate", Color(1.8, 1.1, 0.6), 0.2)
		tw.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.2)
		return true
	if abs(diff_x) <= moon_range and moon_timer <= 0:
		current_state = State.moon_windup
		state_timer = moon_windup
		velocity.x = 0
		_play("idle")
		_flash(Color(1.9, 1.7, 0.6), moon_windup)    # destello amarillo: aviso
		return true
	return false

func _cast_moon():
	moon_timer = moon_cooldown
	var m = MOON_SCENE.instantiate()
	m.position = global_position + Vector2(0, -30)
	_spawn(m)
	_back_to_idle()

func _cast(what : String, charge : float = -1.0):
	if not _player_ok():
		return
	match what:
		"explosion":
			_spawn_explosion(charge if charge >= 0 else explosion_charge)
		"atomic":
			var a = ATOMIC_SCENE.instantiate()
			a.gap = atomic_gap
			a.position = player.global_position + Vector2(0, -22)
			_spawn(a)
		"spines":
			var s = SPINES_SCENE.instantiate()
			s.gap = spines_gap
			s.position = Vector2(player.global_position.x, start_position.y - 40)
			_spawn(s)
		"darkness":
			var d = DARKNESS_SCENE.instantiate()
			d.player = player
			d.warn_time = darkness_warn
			d.floor_y = start_position.y
			d.position = player.global_position
			_spawn(d)
		"ice":
			var b = _floor_bounds()
			var i = ICE_SCENE.instantiate()
			i.direction = facing
			i.speed = ice_speed
			i.min_x = b.x
			i.max_x = b.y
			i.position = global_position + Vector2(facing * 24, -30)
			_spawn(i)

func _spawn_explosion(charge : float):
	var b = _floor_bounds()
	var w = EXPLOSION_SCENE.instantiate()
	w.charge_time = charge
	w.step = explosion_step
	w.interval = explosion_delay
	w.min_x = b.x
	w.max_x = b.y
	w.position = Vector2(global_position.x, start_position.y)
	_spawn(w)

func _floor_bounds() -> Vector2:
	# Limites izquierdo y derecho del suelo de la sala
	if arena.size != Vector2.ZERO:
		return Vector2(arena.position.x + wall_margin, arena.end.x - wall_margin)
	return Vector2(start_position.x - 200, start_position.x + 200)

func _spawn(node : Node2D):
	get_tree().current_scene.add_child(node)

# ---------- Fase 2: combos ----------

func _start_combo():
	want_combo = false
	hit_streak = 0
	combo = COMBOS.pick_random()
	current_state = State.combo
	velocity.x = 0
	step_i = -1
	_next_step()

func _step() -> Dictionary:
	return combo["steps"][step_i]

func _speed_value(key : String) -> float:
	match key:
		"fast": return speed_fast
		"medium": return speed_medium
		"slow": return speed_slow
	return 1.0

func _next_step():
	_set_hitbox(false)
	step_i += 1
	if step_i >= combo["steps"].size():
		_end_combo()
		return
	var s = _step()
	rep = 0
	step_speed = _speed_value(s.get("speed", combo["speed"]))
	animated_sprite_2d.speed_scale = step_speed
	if s.has("cast"):
		_face_player()
		for what in s["cast"]:
			_cast(what, combo_explosion_charge)
		sub = Sub.pause
		state_timer = cast_pause / step_speed
		return
	if s.get("tp", false):
		sub = Sub.vanish
		_restart("vanish")
	elif s["anim"] == "move_attack":
		_face_player()
		sub = Sub.prep
		_restart("move_attack_prep")
	else:
		_play_rep()

func _play_rep():
	_face_player()
	sub = Sub.anim
	last_anim = _step()["anim"]
	_restart(last_anim)

func _update_combo(delta : float):
	velocity.x = 0
	match sub:
		Sub.anim:
			if last_anim == "move_attack" and not is_on_wall():
				velocity.x = facing * move_attack_speed * step_speed
			_update_attack_hitbox()
		Sub.prep:
			if not is_on_wall():
				velocity.x = facing * walk_speed * step_speed
		Sub.gap:
			state_timer -= delta
			if state_timer <= 0:
				_play_rep()
		Sub.pause:
			state_timer -= delta
			if state_timer <= 0:
				_next_step()

func _on_combo_anim_finished():
	match sub:
		Sub.vanish:
			# Reaparece en el aire justo encima del jugador y cae con el Air Slam
			if _player_ok():
				var b = _floor_bounds()
				global_position.x = clampf(player.global_position.x, b.x + 20, b.y - 20)
			_play_rep()
		Sub.prep:
			_play_rep()
		Sub.anim:
			_set_hitbox(false)
			rep += 1
			if rep < _step().get("n", 1):
				if _step().get("gap", false):
					sub = Sub.gap
					state_timer = attack_gap_slow
					animated_sprite_2d.pause()          # se queda en la ultima pose
				else:
					_play_rep()
			else:
				_next_step()

func _end_combo():
	# Recupera la postura segun el ultimo golpe y vuelve a perseguir
	animated_sprite_2d.speed_scale = 1.0
	_set_hitbox(false)
	body_hitbox_shape.set_deferred("disabled", false)
	current_state = State.recover
	no_hit_timer = 0.0
	hit_streak = 0
	if last_anim == "move_attack":
		_restart("stop_after_attack")
	elif last_anim == "attack" or last_anim == "air_slam":
		_restart("return_idle")
	else:
		_back_to_idle()
	last_anim = ""

func _update_attack_hitbox():
	var anim = animated_sprite_2d.animation
	var f = animated_sprite_2d.frame
	# Mientras flota antes del Air Slam (o al desvanecerse) su cuerpo no hace daño
	body_hitbox_shape.set_deferred("disabled", anim == "air_slam" and f < 6)
	if not HITBOXES.has(anim):
		_set_hitbox(false)
		return
	for w in HITBOXES[anim]:
		if f >= w[0] and f <= w[1]:
			var shape = attack_box_shape.shape as RectangleShape2D
			if shape == null or shape.size != w[2]:
				shape = RectangleShape2D.new()
				shape.size = w[2]
				attack_box_shape.shape = shape
			attack_box_shape.position = Vector2(w[3].x * facing, w[3].y)
			_set_hitbox(true)
			return
	_set_hitbox(false)

# ---------- Utilidades ----------

func _face(dir : int):
	facing = dir
	# El sprite mira a la DERECHA por defecto
	animated_sprite_2d.flip_h = dir < 0

func _face_player():
	if _player_ok():
		_face(1 if player.global_position.x > global_position.x else -1)

func _play(anim : String):
	if animated_sprite_2d.animation != anim or not animated_sprite_2d.is_playing():
		animated_sprite_2d.play(anim)

func _restart(anim : String):
	animated_sprite_2d.stop()
	animated_sprite_2d.play(anim)

func _set_hitbox(on : bool):
	attack_box_shape.set_deferred("disabled", not on)

func _flash(col : Color, time : float = 0.25):
	animated_sprite_2d.modulate = col
	var tw = create_tween()
	tw.tween_property(animated_sprite_2d, "modulate", Color.WHITE, time)

func _back_to_idle():
	_set_hitbox(false)
	current_state = State.idle
	_play("idle")

func _on_animation_finished():
	match current_state:
		State.start_move:
			current_state = State.move
			_play("move")
		State.stop_move, State.hurt, State.recover:
			_back_to_idle()
		State.combo:
			_on_combo_anim_finished()
		State.dead:
			# Se queda en el ultimo fotograma
			animated_sprite_2d.frame = animated_sprite_2d.sprite_frames.get_frame_count("death") - 1

# ---------- Vida ----------

func activate():
	if active or is_dead:
		return
	active = true
	boss_ui.visible = true
	explosion_timer = explosion_interval
	atomic_timer = atomic_interval
	spines_timer = spines_interval
	moon_timer = 0.0

func reset_fight():
	# Vuelve a su estado inicial (p. ej. si el jugador muere)
	if is_dead:
		return
	active = false
	phase = 1
	current_hits = 0
	poise_left = poise
	hit_streak = 0
	no_hit_timer = 0.0
	want_combo = false
	last_anim = ""
	health_bar.value = max_hits
	boss_ui.visible = false
	velocity = Vector2.ZERO
	global_position = start_position
	animated_sprite_2d.speed_scale = 1.0
	animated_sprite_2d.modulate = Color.WHITE
	body_hitbox_shape.set_deferred("disabled", false)
	_face(-1)
	_back_to_idle()

func _on_hurtbox_area_entered(area : Area2D):
	if area.name == "AttackBox" and active and not is_dead:
		receive_hit()

func receive_hit():
	current_hits += 1
	health_bar.value = max_hits - current_hits
	if current_hits >= max_hits:
		die()
		return
	_flash(Color(1.6, 0.5, 0.5))
	no_hit_timer = 0.0
	if phase == 1 and max_hits - current_hits <= max_hits * phase2_life:
		phase = 2                                # a partir de aqui: combos fisicos
	if phase == 2 and current_state != State.combo and current_state != State.recover:
		hit_streak += 1
		if hit_streak >= combo_hits_trigger:
			want_combo = true
	# Solo se tambalea al agotar la postura y si no esta en mitad de otra accion
	poise_left -= 1
	if poise_left <= 0 and current_state in [State.idle, State.move]:
		poise_left = poise
		current_state = State.hurt
		velocity.x = 0
		animated_sprite_2d.stop()
		animated_sprite_2d.play("hit")

func die():
	is_dead = true
	active = false
	current_state = State.dead
	velocity.x = 0
	boss_ui.visible = false
	animated_sprite_2d.speed_scale = 1.0
	_set_hitbox(false)
	body_hitbox_shape.set_deferred("disabled", true)
	animated_sprite_2d.stop()
	animated_sprite_2d.play("death")
	boss_defeated.emit()
