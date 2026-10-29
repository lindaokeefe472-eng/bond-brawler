## AI 的一次决策结果：只描述「想做什么」，执行由 application 层负责。
##
## kind 用 StringName 而不是枚举，是为了让敌人配置（JSON）可以直接写意图名，
## 同时避免领域层与具体行为实现产生编译期耦合。
class_name AiIntent
extends RefCounted

const IDLE: StringName = &"idle"
const APPROACH: StringName = &"approach"
const RETREAT: StringName = &"retreat"
const ATTACK: StringName = &"attack"
const SKILL: StringName = &"skill"
const REPOSITION: StringName = &"reposition"
const GUARD: StringName = &"guard"

## 固定顺序用于打分平局时的确定性裁决：声明靠前者优先。
## 没有这个顺序，Dictionary 的遍历顺序会让同一输入的决策不可复现。
const KINDS: Array[StringName] = [IDLE, APPROACH, RETREAT, ATTACK, SKILL, REPOSITION, GUARD]

var kind: StringName = IDLE
var target_id: int = -1
var skill_slot: int = -1
var desired_pos: Vector2 = Vector2.ZERO

static func make(intent_kind: StringName, intent_target_id: int = -1,
		intent_skill_slot: int = -1, intent_desired_pos: Vector2 = Vector2.ZERO) -> AiIntent:
	var intent := AiIntent.new()
	intent.kind = intent_kind
	intent.target_id = intent_target_id
	intent.skill_slot = intent_skill_slot
	intent.desired_pos = intent_desired_pos
	return intent
