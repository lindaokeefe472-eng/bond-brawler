# 架构说明（ARCHITECTURE）

> 本文件是**契约**。任何代码改动都必须先满足这里的依赖方向与接口签名。
> 改接口 = 改本文件 + 改调用方 + 改测试，三者同一个 commit。

## 1. 分层与依赖方向

```
                    bootstrap（组合根，唯一允许 new 具体实现的地方）
                         │
        ┌────────────────┴────────────────┐
        │                                 │
  presentation（适配器）           infrastructure（适配器）
  CharacterBody3D / Sprite3D       JSON 仓库 / GodotClock / GodotRng
        │                                 │
        └──────────────┬──────────────────┘
                       │  只依赖接口（src/core/ports）
                 application（用例编排）
                       │
        ┌──────┬───────┼────────┬─────────┬─────────┐
     combat  skills  talents    ai    locomotion   stage
        └──────┴───────┴────────┴─────────┴─────────┘
                       │
                     core（事件、端口、坐标、随机、常量）
```

**硬规则**

| 规则 | 检查方式 |
|---|---|
| 领域层（`src/*/domain/`）不得出现 `Node`、`SceneTree`、`NodePath`、`Resource`、`Area3D`、`CharacterBody3D`、`Time`、`Engine`、`Input`、`OS` | `tools/check_architecture.py` |
| 领域层只允许继承 `RefCounted` / `Object` | 同上 |
| 跨上下文只能单向依赖：`combat ← skills ← ai`、`talents → combat`、`stage` 与 `locomotion` 独立 | 同上 |
| 只有 `bootstrap/` 可以 `new` 具体实现类；其余地方只持有接口类型 | 代码评审 |
| 任何数值不得写死在领域逻辑里，必须来自 `data/` 或 `GameConstants` | 代码评审 |

领域层允许使用的引擎内置类型（纯值类型，不需要场景树）：
`Vector2`、`Vector3`、`Color`、`Array`、`Dictionary`、`String`、`StringName`、`Callable`、`RefCounted`。

## 2. 坐标约定

领域层在**平面坐标**里工作：

```
Vector2(x, y)
  x -> 世界 X（横轴，推进方向）
  y -> 世界 Z（纵深 / lane），取值范围 [LANE_MIN, LANE_MAX]
```

表现层负责 `Vector3(p.x, height, p.y)` 的映射（见 `PlaneMath.to_world`）。
高度（跳跃）是**独立标量** `height`，不进入平面坐标，因此空中判定与地面判定共用一套几何。

## 3. 命中判定的两段式

这是本项目最重要的设计决定：

1. **宽相（broad phase）**：`Area3D` 只负责「谁可能打到谁」。碰撞层见 `src/core/collision_layers.gd`。
2. **窄相（narrow phase，权威）**：领域层用 `PlaneMath.in_cone` + 纵深对齐 + 帧数据判定是否命中，并计算伤害。

> 宽相可以漏（物理帧率抖动），窄相不能错。所有伤害数字只由领域层产生，物理层永远不改血量。

这样做的收益：战斗可单测、可回放、可联机同步，且物理引擎换实现不影响手感。

## 4. 限界上下文与公开 API

以下签名是**契约**。方法名、参数顺序、返回类型不得随意更改。

### 4.1 core（`src/core/`）

| 类型 | 职责 |
|---|---|
| `GameConstants` | 全部世界常量与事件名 |
| `CollisionLayers` | 3D 碰撞层位掩码 |
| `PlaneMath` | 2.5D 平面几何静态函数 |
| `DomainEvent` / `DomainEventBus` | 同步领域事件总线，支持录制 |
| `IClock` / `IRng` / `IFeedbackSink` / `IPhysicsQuery` / `IDataSource` | 出站端口 |
| `DeterministicRng` / `FakeClock` | 确定性实现 / 测试实现 |

### 4.2 combat（`src/combat/domain/`）

