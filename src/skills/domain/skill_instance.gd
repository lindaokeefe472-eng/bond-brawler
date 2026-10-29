## 技能运行时实例：只负责冷却与充能这类「状态」，不关心相位与施法者。
##
## 冷却按「每格充能」计时：消耗一格后开始转冷却，转满回一格。
## 这样多充能技能（如 2 次冲刺）与单充能技能共用一套逻辑。
class_name SkillInstance
extends RefCounted

## 至少一格充能，避免数据把 charges 写成 0 导致技能永远不可用。
const MIN_CHARGES: int = 1

var def: SkillDef = null
var cooldown_left: float = 0.0
var charges: int = 1
var max_charges: int = 1

## 最近一次 refund 折算出的能量返还量，由持有者（SkillCaster）加回能量池。
var refunded_energy: float = 0.0

func _init(p_def: SkillDef) -> void:
	def = p_def
	var raw_charges: float = 1.0
	if def != null:
		raw_charges = float(def.extra.get("charges", 1.0))
	max_charges = maxi(MIN_CHARGES, int(round(raw_charges)))
	charges = max_charges

func is_ready() -> bool:
	return def != null and charges > 0

## 推进冷却；返回本帧是否刚好回了一格充能（用于发 cooldown_ready 事件）。
func tick(dt: float) -> bool:
	if def == null or dt <= 0.0:
		return false
	if charges >= max_charges:
		cooldown_left = 0.0
		return false
	cooldown_left -= dt
	if cooldown_left > 0.0:
		return false
	charges += 1
	# 还有空格要充时继续计时，否则停下，避免多余倒计时。
	cooldown_left = def.cooldown if charges < max_charges else 0.0
	return true

## 消耗一格充能并开始冷却。没有充能时什么也不做（调用方应先 is_ready）。
func consume() -> void:
	if def == null or charges <= 0:
		return
	charges -= 1
	if cooldown_left <= 0.0:
		cooldown_left = def.cooldown

## 按比例返还冷却与能量：取消前摇时只赔一半，既惩罚误操作又不至于锁死技能。
func refund(fraction: float) -> void:
	if def == null or fraction <= 0.0:
		return
	var f: float = clampf(fraction, 0.0, 1.0)
	refunded_energy = def.cost * f
	cooldown_left = maxf(0.0, cooldown_left - def.cooldown * f)
	# 冷却被一次性赔到 0 时立刻补回一格，保持「可用」与「冷却」自洽。
	if cooldown_left <= 0.0 and charges < max_charges:
		charges += 1
