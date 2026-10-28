## 角色身上的状态集合（湿/灼烧/麻痹/定身/睡眠/减速/中毒/削弱）。
## 只回答「能不能动、速度多少、这一帧谁过期了」，具体效果由调用方按 id 查表。
class_name CombatStatusSet
extends RefCounted

## 默认时长抄自 data/actions.json 的 status_duration。
## 放常量而不是运行时读 JSON：领域层不依赖 IDataSource，且这些值本就是世界常量。
const DEFAULT_DURATIONS: Dictionary = {
	&"wet": 7.0,
	&"burn": 5.0,
	&"paralyze": 2.4,
	&"root": 1.2,
	&"sleep": 3.5,
	&"slow": 2.5,
	&"poison": 5.0,
	&"weaken": 4.0,
}

const STUN_STATUSES: Array[StringName] = [&"paralyze", &"sleep"]
const SLOW_SPEED_MULTIPLIER: float = 0.6
const ROOT_SPEED_MULTIPLIER: float = 0.0
## 同一状态反复命中时的层数上限：不封顶会让 DoT/减速无限叠，
## 三个敌人围殴几秒就能把玩家压死，且状态栏永远清不掉。
const MAX_STACKS: int = 5

## id -> {remaining: float, stacks: int}
var _states: Dictionary = {}
var _durations: Dictionary = {}

## overrides 可覆盖默认时长（例如难度/模式调整），键与 DEFAULT_DURATIONS 一致。
func _init(overrides: Dictionary = {}) -> void:
	_durations = DEFAULT_DURATIONS.duplicate()
	for raw_key: Variant in overrides.keys():
		_durations[StringName(str(raw_key))] = float(overrides[raw_key])

## duration <= 0 表示「用默认表里的时长」，方便技能只写状态名。
func apply(id: StringName, duration: float, stack_count: int = 1) -> void:
	if id == &"":
		return
	var seconds: float = duration
	if seconds <= 0.0:
		seconds = float(_durations.get(id, 0.0))
	var add_stacks: int = maxi(1, stack_count)
	if _states.has(id):
		var state: Dictionary = _states[id]
		# 取较长剩余时间而不是覆盖：短时刷新不该缩短已经存在的长状态。
		state["remaining"] = maxf(float(state["remaining"]), seconds)
		state["stacks"] = mini(int(state["stacks"]) + add_stacks, MAX_STACKS)
	else:
		_states[id] = {"remaining": seconds, "stacks": add_stacks}

func remove(id: StringName) -> void:
	_states.erase(id)

func has(id: StringName) -> bool:
	return _states.has(id)

func stacks(id: StringName) -> int:
	if not _states.has(id):
		return 0
	return int(_states[id]["stacks"])

## 推进所有状态，返回本帧过期的 id 列表（供上层发 EVT_STATUS_EXPIRED）。
func tick(dt: float) -> Array[StringName]:
	var expired: Array[StringName] = []
	if dt <= 0.0:
		return expired
	for id: Variant in _states.keys():
		var state: Dictionary = _states[id]
		state["remaining"] = float(state["remaining"]) - dt
		if float(state["remaining"]) <= 0.0:
			expired.append(id)
	for id: StringName in expired:
		_states.erase(id)
	return expired

func is_stunned() -> bool:
	for id: StringName in STUN_STATUSES:
		if _states.has(id):
			return true
	return false

func speed_multiplier() -> float:
	# 定身优先于减速：同时存在时速度必须是 0，不能被 slow 的 0.6 覆盖。
	if _states.has(&"root"):
		return ROOT_SPEED_MULTIPLIER
	if _states.has(&"slow"):
		return SLOW_SPEED_MULTIPLIER
	return 1.0

## root 只锁移动（speed_multiplier 返回 0），不锁动作。
## 清版游戏里「被定住还能挥刀」比「既动不了又打不了」可玩性高得多；
## 真正让人无法行动的是 paralyze / sleep 这类硬控。
func can_act() -> bool:
	return not is_stunned()