```gdscript
class CombatModifier extends RefCounted
    var id: StringName          # 唯一标识，同 id 重复添加按 stacks 叠加
    var stat: StringName        # "attack" / "defense" / "speed" / "crit_rate" / "max_hp" ...
    var flat: float
    var percent: float          # 0.15 = +15%
    var duration: float         # <0 表示永久
    var stacks: int
    var max_stacks: int
    var source: StringName
    static func make(stat_id: StringName, flat_bonus: float = 0.0, percent_bonus: float = 0.0,
                     duration_seconds: float = -1.0) -> CombatModifier
    func tick(dt: float) -> bool          # 返回是否过期
    func is_expired() -> bool

class CombatActorStats extends RefCounted
    var actor_id: int
    var current_hp: float
    func _init(actor_id: int, base: Dictionary) -> void
    func add_modifier(m: CombatModifier) -> void
    func remove_modifier(id: StringName) -> void
    func clear_modifiers() -> void
    func tick(dt: float) -> void
    func value(stat: StringName) -> float
    func max_hp() -> float
    func is_dead() -> bool
    func take_raw_damage(amount: float) -> float    # 返回实际扣除值
    func heal(amount: float) -> float

class CombatDamageRequest extends RefCounted
    var attacker_id: int
    var target_id: int
    var power: float
    var damage_type: StringName      # 18 属性之一，或 &"neutral"
    var hit_kind: StringName         # &"light" / &"heavy" / &"skill"
    var knockback: float
    var is_aerial: bool
    var can_crit: bool
    var tags: Array[StringName]

class CombatDamageResult extends RefCounted
    var amount: float
    var is_crit: bool
    var is_dodged: bool
    var is_guarded: bool
    var is_lethal: bool
    var knockback_vector: Vector2
    var applied_status: StringName

class CombatTypeChart extends RefCounted
    func _init(chart: Dictionary, names: Dictionary) -> void
    func multiplier(attack_type: StringName, defender_types: Array[StringName]) -> float

class CombatStatusSet extends RefCounted
    func apply(id: StringName, duration: float, stacks: int = 1) -> void
    func remove(id: StringName) -> void
    func has(id: StringName) -> bool
    func stacks(id: StringName) -> int
    func tick(dt: float) -> Array[StringName]     # 返回本帧过期的状态
    func is_stunned() -> bool
    func speed_multiplier() -> float
    func can_act() -> bool

class CombatDamageCalculator extends RefCounted
    func _init(type_chart: CombatTypeChart, rng: IRng) -> void
    func resolve(req: CombatDamageRequest, attacker: CombatActorStats, defender: CombatActorStats,
                 defender_status: CombatStatusSet, defender_invulnerable: bool,
                 defender_guarding: bool) -> CombatDamageResult
```

伤害管线顺序（固定，不得调整）：
`无敌 → 闪避 → 格挡 → 暴击 → 属性倍率 → 防御减免 → 最小伤害(1) → 扣血`

### 4.3 skills（`src/skills/domain/`）

```gdscript
class SkillDef extends RefCounted
    var id: StringName
    var name: String
    var type: StringName
    var kind: StringName          # melee/bolt/beam/dash/...
    var template: StringName      # 执行模板，见 4.3.1
    var power: float
    var cost: float
    var cooldown: float
    var range: float
    var knockback: float
    var windup: float
    var commit: float
    var recovery: float
    var duration: float
    var clash_class: StringName
    var clash_power: float
    var status: StringName
    var dodgeable: bool
    var extra: Dictionary         # 模板专用参数
    static func from_dict(d: Dictionary) -> SkillDef

class SkillInstance extends RefCounted
    var def: SkillDef
    var cooldown_left: float
    var charges: int
    var max_charges: int
    func _init(def: SkillDef) -> void
    func is_ready() -> bool
    func tick(dt: float) -> bool                  # 返回本帧是否刚转好
    func consume() -> void
    func refund(fraction: float) -> void

class SkillCastPhase:
    enum { IDLE, WINDUP, ACTIVE, RECOVERY }

class SkillCaster extends RefCounted
    var actor_id: int
    var phase: int
    var active_slot: int
    func _init(actor_id: int, bus: DomainEventBus) -> void
    func equip(slot: int, inst: SkillInstance) -> void
    func can_cast(slot: int, energy: float) -> bool
    func begin_cast(slot: int, aim: Vector2, facing: int, energy: float) -> bool
    func tick(dt: float) -> void
    func interrupt(reason: StringName) -> void
    func cancel_windup() -> void                  # 返还 50% 能量与冷却
    func is_busy() -> bool
    func phase_progress() -> float
```

