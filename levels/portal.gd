extends Area2D
# Portal dimensional: al tocarlo el jugador, carga la escena de destino.

@export_file("*.tscn") var target_scene : String = ""
@export var travel_delay : float = 0.35   # ← pausa para que se vea el fogonazo
var used : bool = false

func _ready():
	body_entered.connect(_on_body_entered)
	$AnimatedSprite2D.play("spin")

func _on_body_entered(body : Node2D):
	if used or target_scene == "" or not body.is_in_group("player"):
		return
	used = true
	# Fogonazo del portal al absorber al jugador
	var tween = create_tween()
	tween.tween_property($AnimatedSprite2D, "modulate", Color(2.5, 2.5, 2.5), travel_delay)
	await tween.finished
	get_tree().change_scene_to_file(target_scene)
