class_name ObstacleSpawnPlan
extends RefCounted
## Node-free obstacle randomness: which kind comes next and how far to leave before the one after.
## Implements story-003 (design/game-brief.md, MVP feature 3). The RandomNumberGenerator is
## injected, so a seeded rng gives a reproducible sequence.
##
## Minimum gap (edge to edge, px) so the dog can always land and rejump between two obstacles:
##   min_gap = scroll_speed * (max_air_time + reaction_seconds)
## max_air_time is the airtime of the longest jump (full max_hold_time hold); the dog covers
## scroll_speed * max_air_time px during it, reaction_seconds is the buffer to press again.
## It depends on the current speed, so it is re-evaluated at spawn time.

var _rng: RandomNumberGenerator
var _weights: Array[float]
var _gap_min: float
var _gap_max: float
var _max_air_time: float
var _reaction_seconds: float


func _init(rng: RandomNumberGenerator, weights: Array[float], gap_min: float, gap_max: float,
		max_air_time: float, reaction_seconds: float) -> void:
	_rng = rng
	_weights = weights
	_gap_min = gap_min
	_gap_max = gap_max
	_max_air_time = max_air_time
	_reaction_seconds = reaction_seconds


## Simulates one jump with JumpModel. hold_seconds = 0 is a tap (released at once).
## Returns {"peak": px, "air_time": seconds}.
static func jump_stats(gravity: float, initial_velocity: float, boost: float, max_hold_time: float,
		hold_seconds: float) -> Dictionary:
	var model := JumpModel.new(gravity, initial_velocity, boost, max_hold_time)
	var dt: float = 1.0 / 240.0
	var peak: float = 0.0
	var elapsed: float = 0.0
	model.press()
	while not model.is_grounded and elapsed < 10.0:
		if elapsed >= hold_seconds:
			model.release()
		model.step(dt)
		elapsed += dt
		peak = maxf(peak, model.height)
	return {"peak": peak, "air_time": elapsed}


## Smallest allowed edge-to-edge gap at the given scroll speed (px/s).
func min_gap(speed: float) -> float:
	return speed * (_max_air_time + _reaction_seconds)


## Raises a chosen gap to the current minimum.
func effective_gap(gap: float, speed: float) -> float:
	return maxf(gap, min_gap(speed))


## Weighted random index into the weights array.
func pick_kind() -> int:
	var total: float = 0.0
	for w in _weights:
		total += w
	var r: float = _rng.randf() * total
	for i in _weights.size():
		r -= _weights[i]
		if r < 0.0:
			return i
	return _weights.size() - 1


## Random gap in [max(gap_min, min_gap), max(gap_max, that)] for the given speed.
func pick_gap(speed: float) -> float:
	var low: float = effective_gap(_gap_min, speed)
	return _rng.randf_range(low, maxf(_gap_max, low))
