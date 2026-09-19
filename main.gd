extends Node3D

# --- Nodos ---
@onready var boton: Button = $CanvasLayer/BotonAR
@onready var origen: XROrigin3D = $XROrigin3D
@onready var cubo: RigidBody3D = $cubo2
@onready var piso_body: StaticBody3D = $Piso

# --- Config ---
const ALTURA_CAIDA := 0.6      # altura de caída al hacer tap en el piso
const ALCANCE_RAYO := 10.0     # hasta dónde busca el rayo del dedo
const DIST_MIN := 0.25         # no puedes traerlo más cerca que esto
const DIST_MAX := 3.0          # ni alejarlo más que esto
const FUERZA_LANZAMIENTO := 1.2 # multiplicador al soltar

# --- Estado ---
var webxr: WebXRInterface
var altura_piso := 0.0

var agarrando := false
var id_agarre := -1
var dist_agarre := 1.0
var hubo_agarre := false        # evita que el "select" final teletransporte el cubo

var pos_anterior := Vector3.ZERO
var velocidad_estimada := Vector3.ZERO


func _ready() -> void:
	cubo.visible = false
	cubo.freeze = true
	cubo.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	webxr = XRServer.find_interface("WebXR")
	if webxr == null:
		boton.text = "WebXR no disponible"
		boton.disabled = true
		return

	webxr.session_mode = "immersive-ar"
	webxr.requested_reference_space_types = "local-floor, local, viewer"
	webxr.required_features = "local-floor"
	webxr.optional_features = "dom-overlay"

	webxr.session_supported.connect(_on_soportado)
	webxr.session_started.connect(_on_iniciada)
	webxr.session_ended.connect(_on_terminada)
	webxr.session_failed.connect(_on_fallo)

	# Tres señales: inicio del toque, fin del toque, y el tap completo
	webxr.selectstart.connect(_on_selectstart)
	webxr.selectend.connect(_on_selectend)
	webxr.select.connect(_on_select)

	boton.pressed.connect(_on_boton)
	boton.disabled = true
	boton.text = "Verificando AR..."

	webxr.is_session_supported("immersive-ar")


func _on_soportado(modo: String, soportado: bool) -> void:
	if modo != "immersive-ar":
		return
	boton.disabled = not soportado
	boton.text = "Entrar en AR" if soportado else "Este navegador no soporta AR"


func _on_boton() -> void:
	if not webxr.initialize():
		boton.text = "No se pudo iniciar"


func _on_iniciada() -> void:
	get_viewport().use_xr = true
	get_viewport().transparent_bg = true
	webxr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	boton.visible = false

	if webxr.reference_space_type == "local-floor":
		altura_piso = 0.0
	else:
		altura_piso = -1.5

	piso_body.global_position.y = origen.global_position.y + altura_piso
	print("Reference space: ", webxr.reference_space_type)


func _on_terminada() -> void:
	get_viewport().use_xr = false
	boton.visible = true
	agarrando = false
	cubo.freeze = true
	cubo.visible = false


func _on_fallo(mensaje: String) -> void:
	boton.visible = true
	boton.text = "Error: " + mensaje


# =========================================================
#  INTERACCIÓN
# =========================================================

# Empieza el toque: ¿le diste al cubo o al vacío?
func _on_selectstart(input_source_id: int) -> void:
	if not cubo.visible:
		return

	var rayo := _rayo_del_dedo(input_source_id)
	if rayo.is_empty():
		return

	var espacio := get_world_3d().direct_space_state
	var consulta := PhysicsRayQueryParameters3D.create(
		rayo.desde,
		rayo.desde + rayo.direccion * ALCANCE_RAYO
	)
	var golpe := espacio.intersect_ray(consulta)

	if golpe.is_empty() or golpe.collider != cubo:
		return   # tocaste el vacío o el piso: que siga el flujo normal de tap

	# ¡Agarrado!
	agarrando = true
	hubo_agarre = true
	id_agarre = input_source_id
	dist_agarre = clampf(rayo.desde.distance_to(golpe.position), DIST_MIN, DIST_MAX)

	cubo.freeze = true
	pos_anterior = cubo.global_position
	velocidad_estimada = Vector3.ZERO


# Soltaste el dedo: lanzamos el cubo
func _on_selectend(input_source_id: int) -> void:
	if not agarrando or input_source_id != id_agarre:
		return

	agarrando = false
	id_agarre = -1

	cubo.freeze = false
	cubo.linear_velocity = velocidad_estimada * FUERZA_LANZAMIENTO
	cubo.angular_velocity = Vector3(
		randf_range(-3.0, 3.0),
		randf_range(-3.0, 3.0),
		randf_range(-3.0, 3.0)
	)


# Tap completo. Solo coloca el cubo si NO fue un agarre.
func _on_select(input_source_id: int) -> void:
	if hubo_agarre:
		hubo_agarre = false
		return

	var punto = _punto_del_tap(input_source_id)
	if punto == null:
		return
	_soltar_cubo(punto)


# Mientras esté agarrado, el cubo sigue al dedo
func _physics_process(delta: float) -> void:
	if not agarrando:
		return

	var rayo := _rayo_del_dedo(id_agarre)
	if rayo.is_empty():
		agarrando = false   # perdimos el input source
		cubo.freeze = false
		return

	var destino: Vector3 = rayo.desde + rayo.direccion * dist_agarre
	cubo.global_position = destino

	# Estimamos velocidad para poder lanzarlo al soltar.
	# El lerp suaviza el jitter del tracking del teléfono.
	var v_cruda := (destino - pos_anterior) / maxf(delta, 0.0001)
	velocidad_estimada = velocidad_estimada.lerp(v_cruda, 0.35)
	pos_anterior = destino


# =========================================================
#  HELPERS
# =========================================================

func _soltar_cubo(punto: Vector3) -> void:
	cubo.freeze = true
	cubo.linear_velocity = Vector3.ZERO
	cubo.angular_velocity = Vector3.ZERO

	cubo.global_position = punto + Vector3.UP * ALTURA_CAIDA
	cubo.rotation = Vector3(
		randf_range(0.0, TAU),
		randf_range(0.0, TAU),
		randf_range(0.0, TAU)
	)
	cubo.visible = true

	await get_tree().physics_frame
	cubo.freeze = false


# Devuelve {desde, direccion} o {} si no hay pose
func _rayo_del_dedo(input_source_id: int) -> Dictionary:
	if input_source_id < 0:
		return {}

	var tracker := webxr.get_input_source_tracker(input_source_id)
	if tracker == null:
		return {}

	var pose := tracker.get_pose("default")
	if pose == null:
		return {}

	var t: Transform3D = origen.global_transform * pose.get_adjusted_transform()
	return {
		"desde": t.origin,
		"direccion": -t.basis.z.normalized()
	}


func _punto_del_tap(input_source_id: int):
	var rayo := _rayo_del_dedo(input_source_id)
	if rayo.is_empty():
		return null

	var piso := Plane(Vector3.UP, origen.global_position.y + altura_piso)
	var punto = piso.intersects_ray(rayo.desde, rayo.direccion)

	if punto == null:
		punto = rayo.desde + rayo.direccion * 1.0

	return punto
