extends CharacterBody2D
# ChairmanBoss: aparece al entrar en su sala (o si el jugador se acerca),
# persigue lentamente al jugador y ataca con 4 ataques distintos.
# Cada ataque tiene su intervalo (cada cuanto sale) y su duracion, editables.

signal boss_defeated

const FIREBALL_SCENE = preload("res://Bosses/Chairman/Attacks/fireball.tscn")
const ICE_SHARD_SCENE = preload("res://Bosses/Chairman/Attacks/ice_shard.tscn")
const THUNDER_SLASH_SCENE = preload("res://Bosses/Chairman/Attacks/thunder_slash.tscn")
const WATER_ATTACK_SCENE = preload("res://Bosses/Chairman/Attacks/water_attack.tscn")
const FALLING_STAR_SCENE = preload("res://Bosses/Chairman/Attacks/falling_star.tscn")
const SWORD_ATTACK_SCENE = preload("res://Bosses/Chairman/Attacks/sword_attack.tscn")

const GRAVITY = 1000
@export var max_hits : int = 12
@export var speed : float = 35.0             # ← velocidad de avance hacia el jugador
@export var stop_distance : float = 70.0     # ← distancia a la que se detiene
@export var activation_range : float = 150.0 # ← si no hay trigger, aparece por cercania

@export_group("Fireball")
@export var fireball_enabled : bool = true
@export var fireball_interval : float = 3.2  # ← cada cuanto lanza el ataque
@export var fireball_duration : float = 4.0  # ← segundos que tarda en cruzar la sala
@export_group("Ice Shard")
@export var ice_enabled : bool = true
@export var ice_interval : float = 2.5       # ← cada cuanto lanza el ataque
@export var ice_telegraph : float = 0.8      # ← aviso: formacion lenta sin daño
@export var ice_duration : float = 0.9       # ← duracion de la caida rapida
@export_group("Thunder Slash")
@export var slash_enabled : bool = true
@export var slash_interval : float = 3.5     # ← cada cuanto lanza el ataque
@export var slash_duration : float = 0.5     # ← duracion de cada corte
@export var slash_gap : float = 0.4          # ← pausa entre el aviso y el corte real
@export_group("Water Attack")
@export var water_enabled : bool = true
@export var water_interval : float = 2.3     # ← cada cuanto lanza el ataque
@export var water_duration : float = 0.6     # ← duracion de cada chorro
@export var water_gap : float = 0.4          # ← pausa entre el aviso y el chorro real
@export_group("Falling Star")
@export var star_enabled : bool = true
@export var star_interval : float = 4.2      # ← cada cuanto lanza el ataque
@export var star_duration : float = 1.6      # ← lo que tarda en cruzar la sala
@export_group("Sword Attack")
@export var sword_enabled : bool = true
@export var sword_interval : float = 3.7     # ← cada cuanto lanza el ataque
@export var sword_warn : float = 1.5         # ← tiempo exacto para esquivarlo
@export var sword_fall_speed : float = 520.0 # ← velocidad a la que cae

@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var hurtbox = $Hurtbox
@onready var boss_ui = $BossUI
@onready var health_bar = $BossUI/HealthBar
var current_hits : int = 0
var active : bool = false
var is_dead : bool = false
var player : Node = null
var start_position : Vector2
var arena : Rect2 = Rect2()      # limites de la sala (lo rellena el nivel o el fallback)
var fireball_timer : float = 0.0
var ice_timer : float = 0.0
var slash_timer : float = 0.0
var water_timer : float = 0.0
var star_timer : float = 0.0
var sword_timer : float = 0.0
var fireball_from_left : bool = true

func _ready():
	hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	player = get_tree().get_first_node_in_group("player")
	start_position = global_position
	visible = false
	boss_ui.visible = false
	health_bar.max_value = max_hits
	health_bar.value = max_hits

func _physics_process(delta : float):
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if is_dead:
		velocity.x = 0
		move_and_slide()
		return

	if not active:
		# Fallback sin trigger: aparece cuando el jugador se acerca
		if player != null and is_instance_valid(player) \
				and global_position.distance_to(player.global_position) <= activation_range:
			activate()
		move_and_slide()
		return

	_boss_behavior(delta)
	_update_attacks(delta)
	move_and_slide()

func _boss_behavior(delta : float):
	if player == null or not is_instance_valid(player) or player.get("is_dead") == true:
		velocity.x = move_toward(velocity.x, 0, speed)
		return
	var diff_x = player.global_position.x - global_position.x
	animated_sprite_2d.flip_h = diff_x < 0
	if abs(diff_x) > stop_distance:
		velocity.x = sign(diff_x) * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)

# ---------- Ataques ----------

func _update_attacks(delta : float):
	if player == null or not is_instance_valid(player) or player.get("is_dead") == true:
		return
	if fireball_enabled:
		fireball_timer -= delta
		if fireball_timer <= 0:
			fireball_timer = fireball_interval
			_attack_fireball()
	if ice_enabled:
		ice_timer -= delta
		if ice_timer <= 0:
			ice_timer = ice_interval
			_attack_ice_shard()
	if slash_enabled:
		slash_timer -= delta
		if slash_timer <= 0:
			slash_timer = slash_interval
			_attack_thunder_slash()
	if water_enabled:
		water_timer -= delta
		if water_timer <= 0:
			water_timer = water_interval
			_attack_water()
	if star_enabled:
		star_timer -= delta
		if star_timer <= 0:
			star_timer = star_interval
			_attack_falling_star()
	if sword_enabled:
		sword_timer -= delta
		if sword_timer <= 0:
			sword_timer = sword_interval
			_attack_sword()

