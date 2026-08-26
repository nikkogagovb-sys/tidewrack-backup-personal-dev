extends Node2D
class_name LampRoom
## LampRoom — the playable lamp-room chapter.
##
## The room is built in code to match the ground-floor scene. The great lamp
## uses the shared Interactable API; its normal interaction starts the
## lamp-room dialogue graph.

const LAMP_DIALOGUE := "res://data/dialogue/lamp_room.json"
const EDITH_VO_PATH := "audio/vo/keeper_lamp_012_take1.wav"
const INTERACT_RADIUS := 90.0
const ROOM := Rect2(120, 140, 1040, 460)

var _player: Player
var _interactables: Array[Interactable] = []
var _great_lamp: Interactable
var _prompt: Label
var _nearest: Interactable = null
var _paused: bool = false
var _edith_voice: AudioStream


func _ready() -> void:
	_preload_edith_voice()
	_build_room()
	_build_player()
	_build_interactables()
	_build_hud()

	var dialogue_box := preload("res://scenes/ui/dialogue_box.tscn").instantiate()
	add_child(dialogue_box)

	DialogueManager.dialogue_started.connect(func(): _set_movement(false))
	DialogueManager.dialogue_finished.connect(func(): _set_movement(true))


func _preload_edith_voice() -> void:
	var resource_path := "res://%s" % EDITH_VO_PATH
	if ResourceLoader.exists(resource_path):
		_edith_voice = ResourceLoader.load(resource_path) as AudioStream
	else:
		push_warning("LampRoom: expected voice asset is missing: %s" % EDITH_VO_PATH)


func _build_room() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0b1216")
	bg.size = Vector2(1280, 720)
	add_child(bg)

	var floor := ColorRect.new()
	floor.color = Color("#18232a")
	floor.position = ROOM.position
	floor.size = ROOM.size
	add_child(floor)

	var title := Label.new()
	title.text = "Cape Marrow Light — lamp room"
	title.position = Vector2(ROOM.position.x, ROOM.position.y - 34)
	title.modulate = Color(1, 1, 1, 0.5)
	add_child(title)

	var lantern_halo := ColorRect.new()
	lantern_halo.color = Color(0.9, 0.66, 0.25, 0.08)
	lantern_halo.position = Vector2(500, 140)
	lantern_halo.size = Vector2(280, 280)
	add_child(lantern_halo)


func _build_player() -> void:
	_player = Player.new()
	_player.bounds = ROOM.grow(-30)
	_player.position = Vector2(ROOM.position.x + ROOM.size.x * 0.5, ROOM.position.y + ROOM.size.y - 60)
	add_child(_player)

	var camera := Camera2D.new()
	camera.position_smoothing_enabled = true
	_player.add_child(camera)
	camera.make_current()


func _build_interactables() -> void:
	_great_lamp = Interactable.new()
	_great_lamp.name = "GreatLamp"
	_great_lamp.label = "Great lamp"
	_great_lamp.prompt_text = "Examine the great lamp"
	_great_lamp.dialogue_path = LAMP_DIALOGUE
	_great_lamp.dialogue_start = "start"
	_great_lamp.color = Color("#2a2f33")
	_great_lamp.position = Vector2(ROOM.position.x + ROOM.size.x * 0.5, ROOM.position.y + 170)
	add_child(_great_lamp)
	_great_lamp.setup()
	_great_lamp.interacted.connect(_select_lamp_opening)
	_interactables.append(_great_lamp)


func _select_lamp_opening(_source: Interactable) -> void:
	var trusted_edith := bool(GameState.get_flag("trusted_edith", false))
	var believer := bool(GameState.get_flag("believer", false))

	if trusted_edith:
		_great_lamp.dialogue_start = "trusted_believer" if believer else "trusted_skeptic"
	else:
		_great_lamp.dialogue_start = "skeptical_believer" if believer else "uncommitted"


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_prompt = Label.new()
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -70
	_prompt.offset_left = -200
	_prompt.offset_right = 200
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.modulate = Color("#ffd466")
	_prompt.hide()
	layer.add_child(_prompt)


func _process(_delta: float) -> void:
	if _paused or DialogueManager.is_active:
		_prompt.hide()
		return
	_nearest = _find_nearest()
	if _nearest != null:
		_prompt.text = "[ Enter ] %s" % _nearest.prompt_text
		_prompt.show()
	else:
		_prompt.hide()


func _find_nearest() -> Interactable:
	var best: Interactable = null
	var best_dist := INTERACT_RADIUS
	for item in _interactables:
		if not item.can_interact():
			continue
		var dist := _player.position.distance_to(item.position)
		if dist <= best_dist:
			best_dist = dist
			best = item
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if _paused or DialogueManager.is_active:
		return
	if event.is_action_pressed("ui_accept") and _nearest != null:
		_nearest.interact()
		get_viewport().set_input_as_handled()


func _set_movement(enabled: bool) -> void:
	if _player != null:
		_player.can_move = enabled and not _paused


func _toggle_pause() -> void:
	if DialogueManager.is_active:
		return
	_paused = not _paused
	_set_movement(not _paused)
	if _paused:
		_show_pause_menu()


func _show_pause_menu() -> void:
	var overlay := Control.new()
	overlay.name = "PauseOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = 20
	layer.name = "PauseLayer"
	layer.add_child(overlay)
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	var resume := _menu_button("Resume")
	resume.pressed.connect(func():
		layer.queue_free()
		_paused = false
		_set_movement(true))
	vbox.add_child(resume)

	var settings := _menu_button("Settings")
	settings.pressed.connect(func():
		overlay.add_child(preload("res://scenes/ui/settings.tscn").instantiate()))
	vbox.add_child(settings)

	var menu := _menu_button("Main Menu")
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	vbox.add_child(menu)

	resume.grab_focus()


func _menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 40)
	button.add_theme_font_size_override("font_size", 20)
	return button


func is_lamp_lit() -> bool:
	return bool(GameState.get_flag("lamp_relit", false))
