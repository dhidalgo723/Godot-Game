extends Area2D
# Cuchillo invocado: se queda flotando sobre la cabeza del jugador y le da
# exactamente `warn_time` segundos para esquivar.
#   - Si el jugador esquiva (rueda) a tiempo, el cuchillo se clava en el sitio
#     donde estaba y el jugador sale rodando de ahi -> no le hace daño.
#   - Si no esquiva a tiempo, cae sobre el y le hace daño.

var warn_time : float = 1.5        # ← tiempo exacto para esquivar
var hover_height : float = 68.0    # ← altura a la que flota sobre la cabeza
var fall_speed : float = 520.0
var floor_y : float = 1.0e9        # ← altura del suelo (lo pasa el jefe)
var player : Node = null

@onready var sprite = $Sprite2D
@onready var shape = $CollisionShape2D
enum Phase { aim, fall, stuck }
var phase : Phase = Phase.aim
var timer : float = 0.0

func _ready():
	shape.disabled = true            # mientras avisa no hace daño

func _physics_process(delta : float):
	match phase:
		Phase.aim:
			if player == null or not is_instance_valid(player) or player.get("is_dead") == true:
				queue_free()
				return
			# Sigue al jugador por encima de la cabeza
			global_position = player.global_position + Vector2(0, -hover_height)
			timer += delta
			# Parpadeo de aviso, mas rapido segun se acaba el tiempo
			var urgency = clampf(timer / warn_time, 0.0, 1.0)
			sprite.modulate = Color(1, 1, 1) if int(timer * (4 + urgency * 14)) % 2 == 0 \
					else Color(1, 0.5, 0.5)
			# Esquiva a tiempo -> el cuchillo se queda donde estaba el jugador
			if player.get("is_rolling") == true or timer >= warn_time:
				_drop()
		Phase.fall:
			position.y += fall_speed * delta
			if position.y >= floor_y:
				position.y = floor_y
				_stick()

func _drop():
	# Se suelta en la vertical donde esta ahora mismo (el jugador ya no lo mueve)
	phase = Phase.fall
	sprite.modulate = Color(1, 1, 1)
	shape.set_deferred("disabled", false)

func _stick():
	phase = Phase.stuck
	shape.set_deferred("disabled", true)
	var tw = create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)
