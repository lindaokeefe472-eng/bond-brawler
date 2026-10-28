## 出站端口：随机数。
## 战斗必须可复现 —— 所有随机（暴击、闪避、AI 抖动、掉落）都走这里。
class_name IRng
extends RefCounted

func next_float() -> float:
	push_error("IRng.next_float() 未实现")
	return 0.0

func next_int(max_exclusive: int) -> int:
	push_error("IRng.next_int() 未实现（max_exclusive=%d）" % max_exclusive)
	return 0

func chance(probability: float) -> bool:
	return next_float() < probability

func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[next_int(items.size())]

func get_seed() -> int:
	return 0

## 派生子流：同一随机源可以给不同系统开独立子流，互不干扰，便于单测。
func fork(_label: StringName) -> IRng:
	push_error("IRng.fork() 未实现")
	return self
