extends CharacterBody2D
# Jefe Dragon (Kin). Ataques:
#   - Muy cerca: Garrazo lateral o Escupir fuego (al azar). Hacen daño solo en
#     los fotogramas del golpe (AttackBox).
#   - Persecucion: anda despacio y de vez en cuando se para 0,7 s y hace un
#     acelerón hacia el jugador. Tocar su cuerpo quita vida (BodyHitbox).
#   - Garra doble cada 3,7 s: se para y da dos garrazos en la misma zona; el
#     primero solo marca el area (no hace daño) y el segundo si.
#   - Mitad de vida: se queda quieto 3 s dentro de una burbuja azul donde no
#     recibe daño y al acabar se cura 5 golpes (solo una vez por pelea).
#   - Magia: Purple (cada 4,2 s junto al jugador), Wind Slash (cada 1,5 s en
#     cualquier sitio de la sala) — ambos con aviso sin daño y golpe real — y
#     Zoom (cada 3,3 s, aura bajo los pies del jugador: 1,5 s para esquivarla).
# Los sprites miran a la IZQUIERDA por defecto.

signal boss_defeated

const PURPLE_SCENE = preload("res://Bosses/Dragon/Attacks/purple.tscn")
const WIND_SCENE = preload("res://Bosses/Dragon/Attacks/wind_slash.tscn")
const ZOOM_SCENE = preload("res://Bosses/Dragon/Attacks/zoom_attack.tscn")

const GRAVITY = 1000
@export var max_hits : int = 14
@export var walk_speed : float = 38.0            # ← persecucion lenta
@export var activation_range : float = 260.0     # ← despierta por cercania (la sala lo desactiva)
@export var poise : int = 5                      # ← golpes que aguanta antes de tambalearse

@export_group("Cuerpo a cuerpo (garra / fuego)")
@export var close_range : float = 70.0           # ← "muy cerca"
@export var close_cooldown : float = 1.4
@export_group("Acelerones")
@export var dash_interval_min : float = 2.8      # ← cada cuanto (al azar entre min y max)
@export var dash_interval_max : float = 4.5
@export var dash_windup : float = 0.7            # ← tiempo parado antes del acelerón
@export var dash_speed : float = 270.0
@export var dash_duration : float = 0.55
@export_group("Garra doble")
@export var claw_interval : float = 3.7
@export var claw_gap : float = 0.35              # ← pausa entre el aviso y el garrazo real
@export_group("Burbuja a mitad de vida")
@export var shield_time : float = 3.0
@export var shield_heal : int = 5
@export_group("Purple")
@export var purple_enabled : bool = true
@export var purple_interval : float = 4.2
@export var purple_gap : float = 0.4
@export_group("Wind Slash")
@export var wind_enabled : bool = true
@export var wind_interval : float = 1.5
@export var wind_gap : float = 0.4
@export_group("Zoom")
@export var zoom_enabled : bool = true
@export var zoom_interval : float = 3.3
@export var zoom_warn : float = 1.5              # ← tiempo exacto para esquivarlo

# Ataques con el cuerpo: animacion, fotogramas con daño y hitbox (x = distancia
# hacia delante, se multiplica por la direccion en la que mira).
const BODY_ATTACKS = {
	"claw": {"anim": "attack1", "frames": [8, 10], "size": Vector2(46, 48), "off": Vector2(46, -30)},
	"fire": {"anim": "attack2", "frames": [7, 14], "size": Vector2(58, 34), "off": Vector2(54, -24)},
}

@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var hurtbox = $Hurtbox
@onready var attack_box_shape = $AttackBox/CollisionShape2D
@onready var boss_ui = $BossUI
@onready var health_bar = $BossUI/HealthBar

