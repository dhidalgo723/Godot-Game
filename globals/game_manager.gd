extends Node
# Autoload: guarda el ultimo punto de reaparicion (checkpoint) del jugador

var respawn_position : Vector2 = Vector2.ZERO
var respawn_scene : String = ""

func set_checkpoint(pos : Vector2) -> void:
	respawn_position = pos
	respawn_scene = get_tree().current_scene.scene_file_path

func has_checkpoint() -> bool:
	# Solo vale el checkpoint si es de la escena actual
	return respawn_scene != "" and respawn_scene == get_tree().current_scene.scene_file_path

func get_respawn(default_pos : Vector2) -> Vector2:
	if has_checkpoint():
		return respawn_position
	return default_pos

# ---------- Inventario ----------
# Sin limite de objetos ni de peso. Un objeto recogido no se puede tirar.
# Cada objeto es un Dictionary; se iran definiendo mas adelante, p. ej.:
#   { "name": "Pocion", "icon": Texture2D, "type": "talisman"/"weapon"/
#     "helmet"/"chest"/"pants"/"boots"/"object" }

var inventory_items : Array = []            # ← el recogido mas recientemente, primero
var equipped_talismans : Array = [null, null]
var equipped_weapon = null
var equipped_armor = null                   # ← solo UNA pieza de armadura a la vez

func add_item(item) -> void:
	inventory_items.push_front(item)        # lo ultimo recogido sale de primero

func is_boss_fight() -> bool:
	# Hay pelea de jefe (y por tanto barra de vida de jefe en pantalla) si algun
	# jefe esta activo y vivo. Con eso se bloquea el inventario.
	for node in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(node) and node.get("active") == true \
				and node.get("is_dead") != true:
			return true
	return false

# ---------- Camara de las salas de jefe ----------
# Durante la pelea la camara se amolda a la sala y se queda quieta;
# al terminar vuelve a seguir al jugador como siempre.

var _cam : Camera2D = null
var _cam_zoom : Vector2 = Vector2.ONE
var _cam_local : Vector2 = Vector2.ZERO   # ← posicion relativa al jugador antes de fijarla
var _cam_tween : Tween = null

func _kill_cam_tween() -> void:
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = null

func lock_camera_to_room(rect : Rect2, transition : float = 0.6, min_zoom : float = 0.4) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var cam = get_viewport().get_camera_2d()
	if cam == null or cam == _cam:
		return
	# Solo se guarda el estado original si la camara esta de verdad en reposo: ni
	# fijada ni volviendo de un bloqueo previo. Si no, un re-bloqueo encadenado
	# guardaria como "normal" un zoom que aun estaba a medio restaurar.
	if not cam.top_level and (_cam_tween == null or not _cam_tween.is_valid()):
		_cam_zoom = cam.zoom
		_cam_local = cam.position
	_cam = cam
	_kill_cam_tween()
	# Zoom justo para que la sala entera quepa en pantalla
	var vp = cam.get_viewport_rect().size
	var z = clampf(minf(vp.x / rect.size.x, vp.y / rect.size.y), min_zoom, 1.0)
	var here = cam.global_position
	cam.top_level = true                       # deja de seguir al jugador
	cam.global_position = here                 # sin saltos al soltarla
	_cam_tween = cam.create_tween().set_parallel(true)
	_cam_tween.tween_property(cam, "global_position", rect.get_center(), transition)
	_cam_tween.tween_property(cam, "zoom", Vector2(z, z), transition)

func unlock_camera(transition : float = 0.6) -> void:
	var cam = _cam
	_cam = null
	if cam == null or not is_instance_valid(cam):
		return
	_kill_cam_tween()                          # nada mas puede tocar ya la posicion
	# Vuelve al instante a colgar del jugador con su offset original: asi no puede
	# quedarse enfocando un punto suelto de la escena pase lo que pase.
	cam.top_level = false
	cam.position = _cam_local
	# Solo se suaviza el zoom, que no depende de la jerarquia y no puede descuadrarla
	_cam_tween = cam.create_tween()
	_cam_tween.tween_property(cam, "zoom", _cam_zoom, transition)