事件载荷（`DomainEvent.payload`）：
- `skill.cast_started`：`{actor_id, slot, skill_id, aim: Vector2, facing}`
- `skill.activated`：`{actor_id, slot, skill_id, hitbox: {reach, half_arc, lane_tolerance}, effects: Array}`
- `skill.interrupted`：`{actor_id, slot, reason}`

#### 4.3.1 效果器（Effector）

```gdscript
class SkillEffectContext extends RefCounted
    var caster_id: int
    var target_ids: Array[int]
    var origin: Vector2
    var facing: int
    var rng: IRng
    var stats_provider: Callable      # func(actor_id) -> CombatActorStats
    var emit: Callable                # func(event: DomainEvent)

class SkillEffect extends RefCounted
    func apply(ctx: SkillEffectContext) -> void

# 实现：SkillDamageEffect / SkillKnockbackEffect / SkillStatusEffect / SkillHealEffect / SkillBuffEffect / SkillSpawnProjectileEffect
```

模板 → 效果组合的映射表在 `SkillTemplateRegistry`，未知模板回退到 `melee`。
已实现的模板（**只有这些**，其余映射到最近的）：`melee`、`lunge_melee`、`projectile`、`volley`、`beam`、`area_burst`、`dash_attack`、`heal`、`buff`、`channel`。

### 4.4 talents（`src/talents/domain/`）

```gdscript
class TalentNode extends RefCounted
    var id: StringName
    var name: String
    var max_rank: int
    var rank: int
    var cost: int
    var prerequisites: Array[StringName]
    var effects: Array
    func state(tree_unlocked: Dictionary) -> int   # 0 LOCKED / 1 AVAILABLE / 2 ACTIVE

class TalentTree extends RefCounted
    func _init(bus: DomainEventBus) -> void
    func add_node(node: TalentNode) -> void
    func available_points() -> int
    func grant_points(n: int) -> void
    func can_unlock(id: StringName) -> bool
    func unlock(id: StringName) -> bool
    func respec() -> int                       # 返回返还点数
    func modifiers_for(actor_id: int) -> Array[CombatModifier]
    func snapshot() -> Dictionary
    func restore(data: Dictionary) -> void
```

### 4.5 ai（`src/ai/domain/`）

```gdscript
class AiBlackboard extends RefCounted
    var self_id: int
    var self_pos: Vector2
    var self_hp_ratio: float
    var target_id: int
    var target_pos: Vector2
    var target_hp_ratio: float
    var target_guarding: bool
    var skill_ready: Array[bool]
    var distance: float
    var aligned: bool
    var threat: float
    var time: float

class AiIntent extends RefCounted
    var kind: StringName          # idle/approach/retreat/attack/skill/reposition/guard
    var target_id: int
    var skill_slot: int
    var desired_pos: Vector2

class AiEnemyBrain extends RefCounted
    func _init(profile: Dictionary, rng: IRng) -> void
    func tick(dt: float, bb: AiBlackboard) -> AiIntent
    func on_hit_taken(damage: float) -> void
```

效用 AI：每个候选意图有若干 `Consideration`（返回 0..1），加权求和取最大，并带「决策粘滞」计时器防止抖动。

### 4.6 locomotion（`src/locomotion/domain/`）

```gdscript
class LocoInputFrame extends RefCounted
    var move: Vector2             # -1..1，y 为纵深
    var jump: bool
    var dash: bool
    var attack: bool
    var guard: bool
    var skills: Array[bool]       # 长度 4
    static func empty() -> LocoInputFrame

class LocoActionOutput extends RefCounted
    var plane_pos: Vector2
    var velocity: Vector2
    var height: float
    var vertical_velocity: float
    var facing: int
    var state: int
    var super_armor: bool
    var invulnerable: bool
    var can_be_interrupted: bool

class LocoActionMachine extends RefCounted
    func _init(profile: Dictionary, bus: DomainEventBus) -> void
    func tick(dt: float, input: LocoInputFrame, alive: bool) -> LocoActionOutput
    func request_skill_lock(duration: float) -> void
    func apply_hitstun(duration: float, knockback: Vector2) -> void
    func set_knockback(v: Vector2) -> void
    func current_state() -> int
    func snapshot() -> Dictionary
```

`ActionState`：`IDLE / RUN / JUMP / FALL / LAND / DASH / ATTACK / SKILL / HURT / DEAD`。