enum State { idle, run, attack, claw_warn, claw_gap_wait, claw_strike, dash_windup, dash, hurt, shield, dead }
var current_state : State = State.idle
var current_attack : String = ""
var current_hits : int = 0
var poise_left : int = 0
var active : bool = false
var is_dead : bool = false
var player : Node = null
var start_position : Vector2
var arena : Rect2 = Rect2()
var facing : int = -1
var state_timer : float = 0.0
var close_timer : float = 0.0
var dash_timer : float = 0.0
var claw_timer : float = 0.0
var purple_timer : float = 0.0
var wind_timer : float = 0.0
var zoom_timer : float = 0.0
var shield_used : bool = false
var claw_marker : Polygon2D
var bubble : Node2D

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
	_build_claw_marker()
	_build_bubble()
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

	if current_state != State.shield:
		close_timer -= delta
		dash_timer -= delta
		claw_timer -= delta
		_update_magic(delta)

	match current_state:
		State.attack, State.claw_strike:
			velocity.x = 0
			_update_body_hitbox()
		State.claw_warn:
			velocity.x = 0
		State.claw_gap_wait:
			velocity.x = 0
			state_timer -= delta
			if state_timer <= 0:
				_claw_real()
		State.dash_windup:
			velocity.x = 0
			state_timer -= delta
			if state_timer <= 0:
				_start_dash()
		State.dash:
			state_timer -= delta
			velocity.x = facing * dash_speed
			if state_timer <= 0 or is_on_wall():
				_end_dash()
		State.hurt:
			velocity.x = move_toward(velocity.x, 0, walk_speed)
		State.shield:
			velocity.x = 0
			state_timer -= delta
			if state_timer <= 0:
				_end_shield()
		_:
			_decide()

	move_and_slide()

# ---------- Decision (ataques con el cuerpo) ----------

func _decide():
	if player == null or not is_instance_valid(player) or player.get("is_dead") == true:
		velocity.x = move_toward(velocity.x, 0, walk_speed)
		_play("idle")
		return
	var diff_x = player.global_position.x - global_position.x
	_face(1 if diff_x > 0 else -1)

	# 1) Cada 3,7 s: garra doble
	if claw_timer <= 0:
		_start_claw_double()
		return
	# 2) Muy cerca: garrazo o fuego al azar
	if abs(diff_x) <= close_range and close_timer <= 0:
		close_timer = close_cooldown
		_start_body_attack(["claw", "fire"].pick_random())
		return
	# 3) De vez en cuando: se para y hace un acelerón
	if dash_timer <= 0:
		_start_dash_windup()
		return
	# 4) Persecucion lenta
	if abs(diff_x) > close_range * 0.7:
		velocity.x = facing * walk_speed
		current_state = State.run
		_play("run")
	else:
		velocity.x = 0
		current_state = State.idle
		_play("idle")

func _start_body_attack(atk : String):
	current_attack = atk
	current_state = State.attack
	velocity.x = 0
	_set_attack_shape(atk)
	animated_sprite_2d.stop()
	animated_sprite_2d.play(BODY_ATTACKS[atk]["anim"])

func _set_attack_shape(atk : String):
	var data = BODY_ATTACKS[atk]
	var shape = RectangleShape2D.new()
	shape.size = data["size"]
	attack_box_shape.shape = shape
	attack_box_shape.position = Vector2(data["off"].x * facing, data["off"].y)

func _update_body_hitbox():
	var r = BODY_ATTACKS[current_attack]["frames"]
	var f = animated_sprite_2d.frame
	_set_hitbox(f >= r[0] and f <= r[1])

# ---------- Garra doble (aviso + golpe real) ----------

func _start_claw_double():
	claw_timer = claw_interval
	current_attack = "claw"
	current_state = State.claw_warn
	velocity.x = 0
	_set_attack_shape("claw")
	_set_hitbox(false)
	_show_claw_marker()
	animated_sprite_2d.stop()
	animated_sprite_2d.play("attack1")
	animated_sprite_2d.modulate = Color(1, 1, 1, 0.6)    # primer pase: translucido, sin daño

func _claw_real():
	current_state = State.claw_strike
	animated_sprite_2d.modulate = Color.WHITE
	animated_sprite_2d.stop()
	animated_sprite_2d.play("attack1")

func _build_claw_marker():
	# Zona roja que marca donde caera el garrazo real
	claw_marker = Polygon2D.new()
	claw_marker.color = Color(1, 0.2, 0.15, 0.3)
	claw_marker.visible = false
	claw_marker.z_index = -1
	add_child(claw_marker)

func _show_claw_marker():
	var data = BODY_ATTACKS["claw"]
	var c = Vector2(data["off"].x * facing, data["off"].y)
	var h = data["size"] / 2
	claw_marker.polygon = PackedVector2Array([c + Vector2(-h.x, -h.y), c + Vector2(h.x, -h.y), c + Vector2(h.x, h.y), c + Vector2(-h.x, h.y)])
	claw_marker.visible = true
	claw_marker.modulate.a = 1.0

