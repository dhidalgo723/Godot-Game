extends Area2D
# Carambano de hielo: aparece en una zona aleatoria del techo, se forma
# lentamente (aviso, sin daño) y luego cae rapido hasta el suelo, donde
# se rompe. Solo hace daño durante la caida.

var telegraph_time : float = 0.8   # segundos de formacion (lenta, esquivable)
var fall_duration : float = 0.9    # duracion de la caida rapida
var start_speed : float = 30.0     # descenso lento durante la formacion
var floor_y : float = 100000.0     # altura del suelo (lo pasa el jefe)
@onready var sprite = $AnimatedSprite2D
@onready var shape = $CollisionShape2D
enum Phase { form, fall, impact }
var phase : Phase = Phase.form
var timer : float = 0.0
var fall_speed : float = 300.0

func _ready():
	shape.disabled = true
	sprite.play("form")

func _physics_process(delta : float):
	timer += delta
	match phase:
		Phase.form:
			position.y += start_speed * delta
			if timer >= telegraph_time:
				phase = Phase.fall
				shape.disabled = false
				fall_speed = max((floor_y - position.y) / max(fall_duration, 0.05), 60.0)
				sprite.play("fall")
		Phase.fall:
			position.y += fall_speed * delta
			if position.y >= floor_y:
				phase = Phase.impact
				position.y = floor_y
				shape.set_deferred("disabled", true)
				sprite.play("impact")
				await sprite.animation_finished
				queue_free()
