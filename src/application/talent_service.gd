## 天赋应用层：把 TalentTree 的加成真正落到角色属性上。
##
## 纯逻辑都在 TalentTree 里（加点、前置校验、快照），这里只做两件树不该管的事：
##   1. 把效果折成 CombatModifier 应用到某个 ActorRuntime；
##   2. 把树的状态接进存档。
class_name TalentService
extends RefCounted

var tree: TalentTree = null

func _init(bus: DomainEventBus = null) -> void:
	tree = TalentTree.new(bus)

func available_points() -> int:
	return tree.available_points()

func grant_points(points: int) -> void:
	tree.grant_points(points)

func unlock(id: StringName) -> bool:
	return tree.unlock(id)

func respec() -> int:
	return tree.respec()

## 把当前天赋加成应用到角色身上。角色生成后、以及加点/重置之后都要调。
## 先清掉旧的天赋修改器再加，避免重复叠加。
func apply_to(actor: ActorRuntime) -> void:
	if actor == null or actor.stats == null:
		return
	for modifier: CombatModifier in tree.modifiers_for(actor.id):
		actor.stats.add_modifier(modifier)

## 角色死亡或离场时摘掉，免得修改器 id 越积越多。
func clear_from(actor: ActorRuntime) -> void:
	if actor == null or actor.stats == null:
		return
	for modifier: CombatModifier in tree.modifiers_for(actor.id):
		actor.stats.remove_modifier(modifier.id)
