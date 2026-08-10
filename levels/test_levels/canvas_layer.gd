# Script del CanvasLayer del inventario
extends CanvasLayer

func _ready():
	visible = false

func _process(delta):
	visible = Input.is_action_pressed("open_inventory")
