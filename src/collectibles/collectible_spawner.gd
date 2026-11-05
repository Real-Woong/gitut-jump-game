class_name CollectibleSpawner
extends Node2D
## Places collectibles in the gaps between obstacles, scrolls them with the ground, and lets the
## dog collect them. Implements story-008 (design/game-brief.md, MVP feature 7). All numbers
## come from the "collectibles" group of assets/data/jump_tuning.json.
##
## Placement: every time the ObstacleSpawner spawns an obstacle, there is a chance one collectible
## is placed in the gap AFTER it, at least `edge_margin` px clear of both neighbouring obstacles.
## It starts off-screen to the right and moves with the ground, so it never pops into view and
## never overlaps an obstacle. Heights are checked at load so every kind can be reached.

const TUNING_PATH: String = "res://assets/data/jump_tuning.json"
const REQUIRED_KEYS: PackedStringArray = [
	"gravity", "jump_initial_velocity", "hold_boost_acceleration", "max_hold_time",
	"ground_y", "ground_layer_ratio",
]
const GROUP_KEYS: PackedStringArray = [
	"seed", "spawn_chance", "edge_margin", "safety_margin", "sparkle_seconds", "sparkle_scale",
]
const KIND_KEYS: PackedStringArray = [
	"id", "texture", "points", "weight", "scale", "pickup_size", "height_min", "height_max",
]
## Same per-frame clamp as the scenery, so collectibles and ground never drift apart.
const MAX_STEP: float = 1.0 / 30.0

## When false nothing moves or spawns (game over).
var running: bool = true
## Overrides the data seed when >= 0 (0 = randomize). -1 uses the data value.
var seed_override: int = -1
## Highest jump peak (px) of a full hold, computed at load.
var max_jump_peak: float = 0.0

var _world: ScrollingWorld
var _plan: CollectiblePlan
var _rng := RandomNumberGenerator.new()
var _kinds: Array[Dictionary] = []
var _textures: Array[Texture2D] = []
var _items: Array[Collectible] = []
var _sparkle_texture: Texture2D
var _sparkle_seconds: float = 0.0
var _sparkle_scale: float = 1.0
var _ground_y: float = 0.0
var _ground_ratio: float = 1.0
var _edge_margin: float = 0.0
var _seed_value: int = 0
var _ready_to_run: bool = false


## Connects to the world (for the speed) and the obstacle spawner (for gap positions).
## Returns false after push_error when the data is invalid; the spawner then stays idle.
func setup(scroll_world: ScrollingWorld, obstacles: ObstacleSpawner) -> bool:
	_world = scroll_world
	var data: Dictionary = _load_tuning(TUNING_PATH)
	if data.is_empty():
		return false
	var group: Dictionary = data["collectibles"]
	_ground_y = float(data["ground_y"])
	_ground_ratio = float(data["ground_layer_ratio"])
	_edge_margin = float(group["edge_margin"])
	_sparkle_seconds = float(group["sparkle_seconds"])
	_sparkle_scale = float(group["sparkle_scale"])
	_sparkle_texture = load(String(group["sparkle_texture"])) as Texture2D
	var full: Dictionary = ObstacleSpawnPlan.jump_stats(float(data["gravity"]),
			float(data["jump_initial_velocity"]), float(data["hold_boost_acceleration"]),
			float(data["max_hold_time"]), float(data["max_hold_time"]))
	max_jump_peak = full["peak"]
	var reach: float = max_jump_peak + float(data["collision"]["hitbox_height"]) - float(group["safety_margin"])
	_accept_kinds(group, reach)
	if _kinds.is_empty():
		push_error("CollectibleSpawner: no valid collectible kinds, spawner disabled")
		return false
	_seed_value = int(group["seed"]) if seed_override < 0 else seed_override
	_seed_rng()
	var weights: Array[float] = []
	for kind in _kinds:
		weights.append(float(kind["weight"]))
	_plan = CollectiblePlan.new(_rng, weights, float(group["spawn_chance"]))
	obstacles.obstacle_spawned.connect(_on_obstacle_spawned)
	_ready_to_run = true
	return true


func _process(delta: float) -> void:
	if not running or not _ready_to_run:
		return
	var dx: float = _world.scroll_speed * _ground_ratio * minf(delta, MAX_STEP)
	for i in range(_items.size() - 1, -1, -1):
		var item: Collectible = _items[i]
		if not is_instance_valid(item) or item.is_queued_for_deletion():
			_items.remove_at(i)
			continue
		item.position.x -= dx
		if item.position.x + maxf(item.art_half_width, item.pickup_size * 0.5) < 0.0:
			_items.remove_at(i)
			item.queue_free()


## Collects every item the box touches. Returns the points gained this call.
func collect(dog_box: Rect2) -> int:
	var gained: int = 0
	for item in _items:
		if is_instance_valid(item) and not item.collected and CollisionCheck.overlaps(dog_box, item.pickup_box()):
			gained += item.points
			item.collect(_sparkle_texture, _sparkle_scale, _sparkle_seconds)
	return gained


## Live collectibles, including ones that are only playing their sparkle.
func get_items() -> Array[Collectible]:
	return _items


## Removes every collectible, reseeds the rng (a fixed seed repeats its sequence) and starts
## spawning again. Used by the restart.
func reset() -> void:
	for item in _items:
		if is_instance_valid(item):
			item.queue_free()
	_items.clear()
	_seed_rng()
	running = true


