class_name ObstacleSpawner
extends Node2D
## Spawns Obstacle nodes at the right edge and scrolls them left with the ground.
## Implements story-003 (design/game-brief.md, MVP feature 3). All numbers come from the
## "obstacles" group of assets/data/jump_tuning.json.
##
## The scroll speed is read from the referenced ScrollingWorld every frame
## (world.scroll_speed * ground_layer_ratio, the ground's own speed), never copied.

const TUNING_PATH: String = "res://assets/data/jump_tuning.json"
const REQUIRED_KEYS: PackedStringArray = [
	"gravity", "jump_initial_velocity", "hold_boost_acceleration", "max_hold_time",
	"ground_y", "ground_layer_ratio",
]
const GROUP_KEYS: PackedStringArray = [
	"seed", "spawn_x_margin", "gap_min", "gap_max", "safety_margin", "tap_margin",
	"min_gap_reaction_seconds",
]
const KIND_KEYS: PackedStringArray = ["id", "tier", "texture", "weight", "scale", "height", "opaque_rect"]
const TIERS: PackedStringArray = ["low", "medium", "tall"]
## Same per-frame clamp as ScrollingWorld so obstacles and ground never drift apart.
const MAX_STEP: float = 1.0 / 30.0
const HEIGHT_TOLERANCE: float = 1.0

## Emitted after each obstacle is spawned. `gap_after` is the least edge-to-edge distance (px)
## that is guaranteed to separate it from the next obstacle (story-008 places collectibles there).
signal obstacle_spawned(obstacle: Obstacle, gap_after: float)

## Path to the ScrollingWorld whose scroll_speed drives the obstacles (set in main.tscn).
@export var world_path: NodePath
## Overrides the data seed when >= 0 (0 = randomize). -1 uses the data value.
@export var seed_override: int = -1

## Peak heights (px) of the shortest tap and the full-hold jump, computed at load.
var min_jump_peak: float = 0.0
var max_jump_peak: float = 0.0

## When false nothing spawns or moves (game over).
var running: bool = true

var world: ScrollingWorld
var _seed_value: int = 0
var _plan: ObstacleSpawnPlan
var _rng := RandomNumberGenerator.new()
var _kinds: Array[Dictionary] = []
var _textures: Array[Texture2D] = []
var _obstacles: Array[Obstacle] = []
var _ground_y: float = 0.0
var _ground_ratio: float = 1.0
var _spawn_x: float = 0.0
var _pending_gap: float = 0.0
## Speed ramp (px/s gained per second, and the cap), used to look ahead when sizing gaps.
var _ramp_rate: float = 0.0
var _ramp_cap: float = 0.0


func _ready() -> void:
	world = get_node_or_null(world_path) as ScrollingWorld
	if world == null:
		push_error("ObstacleSpawner: world_path '%s' does not point to a ScrollingWorld" % world_path)
		set_process(false)
		return
	var data: Dictionary = _load_tuning(TUNING_PATH)
	if data.is_empty():
		set_process(false)
		return
	var group: Dictionary = data["obstacles"]
	_ground_y = float(data["ground_y"])
	_ground_ratio = float(data["ground_layer_ratio"])
	_ramp_rate = float(data["speed_ramp"]["rate_per_second"])
	_ramp_cap = float(data["speed_ramp"]["max_speed"])
	_spawn_x = get_viewport_rect().size.x + float(group["spawn_x_margin"])
	var tap: Dictionary = ObstacleSpawnPlan.jump_stats(float(data["gravity"]),
			float(data["jump_initial_velocity"]), float(data["hold_boost_acceleration"]),
			float(data["max_hold_time"]), 0.0)
	var full: Dictionary = ObstacleSpawnPlan.jump_stats(float(data["gravity"]),
			float(data["jump_initial_velocity"]), float(data["hold_boost_acceleration"]),
			float(data["max_hold_time"]), float(data["max_hold_time"]))
	min_jump_peak = tap["peak"]
	max_jump_peak = full["peak"]
	_accept_kinds(group)
	if _kinds.is_empty():
		push_error("ObstacleSpawner: no valid obstacle kinds, spawner disabled")
		set_process(false)
		return
	_seed_value = int(group["seed"]) if seed_override < 0 else seed_override
	_seed_rng()
	var weights: Array[float] = []
	for kind in _kinds:
		weights.append(float(kind["weight"]))
	_plan = ObstacleSpawnPlan.new(_rng, weights, float(group["gap_min"]), float(group["gap_max"]),
			float(full["air_time"]), float(group["min_gap_reaction_seconds"]))
	_pending_gap = _plan.pick_gap(_future_speed())


