extends Node3D
## Read-only playback of Lina's existing, approved skeletal clips.
## Core snapshots own position, facing, casting and time. No animation callback
## changes the simulation, and the model's root never supplies gameplay motion.

const MODEL := preload("res://assets/characters/lina_3d/lina_animated.glb")
const IDLE := "Lina_Idle"
const RUN := "Lina_Run"
const ENTER := "Lina_Cast_Enter_R"
const HOLD := "Lina_Cast_Hold_R"
const RELEASE := "Lina_Cast_Release_R"
const EXIT := "Lina_Cast_Exit_R"
const UPPER_BONES := ["spine_01", "spine_02", "spine_03", "neck_01", "Head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r",
	"upperarm_r", "lowerarm_r", "hand_r", "fireball_socket_r", "hat_tip",
	"hair_l", "hair_tip_l", "hair_r", "hair_tip_r", "hair_back", "hair_back_tip"]

var model: Node3D
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var _clips: Dictionary = {}
var _tracks: Dictionary = {}
var _rest: Array[Transform3D] = []
var _upper: Array[int] = []
var _menu_mode := false
var _initialized := false
var _frozen := true
var _last_time := 0.0
var _last_pos := Vector2.ZERO
var _last_casts := 0
var _idle_time := 0.0
var _run_time := 0.0
var _run_weight := 0.0
var _cast_clip := ""
var _cast_time := 0.0
var _cast_weight := 0.0
var _moving := false
var _run_reference_speed := 1.0
var _run_playback_rate := 1.0


func _ready() -> void:
	name = "LinaMotion"
	model = MODEL.instantiate()
	model.name = "AnimatedLinaModel"
	add_child(model)
	_find_rig(model)
	if skeleton == null or animation_player == null:
		push_error("Lina animation asset is missing its skeleton or clip library.")
		return
	# Disable automatic evaluation. Every transform is sampled below, once, using
	# the same imported tracks that AnimationPlayer would evaluate.
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animation_player.stop()
	animation_player.active = false
	for bone in skeleton.get_bone_count():
		_rest.append(skeleton.get_bone_rest(bone))
		if skeleton.get_bone_name(bone) in UPPER_BONES:
			_upper.append(bone)
	for clip_name in animation_player.get_animation_list():
		var clip: Animation = animation_player.get_animation(clip_name)
		_clips[str(clip_name)] = clip
		var bone_tracks: Dictionary = {}
		for track in clip.get_track_count():
			var path: NodePath = clip.track_get_path(track)
			if path.get_subname_count() != 1:
				continue
			var bone := skeleton.find_bone(str(path.get_subname(0)))
			if bone < 0:
				continue
			if not bone_tracks.has(bone):
				bone_tracks[bone] = {}
			bone_tracks[bone][clip.track_get_type(track)] = track
		_tracks[str(clip_name)] = bone_tracks
	_calibrate_stride()
	_apply_pose()


func _find_rig(node: Node) -> void:
	if node is AnimationPlayer:
		animation_player = node
	elif node is Skeleton3D:
		skeleton = node
	for child in node.get_children():
		_find_rig(child)


func set_menu_mode(value: bool) -> void:
	_menu_mode = value
	_initialized = false
	_frozen = true
	_moving = false
	_run_weight = 0.0
	_cast_weight = 0.0
	_cast_clip = ""
	if skeleton != null:
		_apply_pose()


func advance_menu(delta: float) -> void:
	if not _menu_mode or skeleton == null or not is_visible_in_tree():
		return
	var dt := clampf(delta, 0.0, 0.1)
	_idle_time = fposmod(_idle_time + dt, _length(IDLE))
	_frozen = dt <= 0.0
	_apply_pose()


func sync(snapshot: Dictionary, delta: float = 0.0) -> void:
	if _menu_mode or skeleton == null:
		return
	var player: Dictionary = snapshot.get("player", {})
	var point: Vector2 = player.get("pos", Vector2.ZERO)
	var clock := float(snapshot.get("time", 0.0))
	var casts := int(snapshot.get("casts", 0))
	var phase := str(snapshot.get("phase", ""))
	var active := phase in ["combat", "pickup", "exit", "shop"] and not bool(snapshot.get("paused", false))
	var dt := 0.0
	var travelled := 0.0
	if _initialized and active and not _frozen:
		# Travel uses the controller's frame delta as the legacy single-room
		# clock does not include it; route total time and combat time are separate.
		dt = clampf(clock - _last_time if phase == "combat" else delta, 0.0, 0.1)
		travelled = point.distance_to(_last_pos)
	var released := _initialized and casts > _last_casts
	_initialized = true
	_last_time = clock
	_last_pos = point
	_last_casts = casts
	_frozen = not active
	if dt <= 0.0:
		return
	_moving = travelled > 0.00001
	_run_weight = move_toward(_run_weight, 1.0 if _moving else 0.0, dt * 10.0)
	_idle_time = fposmod(_idle_time + dt, _length(IDLE))
	# Continue the genuine run cycle while physically moving, including casts;
	# a blocked movement request cannot make the stationary character run.
	if _moving:
		var world_scale := maxf(0.000001, global_transform.basis.x.length())
		_run_playback_rate = clampf(travelled / dt / (_run_reference_speed * world_scale), 0.35, 2.4)
		_run_time = fposmod(_run_time + dt * _run_playback_rate, _length(RUN))
	_update_cast(snapshot, dt, released, phase == "combat")
	_apply_pose()


