class_name Obstacle
extends Node2D
## One scrolling obstacle (visual only; no collision until Story 004).
## Origin = left edge of the opaque art, on the ground line; the art extends right and up.

## Kind id from the tuning data (e.g. "bug").
var kind_id: StringName = &""
## Opaque art width in px after scaling.
var width: float = 0.0
## Opaque art height in px after scaling (the clearance the dog needs).
var height: float = 0.0


## Builds the sprite so the opaque art's left edge is at x=0 and its bottom edge at y=0.
## kind: {id, scale, opaque_rect [left, top, right, bottom] in texture px}.
func setup(kind: Dictionary, texture: Texture2D, art_scale: float, art_width: float, art_height: float) -> void:
	kind_id = StringName(kind["id"])
	width = art_width
	height = art_height
	var rect: Array = kind["opaque_rect"]
	var center: Vector2 = texture.get_size() * 0.5
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2.ONE * art_scale
	sprite.position = Vector2((center.x - float(rect[0])) * art_scale, (center.y - float(rect[3])) * art_scale)
	add_child(sprite)