func _hide_claw_marker():
	var tw = create_tween()
	tw.tween_property(claw_marker, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): claw_marker.visible = false)

# ---------- Acelerones ----------

func _start_dash_windup():
	current_state = State.dash_windup
	state_timer = dash_windup
	velocity.x = 0
	_play("idle")
	# Se queda quieto y brilla: aviso de que va a embestir
	var tw = create_tween()
	tw.tween_property(animated_sprite_2d, "modulate", Color(1.8, 1.2, 0.7), dash_windup * 0.5)
	tw.tween_property(animated_sprite_2d, "modulate", Color.WHITE, dash_windup * 0.5)

func _start_dash():
	if player != null and is_instance_valid(player):
		_face(1 if player.global_position.x > global_position.x else -1)
	current_state = State.dash
	state_timer = dash_duration
	animated_sprite_2d.play("run")
	animated_sprite_2d.speed_scale = 2.2

func _end_dash():
	animated_sprite_2d.speed_scale = 1.0
	dash_timer = randf_range(dash_interval_min, dash_interval_max)
	_back_to_idle()

# ---------- Magia ----------

func _update_magic(delta : float):
	if player == null or not is_instance_valid(player) or player.get("is_dead") == true:
		return
	if purple_enabled:
		purple_timer -= delta
		if purple_timer <= 0:
			purple_timer = purple_interval
			_cast_purple()
	if wind_enabled:
		wind_timer -= delta
		if wind_timer <= 0:
			wind_timer = wind_interval
			_cast_wind()
	if zoom_enabled:
		zoom_timer -= delta
		if zoom_timer <= 0:
			zoom_timer = zoom_interval
			_cast_zoom()

func _room() -> Rect2:
	if arena.size != Vector2.ZERO:
		return arena
	return Rect2(start_position.x - 320, start_position.y - 220, 640, 220)

func _spawn(node : Node2D):
	get_tree().current_scene.add_child(node)

func _cast_purple():
	# Area mediana junto al jugador (aviso sin daño + golpe real)
	var p = PURPLE_SCENE.instantiate()
	p.gap = purple_gap
	p.position = player.global_position + Vector2(randf_range(-18, 18), -26)
	_spawn(p)

func _cast_wind():
	# Corte de viento en cualquier sitio de la sala
	var r = _room()
	var w = WIND_SCENE.instantiate()
	w.gap = wind_gap
	w.position = Vector2(randf_range(r.position.x + 30, r.end.x - 30), randf_range(r.position.y + 40, r.end.y - 20))
	_spawn(w)

func _cast_zoom():
	# Aura bajo los pies del jugador: 1,5 s para esquivar
	var z = ZOOM_SCENE.instantiate()
	z.player = player
	z.warn_time = zoom_warn
	z.floor_y = _room().end.y
	z.position = player.global_position
	_spawn(z)

# ---------- Burbuja a mitad de vida ----------

func _build_bubble():
	bubble = Node2D.new()
	bubble.position = Vector2(0, -40)
	bubble.visible = false
	bubble.z_index = 2
	var pts := PackedVector2Array()
	for i in range(32):
		var a = TAU * i / 32.0
		pts.append(Vector2(cos(a) * 62, sin(a) * 42))
	var fill = Polygon2D.new()
	fill.polygon = pts
	fill.color = Color(0.55, 0.85, 1, 0.28)
	bubble.add_child(fill)
	var ring = Line2D.new()
	ring.points = pts
	ring.closed = true
	ring.width = 2.0
	ring.default_color = Color(0.75, 0.95, 1, 0.85)
	bubble.add_child(ring)
	add_child(bubble)

func _start_shield():
	shield_used = true
	current_state = State.shield
	state_timer = shield_time
	velocity.x = 0
	_set_hitbox(false)
	claw_marker.visible = false
	animated_sprite_2d.modulate = Color.WHITE
	animated_sprite_2d.speed_scale = 1.0
	_play("idle")
	bubble.visible = true
	bubble.scale = Vector2(0.2, 0.2)
	var tw = create_tween()
	tw.tween_property(bubble, "scale", Vector2(1, 1), 0.3).set_trans(Tween.TRANS_BACK)
	# Latido suave mientras dura
	var pulse = create_tween().set_loops(int(shield_time / 0.6))
	pulse.tween_property(bubble, "modulate:a", 0.6, 0.3)
	pulse.tween_property(bubble, "modulate:a", 1.0, 0.3)

