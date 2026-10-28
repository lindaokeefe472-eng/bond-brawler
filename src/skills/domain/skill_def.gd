## 技能静态定义：从外部 JSON 解析出来的不可变数据。
##
## 为什么需要 from_dict：技能数据由数据策划维护，字段会增删；
## 领域层必须对缺字段/多字段都保持健壮，缺字段走默认值，多字段收进 extra
## 交给模板注册表使用，这样加新参数不需要改这个类。
class_name SkillDef
extends RefCounted

## 已经被 from_dict 消费的字段名（统一用 String，因为 JSON 的键是 String）。
const KNOWN_KEYS: Array[String] = [
	"id", "name", "type", "types", "kind", "template",
	"power", "cost", "cooldown", "cd", "range", "knockback",
	"windup", "wind", "commit", "recovery", "duration",
	"clash_class", "clash_power", "status", "dodgeable",
]

var id: StringName = &""
var name: String = ""
var type: StringName = &"neutral"
var kind: StringName = &"melee"
var template: StringName = &"melee"
var power: float = 0.0
var cost: float = 0.0
var cooldown: float = 0.0
@warning_ignore("shadowed_global_identifier")
var range: float = 0.0
var knockback: float = 0.0
var windup: float = 0.0
var commit: float = 0.0
var recovery: float = 0.0
var duration: float = 0.0
var clash_class: StringName = &""
var clash_power: float = 0.0
var status: StringName = &""
var dodgeable: bool = true
## 模板专用参数（volley_count / cone / heal_ratio / speed ...），原样保留。
var extra: Dictionary = {}

## 容错解析：任何字段缺失都回退到默认值，绝不因为数据缺项崩掉整局。
static func from_dict(d: Dictionary) -> SkillDef:
	var def := SkillDef.new()
	def.id = StringName(str(d.get("id", "")))
	def.name = str(d.get("name", str(def.id)))
	def.kind = StringName(str(d.get("kind", "melee")))
	def.template = StringName(str(d.get("template", "melee")))
	if def.template == &"":
		def.template = &"melee"
	def.power = float(d.get("power", 0.0))
	def.cost = float(d.get("cost", 0.0))
	# 数据里用 cd / wind 缩写，契约字段是 cooldown / windup，两者都接受。
	def.cooldown = float(d.get("cooldown", d.get("cd", 0.0)))
	def.range = float(d.get("range", 0.0))
	def.knockback = float(d.get("knockback", 0.0))
	def.windup = float(d.get("windup", d.get("wind", 0.0)))
	def.commit = float(d.get("commit", 0.0))
	def.recovery = float(d.get("recovery", 0.0))
	def.duration = float(d.get("duration", 0.0))
	def.clash_class = StringName(str(d.get("clash_class", "")))
	def.clash_power = float(d.get("clash_power", 0.0))
	def.status = StringName(str(d.get("status", "")))
	def.dodgeable = bool(d.get("dodgeable", true))

	def.extra = _collect_extra(d)
	_apply_types(def, d)
	return def

## 未识别字段全部收进 extra，并做深拷贝，避免调用方事后改动影响已解析的技能。
static func _collect_extra(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for raw_key: Variant in d.keys():
		var key_name: String = str(raw_key)
		if KNOWN_KEYS.has(key_name):
			continue
		var value: Variant = d[raw_key]
		if value is Array or value is Dictionary:
			value = value.duplicate(true)
		out[key_name] = value
	return out

## 双属性技能：主属性取 type，完整属性表放进 extra["types"]，
## 让效果器/伤害计算能拿到全部属性而不污染 SkillDef 的契约字段。
static func _apply_types(def: SkillDef, d: Dictionary) -> void:
	var raw_type: Variant = d.get("type", null)
	var types: Array = []
	if raw_type is Array:
		types = (raw_type as Array).duplicate()
	if types.is_empty():
		var raw_types: Variant = d.get("types", null)
		if raw_types is Array:
			types = (raw_types as Array).duplicate()

	var primary: StringName = &"neutral"
	if (raw_type is String or raw_type is StringName) and str(raw_type) != "":
		primary = StringName(str(raw_type))
	elif not types.is_empty():
		primary = StringName(str(types[0]))
	def.type = primary

	if types.size() > 1:
		var typed_types: Array[StringName] = []
		for entry: Variant in types:
			typed_types.append(StringName(str(entry)))
		def.extra["types"] = typed_types
