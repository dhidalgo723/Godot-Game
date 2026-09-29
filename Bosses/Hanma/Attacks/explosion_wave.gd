extends Node2D
# Explosion: carga `charge_time` segundos (bola de fuego creciendo en el suelo
# donde estaba el jefe) y luego lanza una fila de explosiones a ras de suelo
# hacia los dos lados hasta cubrir toda la sala. Se esquiva saltando o rodando.

const BLAST = preload("res://Bosses/Hanma/Attacks/explosion.tscn")

var charge_time : float = 2.0
var step : float = 30.0            # ← distancia entre explosiones
var interval : float = 0.07        # ← tiempo entre una explosion y la siguiente
var min_x : float = -1.0e9         # paredes de la sala (lo pasa el jefe)
var max_x : float = 1.0e9

func _ready():
	var orb = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(20):
		var a = TAU * i / 20.0
		pts.append(Vector2(cos(a) * 14, sin(a) * 7 - 4))
	orb.polygon = pts
	orb.color = Color(1, 0.55, 0.15, 0.7)
	orb.scale = Vector2(0.2, 0.2)
	add_child(orb)
	# Aviso: la bola crece y parpadea mientras carga
	var tw = create_tween()
	tw.tween_property(orb, "scale", Vector2(1.4, 1.4), charge_time)
	var blink = create_tween().set_loops(maxi(1, int(charge_time / 0.2)))
	blink.tween_property(orb, "modulate:a", 0.4, 0.1)
	blink.tween_property(orb, "modulate:a", 1.0, 0.1)
	await get_tree().create_timer(charge_time).timeout
	orb.queue_free()
	_spawn(position.x)
	var i := 1
	while position.x - i * step > min_x or position.x + i * step < max_x:
		await get_tree().create_timer(interval).timeout
		if position.x - i * step > min_x:
			_spawn(position.x - i * step)
		if position.x + i * step < max_x:
			_spawn(position.x + i * step)
		i += 1
	await get_tree().create_timer(1.5).timeout
	queue_free()

func _spawn(x : float):
	var b = BLAST.instantiate()
	b.position = Vector2(x, position.y)
	get_parent().add_child(b)