func _end_shield():
	current_hits = max(0, current_hits - shield_heal)
	health_bar.value = max_hits - current_hits
	_flash(Color(0.6, 1.6, 0.7))                 # destello verde: se ha curado
	var tw = create_tween()
	tw.tween_property(bubble, "scale", Vector2(1.3, 1.3), 0.25)
	tw.parallel().tween_property(bubble, "modulate:a", 0.0, 0.25)
	tw.tween_callback(_hide_bubble)
	_back_to_idle()

func _hide_bubble():
	bubble.visible = false
	bubble.modulate.a = 1.0
	bubble.scale = Vector2.ONE

# ---------- Utilidades ----------

func _face(dir : int):
	facing = dir
	# El sprite mira a la IZQUIERDA por defecto
	animated_sprite_2d.flip_h = dir > 0

func _play(anim : String):
	if animated_sprite_2d.animation != anim:
		animated_sprite_2d.play(anim)

func _set_hitbox(on : bool):
	attack_box_shape.set_deferred("disabled", not on)

func _flash(col : Color):
	animated_sprite_2d.modulate = col
	var tw = create_tween()
	tw.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.25)

func _back_to_idle():
	_set_hitbox(false)
	current_state = State.idle
	current_attack = ""
	_play("idle")

func _on_animation_finished():
	match current_state:
		State.attack, State.claw_strike:
			if current_state == State.claw_strike:
				_hide_claw_marker()
			_back_to_idle()
		State.claw_warn:
			animated_sprite_2d.modulate = Color.WHITE
			current_state = State.claw_gap_wait
			state_timer = claw_gap
			_play("idle")
		State.hurt:
			_back_to_idle()
		State.dead:
			# Se queda tumbado en el ultimo fotograma
			animated_sprite_2d.frame = animated_sprite_2d.sprite_frames.get_frame_count("death") - 1

# ---------- Vida ----------

func activate():
	if active or is_dead:
		return
	active = true
	boss_ui.visible = true
	close_timer = 0.5
	dash_timer = randf_range(dash_interval_min, dash_interval_max)
	claw_timer = claw_interval
	purple_timer = 2.0
	wind_timer = 1.0
	zoom_timer = 2.6

func reset_fight():
	# Vuelve a su estado inicial (p. ej. si el jugador muere)
	if is_dead:
		return
	active = false
	current_hits = 0
	poise_left = poise
	shield_used = false
	bubble.visible = false
	claw_marker.visible = false
	health_bar.value = max_hits
	boss_ui.visible = false
	velocity = Vector2.ZERO
	global_position = start_position
	animated_sprite_2d.speed_scale = 1.0
	animated_sprite_2d.modulate = Color.WHITE
	_back_to_idle()

func _on_hurtbox_area_entered(area : Area2D):
	if area.name == "AttackBox" and active and not is_dead:
		receive_hit()

func receive_hit():
	# Dentro de la burbuja no recibe daño
	if current_state == State.shield:
		_flash(Color(0.6, 0.9, 1.8))
		return
	current_hits += 1
	health_bar.value = max_hits - current_hits
	if current_hits >= max_hits:
		die()
		return
	_flash(Color(1.6, 0.5, 0.5))
	# Al llegar a la mitad de la vida: burbuja (solo una vez)
	if not shield_used and current_hits * 2 >= max_hits:
		_start_shield()
		return
	# Solo se tambalea al agotar la postura y si esta andando o quieto
	poise_left -= 1
	if poise_left <= 0 and (current_state == State.idle or current_state == State.run):
		poise_left = poise
		current_state = State.hurt
		velocity.x = 0
		animated_sprite_2d.stop()
		animated_sprite_2d.play("hurt")

func die():
	is_dead = true
	active = false
	current_state = State.dead
	velocity.x = 0
	boss_ui.visible = false
	bubble.visible = false
	claw_marker.visible = false
	_set_hitbox(false)
	$BodyHitbox/CollisionShape2D.set_deferred("disabled", true)
	animated_sprite_2d.speed_scale = 1.0
	animated_sprite_2d.stop()
	animated_sprite_2d.play("death")
	boss_defeated.emit()
