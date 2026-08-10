extends Area2D
# Golpe doble (Thunder Slash / Water Attack): el primer pase es un aviso
# semitransparente que NO hace daño y marca donde caera el golpe; tras una
# pausa, el segundo pase se repite en el mismo sitio y SI hace daño.

var gap : float = 0.4               # pausa entre el aviso y el golpe real
var strike_duration : float = 0.0   # si > 0, cada pase dura exactamente esto
var warn_color : Color = Color(1, 1, 1, 0.45)
@onready var sprite = $AnimatedSprite2D
@onready var shape = $CollisionShape2D

func _ready():
	shape.disabled = true
	if strike_duration > 0:
		var frames : int = sprite.sprite_frames.get_frame_count("strike")
		var base_fps : float = sprite.sprite_frames.get_animation_speed("strike")
		sprite.speed_scale = (frames / base_fps) / strike_duration
	# 1er pase: aviso sin daño
	modulate = warn_color
	sprite.play("strike")
	await sprite.animation_finished
	sprite.visible = false
	await get_tree().create_timer(gap).timeout
	# 2o pase: golpe real
	modulate = Color(1, 1, 1, 1)
	sprite.visible = true
	shape.disabled = false
	sprite.play("strike")
	await sprite.animation_finished
	queue_free()
