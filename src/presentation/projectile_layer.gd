## 弹体表现层：把领域层的弹体列表同步成场上的精灵。
##
## 只读 BattleSession.projectiles()，不改任何战斗状态 —— 和 ActorView 同一个原则：
## 表现层永远是领域状态的投影，不产生第二份真相。
##
## 贴图来自素材包的 Arrow(Projectile) / Magic(Projectile)，由
## tools/build_asset_manifest.py 抽到 assets/sprites/projectiles/，
## 缩放和帧表由 normalize_sprites.py 算好写进 manifest 的 projectiles 段。
## 弹体没配 sprite（或素材缺失）时退回一个按属性上色的方块，保证永远看得见。
class_name ProjectileLayer
extends Node3D

const MANIFEST_KEY: String = "projectiles"
const PROJECTILE_DIR: String = "res://assets/sprites/projectiles"
const FPS: float = 12.0

## 占位方块的边长 = 命中半径 * 这个系数，看起来比判定略大一点点，视觉上更实。
const SIZE_SCALE: float = 2.0
const MIN_SIZE: float = 0.12

## 按属性上色，只在没有贴图时用。
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

## slug -> {texture, frames, pixel_size}
var _sprites: Dictionary = {}
## projectile id -> {node, elapsed}
var _views: Dictionary = {}
var _pool: Array[Sprite3D] = []
var _placeholder: Texture2D = null

## 读 manifest 的 projectiles 段。素材缺失时静默降级成占位方块。
func configure(manifest: Dictionary) -> void:
	_sprites.clear()
	var raw: Variant = manifest.get(MANIFEST_KEY, {})
	if not (raw is Dictionary):
		return
	for key: Variant in (raw as Dictionary).keys():
		var data: Variant = (raw as Dictionary)[key]
		if not (data is Dictionary):
			continue
		var file_name: String = str((data as Dictionary).get("file", ""))
		if file_name.is_empty():
			continue
		var path: String = PROJECTILE_DIR.path_join(file_name)
		if not ResourceLoader.exists(path):
			continue
		_sprites[str(key)] = {
			"texture": load(path) as Texture2D,
			"frames": maxi(int((data as Dictionary).get("frames", 1)), 1),
			"pixel_size": float((data as Dictionary).get("pixel_size", 0.05)),
		}

## 每帧同步：新弹体取节点，消失的还回池子。
func sync(items: Array[Projectile]) -> void:
	var seen: Dictionary = {}
	for shot: Projectile in items:
		seen[shot.id] = true
		var view: Dictionary = _views.get(shot.id, {})
		if view.is_empty():
			view = _acquire(shot)
			_views[shot.id] = view
		var node: Sprite3D = view["node"]
		node.position = PlaneMath.to_world(shot.plane_pos, shot.height)
		node.flip_h = shot.velocity.x < 0.0
	for key: Variant in _views.keys():
		if seen.has(key):
			continue
		_release(key)

func active_views() -> int:
	return _views.size()

func known_sprites() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in _sprites.keys():
		out.append(str(key))
	out.sort()
	return out

## 多帧特效（施法/爆炸）按固定帧率循环；单帧的箭不动。
func _process(delta: float) -> void:
	if _views.is_empty():
		return
	var step: float = maxf(delta, 0.0)
	for key: Variant in _views.keys():
		var view: Dictionary = _views[key]
		var node: Sprite3D = view["node"]
		if node.hframes <= 1:
			continue
		view["elapsed"] = float(view["elapsed"]) + step
		var steps: int = int(float(view["elapsed"]) * FPS)
		if steps <= 0:
			continue
		view["elapsed"] = float(view["elapsed"]) - float(steps) / FPS
		node.frame = (node.frame + steps) % node.hframes

func _acquire(shot: Projectile) -> Dictionary:
	var node: Sprite3D = null
	if not _pool.is_empty():
		node = _pool.pop_back()
	else:
		node = _make_node()
	node.visible = true
	var entry: Dictionary = _sprites.get(String(shot.sprite), {})
	if entry.is_empty():
		# 占位：1x1 白图，pixel_size 直接就是方块边长，modulate 上属性色。
		node.texture = _placeholder_texture()
		node.pixel_size = maxf(shot.radius * SIZE_SCALE, MIN_SIZE)
		node.hframes = 1
		node.frame = 0
		node.modulate = TYPE_COLORS.get(shot.damage_type, FALLBACK_COLOR)
	else:
		node.texture = entry["texture"] as Texture2D
		node.pixel_size = float(entry["pixel_size"])
		node.hframes = int(entry["frames"])
		node.frame = 0
		node.modulate = Color.WHITE
	return {"node": node, "elapsed": 0.0}

func _release(key: Variant) -> void:
	var view: Dictionary = _views.get(key, {})
	_views.erase(key)
	var node: Sprite3D = view.get("node", null)
	if node == null:
		return
	node.visible = false
	_pool.append(node)

func _make_node() -> Sprite3D:
	var node := Sprite3D.new()
	node.name = "Projectile"
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	node.shaded = false
	node.double_sided = true
	node.centered = true
	node.vframes = 1
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func _placeholder_texture() -> Texture2D:
	if _placeholder == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_placeholder = ImageTexture.create_from_image(image)
	return _placeholder
