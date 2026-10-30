## 输入契约：每个动作状态对离散输入的处置。
##
## 这张表是「状态机接受什么输入」的唯一来源（R4）。改手感先改这里，
## 不要在状态机里散落 if。
##
## 处置语义：
##   ACCEPT  立即进入待仲裁集合，由 IntentArbiter 按优先级选一个执行
##   LINK    攻击连段：置连段标志（只在判定段之后有效）
##   BUFFER  存入单槽预输入，等「可执行时刻」兑现（窗口见 LocoActionMachine.BUFFER_TICKS）
##   DISCARD 直接丢弃
class_name InputContract
extends RefCounted

enum Disposition {
	ACCEPT,
	LINK,
	BUFFER,
	DISCARD,
}

## 不含技能：技能在 ActorRuntime 里先于动作机执行，优先级天然最高。
static func disposition(state: int, action: StringName) -> int:
	match state:
		LocoActionState.IDLE, LocoActionState.RUN, LocoActionState.LAND:
			return Disposition.ACCEPT
		LocoActionState.JUMP:
			# 空中只能接空中攻击；二段跳、空中冲刺、空中技能 v1 不开放。
			return Disposition.ACCEPT if action == &"attack" else Disposition.DISCARD
		LocoActionState.FALL:
			# 土狼时间内的跳跃由 _can_jump() 再判一次。
			return Disposition.ACCEPT if action == &"attack" or action == &"jump" \
					else Disposition.DISCARD
		LocoActionState.ATTACK:
			return Disposition.LINK if action == &"attack" else Disposition.BUFFER
		LocoActionState.DASH:
			return Disposition.BUFFER if action == &"attack" or action == &"jump" \
					else Disposition.DISCARD
		_:
			return Disposition.DISCARD
