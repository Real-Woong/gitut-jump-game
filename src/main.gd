extends Node2D
## Main scene: owns the run state (running / game over), the dog-vs-obstacle hit check, the
## game-over screen and the restart. Implements story-004 (design/game-brief.md, MVP feature 4).
##
## Launch flags (user args after `--`):
##   --auto-demo     performs one short press, then one long press (story-001 demo).
##   --no-collision  disables the hit check, so the demo can be watched without dying.
##
## Story 005 hooks its score onto `run_ended` and `run_restarted`.

## Emitted once when the dog hits an obstacle.
signal run_ended
## Emitted after a restart has reset the dog, the obstacles and the scenery.
signal run_restarted

enum State { RUNNING, GAME_OVER }

const TUNING_PATH: String = "res://assets/data/jump_tuning.json"
const COLLISION_KEYS: PackedStringArray = [
	"hitbox_width", "hitbox_height", "hitbox_offset_x", "obstacle_hitbox_shrink",
]
const GAME_OVER_KEYS: PackedStringArray = [
	"restart_delay_seconds", "restart_input_grace_seconds", "game_over_font_size", "restart_hint_font_size",
]
const SCORE_KEYS: PackedStringArray = ["score_per_pixel", "hud_font_size"]
const SPEED_RAMP_KEYS: PackedStringArray = ["rate_per_second", "max_speed"]
## Same per-frame clamp as the scenery, so the score tracks the ground the dog actually ran over.
const MAX_STEP: float = 1.0 / 30.0
const TITLE_TEXT: String = "GAME OVER"
const HINT_TEXT: String = "탭하여 다시 시작\nTAP TO RESTART"

var state: State = State.RUNNING

var _collision_enabled: bool = false
var _hitbox_width: float = 0.0
var _hitbox_height: float = 0.0
var _hitbox_offset_x: float = 0.0
var _obstacle_shrink: float = 0.0
var _restart_delay: float = 0.0
var _input_grace: float = 0.0
var _time_since_game_over: float = 0.0
var _overlay: CanvasLayer
var _result_label: Label
var _score: ScoreTracker
var _store: HighScoreStore
var _ground_ratio: float = 1.0
var _score_label: Label
var _best_label: Label
var _shown_score: int = -1
var _ramp_enabled: bool = false
var _start_speed: float = 0.0
var _ramp_rate: float = 0.0
var _ramp_cap: float = 0.0
## Seconds of running in this run (stops at game over, restarts at 0); drives the speed ramp.
var _run_time: float = 0.0

@onready var _player: Player = $Player
@onready var _world: ScrollingWorld = $World
@onready var _spawner: ObstacleSpawner = $Obstacles
## Collectibles between the obstacles (story-008); null when its data is invalid.
var _collectibles: CollectibleSpawner


func _ready() -> void:
	var config: Dictionary = _load_config(TUNING_PATH)
	if not config.is_empty():
		var collision: Dictionary = config["collision"]
		var game_over: Dictionary = config["game_over"]
		_hitbox_width = float(collision["hitbox_width"])
		_hitbox_height = float(collision["hitbox_height"])
		_hitbox_offset_x = float(collision["hitbox_offset_x"])
		_obstacle_shrink = float(collision["obstacle_hitbox_shrink"])
		_restart_delay = float(game_over["restart_delay_seconds"])
		_input_grace = float(game_over["restart_input_grace_seconds"])
		_build_overlay(int(game_over["game_over_font_size"]), int(game_over["restart_hint_font_size"]))
		var score: Dictionary = config["score"]
		_ground_ratio = float(config["ground_layer_ratio"])
		_start_speed = float(config["scroll_speed"])
		_ramp_rate = float(config["speed_ramp"]["rate_per_second"])
		_ramp_cap = float(config["speed_ramp"]["max_speed"])
		_ramp_enabled = true
		_store = HighScoreStore.new(String(score["high_score_path"]))
		_score = ScoreTracker.new(float(score["score_per_pixel"]), _store.load_best())
		_build_hud(int(score["hud_font_size"]))
		_refresh_hud()
		_setup_collectibles()
		_collision_enabled = not "--no-collision" in OS.get_cmdline_user_args()
	if "--auto-demo" in OS.get_cmdline_user_args():
		_run_demo()


