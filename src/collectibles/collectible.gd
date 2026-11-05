class_name Collectible
extends Node2D
## One scrolling collectible (a treat, bone or cookie). Position is the centre of the art.
## Implements story-008 (design/game-brief.md, MVP feature 7).

## Kind id from the tuning data (e.g. "commit_treat").
var kind_id: StringName = &""
## Points added to the score when collected.
var points: int = 0
## Side of the square pickup box (px) centred on the position.
var pickup_size: float = 0.0
## Half the width (px) of the displayed art, used to remove it only once it is fully off-screen.
var art_half_width: float = 0.0
## True once collected: it no longer counts for pickups and is only playing its sparkle.
var collected: bool = false

var _sprite: Sprite2D


## kind: {id, points}; texture: the item's AtlasTexture; art_scale: display scale of the art.
func setup(kind: Dictionary, texture: Texture2D, art_scale: float, pickup_side: float) -> void:
	kind_id = StringName(kind["id"])
	points = int(kind["points"])
	pickup_size = pickup_side
	art_half_width = texture.get_width() * art_scale * 0.5
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.scale = Vector2.ONE * art_scale
	add_child(_sprite)


## The box the dog must touch to collect this item.
func pickup_box() -> Rect2:
	var side := Vector2(pickup_size, pickup_size)
	return Rect2(position - side * 0.5, side)


## Marks the item collected: hides the art and plays a short sparkle that grows and fades,
## then removes the node. The node keeps scrolling with the ground while the sparkle plays.
func collect(sparkle_texture: Texture2D, sparkle_scale: float, seconds: float) -> void:
	collected = true
	_sprite.visible = false
	var sparkle := Sprite2D.new()
	sparkle.texture = sparkle_texture
	sparkle.scale = Vector2.ONE * sparkle_scale
	add_child(sparkle)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(sparkle, "scale", Vector2.ONE * sparkle_scale * 1.6, seconds)
	tween.tween_property(sparkle, "modulate:a", 0.0, seconds)
	tween.chain().tween_callback(queue_free)
