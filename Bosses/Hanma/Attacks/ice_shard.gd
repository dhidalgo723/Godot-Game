extends "res://Bosses/Chairman/Attacks/fireball.gd"
# Ice Shard de Hanma: vuela recto como la bola de fuego del Chairman, pero sale
# con la animacion "start", vuela con "fly" y al llegar a la pared se rompe ("hit").

var breaking : bool = false

func _ready():
	super()
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play("start")

func _physics_process(delta : float):
	if breaking:
		return
	position.x += direction * speed * delta
	if position.x < min_x or position.x > max_x:
		breaking = true
		shape.set_deferred("disabled", true)
		sprite.play("hit")

func _on_animation_finished():
	if sprite.animation == "start":
		sprite.play("fly")
	elif sprite.animation == "hit":
		queue_free()