必须实现的手感机制：输入缓冲（`INPUT_BUFFER_WINDOW`）、土狼时间（`COYOTE_TIME`）、
可变跳跃高度（`JUMP_CUT_MULTIPLIER`）、冲刺无敌帧、受击硬直与霸体。

### 4.7 stage（`src/stage/domain/`）

```gdscript
class StageWaveSpawner extends RefCounted
    func _init(waves: Array, bus: DomainEventBus) -> void
    func tick(dt: float) -> void
    func on_actor_died(actor_id: int) -> void
    func pending_spawns() -> Array[Dictionary]   # [{species_id, plane_pos, wave}]
    func is_cleared() -> bool
    func current_wave() -> int

class StageProgress extends RefCounted
    func _init(room_ids: Array[StringName]) -> void
    func complete_room(id: StringName) -> void
    func is_unlocked(id: StringName) -> bool
    func snapshot() -> Dictionary
    func restore(data: Dictionary) -> void
```

### 4.8 application（`src/application/`）

```gdscript
class ActorRuntime extends RefCounted
    var id: int
    var faction: StringName
    var stats: CombatActorStats
    var status: CombatStatusSet
    var action: LocoActionMachine
    var caster: SkillCaster
    var brain: AiEnemyBrain          # 玩家为 null
    var facing: int
    var plane_pos: Vector2
    var height: float
    var energy: float
    var stamina: float

class BattleSession extends RefCounted
    func _init(services: Dictionary) -> void
    func spawn_actor(spec: Dictionary) -> int
    func remove_actor(id: int) -> void
    func tick(dt: float, inputs: Dictionary) -> void   # {actor_id: LocoInputFrame}
    func get_actor(id: int) -> ActorRuntime
    func actor_ids() -> Array[int]
    func snapshot() -> Dictionary
```

`BattleSession` 是唯一把各上下文串起来的地方，它不包含业务规则，只做编排。

## 5. 表现层适配器（`src/presentation/`）

| 类 | 基类 | 职责 |
|---|---|---|
| `ActorView` | `CharacterBody3D` | 绑定 `ActorRuntime`，把 `LocoActionOutput` 写进 transform / 动画 |
| `SpriteBillboard` | `Sprite3D` | 图集播放，按朝向翻转，billboard 模式 |
| `HitboxAdapter` | `Area3D` | 宽相：把重叠到的 `HurtboxAdapter` 报给 `ActorView` |
| `HurtboxAdapter` | `Area3D` | 宽相：携带 `actor_id` |
| `FeedbackDirector` | `Node`（实现 `IFeedbackSink`） | 顿帧 / 震屏 / 闪白 / 跳字 / 音效 |
| `CameraRig` | `Camera3D` | 侧视，只跟 x，纵深固定 |
| `InputAdapter` | `RefCounted` | `InputEvent` → `LocoInputFrame` |
| `NodePool` | `RefCounted` | 通用对象池，禁止战斗中 `instantiate()` |
| `DamageNumberPool` | `NodePool` 的使用者 | 伤害跳字 |

## 6. 组合根

`src/bootstrap/` 是唯一允许出现 `new` 具体实现的地方：

| 类 | 职责 |
|---|---|
| `CompositionRoot` | 纯装配：建总线 / RNG / 仓库 / 会话，不碰场景树，可在 headless 里构造整局 |
| `GameRoot` | 场景根节点：消费装配好的服务，建场地、挂反馈、绑事件、推进固定步长 tick |

```gdscript
var bus := DomainEventBus.new()
var rng := DeterministicRng.new(seed)
var clock := GodotClock.new()
var data := JsonDataSource.new("res://data")
var skills := SkillRepository.new(data)
var type_chart := CombatTypeChart.new(chart_dict, names_dict)
```

## 7. 测试

框架：**GdUnit4 6.2.2**，详见 `docs/testing.md`。

| 层 | 位置 | 依赖 |
|---|---|---|
| 单元测试 | `tests/unit/<context>/` | 纯 GDScript，无场景树 |
| 端到端 | `tests/e2e/` | 组合根装配整局，不依赖渲染 |

运行：`bash tools/test.sh [目录...]`
CI 要求：退出码 0；新增领域逻辑必须伴随单元测试。