func _process(delta: float) -> void:
	if state == State.GAME_OVER:
		_time_since_game_over += delta
		return
	if _ramp_enabled:
		_run_time += minf(delta, MAX_STEP)
		_world.scroll_speed = SpeedRamp.speed_at(_run_time, _start_speed, _ramp_rate, _ramp_cap)
	if _collectibles != null and _score != null:
		var dog: Rect2 = CollisionCheck.dog_box(_player.position.x, _player.position.y,
				_hitbox_width, _hitbox_height, _hitbox_offset_x)
		_score.add_bonus(_collectibles.collect(dog))
	if _score != null:
		_score.add_distance(_world.scroll_speed * _ground_ratio * minf(delta, MAX_STEP))
		_refresh_hud()
	if _collision_enabled and _hits_obstacle():
		_end_run()


func _unhandled_input(event: InputEvent) -> void:
	if state != State.GAME_OVER or not _is_press(event):
		return
	get_viewport().set_input_as_handled()
	# Ignore presses right after the hit so a mashed jump button does not skip the screen.
	if _time_since_game_over >= _restart_delay:
		_restart()


## True when the dog's hitbox overlaps any live obstacle's hitbox.
func _hits_obstacle() -> bool:
	var dog: Rect2 = CollisionCheck.dog_box(_player.position.x, _player.position.y,
			_hitbox_width, _hitbox_height, _hitbox_offset_x)
	for obstacle in _spawner.get_obstacles():
		var box: Rect2 = CollisionCheck.obstacle_box(obstacle.position.x, obstacle.position.y,
				obstacle.width, obstacle.height, _obstacle_shrink)
		if CollisionCheck.overlaps(dog, box):
			return true
	return false


func _end_run() -> void:
	state = State.GAME_OVER
	_time_since_game_over = 0.0
	_player.freeze()
	_spawner.running = false
	if _collectibles != null:
		_collectibles.running = false
	_world.running = false
	_finish_score()
	_overlay.visible = true
	run_ended.emit()


func _restart() -> void:
	_player.reset()
	_world.reset()
	_spawner.reset()
	if _collectibles != null:
		_collectibles.reset()
	_score.reset()
	_run_time = 0.0
	_refresh_hud()
	_overlay.visible = false
	state = State.RUNNING
	run_restarted.emit()
	# A touch also arrives as an emulated mouse press right after the touch event; keep the
	# dog deaf to input for a moment so that second event does not start a jump.
	_player.set_process_unhandled_input(false)
	await get_tree().create_timer(_input_grace).timeout
	if state == State.RUNNING:
		_player.set_process_unhandled_input(true)


## True for a left mouse press, a screen touch press or a (non-repeat) Space press.
func _is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		return mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.physical_keycode == KEY_SPACE and key.pressed and not key.echo
	return false


## Builds the game-over text on its own CanvasLayer, hidden until the run ends.
func _build_overlay(title_size: int, hint_size: int) -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 10
	_overlay.visible = false
	add_child(_overlay)
	var box := VBoxContainer.new()
	_overlay.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_make_label(TITLE_TEXT, title_size))
	_result_label = _make_label("", hint_size)
	box.add_child(_result_label)
	box.add_child(_make_label(HINT_TEXT, hint_size))


## Creates the collectible spawner just behind the dog in draw order. If its data is invalid it
## reports the error and the game simply runs without collectibles.
func _setup_collectibles() -> void:
	var spawner := CollectibleSpawner.new()
	add_child(spawner)
	move_child(spawner, _player.get_index())
	if spawner.setup(_world, _spawner):
		_collectibles = spawner
	else:
		spawner.queue_free()


## Freezes the score, saves it when it beats the best, and fills in the game-over result line.
func _finish_score() -> void:
	if _score == null:
		return
	var is_new_best: bool = _score.stop()
	if is_new_best and not _store.save_best(_score.best):
		push_warning("Main: could not save the best score")
	if is_new_best:
		_result_label.text = "NEW BEST!  %d" % _score.score()
	else:
		_result_label.text = "SCORE %d   BEST %d" % [_score.score(), _score.best]
	_refresh_hud()


