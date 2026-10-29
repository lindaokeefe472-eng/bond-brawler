## 无界面跑一段真实对局，确认 AI、命中、伤害、死亡在场景层面也串得起来。
extends SceneTree

const FRAMES: int = 600
var _frames: int = 0
var _scene: Node = null

func _initialize() -> void:
	_scene = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_scene)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % 120 != 0 and _frames != FRAMES:
		return false
	var root_node: Node = _scene
	var session: Variant = root_node.get("_session")
	if session == null:
		return false
	var line: String = "frame %3d:" % _frames
	for id: int in session.actor_ids():
		var a: Variant = session.get_actor(id)
		line += "  [%s %d hp=%.0f pos=%.1f]" % [a.faction, id, a.stats.current_hp, a.plane_pos.x]
	print(line)
	if _frames >= FRAMES:
		quit(0)
		return true
	return false
