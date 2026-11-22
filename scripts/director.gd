extends Node
## Cinematic shot sequencer + free-fly camera, quality presets, HUD and screenshot mode.
##   F free-fly / cinematic   H HUD   1/2/3 quality   P screenshot   Esc quit
##   Free-fly: WASD move, Q/E down/up, mouse look, Shift fast, wheel speed.
## Command line (after --): --shots  renders every shot to res://screenshots and quits.

const CINEMA_ASPECT := 2.39
const FADE := 0.9

## a/b: camera start/end offsets from the pond centre (y = metres above ground or water),
## la/lb: look-at start/end offsets (y = metres above pond level), focus: metres (0 = look-at distance).
const SHOTS := [
	{"name": "Still water", "a": Vector3(1.5, 0.45, 15.5), "b": Vector3(-0.5, 0.35, 5.0), "water": true,
		"la": Vector3(-4, 3.5, -30), "lb": Vector3(-6, 5.0, -30), "dur": 16.0, "fov": 38.0, "focus": 0.0, "dof": 0.03},
	{"name": "Undergrowth", "a": Vector3(-13.5, 0.35, 7.0), "b": Vector3(-11.0, 0.4, 9.5),
		"la": Vector3(-12.5, 0.6, 3.0), "lb": Vector3(-9.0, 0.8, 4.5), "dur": 14.0, "fov": 30.0, "focus": 0.0, "dof": 0.16},
	{"name": "Into the canopy", "a": Vector3(9.0, 1.0, 17.0), "b": Vector3(8.0, 15.0, 15.0),
		"la": Vector3(3, 2.0, -12), "lb": Vector3(-2, 10.0, -35), "dur": 18.0, "fov": 42.0, "focus": 0.0, "dof": 0.02},
	{"name": "The clearing", "a": Vector3(34.0, 20.0, 28.0), "b": Vector3(24.0, 17.0, 36.0),
		"la": Vector3(0, 0.0, 0), "lb": Vector3(-2, 0.0, -2), "dur": 16.0, "fov": 45.0, "focus": 0.0, "dof": 0.01},
	{"name": "Shoreline", "a": Vector3(-9.5, 0.5, -9.0), "b": Vector3(-5.0, 0.6, -12.5),
		"la": Vector3(4, 0.5, 2), "lb": Vector3(8, 1.0, 0), "dur": 15.0, "fov": 34.0, "focus": 0.0, "dof": 0.08},
]

const PRESETS := [
	{"name": "Cinematic (native, TAA)", "mode": Viewport.SCALING_3D_MODE_BILINEAR, "scale": 1.0, "taa": true},
	{"name": "High (FSR2 75%)", "mode": Viewport.SCALING_3D_MODE_FSR2, "scale": 0.75, "taa": false},
	{"name": "Performance (FSR2 50%)", "mode": Viewport.SCALING_3D_MODE_FSR2, "scale": 0.5, "taa": false},
]

var world: Node3D
var cam: Camera3D
var post: ShaderMaterial
var attrs: CameraAttributesPractical
var hud: Label
var shot := 0
var t := 0.0
var free_fly := false
var fly_speed := 4.0
var yaw := 0.0
var pitch := 0.0
var preset := 0
var shots_mode := false


static func clearings(center: Vector2) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for s in SHOTS:
		for k in 6:
			var o: Vector3 = s.a.lerp(s.b, k / 5.0)
			out.append(Vector3(center.x + o.x, center.y + o.z, 2.2))
	return out


func setup(w: Node3D) -> void:
	world = w
	cam = w.cam
	post = w.post_mat
	attrs = CameraAttributesPractical.new()
	attrs.auto_exposure_enabled = true
	attrs.auto_exposure_scale = 0.45
	attrs.auto_exposure_speed = 0.6
	attrs.auto_exposure_min_sensitivity = 50.0
	attrs.auto_exposure_max_sensitivity = 800.0
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_near_enabled = true
	cam.attributes = attrs

	var layer := CanvasLayer.new()
	layer.layer = 2
	hud = Label.new()
	hud.position = Vector2(16, 10)
	hud.add_theme_font_size_override("font_size", 15)
	hud.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	layer.add_child(hud)
	add_child(layer)

	shots_mode = "--shots" in OS.get_cmdline_user_args()
	_apply_preset(0)
	get_viewport().size_changed.connect(_update_letterbox)
	_update_letterbox()
	if shots_mode:
		hud.visible = false
		_capture_all()


func _update_letterbox() -> void:
	var s := get_viewport().get_visible_rect().size
	var bar := 0.0 if free_fly else maxf(0.0, (1.0 - (s.x / s.y) / CINEMA_ASPECT) * 0.5)
	post.set_shader_parameter("letterbox", bar)


