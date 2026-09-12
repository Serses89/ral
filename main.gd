extends Node3D

# --- Nodos ---
@onready var boton: Button = $CanvasLayer/BotonAR
@onready var origen: XROrigin3D = $XROrigin3D
@onready var cubo: MeshInstance3D = $cubo

# --- Estado ---
var webxr: WebXRInterface
var altura_piso := 0.0

const ALTURA_CUBO := 0.2   # tamaño real del cubo en metros


func _ready() -> void:
	cubo.visible = false   # aparece recién con el primer tap

	webxr = XRServer.find_interface("WebXR")
	if webxr == null:
		boton.text = "WebXR no disponible"
		boton.disabled = true
		return

	webxr.session_mode = "immersive-ar"
	webxr.requested_reference_space_types = "local-floor, local, viewer"
	webxr.required_features = "local-floor"
	webxr.optional_features = "dom-overlay, hit-test"

	webxr.session_supported.connect(_on_soportado)
	webxr.session_started.connect(_on_iniciada)
	webxr.session_ended.connect(_on_terminada)
	webxr.session_failed.connect(_on_fallo)
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

	# El piso está en y=0 solo si nos dieron "local-floor"
	if webxr.reference_space_type == "local-floor":
		altura_piso = 0.0
	else:
		altura_piso = -1.5   # "local" pone el origen a la altura de la cabeza

	print("Reference space: ", webxr.reference_space_type)
	print("Features activas: ", webxr.enabled_features)


func _on_terminada() -> void:
	get_viewport().use_xr = false
	boton.visible = true


func _on_fallo(mensaje: String) -> void:
	boton.visible = true
	boton.text = "Error: " + mensaje


# --- Tap en la pantalla ---
func _on_select(input_source_id: int) -> void:
	var punto = _punto_del_tap(input_source_id)
	if punto == null:
		return

	cubo.global_position = punto + Vector3.UP * (ALTURA_CUBO * 0.5)
	cubo.visible = true


func _punto_del_tap(input_source_id: int):
	var tracker := webxr.get_input_source_tracker(input_source_id)
	if tracker == null:
		return null

	var pose := tracker.get_pose("default")
	if pose == null:
		return null

	# El rayo que sale del dedo hacia la escena, en coordenadas del mundo
	var t: Transform3D = origen.global_transform * pose.get_adjusted_transform()
	var desde: Vector3 = t.origin
	var direccion: Vector3 = -t.basis.z.normalized()

	# Lo cruzamos con el plano horizontal del piso
	var piso := Plane(Vector3.UP, origen.global_position.y + altura_piso)
	var punto = piso.intersects_ray(desde, direccion)

	if punto == null:
		punto = desde + direccion * 1.0   # apuntaste hacia arriba: 1 m adelante

	return punto
