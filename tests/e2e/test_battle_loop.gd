## 端到端：不经过任何场景节点，直接用组合根装配一整局，跑真实的战斗闭环。
##
## 覆盖用户视角的完整链路：
##   生成角色 -> 输入攻击 -> 动作机前摇/判定帧 -> 窄相命中 -> 伤害扣血 -> 死亡事件
extends GdUnitTestSuite

## 仓库不包含 data/（版权原因，见 README「数据与素材」），缺数据时整组跳过。
func before(_do_skip := not FileAccess.file_exists("res://data/skills.json"),
        _skip_reason := "需要本地 data/，见 README「数据与素材」") -> void:
    pass

const STEP: float = GameConstants.TICK_DELTA
const PLAYER_SPAWN := Vector2(0.0, 0.0)
## 1.2 m：落在 GameConstants.MELEE_REACH（1.45）之内，普攻才打得到。
const ENEMY_SPAWN := Vector2(1.2, 0.0)

var _app: CompositionRoot = null
var _session: BattleSession = null
var _bus: DomainEventBus = null
var _player_id: int = 0
var _enemy_id: int = 0
var _died: Array = []

func before_test() -> void:
    _app = CompositionRoot.create()
    _session = _app.session
    _bus = _app.bus
    _died.clear()
    _bus.subscribe(GameConstants.EVT_ACTOR_DIED,
        func(e: DomainEvent) -> void: _died.append(int(e.payload.get("actor_id", 0))))
    _player_id = _session.spawn_actor(_spec(GameConstants.FACTION_PLAYER, PLAYER_SPAWN, 100.0))
    _enemy_id = _session.spawn_actor(_spec(GameConstants.FACTION_ENEMY, ENEMY_SPAWN, 100.0))

## 必须显式拆掉引用环：bus 的 handler 是一个捕获 self 的 lambda，
## 而 bus 又属于 self._app —— 不清理的话 TestSuite 永远不会被释放，
## 连带整局对象图（每个 CompositionRoot 约 120 个对象）一起泄漏。
func after_test() -> void:
    if _bus != null:
        _bus.clear()
    _app = null
    _session = null
    _bus = null

func _spec(faction: StringName, pos: Vector2, hp: float) -> Dictionary:
    return {
        "faction": faction,
        "plane_pos": pos,
        "stats": {"max_hp": hp, "battle_hp": hp, "attack": 10.0, "defense": 0.0, "types": []},
        "skills": [],
        "brain_profile": null,
        "melee": {"range": GameConstants.MELEE_REACH, "power_ratio": 1.0, "knockback": 0.0, "half_arc": 0.0},
    }

func _frame(attack: bool = false, move: Vector2 = Vector2.ZERO) -> LocoInputFrame:
    var f: LocoInputFrame = LocoInputFrame.empty()
    f.attack = attack
    f.move = move
    return f

## 推进 n 帧；只在第一帧按下攻击（模拟 just_pressed）。
func _run(ticks: int, first_frame: LocoInputFrame) -> void:
    for i: int in range(ticks):
        var inputs: Dictionary = {}
        inputs[_player_id] = first_frame if i == 0 else LocoInputFrame.empty()
        _session.tick(STEP, inputs)

func test_attack_in_lane_deals_damage() -> void:
    var before: float = _session.get_actor(_enemy_id).stats.current_hp
    _run(40, _frame(true))
    var after: float = _session.get_actor(_enemy_id).stats.current_hp
    assert_float(after).override_failure_message("同纵深的普攻必须造成伤害").is_less(before)

func test_attack_off_lane_misses() -> void:
    # 注意：不能事后改 plane_pos —— 动作机每帧都会用自身状态重写它。
    # 必须一开始就生成在纵深带外，这才是真实场景（敌人站在另一条 lane 上）。
    var far_id: int = _session.spawn_actor(
        _spec(GameConstants.FACTION_ENEMY, Vector2(1.2, 2.0), 100.0))
    var far: ActorRuntime = _session.get_actor(far_id)
    var before: float = far.stats.current_hp
    _run(40, _frame(true))
    assert_float(far.stats.current_hp).is_equal_approx(before, 0.001)
    # 同一招对同纵深的敌人必须命中，证明上面的 0 伤害不是"根本没打出去"
    assert_float(_session.get_actor(_enemy_id).stats.current_hp).is_less(100.0)

func test_lethal_damage_emits_death_once() -> void:
    var enemy: ActorRuntime = _session.get_actor(_enemy_id)
    enemy.stats.current_hp = 1.0
    _run(90, _frame(true))
    assert_int(_died.size()).is_equal(1)
    assert_int(_died[0]).is_equal(_enemy_id)
    assert_bool(enemy.stats.is_dead()).is_true()

