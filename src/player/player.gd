class_name Player
extends Node2D
## The black dog. Feeds pointer/Space press and release events into a JumpModel
## and places itself at ground_y - height. Origin is at the dog's feet.
## Implements story-001 (design/game-brief.md, MVP feature 2).

const TUNING_PATH: String = "res://assets/data/jump_tuning.json"
const REQUIRED_KEYS: PackedStringArray = [
	"gravity", "jump_initial_velocity", "hold_boost_acceleration", "max_hold_time",
	"ground_y", "demo_short_press_seconds", "demo_long_press_seconds", "demo_pause_seconds",
	"dog_scale",
]
const DOG_FRAMES_PATH: String = "res://assets/art/dog/dog_frames.tres"
## Per-frame lowest opaque paw pixel (cell y, 0 = cell top) for each animation, measured
## from assets/art/dog/dog-side-sheet.png with alpha > 0.5. Stored in the tuning file.
const PAW_BOTTOM_KEYS: Dictionary = {&"run": "dog_run_paw_bottoms", &"jump": "dog_jump_paw_bottoms"}

## Loaded tuning values (see assets/data/jump_tuning.json).
var tuning: Dictionary = {}

var _model: JumpModel
var _frozen: bool = false

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	tuning = _load_tuning(TUNING_PATH)
	if tuning.is_empty():
		set_process(false)
		set_process_unhandled_input(false)
		return
	_model = _make_model()
	position.y = float(tuning["ground_y"])
	_sprite.scale = Vector2.ONE * float(tuning["dog_scale"])
	_sprite.frame_changed.connect(_apply_paw_offset)
	_play(&"run")


func _process(delta: float) -> void:
	_model.step(delta)
	position.y = float(tuning["ground_y"]) - _model.height
	if _model.is_grounded and _sprite.animation != &"run":
		_play(&"run")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			_set_pressed(mouse.pressed)
	elif event is InputEventScreenTouch:
		_set_pressed((event as InputEventScreenTouch).pressed)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_SPACE and not key.echo:
			_set_pressed(key.pressed)


## Programmatic press (used by the demo mode); same path as real input.
func press() -> void:
	_set_pressed(true)


## Programmatic release (used by the demo mode).
func release() -> void:
	_set_pressed(false)


## Stops the dog where it is (game over): no jumping, no movement, the run animation holds
## its current frame. press() and release() do nothing until reset().
func freeze() -> void:
	_frozen = true
	set_process(false)
	set_process_unhandled_input(false)
	_sprite.pause()


## Puts the dog back on the ground in a fresh run (restart): height 0, grounded, running.
func reset() -> void:
	_frozen = false
	_model = _make_model()
	position.y = float(tuning["ground_y"])
	_play(&"run")
	set_process(true)
	set_process_unhandled_input(true)


func _make_model() -> JumpModel:
	return JumpModel.new(
		float(tuning["gravity"]),
		float(tuning["jump_initial_velocity"]),
		float(tuning["hold_boost_acceleration"]),
		float(tuning["max_hold_time"]))


func _set_pressed(pressed: bool) -> void:
	if _frozen:
		return
	if pressed:
		if _model.press():
			_play(&"jump")
	else:
		_model.release()


func _play(animation: StringName) -> void:
	_sprite.play(animation)
	_apply_paw_offset()


## Shifts the sprite so the current frame's lowest paw pixel sits on the Player origin
## (feet-on-ground). Frames differ in foot height, so this runs on every frame change.
func _apply_paw_offset() -> void:
	var bottoms: Array = tuning[PAW_BOTTOM_KEYS[_sprite.animation]]
	var texture: Texture2D = _sprite.sprite_frames.get_frame_texture(_sprite.animation, _sprite.frame)
	var center_y: float = texture.get_height() * 0.5
	_sprite.position.y = (center_y - float(bottoms[_sprite.frame])) * float(tuning["dog_scale"])


## Reads and validates the tuning file; returns {} after push_error on failure.
func _load_tuning(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Player: cannot open tuning file %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Player: tuning file %s is not a JSON object" % path)
		return {}
	var data := parsed as Dictionary
	for key in REQUIRED_KEYS:
		if not data.has(key) or not (data[key] is float or data[key] is int):
			push_error("Player: tuning file %s missing numeric key '%s'" % [path, key])
			return {}
	if float(data["gravity"]) <= 0.0 or float(data["max_hold_time"]) <= 0.0:
		push_error("Player: gravity and max_hold_time must be > 0")
		return {}
	if float(data["dog_scale"]) <= 0.0:
		push_error("Player: dog_scale must be > 0")
		return {}
	var frames := load(DOG_FRAMES_PATH) as SpriteFrames
	for anim in PAW_BOTTOM_KEYS:
		var key: String = PAW_BOTTOM_KEYS[anim]
		if not data.has(key) or not data[key] is Array \
				or (data[key] as Array).size() != frames.get_frame_count(anim):
			push_error("Player: '%s' must be an array with one paw-bottom per '%s' frame" % [key, anim])
			return {}
	return data
