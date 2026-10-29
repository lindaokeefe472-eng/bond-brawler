## 程序化测试场地：地面、左右墙、背景板、灯光、侧视相机。
##
## 为什么全部用 BoxMesh/QuadMesh：骨架阶段不该被美术资源阻塞；
## 这些几何体只提供空间参照与碰撞，替换成真实关卡时整个类可以整体丢弃。
class_name ArenaBuilder
extends RefCounted

const ARENA_WIDTH: float = 36.0
const ARENA_HALF_WIDTH: float = ARENA_WIDTH * 0.5
const WALL_HEIGHT: float = 6.0
const WALL_THICKNESS: float = 1.0
const GROUND_THICKNESS: float = 1.0
## 地面比纵深带略宽，角色贴边时脚下不会露出空白。
const GROUND_LANE_MARGIN: float = 1.2
const BACKDROP_HEIGHT: float = 8.0
## 背景板必须在角色纵深带（LANE_MIN..LANE_MAX）之后。
## 相机在 +Z 侧朝 -Z 看，所以这里的值必须比 LANE_MIN 更小，否则整块背景会把角色挡住。
const BACKDROP_Z: float = -4.5
## 侧视机位：压低头部俯角，贴近经典清版游戏的「平视 + 一点俯视」观感。
const CAMERA_POSITION: Vector3 = Vector3(0.0, 3.0, 12.0)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 1.15, 0.0)
const CAMERA_FOV: float = 38.0
const LIGHT_ROTATION_DEGREES: Vector3 = Vector3(-52.0, -38.0, 0.0)
const LIGHT_ENERGY: float = 1.1
const AMBIENT_ENERGY: float = 0.55

const SKY_COLOR: Color = Color(0.13, 0.15, 0.22, 1.0)
const AMBIENT_COLOR: Color = Color(0.55, 0.62, 0.78, 1.0)
const GROUND_COLOR: Color = Color(0.26, 0.28, 0.31, 1.0)
const WALL_COLOR: Color = Color(0.18, 0.19, 0.23, 1.0)
const BACKDROP_COLOR: Color = Color(0.20, 0.24, 0.34, 1.0)

var _root: Node3D = null
var _camera: CameraRig = null

func _init(root: Node3D) -> void:
	_root = root

func build() -> void:
	if _root == null:
		return
	_build_environment()
	_build_ground()
	_build_walls()
	_build_backdrop()
	_build_lights()
	_build_camera()

func camera() -> CameraRig:
	return _camera

func arena_half_width() -> float:
	return ARENA_HALF_WIDTH

func _lane_depth() -> float:
	return (GameConstants.LANE_MAX - GameConstants.LANE_MIN) + GROUND_LANE_MARGIN

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = AMBIENT_ENERGY
	world_env.environment = env
	_root.add_child(world_env)

func _build_ground() -> void:
	var size := Vector3(ARENA_WIDTH, GROUND_THICKNESS, _lane_depth())
	var center := Vector3(0.0, -GROUND_THICKNESS * 0.5, 0.0)
	var ground := _make_static_box(size, center, GROUND_COLOR)
	ground.name = "Ground"
	_root.add_child(ground)

func _build_walls() -> void:
	var size := Vector3(WALL_THICKNESS, WALL_HEIGHT, _lane_depth())
	for side: float in [-1.0, 1.0]:
		var x: float = side * (ARENA_HALF_WIDTH + WALL_THICKNESS * 0.5)
		var center := Vector3(x, WALL_HEIGHT * 0.5, 0.0)
		var wall := _make_static_box(size, center, WALL_COLOR)
		wall.name = "WallLeft" if side < 0.0 else "WallRight"
		_root.add_child(wall)

func _build_backdrop() -> void:
	var backdrop := MeshInstance3D.new()
	backdrop.name = "Backdrop"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(ARENA_WIDTH * 2.0, BACKDROP_HEIGHT)
	backdrop.mesh = mesh
	backdrop.position = Vector3(0.0, BACKDROP_HEIGHT * 0.5, BACKDROP_Z)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := _make_material(BACKDROP_COLOR)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backdrop.material_override = material
	_root.add_child(backdrop)

func _build_lights() -> void:
	var light := DirectionalLight3D.new()
	light.name = "SunLight"
	light.rotation_degrees = LIGHT_ROTATION_DEGREES
	light.light_energy = LIGHT_ENERGY
	light.shadow_enabled = true
	_root.add_child(light)

func _build_camera() -> void:
	_camera = CameraRig.new()
	_camera.name = "CameraRig"
	_camera.fov = CAMERA_FOV
	_root.add_child(_camera)
	_camera.set_home(CAMERA_POSITION, CAMERA_TARGET)
	_camera.current = true

func _make_static_box(size: Vector3, center: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = CollisionLayers.ENVIRONMENT
	body.collision_mask = 0

	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)

	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_node.mesh = mesh
	mesh_node.material_override = _make_material(color)
	body.add_child(mesh_node)
	return body

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	material.metallic = 0.0
	return material
