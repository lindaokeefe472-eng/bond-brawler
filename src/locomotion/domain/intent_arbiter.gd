## 意图仲裁：同一 tick 最多选出一个离散动作。
##
## 优先级固定为「逃生类优先」：冲刺 > 跳跃 > 攻击。技能在 ActorRuntime 里
## 先于动作机执行，所以实际顺序是 技能 > 冲刺 > 跳跃 > 攻击。
##
## 为什么输的键直接丢弃：同帧多键绝大多数是误触。保留下来只会制造
## 「按了一下，过一会儿角色自己动」的幽灵输入。
class_name IntentArbiter
extends RefCounted

const PRIORITY: Array[StringName] = [&"dash", &"jump", &"attack"]

## 返回优先级最高的一个意图；没有则空串。
static func pick(pressed: Dictionary) -> StringName:
	for action: StringName in PRIORITY:
		if bool(pressed.get(action, false)):
			return action
	return &""