func test_deterministic_replay_same_seed() -> void:
    _run(60, _frame(true))
    var hp_a: float = _session.get_actor(_enemy_id).stats.current_hp

    var app_b: CompositionRoot = CompositionRoot.create(CompositionRoot.DATA_ROOT_DEFAULT, 20261028)
    var session_b: BattleSession = app_b.session
    var p: int = session_b.spawn_actor(_spec(GameConstants.FACTION_PLAYER, PLAYER_SPAWN, 100.0))
    var e: int = session_b.spawn_actor(_spec(GameConstants.FACTION_ENEMY, ENEMY_SPAWN, 100.0))
    for i: int in range(60):
        var inputs: Dictionary = {}
        inputs[p] = _frame(true) if i == 0 else LocoInputFrame.empty()
        session_b.tick(STEP, inputs)
    assert_float(session_b.get_actor(e).stats.current_hp).override_failure_message(
        "同一随机种子下同一输入序列必须产生同一结果").is_equal_approx(hp_a, 0.001)
    app_b.bus.clear()
    app_b = null

func test_snapshot_restore_roundtrip() -> void:
    _run(30, _frame(true))
    var snap: Dictionary = _session.snapshot()
    var app_b: CompositionRoot = CompositionRoot.create()
    app_b.session.restore(snap)
    assert_int(app_b.session.actor_ids().size()).is_equal(_session.actor_ids().size())
    var restored: ActorRuntime = app_b.session.get_actor(_enemy_id)
    assert_object(restored).is_not_null()
    assert_float(restored.stats.current_hp).is_equal_approx(
        _session.get_actor(_enemy_id).stats.current_hp, 0.001)
    app_b.bus.clear()
    app_b = null

# ---------------------------------------------------------------- 控制与硬直（回归）
func test_rooted_player_can_still_attack() -> void:
    # 用户报的现象：被草系技能定身后「还没死就不能操作」。
    var player: ActorRuntime = _session.get_actor(_player_id)
    player.status.apply(&"root", 1.2)
    assert_bool(player.status.can_act()).is_true()
    _run(40, _frame(true))
    assert_float(_session.get_actor(_enemy_id).stats.current_hp).override_failure_message(
        "被定身时仍然应该能出手").is_less(100.0)

func test_player_recovers_control_after_hitstun() -> void:
    var player: ActorRuntime = _session.get_actor(_player_id)
    player.action.apply_hitstun(0.15, Vector2(1.0, 0.0))
    assert_bool(player.action.is_in_hurt()).is_true()
    # 0.33 秒后必须已经能动
    _run(20, LocoInputFrame.empty())
    assert_bool(player.action.is_in_hurt()).override_failure_message(
        "硬直不该持续超过 0.33 秒").is_false()
    _run(40, _frame(true))
    assert_float(_session.get_actor(_enemy_id).stats.current_hp).override_failure_message(
        "硬直结束后必须能立刻反击").is_less(100.0)

func test_sleep_breaks_when_damaged() -> void:
    # 回归：睡眠 3.5 秒期间玩家完全无法操作，血量被白打。
    var player: ActorRuntime = _session.get_actor(_player_id)
    player.status.apply(&"sleep", 3.5)
    assert_bool(player.status.can_act()).is_false()

    var req := CombatDamageRequest.new()
    req.attacker_id = _enemy_id
    req.target_id = _player_id
    req.power = 5.0
    req.damage_type = &"neutral"
    req.hit_kind = &"light"
    var result: CombatDamageResult = player.take_hit(req)

    assert_float(result.amount).is_greater(0.0)
    assert_bool(player.status.has(&"sleep")).override_failure_message(
        "挨打必须破睡，否则玩家会被白打 3.5 秒").is_false()
    assert_bool(player.status.can_act()).is_true()

## 不变量：除睡眠（硬控，由 test_sleep_breaks_when_damaged 单独保证）之外，
## 玩家连续无法操作的时间不该超过 0.6 秒。
## 这条用例在「root 锁动作」的版本上会失败（当时最长 1.0 秒）。
func test_player_never_locked_out_longer_than_half_a_second() -> void:
    var player: ActorRuntime = _session.get_actor(_player_id)
    var worst: float = 0.0
    var streak: float = 0.0
    for i: int in 600:
        var inputs: Dictionary = {}
        inputs[_player_id] = _frame(true) if i % 12 == 0 else LocoInputFrame.empty()
        _session.tick(STEP, inputs)
        if player.status.can_act() or player.status.has(&"sleep"):
            streak = 0.0
        else:
            streak += STEP
            worst = maxf(worst, streak)
    assert_float(worst).override_failure_message(
        "玩家最长被锁 %.2f 秒，超过 0.6 秒说明有控制效果在锁动作" % worst).is_less(0.6)

## 回归：普攻不能打到 reach 之外。修之前判定盒写死在 .tscn（2.4 m），
## 领域层却按数据表算，实测出现过 2.67 m 的「隔空命中」。
func test_melee_cannot_reach_beyond_configured_range() -> void:
    var reach: float = float(_session.get_actor(_player_id).melee_config().get("range", 0.0))
    var far_id: int = _session.spawn_actor(
        _spec(GameConstants.FACTION_ENEMY, Vector2(reach + 0.6, 0.0), 100.0))
    var far: ActorRuntime = _session.get_actor(far_id)
    _run(40, _frame(true))
    assert_float(far.stats.current_hp).override_failure_message(
        "打到了 %.2f m 外的目标（reach=%.2f），判定范围与视觉脱节" % [reach + 0.6, reach]
    ).is_equal(100.0)
    # 同一招在 reach 内必须命中，证明不是根本没打出去
    assert_float(_session.get_actor(_enemy_id).stats.current_hp).is_less(100.0)
