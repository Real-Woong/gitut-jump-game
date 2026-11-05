class_name JumpModel
extends RefCounted
## Pure jump simulation (no nodes, no input). Heights are in pixels, positive up.
##
## Implements design/game-brief.md MVP feature 2 / story-001: press starts a jump
## at a minimum height; while the press is held (up to max_hold_time) an upward
## boost acceleration offsets gravity, so a longer hold gives a continuously
## higher jump. Releasing or hitting the time limit ends the boost for good.
## Pressing while airborne is ignored (no double jump).

var height: float = 0.0
var velocity: float = 0.0
var is_grounded: bool = true
var is_holding: bool = false

var _gravity: float
var _initial_velocity: float
var _boost_acceleration: float
var _max_hold_time: float
var _hold_time: float = 0.0


func _init(gravity: float, initial_velocity: float, boost_acceleration: float, max_hold_time: float) -> void:
	_gravity = gravity
	_initial_velocity = initial_velocity
	_boost_acceleration = boost_acceleration
	_max_hold_time = max_hold_time


## Starts a jump if grounded. Returns true when a jump began.
func press() -> bool:
	if not is_grounded:
		return false
	is_grounded = false
	is_holding = true
	_hold_time = 0.0
	velocity = _initial_velocity
	return true


## Ends the boost phase of the current jump (no effect on the ground).
func release() -> void:
	is_holding = false


## Advances the simulation by delta seconds.
func step(delta: float) -> void:
	if is_grounded:
		return
	var boost_time: float = 0.0
	if is_holding:
		boost_time = minf(delta, _max_hold_time - _hold_time)
		_hold_time += delta
		if _hold_time >= _max_hold_time:
			is_holding = false
	velocity += _boost_acceleration * boost_time - _gravity * delta
	height += velocity * delta
	if height <= 0.0:
		height = 0.0
		velocity = 0.0
		is_grounded = true
		is_holding = false
