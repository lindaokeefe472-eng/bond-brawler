## 弹体表现层：把领域层的弹体列表同步成场上的方块。
##
## 只读 BattleSession.projectiles()，不改任何战斗状态 —— 和 ActorView 同一个原则：
## 表现层永远是领域状态的投影，不产生第二份真相。
## 现在用色块占位，换正式特效时只需要改 _make_mesh 和 _material_for。
class_name ProjectileLayer
extends Node3D

## 方块边长 = 命中半径 * 这个系数，看起来比判定略大一点点，视觉上更实。
const SIZE_SCALE: float = 2.0
const MIN_SIZE: float = 0.12

## 按属性上色，先给能一眼分辨的占位配色。
const TYPE_COLORS: Dictionary = {
	&"fire": Color(1.0, 0.45, 0.15),
	&"water": Color(0.30, 0.60, 1.0),
	&"grass": Color(0.40, 0.90, 0.40),
	&"electric": Color(1.0, 0.95, 0.30),
	&"ice": Color(0.60, 0.95, 1.0),
	&"poison": Color(0.75, 0.35, 0.85),
	&"neutral": Color(0.92, 0.92, 0.92),
}
const FALLBACK_COLOR: Color = Color(1.0, 0.80, 0.40)

var _views: Dictionary = {}   # projectile id -> MeshInstance3D
var _pool: Array[MeshInstance3D] = []
var _materials: Dictionary = {}   # damage_type -> StandardMaterial3D

## 每帧同步：新弹体取节点，消失的还回池子。
func sync(items: Array[Projectile]) -> void:
	var seen: Dictionary = {}
	for shot: Projectile in items:
		seen[shot.id] = true
		var node: MeshInstance3D = _views.get(shot.id, null)
		if node == null:
			node = _acquire()
			_views[shot.id] = node
		node.position = PlaneMath.to_world(shot.plane_pos, shot.height)
		node.scale = Vector3.ONE * maxf(shot.radius * SIZE_SCALE, MIN_SIZE)
		node.material_override = _material_for(shot.damage_type)
	for key: Variant in _views.keys():
		if seen.has(key):
			continue
		_release(key)

func active_views() -> int:
	return _views.size()

func _acquire() -> MeshInstance3D:
	var node: MeshInstance3D = null
	if not _pool.is_empty():
		node = _pool.pop_back()
		node.visible = true
	else:
		node = MeshInstance3D.new()
		node.name = "Projectile"
		node.mesh = _make_mesh()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	return node

func _release(key: Variant) -> void:
	var node: MeshInstance3D = _views.get(key, null)
	_views.erase(key)
	if node == null:
		return
	node.visible = false
	_pool.append(node)

func _make_mesh() -> QuadMesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	return mesh

func _material_for(damage_type: StringName) -> StandardMaterial3D:
	if _materials.has(damage_type):
		return _materials[damage_type]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 2.5D 侧视：四边形永远面向相机，转向时不会变成一条线。
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var color: Color = TYPE_COLORS.get(damage_type, FALLBACK_COLOR)
	color.a = 0.95
	material.albedo_color = color
	_materials[damage_type] = material
	return material
