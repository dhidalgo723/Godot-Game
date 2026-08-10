extends Area2D
# Estrella fugaz: cae en diagonal atravesando la sala. El jefe la lanza de
# forma que pase por donde estaba el jugador, asi que hay que apartarse.

var direction : Vector2 = Vector2(-1, 1).normalized()
var speed : float = 320.0
var limits : Rect2 = Rect2()      # ← al salirse de la sala desaparece
@onready var sprite = $AnimatedSprite2D
@onready var shape = $CollisionShape2D

func _ready():
	# El cometa del sprite viaja hacia abajo-izquierda; se voltea si va al otro lado
	sprite.flip_h = direction.x > 0
	if direction.x > 0:
		shape.position.x = -shape.position.x   # la cabeza cambia de lado al voltear
	sprite.play("fly")

func _physics_process(delta : float):
	position += direction * speed * delta
	if limits.size == Vector2.ZERO:
		return
	if position.y > limits.end.y or position.x < limits.position.x - 32 \
			or position.x > limits.end.x + 32:
		queue_free()
