## 组合根：全项目唯一允许 new 具体实现的地方。
##
## 为什么单独成类而不是塞进场景脚本：
##   1. 「具体实现只在一处被创建」这条规则可以用 grep 验证，评审有据可依。
##   2. 服务装配不依赖场景树，可以在 headless 测试里直接构造一整局。
##   3. 换实现（比如把 JSON 换成 .tres、把确定性 RNG 换成网络同步 RNG）只改这里。
class_name CompositionRoot
extends RefCounted

const DATA_ROOT_DEFAULT: String = "res://data"
const SEED_DEFAULT: int = 20261028
const ACTIONS_FILE: String = "actions.json"

var bus: DomainEventBus = null
var rng: DeterministicRng = null
var data: JsonDataSource = null
var species: SpeciesRepository = null
var skills: SkillRepository = null
var combat_data: CombatDataRepository = null
var calculator: CombatDamageCalculator = null
var session: BattleSession = null
## 普攻帧数据：来自 data/actions.json 的 basic_attack，缺字段时用 ActorRuntime 的默认值。
var melee_config: Dictionary = {}

## 装配一整局需要的全部服务。数据缺失只会降级，不会抛异常。
static func create(data_root: String = DATA_ROOT_DEFAULT, seed_value: int = SEED_DEFAULT) -> CompositionRoot:
	var root := CompositionRoot.new()
	root._assemble(data_root, seed_value)
	return root

func _assemble(data_root: String, seed_value: int) -> void:
	bus = DomainEventBus.new()
	rng = DeterministicRng.new(seed_value)
	data = JsonDataSource.new(data_root)
	species = SpeciesRepository.new(data)
	skills = SkillRepository.new(data)
	combat_data = CombatDataRepository.new(data)
	calculator = CombatDamageCalculator.new(combat_data.type_chart(), rng)
	melee_config = _read_melee_config()

	var species_table: Dictionary = {}
	for entry: Dictionary in species.all():
		var species_id: String = str(entry.get("id", ""))
		if not species_id.is_empty():
			species_table[StringName(species_id)] = entry

	session = BattleSession.new({
		BattleSession.SERVICE_BUS: bus,
		BattleSession.SERVICE_RNG: rng,
		BattleSession.SERVICE_DAMAGE_CALCULATOR: calculator,
		BattleSession.SERVICE_TYPE_CHART: combat_data.type_chart(),
		BattleSession.SERVICE_SPECIES: species_table,
	})

## 普攻的射程/威力/击退来自数据表，取不到就退回 ActorRuntime 的常量。
func _read_melee_config() -> Dictionary:
	var basic: Dictionary = {}
	var raw_actions: Variant = data.read_json(ACTIONS_FILE)
	if raw_actions is Dictionary:
		var actions: Dictionary = raw_actions
		var raw_basic: Variant = actions.get("basic_attack", {})
		if raw_basic is Dictionary:
			basic = raw_basic

	var knockback: float = ActorRuntime.MELEE_KNOCKBACK_DEFAULT
	var raw_knockback: Variant = basic.get("knockback", knockback)
	if raw_knockback is Array:
		var stages: Array = raw_knockback
		if not stages.is_empty():
			knockback = float(stages[0])
	elif raw_knockback is float or raw_knockback is int:
		knockback = float(raw_knockback)

	# 原游戏的 range 是按它自己的角色体型定的，本项目角色统一 1.8 m，
	# 直接照搬会出现「隔空打人」（实测命中距离到过 2.67 m）。
	var raw_range: float = float(basic.get("range", GameConstants.MELEE_RANGE_REFERENCE))
	return {
		"range": clampf(raw_range * GameConstants.MELEE_RANGE_SCALE, 0.8, 2.2),
		"power_ratio": ActorRuntime.MELEE_POWER_RATIO_DEFAULT,
		"knockback": maxf(knockback, 0.0),
	}
