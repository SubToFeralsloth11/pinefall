extends Node3D
## Builds the whole forest at startup: terrain, scattered Poly Haven assets, pond,
## sky/sun/fog/GI, dust, cinematic camera and lens post-processing.

const PH := "res://assets/polyhaven/"
const FOLIAGE := preload("res://shaders/foliage.gdshader")
const WATER := preload("res://shaders/water.gdshader")
const POST := preload("res://shaders/post.gdshader")
const DIRECTOR := preload("res://scripts/director.gd")

const TERRAIN_SIZE := 240.0
const TERRAIN_RES := 400
const POND_CENTER := Vector2(6.0, -4.0)
const POND_RADIUS := 11.0
const POND_DEPTH := 1.6

var noise := FastNoiseLite.new()
var pond_center := POND_CENTER
var pond_base := 0.0
var water_level := 0.0
var rng := RandomNumberGenerator.new()
var _occupied: Array[Vector3] = [] # x, z, radius of trunks/rocks already placed
var env: Environment
var sun: DirectionalLight3D
var cam: Camera3D
var post_mat: ShaderMaterial


func _ready() -> void:
	rng.seed = 7
	noise.seed = 1337
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	pond_base = _base_height(POND_CENTER.x, POND_CENTER.y)
	water_level = pond_base - 0.35

	_build_environment()
	_build_terrain()
	_build_pond()
	_scatter_all()
	_build_dust()
	_build_mist()
	_build_camera()


# ---------------------------------------------------------------- terrain

func _base_height(x: float, z: float) -> float:
	return noise.get_noise_2d(x, z) * 3.5 + noise.get_noise_2d(x * 0.22 + 400.0, z * 0.22) * 10.0


func height_at(x: float, z: float) -> float:
	var h := _base_height(x, z)
	var d := Vector2(x, z).distance_to(POND_CENTER)
	h = lerpf(h, pond_base, smoothstep(POND_RADIUS * 2.6, POND_RADIUS * 1.05, d))
	if d < POND_RADIUS:
		var k := d / POND_RADIUS
		h -= POND_DEPTH * (1.0 - k * k)
	return h


func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := TERRAIN_SIZE / TERRAIN_RES
	var half := TERRAIN_SIZE * 0.5
	for j in TERRAIN_RES + 1:
		for i in TERRAIN_RES + 1:
			var x := -half + i * step
			var z := -half + j * step
			var e := 0.25
			var n := Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e,
					height_at(x, z - e) - height_at(x, z + e)).normalized()
			st.set_normal(n)
			st.set_uv(Vector2(x, z) / 2.5)
			st.add_vertex(Vector3(x, height_at(x, z), z))
	var row := TERRAIN_RES + 1
	for j in TERRAIN_RES:
		for i in TERRAIN_RES:
			var a := j * row + i
			st.add_index(a); st.add_index(a + 1); st.add_index(a + row)
			st.add_index(a + 1); st.add_index(a + row + 1); st.add_index(a + row)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var t := PH + "textures/forrest_ground_01/forrest_ground_01_%s_2k.jpg"
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(t % "diff")
	m.normal_enabled = true
	m.normal_texture = load(t % "nor_gl")
	m.normal_scale = 1.3
	m.roughness_texture = load(t % "rough")
	m.ao_enabled = true
	m.ao_texture = load(t % "ao")
	m.heightmap_enabled = true
	m.heightmap_texture = load(t % "disp")
	m.heightmap_scale = 3.0
	m.heightmap_deep_parallax = true
	m.heightmap_min_layers = 12
	m.heightmap_max_layers = 48
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = m
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(mi)


# ---------------------------------------------------------------- pond

func _build_pond() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(POND_RADIUS * 2.2, POND_RADIUS * 2.2)
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.position = Vector3(POND_CENTER.x, water_level, POND_CENTER.y)
	var m := ShaderMaterial.new()
	m.shader = WATER
	m.set_shader_parameter("wave_a", _wave_normal(11, 0.012))
	m.set_shader_parameter("wave_b", _wave_normal(23, 0.03))
	water.material_override = m
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	var probe := ReflectionProbe.new()
	probe.position = Vector3(POND_CENTER.x, water_level + 6.0, POND_CENTER.y)
	probe.size = Vector3(90, 40, 90)
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.enable_shadows = true
	probe.max_distance = 250.0
	probe.intensity = 1.0
	add_child(probe)


