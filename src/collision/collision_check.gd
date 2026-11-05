class_name CollisionCheck
extends RefCounted
## Pure collision helpers (no nodes): the dog's box, an obstacle's box, and a strict overlap test.
## Implements story-004 (design/game-brief.md, MVP feature 4). Boxes are Rect2 in world px,
## y down, so a box's bottom edge is position.y + size.y.


## True when the boxes overlap with positive area. Touching edges is not a hit.
static func overlaps(a: Rect2, b: Rect2) -> bool:
	return a.position.x < b.end.x and a.end.x > b.position.x \
			and a.position.y < b.end.y and a.end.y > b.position.y


## The dog's hitbox: centred on foot_x + offset_x, bottom edge at foot_y (the feet).
static func dog_box(foot_x: float, foot_y: float, width: float, height: float, offset_x: float) -> Rect2:
	return Rect2(foot_x + offset_x - width * 0.5, foot_y - height, width, height)


## An obstacle's hitbox: left edge at left_x, bottom edge on ground_y. The box is shrunk by
## `shrink` px on the left, right and top (the bottom stays on the ground), so near-misses
## are forgiven. The size never goes below zero.
static func obstacle_box(left_x: float, ground_y: float, width: float, height: float, shrink: float) -> Rect2:
	var box_width: float = maxf(width - 2.0 * shrink, 0.0)
	var box_height: float = maxf(height - shrink, 0.0)
	return Rect2(left_x + shrink, ground_y - box_height, box_width, box_height)
