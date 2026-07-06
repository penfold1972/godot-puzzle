extends Node
## Autoload singleton: tracks the current level, unlock progress, and owns
## all scene transitions so scene paths live in one place.

const LevelLoaderScript := preload("res://src/core/level_loader.gd")

const SAVE_PATH := "user://progress.cfg"
const TITLE_SCENE := "res://scenes/title.tscn"
const LEVEL_SELECT_SCENE := "res://scenes/level_select.tscn"
const GAME_SCENE := "res://scenes/game.tscn"

var current_level: int = 1
var unlocked_up_to: int = 1


func _ready() -> void:
	load_progress()


func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		unlocked_up_to = int(cfg.get_value("progress", "unlocked", 1))
	var count := LevelLoaderScript.level_count()
	if count > 0:
		unlocked_up_to = clampi(unlocked_up_to, 1, count)


func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked_up_to)
	cfg.save(SAVE_PATH)


func mark_completed(level: int) -> void:
	var next_level := mini(level + 1, LevelLoaderScript.level_count())
	if next_level > unlocked_up_to:
		unlocked_up_to = next_level
		save_progress()


func reset_progress() -> void:
	unlocked_up_to = 1
	current_level = 1
	save_progress()


func start_level(n: int) -> void:
	current_level = n
	get_tree().change_scene_to_file(GAME_SCENE)


func goto_title() -> void:
	get_tree().change_scene_to_file(TITLE_SCENE)


func goto_level_select() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECT_SCENE)
