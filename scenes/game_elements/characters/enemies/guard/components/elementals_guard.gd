# SPDX-FileCopyrightText: The Threadbare Authors
# SPDX-License-Identifier: MPL-2.0
@tool
class_name ElementalsGuard
extends CharacterBody2D

## Enemy type that patrols along a path and raises an alert if the player is detected.

## Emitted when the player is detected.
signal player_detected(player: Node)

enum State {
	PATROLLING,
	DETECTING,
	ALERTED,
	INVESTIGATING,
	RETURNING,
}

const DEFAULT_SPRITE_FRAMES = preload("uid://ovu5wqo15s5g")

@export_category("Appearance")
# backing var + exported property linked to setter to avoid recursion
var _sprite_frames: SpriteFrames = DEFAULT_SPRITE_FRAMES
@export var sprite_frames: SpriteFrames = DEFAULT_SPRITE_FRAMES:
	set = _set_sprite_frames

@export_category("Sounds")
var _alerted_sound_stream: AudioStream
var _footsteps_sound_stream: AudioStream
var _idle_sound_stream: AudioStream
var _alert_others_sound_stream: AudioStream

@export var alerted_sound_stream: AudioStream:
	set = _set_alerted_sound_stream
@export var footsteps_sound_stream: AudioStream:
	set = _set_footsteps_sound_stream
@export var idle_sound_stream: AudioStream:
	set = _set_idle_sound_stream
@export var alert_others_sound_stream: AudioStream:
	set = _set_alert_other_sound_stream

@export_category("Patrol")
@warning_ignore("unused_private_class_variable")
@export_tool_button("Add/Edit Patrol Path") var _edit_patrol_path: Callable = edit_patrol_path

@export var patrol_path: Path2D
@export_range(0, 5, 0.1, "or_greater", "suffix:s") var wait_time: float = 1.0
@export_range(20, 300, 5, "or_greater", "or_less", "suffix:m/s") var move_speed: float = 100.0

@export_category("Player Detection")
@export var player_instantly_detected_on_sight: bool = false
@export_range(0.1, 5, 0.1, "or_greater", "suffix:s") var time_to_detect_player: float = 1.0
@export_range(0.1, 5, 0.1, "or_greater", "or_less") var detection_area_scale: float = 1.0:
	set(value):
		detection_area_scale = value
		if detection_area:
			detection_area.scale = Vector2.ONE * detection_area_scale

@export_category("Debug")
@export var move_while_in_editor: bool = false
@export var show_debug_info: bool = false

# Internal state
var previous_patrol_point_idx: int = -1
var current_patrol_point_idx: int = 0
var last_seen_position: Vector2
var breadcrumbs: Array[Vector2] = []
var state: State = State.PATROLLING:
	set = _set_state

# The player that's being detected (tipo dinámico para evitar errores de scope).
var _player: Node = null

# --- INSTA-KILL POR RETENCIÓN ---
@export_category("Attack")
@export var instakill_delay: float = 1.5    # segundos que el jugador debe permanecer en alerta antes del instakill
var _instakill_timer: float = 0.0
var _has_instakilled: bool = false

# --- ATAQUE / INSTA-KILL ---
@export var attack_range: float = 24.0        # distancia para golpear (ajusta)
@export var attack_cooldown: float = 0.5      # segundos entre ataques (evita multi-hit)
var _attack_timer: float = 0.0

# Node references (onready)
@onready var detection_area: Area2D = %DetectionArea
@onready var player_awareness: TextureProgressBar = %PlayerAwareness
@onready var sight_ray_cast: RayCast2D = %SightRayCast
@onready var debug_info: Label = %DebugInfo

# gdlint:ignore = max-line-length
@onready var character_animation_player_behavior: CharacterAnimationPlayerBehavior = %CharacterAnimationPlayerBehavior

# guard_movement: relajamos el tipo para evitar errores si tu clase tiene nombre distinto
@onready var guard_movement :ElementalsGuardMovement= %GuardMovement
@onready var animated_sprite_2d: AnimatedSprite2D = %AnimatedSprite2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var _alert_sound: AudioStreamPlayer = %AlertSound
@onready var _foot_sound: AudioStreamPlayer2D = %FootSound
@onready var _fire_sound: AudioStreamPlayer2D = %FireSound
@onready var _torch_hit_sound: AudioStreamPlayer2D = %TorchHitSound