func _seed_rng() -> void:
	if _seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = _seed_value


## Possibly places one collectible in the gap after `obstacle` (gap_after px long).
func _on_obstacle_spawned(obstacle: Obstacle, gap_after: float) -> void:
	if not running or not _plan.should_place():
		return
	# The item is created before this frame's scroll step is applied to it, so keep one frame of
	# travel (at the current speed) on top of the margin; it can then never reach the obstacle.
	var one_frame: float = MAX_STEP * _world.scroll_speed * _ground_ratio
	var span: Vector2 = CollectiblePlan.gap_range(obstacle.position.x + obstacle.width, gap_after,
			_edge_margin + one_frame)
	if span.y < span.x:
		return
	var index: int = _plan.pick_kind()
	var kind: Dictionary = _kinds[index]
	var x: float = _plan.pick_between(span.x, span.y)
	var height: float = _plan.pick_between(float(kind["height_min"]), float(kind["height_max"]))
	var item := Collectible.new()
	item.setup(kind, _textures[index], float(kind["scale"]), float(kind["pickup_size"]))
	item.position = Vector2(x, _ground_y - height)
	add_child(item)
	_items.append(item)


## Keeps only kinds that are well-formed and can be reached by a jump.
func _accept_kinds(group: Dictionary, reach: float) -> void:
	for raw in group["kinds"]:
		var kind: Dictionary = raw
		var problem: String = _kind_problem(kind, reach)
		if problem != "":
			push_error("CollectibleSpawner: kind '%s' rejected: %s" % [kind.get("id", "?"), problem])
			continue
		_kinds.append(kind)
		_textures.append(load(String(kind["texture"])) as Texture2D)


## Returns "" when the kind is valid, else the reason. `reach` is the highest box bottom (px
## above the ground) the dog's hitbox can touch with a full-hold jump, minus a safety margin.
func _kind_problem(kind: Dictionary, reach: float) -> String:
	for key in KIND_KEYS:
		if not kind.has(key):
			return "missing key '%s'" % key
	if not kind["texture"] is String or not load(kind["texture"]) is Texture2D:
		return "texture is not a loadable Texture2D"
	for key in ["points", "weight", "scale", "pickup_size", "height_min", "height_max"]:
		if not (kind[key] is float or kind[key] is int):
			return "%s must be a number" % key
	var side: float = float(kind["pickup_size"])
	if int(kind["points"]) <= 0 or float(kind["weight"]) <= 0.0 or float(kind["scale"]) <= 0.0 or side <= 0.0:
		return "points, weight, scale and pickup_size must be > 0"
	var low: float = float(kind["height_min"])
	var high: float = float(kind["height_max"])
	if high < low:
		return "height_max must be >= height_min"
	if low - side * 0.5 < 0.0:
		return "height_min %.0f puts the pickup box below the ground (needs >= %.0f)" % [low, side * 0.5]
	if high - side * 0.5 > reach:
		return "height_max %.0f is out of reach: box bottom %.0f > reach %.0f" % [high, high - side * 0.5, reach]
	return ""


## Reads and validates the tuning file; returns {} after push_error on failure.
func _load_tuning(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("CollectibleSpawner: cannot open tuning file %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("CollectibleSpawner: tuning file %s is not a JSON object" % path)
		return {}
	var data := parsed as Dictionary
	for key in REQUIRED_KEYS:
		if not data.has(key) or not (data[key] is float or data[key] is int):
			push_error("CollectibleSpawner: tuning file %s missing numeric key '%s'" % [path, key])
			return {}
	for group_name in ["collision", "obstacles", "collectibles"]:
		if not data.has(group_name) or not data[group_name] is Dictionary:
			push_error("CollectibleSpawner: '%s' group missing" % group_name)
			return {}
	if not (data["collision"].get("hitbox_height") is float or data["collision"].get("hitbox_height") is int):
		push_error("CollectibleSpawner: collision.hitbox_height missing or not numeric")
		return {}
	var group: Dictionary = data["collectibles"]
	for key in GROUP_KEYS:
		if not group.has(key) or not (group[key] is float or group[key] is int):
			push_error("CollectibleSpawner: collectibles.%s missing or not numeric" % key)
			return {}
	var chance: float = float(group["spawn_chance"])
	if chance < 0.0 or chance > 1.0 or float(group["edge_margin"]) < 0.0 or float(group["safety_margin"]) < 0.0 \
			or float(group["sparkle_seconds"]) <= 0.0 or float(group["sparkle_scale"]) <= 0.0:
		push_error("CollectibleSpawner: spawn_chance must be 0..1, margins >= 0, sparkle values > 0")
		return {}
	if not group.get("sparkle_texture") is String or not load(group["sparkle_texture"]) is Texture2D:
		push_error("CollectibleSpawner: collectibles.sparkle_texture is not a loadable Texture2D")
		return {}
	if not group.has("kinds") or not group["kinds"] is Array or (group["kinds"] as Array).is_empty():
		push_error("CollectibleSpawner: collectibles.kinds must be a non-empty array")
		return {}
	# The smallest obstacle gap must leave room for a collectible between its two margins.
	if not (data["obstacles"].get("gap_min") is float or data["obstacles"].get("gap_min") is int) \
			or float(data["obstacles"]["gap_min"]) <= 2.0 * float(group["edge_margin"]):
		push_error("CollectibleSpawner: obstacles.gap_min must be larger than 2 * collectibles.edge_margin")
		return {}
	return data
