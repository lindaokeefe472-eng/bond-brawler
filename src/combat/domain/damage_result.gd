## 一次伤害结算的输出。只读语义：由 CombatDamageCalculator 填好，调用方消费。
class_name CombatDamageResult
extends RefCounted

## 结算出的伤害值（不是实际扣血量）：显示跳字用这个，溢出击杀也照常显示。
var amount: float = 0.0
var is_crit: bool = false
var is_dodged: bool = false
var is_guarded: bool = false
var is_lethal: bool = false
var knockback_vector: Vector2 = Vector2.ZERO
var applied_status: StringName = &""
