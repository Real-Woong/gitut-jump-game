class_name CollectiblePlan
extends RefCounted
## Node-free collectible randomness: whether to place one, which kind, and where in a gap.
## Implements story-008 (design/game-brief.md, MVP feature 7). The RandomNumberGenerator is
## injected, so a seeded rng gives a reproducible sequence.

var _rng: RandomNumberGenerator
var _weights: Array[float]
var _chance: float


## rng: injected generator; weights: relative frequency per kind; chance: 0..1 odds that a gap
## between obstacles gets a collectible.
func _init(rng: RandomNumberGenerator, weights: Array[float], chance: float) -> void:
	_rng = rng
	_weights = weights
	_chance = chance


## True when this gap should get a collectible.
func should_place() -> bool:
	return _rng.randf() < _chance


## Weighted random index into the weights array.
func pick_kind() -> int:
	var total: float = 0.0
	for weight in _weights:
		total += weight
	var roll: float = _rng.randf() * total
	for i in _weights.size():
		roll -= _weights[i]
		if roll < 0.0:
			return i
	return _weights.size() - 1


## Random value in [low, high] (low when high <= low).
func pick_between(low: float, high: float) -> float:
	return low if high <= low else _rng.randf_range(low, high)


## The x range (x = start, y = end) inside a gap that starts at gap_start and is `gap` px long,
## keeping `margin` px clear of both ends. y < x means there is no room.
static func gap_range(gap_start: float, gap: float, margin: float) -> Vector2:
	return Vector2(gap_start + margin, gap_start + gap - margin)