# -----------------------
# Configuration warnings
# -----------------------
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray
	if not _sprite_frames:
		warnings.push_back("sprite_frames must be set.")

	for required_animation: StringName in [&"alerted", &"idle", &"walk"]:
		if _sprite_frames and not _sprite_frames.has_animation(required_animation):
			warnings.push_back("sprite_frames is missing the following animation: %s" % required_animation)

	return warnings

func _ready() -> void:
	if not Engine.is_editor_hint():
		if player_awareness:
			player_awareness.max_value = time_to_detect_player
			player_awareness.value = 0.0

	_set_sprite_frames(_sprite_frames)

	if detection_area:
		detection_area.scale = Vector2.ONE * detection_area_scale

	if patrol_path:
		global_position = _patrol_point_position(0)

	if guard_movement:
		guard_movement.destination_reached.connect(self._on_destination_reached)
		guard_movement.still_time_finished.connect(self._on_still_time_finished)
		guard_movement.path_blocked.connect(self._on_path_blocked)


func _process(delta: float) -> void:
	_update_debug_info()

	if Engine.is_editor_hint() and not move_while_in_editor:
		return

	_process_state()
	if guard_movement:
		guard_movement.move()

	if state == State.ALERTED:
		_attack_player(delta)
	else:
		_update_player_awareness(delta)

	_update_animation()

	# Manejo del temporizador de instakill: solo cuenta mientras esté ALERTED y haya player válido
	if state == State.ALERTED and not _has_instakilled and _player and is_instance_valid(_player):
		_instakill_timer = max(0.0, _instakill_timer - delta)
		if _instakill_timer <= 0.0:
			_apply_instakill()
			_has_instakilled = true


# State processing
func _process_state() -> void:
	match state:
		State.PATROLLING:
			if patrol_path:
				var target_position: Vector2 = _patrol_point_position(current_patrol_point_idx)
				if guard_movement:
					guard_movement.set_destination(target_position)
			else:
				if guard_movement:
					guard_movement.stop_moving()
		State.INVESTIGATING:
			if guard_movement:
				guard_movement.set_destination(last_seen_position)
		State.RETURNING:
			if not breadcrumbs.is_empty():
				var target_position: Vector2 = breadcrumbs.back()
				if guard_movement:
					guard_movement.set_destination(target_position)
			else:
				state = State.PATROLLING
		State.ALERTED:
			if guard_movement:
				guard_movement.stop_moving()


# Player awareness bar logic
func _update_player_awareness(delta: float) -> void:
	var player_in_sight: bool = _player != null and not _is_sight_to_point_blocked(_player.global_position)

	# Smoothly move awareness value toward max or zero
	player_awareness.value = move_toward(
		player_awareness.value, player_awareness.max_value if player_in_sight else 0.0, delta
	)
	player_awareness.visible = player_awareness.ratio > 0.0
	player_awareness.modulate.a = clamp(player_awareness.ratio, 0.5, 1.0)

	if player_awareness.ratio >= 1.0:
		state = State.ALERTED
		player_detected.emit(_player)


# Animation updates
func _update_animation() -> void:
	if state == State.ALERTED:
		return

	if velocity.is_zero_approx():
		animation_player.play("idle")
	else:
		animation_player.play("walk")


# Debug info
func _update_debug_info() -> void:
	debug_info.visible = show_debug_info
	if not debug_info.visible:
		return
	debug_info.text = ""
	debug_property("position")
	debug_value("state", State.keys()[state])
	debug_property("previous_patrol_point_idx")
	debug_property("current_patrol_point_idx")
	if guard_movement:
		debug_value("time left", "%.2f" % guard_movement.still_time_left_in_seconds)
		debug_value("target point", guard_movement.destination)


# Destination reached / still time finished / path blocked
func _on_destination_reached() -> void:
	match state:
		State.PATROLLING:
			if guard_movement:
				guard_movement.wait_seconds(wait_time)
			_advance_target_patrol_point()
		State.INVESTIGATING:
			if guard_movement:
				guard_movement.wait_seconds(wait_time)
		State.RETURNING:
			if not breadcrumbs.is_empty():
				breadcrumbs.pop_back()

