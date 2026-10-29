## 动作输入缓冲：把「按早了」变成「按对了」。
## 只记录时间戳、不消费游戏状态，因此可以脱离状态机独立单测。
class_name InputBuffer
extends RefCounted

## 动作名用 StringName：与事件总线一致，字典查找不产生字符串分配。
const ACTION_ATTACK: StringName = &"attack"
const ACTION_JUMP: StringName = &"jump"
const ACTION_DASH: StringName = &"dash"

## 时间戳比较的容差：dt 累加会带来 1e-7 量级的漂移。
const TIME_EPSILON: float = 0.000001

var _now: float = 0.0
var _press_times: Dictionary = {}   # StringName -> float
var last_action: StringName = &""
var last_time: float = -INF

## 由拥有者在每个逻辑步开始时推进。缓冲不依赖引擎时钟，保证可重放。
func advance(dt: float) -> void:
	_now += maxf(dt, 0.0)

func now() -> float:
	return _now

## 同一动作重复按下时以最后一次为准：玩家更希望执行刚按下的那一下。
func press(action: StringName) -> void:
	_press_times[action] = _now
	last_action = action
	last_time = _now

func is_buffered(action: StringName, window: float) -> bool:
	if not _press_times.has(action):
		return false
	var age: float = _now - float(_press_times[action])
	return age >= 0.0 and age <= window + TIME_EPSILON

## 窗口内命中则返回 true 并清空该动作；窗口外只返回 false 且保留记录，
## 让调用方自己决定何时丢弃（例如空中的跳跃预输入要留到落地再吃）。
func consume(action: StringName, window: float) -> bool:
	if not is_buffered(action, window):
		return false
	_press_times.erase(action)
	return true

func clear_action(action: StringName) -> void:
	_press_times.erase(action)

func clear() -> void:
	_press_times.clear()
	last_action = &""
	last_time = -INF
