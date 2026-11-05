class_name ScrollingWorld
extends Node2D
## Endless leftward parallax scenery (night-city art).
## Implements story-002 (design/game-brief.md, MVP feature 1: auto-run + scrolling).
##
## The single scroll speed lives in assets/data/jump_tuning.json ("scroll_speed").
## Each layer moves at scroll_speed * its ratio. Story 006 changes the speed at
## runtime by assigning `scroll_speed`.

const TUNING_PATH: String = "res://assets/data/jump_tuning.json"
const REQUIRED_KEYS: PackedStringArray = [
	"scroll_speed", "ground_layer_ratio", "city_layer_ratio", "cloud_layer_ratio", "ground_y",
	"city_scale", "city_bottom_offset", "cloud_scale",
]
const MAX_STEP: float = 1.0 / 30.0
const CITY_TEXTURE: Texture2D = preload("res://assets/art/world/night-city.png")
const CLOUD_TEXTURES: Array[Texture2D] = [
	preload("res://assets/art/items/cloud_blue.tres"),
	preload("res://assets/art/items/cloud_lavender.tres"),
]

# Layout constants. The cloud layer repeats every TILE_WIDTH px (cloud_layout x values
# must leave each cloud fully inside [0, TILE_WIDTH)); ground marks repeat every
# GROUND_PERIOD (TILE_WIDTH is a multiple of it).
# The city layer alternates normal and horizontally mirrored copies of night-city.png
# (its edges are not seamless), so it repeats every 2 * scaled image width.
const TILE_WIDTH: float = 1152.0
const GROUND_PERIOD: float = 288.0
const GROUND_COLOR: Color = Color(0.2, 0.22, 0.32)

## Current base scroll speed in px/s (loaded from data; Story 006 may change it).
var scroll_speed: float = 0.0
## When false the scenery stands still (game over). scroll_speed is left untouched.
var running: bool = true

var _ground_y: float = 0.0
var _ground_ratio: float = 0.0
var _city_ratio: float = 0.0
var _cloud_ratio: float = 0.0
var _city_size: Vector2 = Vector2.ZERO
var _city_bottom_offset: float = 0.0
var _cloud_scale: float = 0.0
var _cloud_layout: Array = []
# Per-layer scrolled distance, accumulated so a speed change never makes a layer jump.
var _ground_offset: float = 0.0
var _city_offset: float = 0.0
var _cloud_offset: float = 0.0
var _initial_scroll_speed: float = 0.0


func _ready() -> void:
	var data: Dictionary = _load_tuning(TUNING_PATH)
	if data.is_empty():
		set_process(false)
		return
	scroll_speed = float(data["scroll_speed"])
	_initial_scroll_speed = scroll_speed
	_ground_ratio = float(data["ground_layer_ratio"])
	_city_ratio = float(data["city_layer_ratio"])
	_cloud_ratio = float(data["cloud_layer_ratio"])
	_ground_y = float(data["ground_y"])
	_city_size = CITY_TEXTURE.get_size() * float(data["city_scale"])
	_city_bottom_offset = float(data["city_bottom_offset"])
	_cloud_scale = float(data["cloud_scale"])
	_cloud_layout = data["cloud_layout"]


## Returns the scenery to its starting state: offsets at 0, scroll speed back to the data
## value, scrolling on. Used by the restart (story-004).
func reset() -> void:
	_ground_offset = 0.0
	_city_offset = 0.0
	_cloud_offset = 0.0
	scroll_speed = _initial_scroll_speed
	running = true
	queue_redraw()


func _process(delta: float) -> void:
	if not running:
		return
	var step: float = minf(delta, MAX_STEP)
	_ground_offset = fposmod(_ground_offset + scroll_speed * _ground_ratio * step, GROUND_PERIOD)
	_city_offset = fposmod(_city_offset + scroll_speed * _city_ratio * step, _city_size.x * 2.0)
	_cloud_offset = fposmod(_cloud_offset + scroll_speed * _cloud_ratio * step, TILE_WIDTH)
	queue_redraw()


func _draw() -> void:
	# Clouds (slowest), then city, then ground marks.
	for tile in 2:
		for c in _cloud_layout:
			var texture: Texture2D = CLOUD_TEXTURES[int(c[2])]
			var size: Vector2 = texture.get_size() * _cloud_scale
			draw_texture_rect(texture, Rect2(tile * TILE_WIDTH - _cloud_offset + float(c[0]), float(c[1]), size.x, size.y), false)
	# City: copy k covers [k*W - offset, (k+1)*W - offset]; odd copies are mirrored.
	# Offset is in [0, 2W), so parity stays consistent and the loop never pops.
	var city_top: float = _ground_y + _city_bottom_offset - _city_size.y
	var copies: int = ceili(TILE_WIDTH / _city_size.x) + 2
	for k in copies:
		var left: float = k * _city_size.x - _city_offset
		if k % 2 == 0:
			draw_texture_rect(CITY_TEXTURE, Rect2(left, city_top, _city_size.x, _city_size.y), false)
		else:
			draw_set_transform(Vector2(left + _city_size.x, city_top), 0.0, Vector2(-1.0, 1.0))
			draw_texture_rect(CITY_TEXTURE, Rect2(0.0, 0.0, _city_size.x, _city_size.y), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var count: int = int(TILE_WIDTH / GROUND_PERIOD) + 1
	for i in count:
		var x: float = i * GROUND_PERIOD - _ground_offset
		draw_rect(Rect2(x + 20.0, _ground_y + 22.0, 60.0, 4.0), GROUND_COLOR)
		draw_rect(Rect2(x + 170.0, _ground_y + 58.0, 36.0, 4.0), GROUND_COLOR)
		draw_rect(Rect2(x + 96.0, _ground_y + 94.0, 24.0, 4.0), GROUND_COLOR)


## Reads and validates the tuning file; returns {} after push_error on failure.
func _load_tuning(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ScrollingWorld: cannot open tuning file %s (error %d)" % [path, FileAccess.get_open_error()])
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("ScrollingWorld: tuning file %s is not a JSON object" % path)
		return {}
	var data := parsed as Dictionary
	for key in REQUIRED_KEYS:
		if not data.has(key) or not (data[key] is float or data[key] is int):
			push_error("ScrollingWorld: tuning file %s missing numeric key '%s'" % [path, key])
			return {}
	for key in ["scroll_speed", "ground_layer_ratio", "city_layer_ratio", "cloud_layer_ratio"]:
		if float(data[key]) < 0.0:
			push_error("ScrollingWorld: '%s' must be >= 0" % key)
			return {}
	if float(data["city_scale"]) <= 0.0 or float(data["cloud_scale"]) <= 0.0:
		push_error("ScrollingWorld: city_scale and cloud_scale must be > 0")
		return {}
	if not data.has("cloud_layout") or not data["cloud_layout"] is Array:
		push_error("ScrollingWorld: 'cloud_layout' must be an array of [x, y, texture_index]")
		return {}
	for c in data["cloud_layout"]:
		if not c is Array or (c as Array).size() != 3 or int(c[2]) < 0 or int(c[2]) >= CLOUD_TEXTURES.size():
			push_error("ScrollingWorld: each cloud_layout entry must be [x, y, 0..%d]" % (CLOUD_TEXTURES.size() - 1))
			return {}
	return data
