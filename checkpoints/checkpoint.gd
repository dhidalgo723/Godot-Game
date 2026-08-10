extends Area2D
# Checkpoint: al tocarlo el jugador, se guarda como punto de reaparicion

@onready var particles = $Particles

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body : Node2D):
	if not body.is_in_group("player"):
		return
	# Si ya es el checkpoint activo, no hace falta re-guardarlo
	if GameManager.has_checkpoint() and GameManager.respawn_position == global_position:
		return
	GameManager.set_checkpoint(global_position)
	particles.restart()
	particles.emitting = true