func _spawn(node : Node2D):
	get_tree().current_scene.add_child(node)

func _attack_fireball():
	# 2 bolas de fuego a distinta altura: nacen en una pared y mueren en la otra
	var fb_speed = arena.size.x / max(fireball_duration, 0.2)
	var from_left = fireball_from_left
	fireball_from_left = not fireball_from_left   # alterna la pared de origen
	var start_x = (arena.position.x + 8.0) if from_left else (arena.end.x - 8.0)
	for h in [arena.end.y - 24.0, arena.end.y - 64.0]:
		var fb = FIREBALL_SCENE.instantiate()
		fb.direction = 1 if from_left else -1
		fb.speed = fb_speed
		fb.min_x = arena.position.x
		fb.max_x = arena.end.x
		fb.position = Vector2(start_x, h)
		_spawn(fb)

func _attack_ice_shard():
	# Cae en una zona aleatoria de la sala
	var shard = ICE_SHARD_SCENE.instantiate()
	shard.telegraph_time = ice_telegraph
	shard.fall_duration = ice_duration
	shard.floor_y = arena.end.y - 12
	shard.position = Vector2(randf_range(arena.position.x + 24, arena.end.x - 24), arena.position.y + 30)
	_spawn(shard)

func _attack_thunder_slash():
	# Corte doble junto al jugador: el 1o avisa, el 2o hace daño
	var slash = THUNDER_SLASH_SCENE.instantiate()
	slash.gap = slash_gap
	slash.strike_duration = slash_duration
	slash.position = player.global_position + Vector2(randf_range(-14, 14), -24)
	_spawn(slash)

func _attack_water():
	# Chorro doble en el suelo, bajo el jugador: el 1o avisa, el 2o hace daño
	var water = WATER_ATTACK_SCENE.instantiate()
	water.gap = water_gap
	water.strike_duration = water_duration
	var x = clamp(player.global_position.x, arena.position.x + 40, arena.end.x - 40)
	water.position = Vector2(x, arena.end.y - 26)
	_spawn(water)

func _attack_falling_star():
	# Cae en diagonal a 45 grados pasando por donde esta el jugador ahora mismo
	var star = FALLING_STAR_SCENE.instantiate()
	var dx = -1.0 if player.global_position.x > arena.get_center().x else 1.0
	var drop = player.global_position.y - arena.position.y      # altura de caida
	var spawn_x = player.global_position.x - dx * drop
	# Si nacería fuera de la sala, entra por el otro lado
	if spawn_x < arena.position.x or spawn_x > arena.end.x:
		dx = -dx
		spawn_x = player.global_position.x - dx * drop
	star.direction = Vector2(dx, 1).normalized()
	star.speed = (drop * sqrt(2.0)) / max(star_duration, 0.2)
	star.limits = arena
	star.position = Vector2(spawn_x, arena.position.y)
	_spawn(star)

func _attack_sword():
	# Cuchillo sobre la cabeza del jugador: 1,5 s para rodar y esquivarlo
	var sword = SWORD_ATTACK_SCENE.instantiate()
	sword.player = player
	sword.warn_time = sword_warn
	sword.fall_speed = sword_fall_speed
	sword.floor_y = arena.end.y - 20
	sword.position = player.global_position + Vector2(0, -68)
	_spawn(sword)

func _reset_attack_timers():
	# Escalonados para que no salgan todos a la vez nada mas empezar
	fireball_timer = 1.2
	ice_timer = 2.0
	slash_timer = 2.8
	water_timer = 3.6
	star_timer = 4.4
	sword_timer = 5.2
	fireball_from_left = true

# ---------- Estado ----------

func activate():
	if active or is_dead:
		return
	if arena == Rect2():
		# Fallback: sala centrada en su posicion inicial (para test_level)
		var floor_level = start_position.y + 84.0
		arena = Rect2(start_position.x - 300.0, floor_level - 234.0, 600.0, 234.0)
	active = true
	visible = true
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.8)
	boss_ui.visible = true
	_reset_attack_timers()

func reset_fight():
	# Vuelve a su estado inicial (p. ej. si el jugador muere)
	if is_dead:
		return
	active = false
	visible = false
	current_hits = 0
	health_bar.value = max_hits
	boss_ui.visible = false
	velocity = Vector2.ZERO
	global_position = start_position
	_reset_attack_timers()

func _on_hurtbox_area_entered(area : Area2D):
	if area.name == "AttackBox" and active and not is_dead:
		receive_hit()

func receive_hit():
	current_hits += 1
	health_bar.value = max_hits - current_hits
	animated_sprite_2d.modulate = Color(1, 0.35, 0.35)
	var tween = create_tween()
	tween.tween_property(animated_sprite_2d, "modulate", Color.WHITE, 0.25)
	if current_hits >= max_hits:
		die()

func die():
	is_dead = true
	active = false
	boss_ui.visible = false
	velocity.x = 0
	boss_defeated.emit()
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 1.2)
	tween.tween_callback(queue_free)
