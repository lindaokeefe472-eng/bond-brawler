## 一次伤害结算的输入。纯数据，由普攻 / 技能 / 环境伤害构造。
## 全部字段带默认值，调用方只覆盖自己关心的部分，避免到处写一大串参数。
class_name CombatDamageRequest
extends RefCounted

var attacker_id: int = 0
var target_id: int = 0
## 最终威力。上游（技能效果器）已把攻击力折算进来，管线内不再乘 attack，
## 否则天赋加攻击会在每段伤害里被重复计入。
var power: float = 0.0
## 18 属性之一，或 &"neutral"（不吃克制表）。
var damage_type: StringName = &"neutral"
var hit_kind: StringName = &"light"
var knockback: float = 0.0
var is_aerial: bool = false
var can_crit: bool = true
var tags: Array[StringName] = []
## 击退方向（攻击者指向目标）。结算器拿不到坐标，只能由上游给方向；
## 为零向量时结果的 knockback_vector 也为零，由调用方自行兜底。
var knockback_direction: Vector2 = Vector2.ZERO
