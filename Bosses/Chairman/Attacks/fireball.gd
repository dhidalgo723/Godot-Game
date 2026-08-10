extends Area2D
# Bola de fuego: cruza la sala en horizontal de una pared a la otra
# y desaparece al llegar. El jefe le pasa direccion, velocidad y limites.

var direction : int = 1          # 1 = derecha, -1 = izquierda
var speed : float = 160.0
var min_x : float = -1.0e9       # pared izquierda (desaparece al pasarla)
var max_x : float = 1.0e9        # pared derecha
@onready var sprite = $AnimatedSprite2D
@onready var shape = $CollisionShape2D

func _ready():
	sprite.flip_h = direction < 0
	shape.position.x = 14 * direction   # la bola va en la punta, el rastro detras
	sprite.play("fly")

func _physics_process(delta : float):
	position.x += direction * speed * delta
	if position.x < min_x or position.x > max_x:
		queue_free()
