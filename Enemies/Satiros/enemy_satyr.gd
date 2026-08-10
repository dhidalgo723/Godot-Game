extends CharacterBody2D
@export var patrol_points : Node
@export var speed : int = 1500
@export var wait_time : int = 3
@export var max_hits : int = 3
@export var vision_range : float = 130.0        # ← distancia a la que ve al jugador
@export var vision_height : float = 64.0        # ← tolerancia vertical de la vision
@export var attack_range : float = 42.0         # ← distancia a la que ataca
@export var attack_cooldown : float = 1.4       # ← segundos entre ataques
@export var chase_speed_multiplier : float = 1.6
@onready var animated_sprite_2d = $AnimatedSprite2D
@onready var timer = $Timer
@onready var hurtbox = $Hurtbox
@onready var attack_box = $AttackBox
@onready var attack_box_shape = $AttackBox/CollisionShape2D
const GRAVITY = 1000
enum State { idle, walk, hit, dead, chase, attack }
var current_state : State
var direction : Vector2 = Vector2.LEFT
var number_of_points : int
var points_positions : Array[Vector2]
var current_points : Vector2
var current_points_position : int
var can_walk : bool
var current_hits : int = 0
var is_dead : bool = false
var is_hit : bool = false               # ← bloquea movimiento durante el hit
var is_attacking : bool = false
var attack_cooldown_timer : float = 0.0
var attack_shape_offset : float = 0.0
var player : Node = null

func _ready():
	if patrol_points != null:
		number_of_points = patrol_points.get_children().size()
		for point in patrol_points.get_children():
			points_positions.append(point.global_position)
		current_points = points_positions[current_points_position]
	else:
		print("No hay puntos de patrulla")

	timer.wait_time = wait_time
	current_state = State.idle
	if not hurtbox.area_entered.is_connected(_on_hurtbox_area_entered):
		hurtbox.area_entered.connect(_on_hurtbox_area_entered)
	animated_sprite_2d.animation_finished.connect(_on_animation_finished)
	player = get_tree().get_first_node_in_group("player")
	attack_box_shape.disabled = true
	attack_shape_offset = abs(attack_box_shape.position.x)

func _physics_process(delta : float):
	if is_dead or is_hit:
		return                          # No hace nada si está muerto o recibiendo hit
	enemy_gravity(delta)
	if attack_cooldown_timer > 0:
		attack_cooldown_timer -= delta

	if is_attacking:
		velocity.x = 0
		move_and_slide()
		return

	if can_see_player():
		enemy_combat(delta)
		move_and_slide()
		return
	elif current_state == State.chase:
		# Perdio de vista al jugador: vuelve a patrullar tras una pausa
		current_state = State.idle
		can_walk = false
		velocity.x = 0
		timer.start()

	enemy_idle(delta)
	enemy_walk(delta)
	move_and_slide()
	enemy_animations()

func enemy_gravity(delta : float):
	if not is_on_floor():
		velocity.y += GRAVITY * delta

func update_facing_direction():
	animated_sprite_2d.flip_h = direction.x < 0
	attack_box_shape.position.x = attack_shape_offset * direction.x

func can_see_player() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if player.get("is_dead") == true:
		return false
	var diff = player.global_position - global_position
	return abs(diff.x) <= vision_range and abs(diff.y) <= vision_height

func enemy_combat(delta : float):
	var diff_x = player.global_position.x - global_position.x
	direction = Vector2.RIGHT if diff_x > 0 else Vector2.LEFT
	update_facing_direction()
	if abs(diff_x) <= attack_range:
		velocity.x = 0
		if attack_cooldown_timer <= 0:
			start_attack()
		else:
			current_state = State.chase
			if animated_sprite_2d.animation != "idle":
				animated_sprite_2d.play("idle")
	else:
		velocity.x = direction.x * speed * delta * chase_speed_multiplier
		current_state = State.chase
		if animated_sprite_2d.animation != "walk":
			animated_sprite_2d.play("walk")

func start_attack():
	is_attacking = true
	current_state = State.attack
	velocity.x = 0
	attack_cooldown_timer = attack_cooldown
	attack_box_shape.disabled = false
	animated_sprite_2d.stop()
	animated_sprite_2d.play("attack")

func stop_attack():
	is_attacking = false
	attack_box_shape.disabled = true

func enemy_idle(delta : float):
	if !can_walk:
		velocity.x = move_toward(velocity.x, 0, speed * delta)
		current_state = State.idle

func enemy_walk(delta : float):
	if !can_walk:
		return
	if abs(position.x - current_points.x) > 0.5:
		velocity.x = direction.x * speed * delta
		current_state = State.walk
	else:
		current_points_position += 1
		if current_points_position >= number_of_points:
			current_points_position = 0
		current_points = points_positions[current_points_position]
		if current_points.x > position.x:
			direction = Vector2.RIGHT
		else:
			direction = Vector2.LEFT
		can_walk = false
		timer.start()
	update_facing_direction()

func enemy_animations():
	if current_state == State.idle and !can_walk:
		animated_sprite_2d.play("idle")
	elif current_state == State.walk and can_walk:
		animated_sprite_2d.play("walk")

func _on_hurtbox_area_entered(area: Area2D):
	if area.name == "AttackBox":
		receive_hit()

func receive_hit():
	if is_dead:
		return

	stop_attack()
	current_hits += 1
	is_hit = true
	current_state = State.hit
	velocity.x = 0                      # Se detiene al recibir el golpe
	animated_sprite_2d.stop()
	animated_sprite_2d.play("hit")      # Reproduce animación hit

func die():
	is_dead = true
	is_hit = false
	stop_attack()
	current_state = State.dead
	velocity.x = 0
	animated_sprite_2d.stop()
	animated_sprite_2d.play("dead")     # Reproduce animación muerte

func _on_animation_finished():
	if current_state == State.attack:
		stop_attack()
		current_state = State.chase
	elif current_state == State.hit:
		is_hit = false                  # Termina el hit, vuelve a moverse
		if current_hits >= max_hits:
			die()                       # Si llegó al límite de hits, muere
		else:
			current_state = State.idle
	elif current_state == State.dead:
		queue_free()                    # Elimina el enemigo al terminar la animación

func _on_timer_timeout() -> void:
	can_walk = true
