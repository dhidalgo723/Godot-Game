extends Area2D
# Golpe de un solo pase (una explosion de la ola, la Luna): reproduce "strike"
# y solo hace daño entre los fotogramas hit_from y hit_to. Luego desaparece.

@export var hit_from : int = 0
@export var hit_to : int = 99
@onready var sprite = $AnimatedSprite2D
@onready var shape = $CollisionShape2D

func _ready():
	shape.disabled = true
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(queue_free)
	sprite.play("strike")
	_on_frame_changed()

func _on_frame_changed():
	var on = sprite.frame >= hit_from and sprite.frame <= hit_to
	shape.set_deferred("disabled", not on)
