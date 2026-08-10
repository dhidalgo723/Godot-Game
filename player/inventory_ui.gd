extends CanvasLayer
# Inventario del jugador (tecla I). Al abrirlo el juego entero se pausa:
# el jugador se congela donde este (incluso en el aire), los enemigos no se
# mueven ni atacan y las animaciones se detienen. No se puede abrir durante
# una pelea de jefe (mientras haya barra de vida de jefe en pantalla).

const MIN_CELLS : int = 24        # celdas minimas visibles en la rejilla
const CELL_SIZE : Vector2 = Vector2(34, 34)

@onready var grid = $Panel/Objetos/Grid
@onready var cell_template = $Panel/CellTemplate
@onready var talisman_slots = [$Panel/TalismanSlot1, $Panel/TalismanSlot2]
@onready var weapon_slot = $Panel/WeaponSlot
@onready var armor_slot = $Panel/ArmorSlot
var is_open : bool = false

func _ready():
	visible = false

func _unhandled_input(event : InputEvent):
	if event.is_action_pressed("inventory"):
		toggle()

func toggle():
	if is_open:
		close()
	else:
		open()

func open():
	# Bloqueado en peleas de jefe / con barra de vida de jefe en pantalla
	if GameManager.is_boss_fight():
		return
	var player = get_parent()
	if player != null and player.get("is_dead") == true:
		return
	is_open = true
	visible = true
	get_tree().paused = true          # pausa total: jugador, enemigos y animaciones
	_refresh()

func close():
	is_open = false
	visible = false
	get_tree().paused = false

# ---------- Pintado ----------

func _refresh():
	_fill_slot(talisman_slots[0], GameManager.equipped_talismans[0])
	_fill_slot(talisman_slots[1], GameManager.equipped_talismans[1])
	_fill_slot(weapon_slot, GameManager.equipped_weapon)
	_fill_slot(armor_slot, GameManager.equipped_armor)

	for child in grid.get_children():
		child.queue_free()
	var items = GameManager.inventory_items   # ya viene con lo mas reciente primero
	var total = maxi(items.size(), MIN_CELLS)
	for i in range(total):
		var cell = cell_template.duplicate()
		cell.visible = true
		if i < items.size():
			_put_item_in(cell, items[i])
		grid.add_child(cell)

func _fill_slot(slot : Panel, item):
	# Limpia lo pintado antes y pone el objeto equipado (si hay)
	for child in slot.get_children():
		child.queue_free()
	if item != null:
		_put_item_in(slot, item)

func _put_item_in(cell : Control, item):
	if item is Dictionary and item.get("icon") is Texture2D:
		var tex = TextureRect.new()
		tex.texture = item["icon"]
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		cell.add_child(tex)
	else:
		# Sin icono todavia: se muestran las iniciales del nombre
		var label = Label.new()
		label.text = str(item.get("name", "?")).left(2).to_upper() if item is Dictionary else "?"
		label.add_theme_font_size_override("font_size", 8)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		cell.add_child(label)
	if item is Dictionary and item.has("name"):
		cell.tooltip_text = str(item["name"])