func _on_still_time_finished() -> void:
	if state == State.INVESTIGATING:
		state = State.RETURNING

func _on_path_blocked() -> void:
	match state:
		State.PATROLLING:
			if guard_movement:
				guard_movement.wait_seconds(wait_time)
			if previous_patrol_point_idx > -1:
				var new_patrol_point: int = previous_patrol_point_idx
				previous_patrol_point_idx = current_patrol_point_idx
				current_patrol_point_idx = new_patrol_point
		State.INVESTIGATING:
			state = State.RETURNING
		State.RETURNING:
			if not breadcrumbs.is_empty():
				breadcrumbs.pop_back()


# Safe setter for state (initializes instakill timer on ALERTED)
func _set_state(new_state: State) -> void:
	if state == new_state:
		return

	state = new_state

	match state:
		State.DETECTING:
			if not _alert_sound.playing:
				_alert_sound.play()

		State.ALERTED:
			character_animation_player_behavior.process_mode = Node.PROCESS_MODE_DISABLED
			if not _alert_sound.playing:
				_alert_sound.play()
			animation_player.play("alerted")
			player_awareness.ratio = 1.0
			player_awareness.tint_progress = Color.RED
			player_awareness.visible = true

			# Inicializa temporizador de instakill (no mata inmediatamente)
			_instakill_timer = instakill_delay
			_has_instakilled = false

		State.INVESTIGATING:
			if guard_movement:
				guard_movement.start_moving_now()
			breadcrumbs.push_back(global_position)


# Debug helpers
func debug_property(property_name: String) -> void:
	debug_value(property_name, get(property_name))

func debug_value(value_name: String, value: Variant) -> void:
	debug_info.text += "%s: %s\n" % [value_name, value]


# Patrol helpers
func _advance_target_patrol_point() -> void:
	if not patrol_path or not patrol_path.curve or _amount_of_patrol_points() < 2:
		return

	var new_patrol_point_idx: int

	if _is_patrol_path_closed():
		new_patrol_point_idx = (current_patrol_point_idx + 1) % (_amount_of_patrol_points() - 1)
	else:
		var at_last_point: bool = current_patrol_point_idx == (_amount_of_patrol_points() - 1)
		var at_first_point: bool = current_patrol_point_idx == 0
		var going_backwards_in_path: bool = previous_patrol_point_idx > current_patrol_point_idx
		if at_last_point:
			new_patrol_point_idx = current_patrol_point_idx - 1
		elif at_first_point:
			new_patrol_point_idx = current_patrol_point_idx + 1
		elif going_backwards_in_path:
			new_patrol_point_idx = current_patrol_point_idx - 1
		else:
			new_patrol_point_idx = current_patrol_point_idx + 1

	previous_patrol_point_idx = current_patrol_point_idx
	current_patrol_point_idx = new_patrol_point_idx


func _is_sight_to_point_blocked(point_position: Vector2) -> bool:
	sight_ray_cast.target_position = sight_ray_cast.to_local(point_position)
	sight_ray_cast.force_raycast_update()
	return sight_ray_cast.is_colliding()


func _patrol_point_position(point_idx: int) -> Vector2:
	var local_point_position: Vector2 = patrol_path.curve.get_point_position(point_idx)
	return patrol_path.to_global(local_point_position)


func _amount_of_patrol_points() -> int:
	return patrol_path.curve.point_count


func _is_patrol_path_closed() -> bool:
	if not patrol_path:
		return false
	var curve: Curve2D = patrol_path.curve
	if curve.point_count < 3:
		return false
	var first_point_position: Vector2 = curve.get_point_position(0)
	var last_point_position: Vector2 = curve.get_point_position(curve.point_count - 1)
	return first_point_position.is_equal_approx(last_point_position)


func _reset() -> void:
	previous_patrol_point_idx = -1
	current_patrol_point_idx = 0
	velocity = Vector2.ZERO
	if patrol_path:
		global_position = _patrol_point_position(0)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EDITOR_PRE_SAVE:
			_reset()


static func _editor_interface() -> Object:
	return Engine.get_singleton("EditorInterface")