func _wave_normal(seed: int, freq: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 6.0
	tex.noise = n
	return tex


# ---------------------------------------------------------------- assets

## Asset name -> [foliage material keyword ("" = all materials), sway height m, wind m, flutter m]
const FOLIAGE_RULES := {
	"fir_tree_01": ["twig", 18.0, 0.22, 0.006],
	"fir_sapling_medium": ["twigs", 8.0, 0.12, 0.006],
	"pine_sapling_small": ["twig", 1.0, 0.04, 0.004],
	"fern_02": ["", 0.5, 0.05, 0.01],
	"grass_medium_01": ["", 0.15, 0.03, 0.004],
	"moss_01": ["", 0.03, 0.0, 0.0],
}


## Loads a Poly Haven glTF and returns one [Mesh, Basis] pair per variant (top-level node).
func _variants(asset: String) -> Array:
	var scene: PackedScene = load(PH + "models/%s/%s.gltf" % [asset, asset])
	var root := scene.instantiate()
	var out := []
	for child in root.get_children():
		if child is MeshInstance3D:
			_prepare_mesh(asset, child.mesh)
			out.append([child.mesh, child.transform.basis])
	root.free()
	return out


func _prepare_mesh(asset: String, mesh: Mesh) -> void:
	var rule = FOLIAGE_RULES.get(asset)
	for s in mesh.get_surface_count():
		var src := mesh.surface_get_material(s) as StandardMaterial3D
		if src == null:
			continue
		if rule != null and (rule[0] == "" or src.resource_name.contains(rule[0])):
			var m := ShaderMaterial.new()
			m.shader = FOLIAGE
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
			m.set_shader_parameter("normal_tex", src.normal_texture)
			m.set_shader_parameter("arm_tex", src.roughness_texture)
			m.set_shader_parameter("sway_height", rule[1])
			m.set_shader_parameter("wind_strength", rule[2])
			m.set_shader_parameter("flutter", rule[3])
			mesh.surface_set_material(s, m)
		else:
			# Poly Haven *_arm textures also carry AO in red.
			if src.roughness_texture and src.roughness_texture.resource_path.contains("_arm_"):
				src.ao_enabled = true
				src.ao_texture = src.roughness_texture
				src.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
				src.ao_light_affect = 0.4
			src.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			src.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


func _place(variants: Array, pos: Vector3, yaw: float, scale: float, opts := {}) -> MeshInstance3D:
	var v: Array = variants[rng.randi() % variants.size()]
	var mi := MeshInstance3D.new()
	mi.mesh = v[0]
	var b := Basis(Vector3.UP, yaw) * v[1]
	if opts.has("tilt"):
		b = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), opts.tilt) * b
	mi.transform = Transform3D(b.scaled(Vector3.ONE * scale), pos)
	mi.gi_mode = opts.get("gi", GeometryInstance3D.GI_MODE_STATIC)
	if opts.has("range"):
		mi.visibility_range_end = opts.range
		mi.visibility_range_end_margin = opts.range * 0.15
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if opts.get("no_shadow", false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _free_spot(x: float, z: float, r: float) -> bool:
	for o in _occupied:
		if Vector2(x, z).distance_to(Vector2(o.x, o.y)) < r + o.z:
			return false
	return true


## Random point in an annulus around the pond, optionally honouring the occupancy list.
func _spot(rmin: float, rmax: float, radius := 0.0, tries := 30) -> Variant:
	for t in tries:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf_range(rmin * rmin, rmax * rmax))
		var x := POND_CENTER.x + cos(a) * d
		var z := POND_CENTER.y + sin(a) * d
		if radius <= 0.0 or _free_spot(x, z, radius):
			if radius > 0.0:
				_occupied.append(Vector3(x, z, radius))
			return Vector3(x, height_at(x, z), z)
	return null


