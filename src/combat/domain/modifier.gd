## 战斗属性修饰器：天赋、增益、装备等一切「临时改数值」的唯一载体。
## 为什么用 id 而不是对象身份：同一来源重复施加（叠层 buff）必须合并成一条，
## 否则每帧 tick 都会线性增加数组长度，清除时也无法精确撤销。
class_name CombatModifier
extends RefCounted

var id: StringName
var stat: StringName
var flat: float = 0.0
var percent: float = 0.0
## 负数表示永久（天赋、装备），不参与 tick 递减。
var duration: float = -1.0
var stacks: int = 1
var max_stacks: int = 1
var source: StringName = &""

func _init(p_stat: StringName = &"", p_flat: float = 0.0, p_percent: float = 0.0, p_duration: float = -1.0) -> void:
	stat = p_stat
	flat = p_flat
	percent = p_percent
	duration = p_duration
	# 契约里的 make() 不接收 id，默认用 stat 当身份：同属性自然合并叠层；
	# 需要各自独立的同属性 buff（如两个不同天赋）请自行赋唯一 id。
	id = p_stat

## 契约入口。
static func make(stat_id: StringName, flat_bonus: float = 0.0, percent_bonus: float = 0.0,
		duration_seconds: float = -1.0) -> CombatModifier:
	return CombatModifier.new(stat_id, flat_bonus, percent_bonus, duration_seconds)

## 推进时长，返回「本帧是否过期」。永久修饰器永远返回 false。
func tick(dt: float) -> bool:
	if is_permanent():
		return false
	# 夹到 0 而不是继续减成负数：负数在契约里代表永久，
	# 一旦越界，过期判断会永远失效。
	duration = maxf(0.0, duration - dt)
	return is_expired()

func is_expired() -> bool:
	return not is_permanent() and duration <= 0.0

func is_permanent() -> bool:
	return duration < 0.0

## 叠层后的实际贡献：stacks 是乘数，不是重复条目。
func effective_flat() -> float:
	return flat * float(stacks)

func effective_percent() -> float:
	return percent * float(stacks)
