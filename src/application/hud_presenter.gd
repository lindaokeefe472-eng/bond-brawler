## HUD 编排：从会话读快照喂给视图模型，并订阅领域事件补充瞬时反馈。
##
## 这一层是唯一「既认识领域对象、又认识视图模型」的地方：
## 视图只认 HudModel，领域只管自己的状态，两边都不需要知道对方。
class_name HudPresenter
extends RefCounted

var model: HudModel = HudModel.new()

var _bus: DomainEventBus = null
var _player_id: int = 0
var _subs: Array[int] = []

func _init(bus: DomainEventBus = null, p_player_id: int = 0) -> void:
	_bus = bus
	_player_id = p_player_id
	if _bus != null:
		_subs.append(_bus.subscribe(GameConstants.EVT_DAMAGE_APPLIED, _on_damage))

func set_player_id(id: int) -> void:
	_player_id = id

func player_id() -> int:
	return _player_id

## 退订。总线持有 Callable，不退就会和本对象互相引用（CONVENTIONS 规则 9）。
func unbind() -> void:
	if _bus != null:
		for handle: int in _subs:
			_bus.unsubscribe(handle)
	_subs.clear()
	_bus = null

## 每帧调用：先按会话重建快照，再推进瞬时状态。
func sync(session: BattleSession, dt: float) -> void:
	if session == null:
		return
	model.apply_snapshot(_snapshot(session))
	model.tick(dt)

func _snapshot(session: BattleSession) -> Array:
	var out: Array = []
	for id: int in session.actor_ids():
		var actor: ActorRuntime = session.get_actor(id)
		if actor == null:
			continue
		out.append(HudModel.make_entry(
				actor.id,
				str(actor.species_id()),
				actor.stats.current_hp,
				actor.stats.max_hp(),
				actor.energy,
				actor.energy_max(),
				actor.skill_cooldown_ratios(),
				actor.is_alive()))
	return out

func _on_damage(event: DomainEvent) -> void:
	if event == null:
		return
	var payload: Dictionary = event.payload
	model.note_damage(int(payload.get("target_id", 0)))
	# 只有玩家打出去的才算连击，敌人挨打不算。
	if _player_id > 0 and int(payload.get("attacker_id", 0)) == _player_id:
		model.note_player_hit()