## Builds the score (top left) and best score (top right) display.
func _build_hud(font_size: int) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_score_label = _make_label("", font_size)
	layer.add_child(_score_label)
	_score_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_best_label = _make_label("", font_size)
	layer.add_child(_best_label)
	_best_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_best_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN


## Updates the display, only touching the text when a number changed.
func _refresh_hud() -> void:
	if _score == null:
		return
	var current: int = _score.score()
	if current == _shown_score and _best_label.text == "BEST %d" % _score.best:
		return
	_shown_score = current
	_score_label.text = "SCORE %d" % current
	_best_label.text = "BEST %d" % _score.best


func _make_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	return label


func _run_demo() -> void:
	var tuning: Dictionary = _player.tuning
	if tuning.is_empty():
		return
	var pause: float = float(tuning["demo_pause_seconds"])
	await get_tree().create_timer(pause).timeout
	_player.press()
	await get_tree().create_timer(float(tuning["demo_short_press_seconds"])).timeout
	_player.release()
	await get_tree().create_timer(pause).timeout
	_player.press()
	await get_tree().create_timer(float(tuning["demo_long_press_seconds"])).timeout
	_player.release()


## Reads and validates the collision and game_over groups; returns {} after push_error on
## failure (the hit check and game-over screen then stay off).
func _load_config(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Main: cannot open tuning file %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Main: tuning file %s is not a JSON object" % path)
		return {}
	var data := parsed as Dictionary
	var groups: Dictionary = {"collision": COLLISION_KEYS, "game_over": GAME_OVER_KEYS, "score": SCORE_KEYS,
			"speed_ramp": SPEED_RAMP_KEYS}
	for top_key in ["ground_layer_ratio", "scroll_speed"]:
		var top_value: Variant = data.get(top_key)
		if not (top_value is float or top_value is int):
			push_error("Main: %s missing or not numeric" % top_key)
			return {}
	for group_name in groups:
		if not data.has(group_name) or not data[group_name] is Dictionary:
			push_error("Main: '%s' group missing" % group_name)
			return {}
		for key in groups[group_name]:
			var value: Variant = (data[group_name] as Dictionary).get(key)
			if not (value is float or value is int):
				push_error("Main: %s.%s missing or not numeric" % [group_name, key])
				return {}
	var collision: Dictionary = data["collision"]
	var game_over: Dictionary = data["game_over"]
	if float(collision["hitbox_width"]) <= 0.0 or float(collision["hitbox_height"]) <= 0.0 \
			or float(collision["obstacle_hitbox_shrink"]) < 0.0:
		push_error("Main: hitbox size must be > 0 and obstacle_hitbox_shrink >= 0")
		return {}
	if float(game_over["restart_delay_seconds"]) < 0.0 or float(game_over["restart_input_grace_seconds"]) < 0.0 \
			or float(game_over["game_over_font_size"]) <= 0.0 or float(game_over["restart_hint_font_size"]) <= 0.0:
		push_error("Main: restart delays must be >= 0 and font sizes > 0")
		return {}
	var ramp: Dictionary = data["speed_ramp"]
	if float(data["scroll_speed"]) <= 0.0 or float(ramp["rate_per_second"]) < 0.0 \
			or float(ramp["max_speed"]) < float(data["scroll_speed"]):
		push_error("Main: need scroll_speed > 0, speed_ramp.rate_per_second >= 0 and max_speed >= scroll_speed")
		return {}
	var score: Dictionary = data["score"]
	if float(score["score_per_pixel"]) <= 0.0 or float(score["hud_font_size"]) <= 0.0 \
			or float(data["ground_layer_ratio"]) < 0.0:
		push_error("Main: score_per_pixel and hud_font_size must be > 0")
		return {}
	if not score.get("high_score_path") is String or (score["high_score_path"] as String).is_empty():
		push_error("Main: score.high_score_path must be a non-empty string")
		return {}
	return data
