class_name CourtyardResident
extends CourtyardInteractionPoint

@export var appearance: SpriteFrames
## Owner 9 Oct: standing NPCs looked like posters - every resident breathes: the drawing rises up to
## BREATH_DEPTH from planted feet on a 3-4 s breath, each with his own rhythm (as the inn's characters).
@export var breathing := true
const BREATH_DEPTH := 0.02
var _body_y := 0.0
var _breath_phase := 0.0
var _breath_period := 3.4

func _ready() -> void:
	super._ready()
	var body := $Body as AnimatedSprite3D
	if body != null and appearance != null:
		body.sprite_frames = appearance
		body.play("idle")
	if body != null:
		_body_y = body.position.y
	var seed := float(hash(String(get_path())) % 1000) / 1000.0
	_breath_phase = seed * TAU
	_breath_period = 3.0 + seed

func _process(delta: float) -> void:
	var body := get_node_or_null("Body") as AnimatedSprite3D
	if not breathing or body == null or not body.visible:
		return
	_breath_phase += delta * TAU / _breath_period
	var rise := 1.0 + BREATH_DEPTH * 0.5 * (1.0 - cos(_breath_phase))
	# The sprite is centred on its half height: scale up and lift by the same factor - feet stay put.
	body.scale = Vector3(1.0, rise, 1.0)
	body.position.y = _body_y * rise
