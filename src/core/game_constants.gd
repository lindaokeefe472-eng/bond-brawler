## 全局常量：坐标系、纵深带、帧率、命名前缀。
## 领域层唯一允许的「世界几何」知识来源，任何魔法数字都必须收敛到这里。
class_name GameConstants
extends RefCounted

# ---------------------------------------------------------------- 2.5D 坐标
## 领域平面坐标 (Vector2) 的约定：
##   x -> 世界 X（横轴，主要推进方向）
##   y -> 世界 Z（纵深 / lane）
## 表现层负责 Vector2(plane) -> Vector3(x, height, y) 的映射。
const LANE_MIN: float = -2.6
const LANE_MAX: float = 2.6
## 纵深对齐容差（米）。|Δlane| 超过它则近战判定失败 —— 清版游戏的走位核心。
const LANE_ALIGN_TOLERANCE: float = 0.85
## 角色身位半径（米），用于软碰撞与推挤。
const BODY_RADIUS: float = 0.42
## 场地半宽（米）。墙的内表面就在这里，弹体出界即回收。
const ARENA_HALF_WIDTH: float = 18.0
## 地面高度。
const GROUND_Y: float = 0.0
## 每个 sprite 帧对应的世界高度（米），100px 图集 -> 1.8m 身高。
const PIXELS_PER_METER: float = 100.0 / 1.8

# ---------------------------------------------------------------- 近战判定几何
## 角色身高 1.8 m、身位半径 0.42 m；一把长剑从身体中心算起约 1.45 m。
## 这三个值是「看到的剑」与「打得到的范围」的唯一来源，判定盒也由它们推导。
const MELEE_REACH: float = 1.45
const MELEE_LANE_TOLERANCE: float = LANE_ALIGN_TOLERANCE
const MELEE_HIT_HEIGHT: float = 1.6
## 判定盒比真实判定范围各方向再大一圈：保证宽相永远是窄相的超集，
## 宽相漏判只会让校验通道报警，绝不会让玩家少打一次。
const HITBOX_MARGIN: float = 0.06
## data/actions.json 的 basic_attack.range 是按原游戏角色体型定的（2.4）。
## 本项目角色统一 1.8 m 高，必须按比例换算，否则会出现「隔空打人」。
## 瞬发技能（没有弹体）的射程上限（米）。
## 没有可见弹道却打得到六七米外，玩家只会觉得「隔空挨打」。
## 等光束/冲击波有正式表现之后再放开。
const SKILL_INSTANT_REACH_CAP: float = 2.6

const MELEE_RANGE_REFERENCE: float = 2.4
const MELEE_RANGE_SCALE: float = MELEE_REACH / MELEE_RANGE_REFERENCE

## 远程角色（弓手 / 法师）普攻弹体的兜底参数。
## 数据里 attack = "projectile" 的角色走这条路，具体数值在 data/melee.json 覆盖。
const BASIC_PROJECTILE_SPEED: float = 14.0
const BASIC_PROJECTILE_RANGE: float = 9.0

# ---------------------------------------------------------------- 时间
## 固定逻辑步长：领域层所有 tick 都以它为单位推进，保证可重放。
const TICK_RATE: int = 60
const TICK_DELTA: float = 1.0 / float(TICK_RATE)
## 单帧最多追赶的逻辑步数，防止卡顿后的死亡螺旋。
const MAX_CATCHUP_TICKS: int = 5

# ---------------------------------------------------------------- 输入
## 土狼时间：离开平台后仍可起跳的宽限。
const COYOTE_TIME: float = 0.10
## 跳跃可变高度：松手时上升速度乘以此系数。
const JUMP_CUT_MULTIPLIER: float = 0.45

# ---------------------------------------------------------------- 打击感
const HITSTOP_LIGHT: float = 0.045
const HITSTOP_MEDIUM: float = 0.075
const HITSTOP_HEAVY: float = 0.110
const SHAKE_LIGHT: float = 0.12
const SHAKE_MEDIUM: float = 0.26
const SHAKE_HEAVY: float = 0.45

# ---------------------------------------------------------------- 事件命名
## 领域事件统一使用 "<上下文>.<过去式>" 命名，全部小写点分。
## 全部音效 cue。data/audio.json 必须覆盖这里的每一项，
## 少一条就是某个事件永远没声音，而且不会有任何报错。
const SFX_CUES: Array[StringName] = [
	&"hit", &"crit", &"guard", &"dodge", &"cast", &"hurt", &"death", &"ui_click",
]

const EVT_ACTOR_SPAWNED: StringName = &"actor.spawned"
const EVT_ACTOR_DIED: StringName = &"actor.died"
const EVT_DAMAGE_APPLIED: StringName = &"combat.damage_applied"
const EVT_DAMAGE_MITIGATED: StringName = &"combat.damage_mitigated"
const EVT_ACTOR_DODGED: StringName = &"combat.dodged"
const EVT_ACTOR_GUARDED: StringName = &"combat.guarded"
const EVT_STATUS_APPLIED: StringName = &"combat.status_applied"
const EVT_STATUS_EXPIRED: StringName = &"combat.status_expired"
const EVT_SKILL_CAST_STARTED: StringName = &"skill.cast_started"
const EVT_SKILL_ACTIVATED: StringName = &"skill.activated"
const EVT_SKILL_INTERRUPTED: StringName = &"skill.interrupted"
const EVT_SKILL_COOLDOWN_READY: StringName = &"skill.cooldown_ready"
const EVT_ACTION_CHANGED: StringName = &"locomotion.action_changed"
const EVT_ACTION_CANCELLED: StringName = &"locomotion.action_cancelled"
const EVT_WAVE_STARTED: StringName = &"stage.wave_started"
const EVT_WAVE_CLEARED: StringName = &"stage.wave_cleared"
const EVT_ROOM_CLEARED: StringName = &"stage.room_cleared"
const EVT_TALENT_UNLOCKED: StringName = &"talent.unlocked"
const EVT_INTENT_EMITTED: StringName = &"ai.intent_emitted"

# ---------------------------------------------------------------- 阵营
const FACTION_PLAYER: StringName = &"player"
const FACTION_ENEMY: StringName = &"enemy"
const FACTION_NEUTRAL: StringName = &"neutral"
