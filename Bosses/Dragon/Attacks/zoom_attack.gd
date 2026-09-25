extends Area2D
# Zoom: aura que aparece bajo los pies del jugador y le sigue durante
# `warn_time` segundos (aviso, sin daño).
#   - Si el jugador esquiva (rueda) a tiempo, el aura se queda y estalla en el
#     sitio donde empezo a esquivar -> no le hace daño.
#   - Si no esquiva a tiempo, estalla bajo sus pies y le hace daño.

var warn_time : float = 1.5          # ← tiempo exacto para esquivar
var hit_time : float = 0.3           # ← tiempo que hace daño al estallar
var floor_y : float = 1.0e9          # ← altura del suelo (lo pasa el jefe)
var player : Node = null

@onready var sprite = $AnimatedSprite2D
@onready var shape = $CollisionShape2D
enum Phase { aim, strike }
var phase : Phase = Phase.aim
var timer : float = 0.0

func _ready():
	shape.disabled = true            # mientras avisa no hace daño
	sprite.play("aura")

func _physics_process(delta : float):
	timer += delta
	match phase:
		Phase.aim:
			if player == null or not is_instance_valid(player) or player.get("is_dead") == true:
				queue_free()
				return
			# Sigue los pies del jugador, siempre pegado al suelo
			global_position = Vector2(player.global_position.x, min(player.global_position.y, floor_y))
			# Parpadeo de aviso, mas rapido segun se acaba el tiempo
			var urgency = clampf(timer / warn_time, 0.0, 1.0)
			sprite.modulate = Color(1, 1, 1) if int(timer * (4 + urgency * 14)) % 2 == 0 \
					else Color(0.6, 1.4, 1.6)
			# Esquiva a tiempo -> estalla donde estaba; si no, bajo sus pies
			if player.get("is_rolling") == true or timer >= warn_time:
				_strike()
		Phase.strike:
			if timer >= hit_time and not shape.disabled:
				shape.set_deferred("disabled", true)

func _strike():
	phase = Phase.strike
	timer = 0.0
	sprite.modulate = Color(1, 1, 1)
	shape.set_deferred("disabled", false)
	sprite.play("strike")
	await sprite.animation_finished
	queue_free()