func _scatter_all() -> void:
	# Keep the camera paths clear of trunks.
	for c in DIRECTOR.clearings(POND_CENTER):
		_occupied.append(c)

	var firs := _variants("fir_tree_01")
	for i in 70:
		var p = _spot(POND_RADIUS + 5.0, 110.0, 3.2)
		if p != null:
			_place(firs, p - Vector3(0, 0.3, 0), rng.randf() * TAU, rng.randf_range(0.8, 1.3))

	var saplings := _variants("fir_sapling_medium")
	for i in 28:
		var p = _spot(POND_RADIUS + 2.0, 60.0, 1.5)
		if p != null:
			_place(saplings, p - Vector3(0, 0.15, 0), rng.randf() * TAU, rng.randf_range(0.45, 0.9))

	var small_pines := _variants("pine_sapling_small")
	for i in 60:
		var p = _spot(POND_RADIUS - 1.0, 45.0, 0.4)
		if p != null:
			_place(small_pines, p, rng.randf() * TAU, rng.randf_range(0.7, 1.6), {"range": 70.0})

	var boulders := _variants("boulder_01")
	for i in 5:
		var p = _spot(POND_RADIUS * 0.6, 40.0, 2.5)
		if p != null:
			_place(boulders, p - Vector3(0, 0.6, 0), rng.randf() * TAU, rng.randf_range(1.6, 3.2))

	var rocks := _variants("rock_moss_set_01") + _variants("rock_moss_set_02")
	for i in 22: # shoreline
		var a := rng.randf() * TAU
		var d := POND_RADIUS * rng.randf_range(0.82, 1.05)
		var x := POND_CENTER.x + cos(a) * d
		var z := POND_CENTER.y + sin(a) * d
		_place(rocks, Vector3(x, height_at(x, z) - 0.25, z), rng.randf() * TAU, rng.randf_range(0.5, 1.4))
	for i in 40:
		var p = _spot(POND_RADIUS + 1.0, 60.0, 0.8)
		if p != null:
			_place(rocks, p - Vector3(0, 0.2, 0), rng.randf() * TAU, rng.randf_range(0.4, 1.2), {"range": 90.0})

	var logs := _variants("dead_tree_trunk")
	for i in 6:
		var p = _spot(POND_RADIUS + 1.0, 35.0, 2.5)
		if p != null:
			_place(logs, p - Vector3(0, 0.08, 0), rng.randf() * TAU, rng.randf_range(2.0, 3.0))
	var roots := _variants("pine_roots")
	for i in 10:
		var p = _spot(POND_RADIUS + 2.0, 35.0, 1.5)
		if p != null:
			_place(roots, p - Vector3(0, 0.05, 0), rng.randf() * TAU, rng.randf_range(1.0, 1.6))

	var branches := _variants("dry_branches_medium_01")
	for i in 120:
		var p = _spot(POND_RADIUS * 0.9, 45.0)
		if p != null and p.y > water_level:
			_place(branches, p, rng.randf() * TAU, rng.randf_range(0.8, 1.6),
					{"range": 45.0, "gi": GeometryInstance3D.GI_MODE_DISABLED})
	for i in 3: # floating on the pond
		var a := rng.randf() * TAU
		var d := rng.randf_range(2.0, POND_RADIUS * 0.7)
		_place(branches, Vector3(POND_CENTER.x + cos(a) * d, water_level - 0.02, POND_CENTER.y + sin(a) * d),
				rng.randf() * TAU, 1.4, {"gi": GeometryInstance3D.GI_MODE_DISABLED})

	var ferns := _variants("fern_02")
	_scatter_clustered(ferns, 380, POND_RADIUS * 0.95, 42.0, Vector2(0.9, 1.8), 60.0)
	var grass := _variants("grass_medium_01")
	_scatter_clustered(grass, 900, POND_RADIUS * 0.85, 30.0, Vector2(2.0, 3.5), 38.0)
	var moss := _variants("moss_01")
	for i in 500:
		var a := rng.randf() * TAU
		var d := POND_RADIUS * rng.randf_range(0.86, 1.4)
		var x := POND_CENTER.x + cos(a) * d
		var z := POND_CENTER.y + sin(a) * d
		_place(moss, Vector3(x, height_at(x, z) - 0.01, z), rng.randf() * TAU, rng.randf_range(4.0, 9.0),
				{"range": 30.0, "no_shadow": true, "gi": GeometryInstance3D.GI_MODE_DISABLED})


## Ground cover placed where a low-frequency mask is high, so it forms natural patches.
func _scatter_clustered(variants: Array, count: int, rmin: float, rmax: float, scale: Vector2, vis: float) -> void:
	var placed := 0
	var guard := 0
	while placed < count and guard < count * 20:
		guard += 1
		var p = _spot(rmin, rmax)
		if p == null or p.y < water_level + 0.02:
			continue
		var mask := noise.get_noise_2d(p.x * 3.0 + 77.0, p.z * 3.0) * 0.5 + 0.5
		if rng.randf() > mask * mask * 2.2:
			continue
		if not _free_spot(p.x, p.z, 0.3):
			continue
		_place(variants, p - Vector3(0, 0.03, 0), rng.randf() * TAU, rng.randf_range(scale.x, scale.y),
				{"range": vis, "gi": GeometryInstance3D.GI_MODE_DISABLED})
		placed += 1