## Seeds the rng: 0 randomizes, any other value gives the same sequence every time.
func _seed_rng() -> void:
	if _seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = _seed_value


## Clears every obstacle, reseeds the rng (a fixed seed repeats its sequence) and starts
## spawning again. Used by the restart (story-004).
func reset() -> void:
	for obstacle in _obstacles:
		obstacle.queue_free()
	_obstacles.clear()
	_seed_rng()
	_pending_gap = _plan.pick_gap(_future_speed())
	running = true


func _process(delta: float) -> void:
	if not running:
		return
	var step: float = minf(delta, MAX_STEP)
	var dx: float = _speed() * step
	for i in range(_obstacles.size() - 1, -1, -1):
		var obstacle: Obstacle = _obstacles[i]
		obstacle.position.x -= dx
		if obstacle.position.x + obstacle.width < 0.0:
			_obstacles.remove_at(i)
			obstacle.queue_free()
	# Enforce the physical minimum against the speed the pair will meet, not just the speed now.
	var required: float = _plan.effective_gap(_pending_gap, _future_speed())
	if _obstacles.is_empty() or _obstacles.back().position.x + _obstacles.back().width + required <= _spawn_x:
		_spawn()
		_pending_gap = _plan.pick_gap(_future_speed())
		obstacle_spawned.emit(_obstacles.back(), _plan.effective_gap(_pending_gap, _future_speed()))


## Live obstacles, oldest (leftmost) first.
func get_obstacles() -> Array[Obstacle]:
	return _obstacles


func _speed() -> float:
	return world.scroll_speed * _ground_ratio


## The highest ground speed (px/s) the scenery can reach by the time an obstacle spawned now has
## travelled from the spawn point to the left edge (a safe over-estimate of when the dog meets
## it). Gaps are sized against this, so a pair of obstacles that is clearable when spawned stays
## clearable as the speed ramps up. Never below the current speed or above the ramp cap.
func _future_speed() -> float:
	var speed: float = _speed()
	if speed <= 0.0:
		return speed
	var travel_seconds: float = _spawn_x / speed
	var ramped: float = speed + _ramp_rate * _ground_ratio * travel_seconds
	return maxf(speed, minf(_ramp_cap * _ground_ratio, ramped))


func _spawn() -> void:
	var index: int = _plan.pick_kind()
	var kind: Dictionary = _kinds[index]
	var rect: Array = kind["opaque_rect"]
	var art_scale: float = float(kind["scale"])
	var obstacle := Obstacle.new()
	obstacle.setup(kind, _textures[index], art_scale,
			(float(rect[2]) - float(rect[0])) * art_scale, float(kind["height"]))
	obstacle.position = Vector2(_spawn_x, _ground_y)
	add_child(obstacle)
	_obstacles.append(obstacle)


## Keeps only kinds that are clearable (and, per tier, clearable only as intended).
func _accept_kinds(group: Dictionary) -> void:
	var safety: float = float(group["safety_margin"])
	var tap_margin: float = float(group["tap_margin"])
	for raw in group["kinds"]:
		var kind: Dictionary = raw
		var problem: String = _kind_problem(kind, safety, tap_margin)
		if problem != "":
			push_error("ObstacleSpawner: kind '%s' rejected: %s" % [kind.get("id", "?"), problem])
			continue
		_kinds.append(kind)
		_textures.append(load(kind["texture"]) as Texture2D)


