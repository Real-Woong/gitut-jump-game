class_name ScoreTracker
extends RefCounted
## Distance score for one run and the comparison with the best score. No nodes, no file I/O.
## Implements story-005 (design/game-brief.md, MVP feature 5).
##
## Score = distance run (px) * points_per_pixel, rounded down. It only grows while running;
## stop() freezes it for the game-over screen and says whether it beat the best score.

## Points per pixel run (from the tuning data).
var points_per_pixel: float
## Distance run in this run, px.
var distance: float = 0.0
## Bonus points collected in this run (story-008).
var bonus: int = 0
## Best score so far, including any saved from earlier sessions.
var best: int
## False after stop() until reset().
var running: bool = true


func _init(points_per_pixel_value: float, best_score: int) -> void:
	points_per_pixel = points_per_pixel_value
	best = maxi(best_score, 0)


## Adds distance run this frame. Ignored when stopped or when the distance is not positive.
func add_distance(pixels: float) -> void:
	if running and pixels > 0.0:
		distance += pixels


## Adds collected bonus points. Ignored when stopped or when the amount is not positive.
func add_bonus(points: int) -> void:
	if running and points > 0:
		bonus += points


## Current score of this run: distance points plus collected bonus.
func score() -> int:
	return int(distance * points_per_pixel) + bonus


## Freezes the score. Returns true (and updates `best`) when this run beat the best score.
## Calling it again after a stop returns false.
func stop() -> bool:
	if not running:
		return false
	running = false
	if score() > best:
		best = score()
		return true
	return false


## Starts a new run at 0. `best` is kept.
func reset() -> void:
	distance = 0.0
	bonus = 0
	running = true