# ---------------------------------------------------------------- lighting

func _build_environment() -> void:
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load(PH + "hdri/kloofendal_28d_misty_puresky.hdr")
	sky_mat.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_1024
	sky.process_mode = Sky.PROCESS_MODE_QUALITY

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0

	env.ssr_enabled = true
	env.ssr_max_steps = 256
	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 3.0
	env.ssr_depth_tolerance = 0.15

	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.ssao_ao_channel_affect = 0.4

	env.ssil_enabled = true
	env.ssil_radius = 6.0
	env.ssil_intensity = 1.2

	env.sdfgi_enabled = true
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = 0.15
	env.sdfgi_use_occlusion = true
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_read_sky_light = true
	env.sdfgi_energy = 1.1
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT

	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	for l in 7:
		env.set_glow_level(l, 1.0 if l in [2, 3, 4, 5] else 0.0)

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	env.volumetric_fog_albedo = Color(0.86, 0.9, 0.93)
	env.volumetric_fog_emission = Color(0.012, 0.016, 0.02)
	env.volumetric_fog_anisotropy = 0.72
	env.volumetric_fog_length = 180.0
	env.volumetric_fog_detail_spread = 1.6
	env.volumetric_fog_gi_inject = 1.0
	env.volumetric_fog_ambient_inject = 0.25
	env.volumetric_fog_sky_affect = 0.15
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.92

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.08

	var we := WorldEnvironment.new()
	we.environment = env
	var attrs := CameraAttributesPractical.new()
	attrs.auto_exposure_enabled = true
	attrs.auto_exposure_scale = 0.45
	attrs.auto_exposure_speed = 0.6
	attrs.auto_exposure_min_sensitivity = 50.0
	attrs.auto_exposure_max_sensitivity = 800.0
	we.camera_attributes = attrs
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-17.0, 205.0, 0.0)
	sun.light_color = Color(1.0, 0.8, 0.6)
	sun.light_energy = 2.6
	sun.light_angular_distance = 0.6
	sun.light_volumetric_fog_energy = 1.6
	sun.shadow_enabled = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 0.8
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.15
	sun.directional_shadow_split_3 = 0.4
	add_child(sun)


func _build_dust() -> void:
	var p := GPUParticles3D.new()
	p.amount = 4000
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 18, 80))
	p.position = Vector3(POND_CENTER.x, pond_base + 2.0, POND_CENTER.y)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(38, 6, 38)
	pm.gravity = Vector3(0, -0.01, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.05
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_speed = Vector3(0.05, 0.02, 0.05)
	pm.scale_min = 0.4
	pm.scale_max = 1.2
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.018, 0.018)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(0.5, 0.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 0.95, 0.85, 1))
	grad.set_color(1, Color(1, 0.95, 0.85, 0))
	g.gradient = grad
	m.albedo_texture = g
	m.albedo_color = Color(1.0, 0.9, 0.75, 0.55)
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)


func _build_mist() -> void:
	# Low ground mist hugging the pond and clearing.
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	fv.size = Vector3(70, 5, 70)
	fv.position = Vector3(POND_CENTER.x, water_level + 0.6, POND_CENTER.y)
	var fm := FogMaterial.new()
	fm.density = 0.12
	fm.albedo = Color(0.9, 0.93, 0.96)
	fm.height_falloff = 0.6
	fm.edge_fade = 0.8
	var n := FastNoiseLite.new()
	n.frequency = 0.05
	var tex := NoiseTexture3D.new()
	tex.width = 64; tex.height = 32; tex.depth = 64
	tex.seamless = true
	tex.noise = n
	fm.density_texture = tex
	fv.material = fm
	add_child(fv)


# ---------------------------------------------------------------- camera + post

func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.05
	cam.far = 600.0
	add_child(cam)
	cam.make_current()

	var layer := CanvasLayer.new()
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = POST
	rect.material = post_mat
	layer.add_child(rect)
	add_child(layer)

	var director := Node.new()
	director.set_script(DIRECTOR)
	director.name = "Director"
	add_child(director)
	director.setup(self)