func _apply_preset(i: int) -> void:
	preset = i
	var p: Dictionary = PRESETS[i]
	var vp := get_viewport()
	vp.scaling_3d_mode = p.mode
	vp.scaling_3d_scale = p.scale
	vp.use_taa = p.taa


func _shot_pose(s: Dictionary, u: float) -> Array:
	var e := u * u * (3.0 - 2.0 * u)
	var c: Vector2 = world.pond_center
	var o: Vector3 = s.a.lerp(s.b, e)
	var x := c.x + o.x
	var z := c.y + o.z
	var ground: float = world.water_level if s.get("water", false) else world.height_at(x, z)
	var pos := Vector3(x, ground + o.y, z)
	var l: Vector3 = s.la.lerp(s.lb, e)
	var look := Vector3(c.x + l.x, world.pond_base + l.y, c.y + l.z)
	return [pos, look]


func _pose_camera(s: Dictionary, u: float) -> void:
	var pose := _shot_pose(s, u)
	cam.global_position = pose[0]
	cam.look_at(pose[1])
	cam.fov = s.fov
	var focus: float = s.focus if s.focus > 0.0 else pose[0].distance_to(pose[1])
	attrs.dof_blur_far_distance = focus * 1.15
	attrs.dof_blur_far_transition = focus * 1.5
	attrs.dof_blur_near_distance = focus * 0.55
	attrs.dof_blur_near_transition = focus * 0.4
	attrs.dof_blur_amount = s.dof


func _process(delta: float) -> void:
	if shots_mode:
		return
	if free_fly:
		_fly(delta)
		post.set_shader_parameter("fade", 0.0)
	else:
		var s: Dictionary = SHOTS[shot]
		t += delta
		if t >= s.dur:
			t = 0.0
			shot = (shot + 1) % SHOTS.size()
			s = SHOTS[shot]
		_pose_camera(s, t / s.dur)
		var f := 1.0 - minf(minf(t, s.dur - t) / FADE, 1.0)
		post.set_shader_parameter("fade", f * f)
	if hud.visible:
		hud.text = "PINEFALL  |  %d fps  |  %s  |  %s\nF free-fly   H hide HUD   1/2/3 quality   P screenshot   Esc quit" % [
			Engine.get_frames_per_second(), PRESETS[preset].name,
			"Free-fly" if free_fly else "Shot %d/%d: %s" % [shot + 1, SHOTS.size(), SHOTS[shot].name]]


func _fly(delta: float) -> void:
	var dir := Vector3(
			float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
			float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q)),
			float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W)))
	var speed := fly_speed * (4.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	cam.global_position += cam.global_basis * dir * speed * delta
	cam.rotation = Vector3(pitch, yaw, 0.0)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_F:
				free_fly = not free_fly
				attrs.dof_blur_far_enabled = not free_fly
				attrs.dof_blur_near_enabled = not free_fly
				if free_fly:
					yaw = cam.rotation.y
					pitch = cam.rotation.x
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if free_fly else Input.MOUSE_MODE_VISIBLE
				_update_letterbox()
			KEY_H:
				hud.visible = not hud.visible
			KEY_1, KEY_2, KEY_3:
				_apply_preset(ev.keycode - KEY_1)
			KEY_P:
				_save_screenshot("user://pinefall_%d.png" % Time.get_unix_time_from_system())
	elif ev is InputEventMouseMotion and free_fly:
		yaw -= ev.relative.x * 0.0025
		pitch = clampf(pitch - ev.relative.y * 0.0025, -1.5, 1.5)
	elif ev is InputEventMouseButton and free_fly and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			fly_speed *= 1.2
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			fly_speed /= 1.2


func _save_screenshot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", ProjectSettings.globalize_path(path))


func _capture_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	post.set_shader_parameter("fade", 0.0)
	var frames := 0
	var fps_sum := 0.0
	for i in SHOTS.size():
		var s: Dictionary = SHOTS[i]
		# Let SDFGI, TAA, auto exposure and volumetric fog converge on a slowly moving camera.
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 6000:
			var u := 0.35 + 0.1 * (Time.get_ticks_msec() - start) / 6000.0
			_pose_camera(s, u)
			await get_tree().process_frame
			if Time.get_ticks_msec() - start > 3000:
				frames += 1
				fps_sum += Engine.get_frames_per_second()
		await RenderingServer.frame_post_draw
		_save_screenshot("res://screenshots/shot_%d.png" % (i + 1))
	print("avg fps %.1f" % (fps_sum / maxf(frames, 1)))
	get_tree().quit()
