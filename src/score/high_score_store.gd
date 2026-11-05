class_name HighScoreStore
extends RefCounted
## Loads and saves the best score as a small JSON file ({"best": n}). The path is injected,
## so a test can point it at a temporary file. Implements story-005.
##
## A missing, unreadable or corrupt file is not an error: the best score is then 0.

var _path: String


func _init(path: String) -> void:
	_path = path


## The saved best score, or 0 when there is no usable save.
func load_best() -> int:
	if not FileAccess.file_exists(_path):
		return 0
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return 0
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return 0
	var value: Variant = (parsed as Dictionary).get("best")
	if not (value is float or value is int) or float(value) < 0.0:
		return 0
	return int(value)


## Writes the best score. Returns false when the file could not be written.
func save_best(best: int) -> bool:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return false
	return file.store_string(JSON.stringify({"best": best}))
