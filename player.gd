class_name Player
extends CharacterBody3D
## Jugador en primera persona: WASD / flechas, Shift (mantener) corre, Ctrl (mantener) agacha,
## mouse para mirar, zoom de cámara.

# ---------- CONFIGURACIÓN ----------
const WALK_SPEED := 2.5          # m/s
const RUN_SPEED := 4.0           # m/s (mantener Shift)
const CROUCH_SPEED := 1.2        # m/s (mantener Ctrl)
const ACCELERATION := 14.0       # suavizado del movimiento
const MOUSE_SENSITIVITY := 0.0025
const PITCH_LIMIT_DEG := 85.0
const EYE_HEIGHT := 1.6          # m
const CROUCH_EYE_HEIGHT := 0.95  # m, altura de la cámara agachado
const RADIUS := 0.3              # m
const HEIGHT := 1.7              # m
const CROUCH_HEIGHT := 1.1       # m, altura de la cápsula agachado
const CROUCH_SMOOTHING := 12.0   # velocidad de la transición al agacharse / levantarse
const FOV := 65.0                # FOV vertical; más bajo que 75 para que la escala se perciba real
const ZOOM_LEVELS := [2.0, 4.0, 8.0]   # aumentos de los tres niveles de zoom
const ZOOM_SMOOTHING := 12.0     # velocidad de la transición de zoom

var enabled := false             # main.gd lo activa/desactiva
var camera: Camera3D
var shape: CapsuleShape3D
var zoom_level := 0              # 0 = normal, 1..3 = niveles de ZOOM_LEVELS
var crouch_amount := 0.0         # 0 = de pie, 1 = agachado del todo

var _col: CollisionShape3D
var _fov_target := FOV


func _init() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	shape = CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT
	_col = CollisionShape3D.new()
	_col.shape = shape
	_col.position.y = HEIGHT * 0.5
	add_child(_col)
	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 300.0
	add_child(camera)


## Aumento actual (1.0 sin zoom).
func zoom_magnification() -> float:
	if zoom_level == 0:
		return 1.0
	var m: float = ZOOM_LEVELS[zoom_level - 1]
	return m


## Z: normal -> nivel 1 -> nivel 2 -> nivel 3 -> normal.
func cycle_zoom() -> void:
	zoom_level = (zoom_level + 1) % (ZOOM_LEVELS.size() + 1)
	_fov_target = rad_to_deg(2.0 * atan(tan(deg_to_rad(FOV) * 0.5) / zoom_magnification()))


func _process(delta: float) -> void:
	camera.fov = lerpf(camera.fov, _fov_target, 1.0 - exp(-ZOOM_SMOOTHING * delta))
	var target := 1.0 if (enabled and _key(KEY_CTRL)) else 0.0
	crouch_amount = lerpf(crouch_amount, target, 1.0 - exp(-CROUCH_SMOOTHING * delta))
	camera.position.y = lerpf(EYE_HEIGHT, CROUCH_EYE_HEIGHT, crouch_amount)
	shape.height = lerpf(HEIGHT, CROUCH_HEIGHT, crouch_amount)
	_col.position.y = shape.height * 0.5


func _input(event: InputEvent) -> void:
	if enabled and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENSITIVITY / zoom_magnification()   # con zoom, giro más fino
		rotate_y(-event.relative.x * sens)
		var limit := deg_to_rad(PITCH_LIMIT_DEG)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * sens, -limit, limit)


func _physics_process(delta: float) -> void:
	var move := Vector2.ZERO
	var speed := WALK_SPEED
	if enabled:
		move.x = float(_key(KEY_D) or _key(KEY_RIGHT)) - float(_key(KEY_A) or _key(KEY_LEFT))
		move.y = float(_key(KEY_S) or _key(KEY_DOWN)) - float(_key(KEY_W) or _key(KEY_UP))
		if _key(KEY_SHIFT):
			speed = RUN_SPEED
	speed = lerpf(speed, CROUCH_SPEED, crouch_amount)   # agachado manda sobre correr
	var wish := (global_transform.basis * Vector3(move.x, 0.0, move.y)).normalized()
	velocity = velocity.move_toward(wish * speed, ACCELERATION * delta)
	velocity.y = 0.0
	move_and_slide()


func _key(code: Key) -> bool:
	return Input.is_physical_key_pressed(code)