func _update_cast(snapshot: Dictionary, dt: float, released: bool, combat: bool) -> void:
	var chanting: Dictionary = {}
	if combat:
		for spell in snapshot.get("spells", []):
			if float(spell.get("cast_remaining", 0.0)) > 0.0:
				chanting = spell
				break
	if released and combat:
		_cast_clip = RELEASE
		_cast_time = 0.0
	elif _cast_clip == RELEASE and _cast_time < _length(RELEASE):
		_cast_time = minf(_cast_time + dt, _length(RELEASE))
	elif not chanting.is_empty():
		var windup := maxf(0.000001, float(chanting.get("windup", 0.0)))
		var elapsed := maxf(0.0, windup - float(chanting.cast_remaining))
		var enter_duration := minf(windup, _length(ENTER))
		if elapsed < enter_duration:
			_cast_clip = ENTER
			_cast_time = elapsed / enter_duration * _length(ENTER)
		else:
			_cast_clip = HOLD
			_cast_time = fposmod(elapsed - enter_duration, _length(HOLD))
	elif _cast_clip in [ENTER, HOLD, RELEASE]:
		_cast_clip = EXIT
		_cast_time = 0.0
	elif _cast_clip == EXIT:
		_cast_time += dt
		if _cast_time >= _length(EXIT):
			_cast_clip = ""
			_cast_time = 0.0
	var target := 0.0 if _cast_clip.is_empty() else 1.0
	_cast_weight = move_toward(_cast_weight, target, dt * (12.0 if target > 0.0 else 7.0))


func _length(clip_name: String) -> float:
	return maxf(0.000001, float(_clips[clip_name].length)) if _clips.has(clip_name) else 1.0


func _calibrate_stride() -> void:
	# Estimate the clip's authored forward speed from backward travel of the
	# low, planted toes. This is animation geometry, not a gameplay speed copy.
	var feet: Array[int] = [skeleton.find_bone("ball_l"), skeleton.find_bone("ball_r")]
	if feet.min() < 0:
		return
	var samples: Array = []
	var low := INF
	var high := -INF
	for frame in range(61):
		var poses: Array[Transform3D] = []
		for bone in skeleton.get_bone_count():
			var pose := _sample(RUN, bone, _length(RUN) * frame / 60.0)
			var parent := skeleton.get_bone_parent(bone)
			poses.append(poses[parent] * pose if parent >= 0 else pose)
		var pair: Array[Vector3] = []
		for foot in feet:
			var point := poses[foot].origin
			pair.append(point)
			low = minf(low, point.y)
			high = maxf(high, point.y)
		samples.append(pair)
	var speeds: Array[float] = []
	var contact_height := low + (high - low) * 0.2
	for frame in range(1, samples.size()):
		for foot in range(2):
			var before: Vector3 = samples[frame - 1][foot]
			var after: Vector3 = samples[frame][foot]
			var speed := (before.x - after.x) / (_length(RUN) / 60.0)
			if maxf(before.y, after.y) <= contact_height and speed > 0.1:
				speeds.append(speed)
	if not speeds.is_empty():
		speeds.sort()
		_run_reference_speed = maxf(0.1, speeds[speeds.size() / 2])


func _sample(clip_name: String, bone: int, clock: float) -> Transform3D:
	var pose: Transform3D = _rest[bone]
	if not _clips.has(clip_name):
		return pose
	var clip: Animation = _clips[clip_name]
	var tracks: Dictionary = _tracks[clip_name].get(bone, {})
	var point := pose.origin
	var rotation := pose.basis.get_rotation_quaternion()
	var size := pose.basis.get_scale()
	if tracks.has(Animation.TYPE_POSITION_3D):
		point = clip.position_track_interpolate(tracks[Animation.TYPE_POSITION_3D], clock)
	if tracks.has(Animation.TYPE_ROTATION_3D):
		rotation = clip.rotation_track_interpolate(tracks[Animation.TYPE_ROTATION_3D], clock)
	if tracks.has(Animation.TYPE_SCALE_3D):
		size = clip.scale_track_interpolate(tracks[Animation.TYPE_SCALE_3D], clock)
	return Transform3D(Basis(rotation).scaled(size), point)


func _apply_pose() -> void:
	for bone in skeleton.get_bone_count():
		var pose := _sample(IDLE, bone, _idle_time)
		if _run_weight > 0.0:
			pose = pose.interpolate_with(_sample(RUN, bone, _run_time), _run_weight)
		# The cast mask deliberately excludes root, pelvis, legs and skirt.
		# Locomotion remains responsible for all actual lower-body footwork.
		if _cast_weight > 0.0 and not _cast_clip.is_empty() and bone in _upper:
			pose = pose.interpolate_with(_sample(_cast_clip, bone, _cast_time), _cast_weight)
		skeleton.set_bone_pose_position(bone, pose.origin)
		skeleton.set_bone_pose_rotation(bone, pose.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(bone, pose.basis.get_scale())


func get_debug_state() -> Dictionary:
	return {"menu": _menu_mode, "frozen": _frozen, "moving": _moving,
		"idle_time": _idle_time, "run_time": _run_time, "run_weight": _run_weight,
		"run_playback_rate": _run_playback_rate, "run_reference_speed": _run_reference_speed,
		"cast_clip": _cast_clip, "cast_time": _cast_time, "cast_weight": _cast_weight,
		"clip_names": _clips.keys(), "bone_count": skeleton.get_bone_count() if skeleton else 0,
		"upper_bones": _upper.size(), "model_transform": model.transform if model else Transform3D.IDENTITY}
