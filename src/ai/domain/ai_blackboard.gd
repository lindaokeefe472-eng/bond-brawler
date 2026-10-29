## 敌人 AI 的观测快照：纯数据容器，不含任何决策逻辑。
##
## 为什么单独成类：AI 的输入必须能在测试里手工拼出来，且不携带引擎对象，
## 这样「同一份快照 -> 同一决策」可以在无场景树的环境里被验证与回放。
class_name AiBlackboard
extends RefCounted

var self_id: int = -1
var self_pos: Vector2 = Vector2.ZERO
var self_hp_ratio: float = 1.0
var target_id: int = -1
var target_pos: Vector2 = Vector2.ZERO
var target_hp_ratio: float = 1.0
var target_guarding: bool = false
var skill_ready: Array[bool] = []
var distance: float = 0.0
var aligned: bool = false
var threat: float = 0.0
var time: float = 0.0

## 没有目标时只能待机。把这条判断收敛在这里，避免调用方各自重复写 target_id >= 0。
func has_target() -> bool:
	return target_id >= 0
