## 打开碰撞形状调试渲染并截图，用来核对判定盒的实际位置。
##
## 判定盒位置对不对没法靠读代码确认 —— 一定要看渲染结果。
## 同时把盒子的世界尺寸和屏幕投影打印出来，避免只靠肉眼比划。
extends SceneTree

const OUT: String = "res://docs/shapes.png"

var _f: int = 0
var _scene: Node = null
var _session: Variant = null
var _pid: int = 0

func _initialize() -> void:
	_scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	debug_collisions_hint = true

func _process(_delta: float) -> bool:
	_f += 1
	if _session == null:
		_session = _scene.get("_session")
		_pid = int(_scene.get("_player_id"))
		return false
	if _f < 150:
		return false
	var p: Variant = _session.get_actor(_pid)
	if p == null:
		return false
	if _f % 15 == 0:
		var fr: LocoInputFrame = LocoInputFrame.empty()
		fr.attack = true
		var inputs: Dictionary = {}
		inputs[_pid] = fr
		_session.tick(GameConstants.TICK_DELTA, inputs)
	if _f > 200 and p.action.current_state() == 6 and p.action.attack_phase() == 1:
		var cam: Camera3D = null
		for n: Node in _scene.find_children("*", "Camera3D", true, false):
			cam = n as Camera3D
			break
		var v: Node = _scene.get("_views").get(_pid, null)
		var hb: Area3D = v.get_node_or_null("Hitbox") as Area3D
		var sh: CollisionShape3D = hb.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var b: BoxShape3D = sh.shape as BoxShape3D
		var scl: Vector3 = sh.global_transform.basis.get_scale()
		print("box.size=%s  形状节点全局缩放=%s  ActorView缩放=%s" % [str(b.size), str(scl), str(v.scale)])
		var c: Vector3 = hb.global_position
		var hx: float = b.size.x * 0.5 * scl.x
		var hy: float = b.size.y * 0.5 * scl.y
		var l: Vector2 = cam.unproject_position(Vector3(c.x - hx, c.y + hy, c.z))
		var r: Vector2 = cam.unproject_position(Vector3(c.x + hx, c.y - hy, c.z))
		print("投影: 宽=%.0fpx 高=%.0fpx" % [absf(r.x - l.x), absf(r.y - l.y)])
		var img: Image = root.get_texture().get_image()
		img.save_png(OUT)
		quit(0)
		return true
	if _f > 900:
		quit(1)
		return true
	return false
