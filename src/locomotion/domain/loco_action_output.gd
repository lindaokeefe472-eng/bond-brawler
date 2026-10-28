## 一帧动作结果：表现层只读它来驱动 transform / 动画 / 特效。
## 刻意不包含「下一步该做什么」的信息，决策全部留在 LocoActionMachine，
## 这样同一份输出可以被本地玩家、AI、回放三种来源复用。
class_name LocoActionOutput
extends RefCounted

var plane_pos: Vector2 = Vector2.ZERO
var velocity: Vector2 = Vector2.ZERO
var height: float = 0.0
var vertical_velocity: float = 0.0
var facing: int = 1
var state: int = LocoActionState.IDLE
var super_armor: bool = false
var invulnerable: bool = false
var can_be_interrupted: bool = true

func _to_string() -> String:
    return "LocoActionOutput(state=%s, pos=%s, h=%.3f, v=%s)" % [
        LocoActionState.name_of(state), plane_pos, height, velocity
    ]