func edit_patrol_path() -> void:
	if not Engine.is_editor_hint():
		return

	var editor_interface := _editor_interface()

	if patrol_path:
		editor_interface.edit_node.call_deferred(patrol_path)
	else:
		var new_patrol_path: Path2D = Path2D.new()
		patrol_path = new_patrol_path
		get_parent().add_child(patrol_path)
		patrol_path.owner = owner
		patrol_path.global_position = global_position
		var patrol_path_curve: Curve2D = Curve2D.new()
		patrol_path.curve = patrol_path_curve
		patrol_path.name = "%s-PatrolPath" % name
		patrol_path_curve.add_point(Vector2.ZERO)
		patrol_path_curve.add_point(Vector2.RIGHT * 150.0)
		editor_interface.edit_node.call_deferred(patrol_path)


# ---------- Safe property setters (use backing vars) ----------
func _set_sprite_frames(new_sprite_frames: SpriteFrames) -> void:
	_sprite_frames = new_sprite_frames
	if not is_node_ready():
		return
	animated_sprite_2d.sprite_frames = _sprite_frames
	update_configuration_warnings()


func _set_alerted_sound_stream(new_value: AudioStream) -> void:
	_alerted_sound_stream = new_value
	if not is_node_ready():
		await ready
	_alert_sound.stream = _alerted_sound_stream


func _set_footsteps_sound_stream(new_value: AudioStream) -> void:
	_footsteps_sound_stream = new_value
	if not is_node_ready():
		await ready
	_foot_sound.stream = _footsteps_sound_stream


func _set_idle_sound_stream(new_value: AudioStream) -> void:
	_idle_sound_stream = new_value
	if not is_node_ready():
		await ready
	_fire_sound.stream = _idle_sound_stream


func _set_alert_other_sound_stream(new_value: AudioStream) -> void:
	_alert_others_sound_stream = new_value
	if not is_node_ready():
		await ready
	_torch_hit_sound.stream = _alert_others_sound_stream


# Detection area callbacks
func _on_instant_detection_area_body_entered(body: Node2D) -> void:
	if not body is Player:
		return

	# Solo ALERTED si tiene línea de visión
	if not _is_sight_to_point_blocked(body.global_position):
		state = State.ALERTED
		player_detected.emit(body as Player)
	else:
		# Si está detrás del guardia o con pared, solo pasa a "DETECTING"
		state = State.DETECTING




func _on_detection_area_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player = body
	if _is_sight_to_point_blocked(body.global_position):
		return
	if player_instantly_detected_on_sight:
		state = State.ALERTED
		player_detected.emit(_player)
	else:
		state = State.DETECTING


func _on_detection_area_body_exited(body: Node2D) -> void:
	if _player == body:
		_player = null
	last_seen_position = body.global_position
	if state == State.DETECTING:
		if guard_movement:
			guard_movement.stop_moving()
		state = State.INVESTIGATING


# Instakill / damage functions
func _apply_instakill() -> void:
	if _player and is_instance_valid(_player):
		if _player.has_method("take_damage"):
			_player.take_damage(9999) # instakill
		else:
			# fallback if player uses different system
			if _player.has_variable("current_health_halves"):
				_player.current_health_halves = 0
				if _player.has_method("die"):
					_player.die()
			elif _player.has_method("die"):
				_player.die()

		# If you have a scene switcher, use it; otherwise you can reload manually.
		if Engine.has_singleton("SceneSwitcher"):
			SceneSwitcher.reload_with_transition(Transition.Effect.FADE, Transition.Effect.FADE)
		else:
			get_tree().reload_current_scene()


func do_damage() -> void:
	if _player and is_instance_valid(_player) and _player.has_method("take_damage"):
		_player.take_damage(10000) # muerte instantánea
		print("Guardia: golpe mortal!")


# Attack routine called when ALERTED
func _attack_player(delta: float) -> void:
	_attack_timer = max(0.0, _attack_timer - delta)
	if not _player or not is_instance_valid(_player):
		return

	var dist := global_position.distance_to(_player.global_position)
	if dist <= attack_range and _attack_timer <= 0.0:
		if _player.has_method("take_damage"):
			_player.take_damage(9999)
		else:
			if _player.has_variable("current_health_halves"):
				_player.current_health_halves = 0
				if _player.has_method("die"):
					_player.die()
		_attack_timer = attack_cooldown