## Returns "" when the kind is valid, else the reason.
func _kind_problem(kind: Dictionary, safety: float, tap_margin: float) -> String:
	for key in KIND_KEYS:
		if not kind.has(key):
			return "missing key '%s'" % key
	if not kind["tier"] in TIERS:
		return "tier must be one of %s" % [TIERS]
	if not load(kind["texture"]) is Texture2D:
		return "texture %s not loadable" % kind["texture"]
	var rect: Variant = kind["opaque_rect"]
	if not rect is Array or (rect as Array).size() != 4:
		return "opaque_rect must be [left, top, right, bottom]"
	var art_scale: float = float(kind["scale"])
	var height: float = float(kind["height"])
	if art_scale <= 0.0 or float(kind["weight"]) <= 0.0 or height <= 0.0:
		return "scale, weight and height must be > 0"
	var art_height: float = (float(rect[3]) - float(rect[1])) * art_scale
	if absf(art_height - height) > HEIGHT_TOLERANCE:
		return "height %.1f does not match opaque art height %.1f" % [height, art_height]
	if height >= max_jump_peak - safety:
		return "height %.1f >= max jump peak %.1f - margin %.1f (unclearable)" % [height, max_jump_peak, safety]
	if kind["tier"] == "low" and height > min_jump_peak - tap_margin:
		return "low kind height %.1f exceeds min tap peak %.1f - margin %.1f" % [height, min_jump_peak, tap_margin]
	if kind["tier"] != "low" and height <= min_jump_peak:
		return "%s kind height %.1f must exceed the min tap peak %.1f" % [kind["tier"], height, min_jump_peak]
	return ""


## Reads and validates the tuning file; returns {} after push_error on failure.
func _load_tuning(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ObstacleSpawner: cannot open tuning file %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("ObstacleSpawner: tuning file %s is not a JSON object" % path)
		return {}
	var data := parsed as Dictionary
	for key in REQUIRED_KEYS:
		if not data.has(key) or not (data[key] is float or data[key] is int):
			push_error("ObstacleSpawner: tuning file %s missing numeric key '%s'" % [path, key])
			return {}
	if not data.has("speed_ramp") or not data["speed_ramp"] is Dictionary:
		push_error("ObstacleSpawner: 'speed_ramp' group missing")
		return {}
	var ramp: Dictionary = data["speed_ramp"]
	for key in ["rate_per_second", "max_speed"]:
		if not (ramp.get(key) is float or ramp.get(key) is int) or float(ramp[key]) < 0.0:
			push_error("ObstacleSpawner: speed_ramp.%s missing or negative" % key)
			return {}
	if not data.has("obstacles") or not data["obstacles"] is Dictionary:
		push_error("ObstacleSpawner: 'obstacles' group missing")
		return {}
	var group: Dictionary = data["obstacles"]
	for key in GROUP_KEYS:
		if not group.has(key) or not (group[key] is float or group[key] is int):
			push_error("ObstacleSpawner: obstacles.%s missing or not numeric" % key)
			return {}
	if float(group["gap_min"]) <= 0.0 or float(group["gap_max"]) < float(group["gap_min"]):
		push_error("ObstacleSpawner: need 0 < gap_min <= gap_max")
		return {}
	if float(group["safety_margin"]) < 0.0 or float(group["tap_margin"]) < 0.0 \
			or float(group["min_gap_reaction_seconds"]) < 0.0 or float(group["spawn_x_margin"]) < 0.0:
		push_error("ObstacleSpawner: margins and reaction time must be >= 0")
		return {}
	if not group.has("kinds") or not group["kinds"] is Array or (group["kinds"] as Array).is_empty():
		push_error("ObstacleSpawner: obstacles.kinds must be a non-empty array")
		return {}
	return data
