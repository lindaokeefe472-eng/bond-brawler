## 角色视图：把领域层的平面状态映射成 3D 变换、动画与碰撞盒。
##
## 为什么只读 ActorRuntime 的公开字段：领域层每帧已经把权威结果写回
## plane_pos / height / facing / action.current_state()，视图再推一遍不会产生第二份真相，
## 也不会反过来修改血量或命中结果。
class_name ActorView
extends CharacterBody3D

const SPRITE_NODE: String = "Sprite"
const HITBOX_NODE: String = "Hitbox"
const HURTBOX_NODE: String = "Hurtbox"

## 死亡淡出时长：death 动画播完后才开始，给玩家看清倒地的余韵。
const DEATH_FADE_SECONDS: float = 0.55
## 缺少 death 图集时的兜底停留，保证尸体不会永远杵在场上。
const DEATH_HOLD_SECONDS: float = 0.8
const FLASH_SECONDS: float = 0.09
## 攻击盒放在身体前方多远：宽相只需要覆盖「可能够到」的区域，窄相才是权威。
## 判定盒的碰撞形状节点名（Hitbox 的子节点）。
const HITBOX_SHAPE_NODE: String = "CollisionShape3D"
## 跳字从头顶多高处冒出。
const DAMAGE_NUMBER_HEIGHT: float = 1.9

## 动作状态编号：必须与 locomotion 的 ActionState 顺序一致（见 ARCHITECTURE 4.6）。
## 表现层只按编号分派动画，不引用 locomotion 的类型，避免跨上下文依赖。
enum ActionState {
    IDLE,
    RUN,
    JUMP,
    FALL,
    LAND,
    DASH,
    ATTACK,
    SKILL,
    HURT,
    DEAD,
}

## 攻击相位：只有 ACTIVE 段开启宽相盒，起手与收招都不该打到人。
const ATTACK_PHASE_ACTIVE: int = 1

var actor_id: int = 0
var runtime: ActorRuntime = null
## 宽相候选回调：func(attacker_id: int, target_id: int)，由组合根决定用途。
var broadphase_sink: Callable = Callable()

var _sprite: SpriteBillboard = null
var _hitbox: HitboxAdapter = null
var _hurtbox: HurtboxAdapter = null
var _manifest: Dictionary = {}
var _character_id: String = ""
var _sprite_dir: String = ""
var _facing: int = 1
var _last_anim: StringName = &""
var _flash_left: float = 0.0
var _flash_color: Color = Color.WHITE
var _is_dead: bool = false
var _death_time: float = 0.0
var _death_fading: bool = false
var _death_alpha: float = 1.0
var _candidates: Array[int] = []
## 判定盒相对角色原点的偏移，由近战参数推导（见 _apply_hitbox_geometry）。
var _hitbox_center_x: float = 0.0
var _hitbox_height: float = 0.8
## 本帧动作状态，refresh_hitbox() 要按它决定盒子该不该显示。
var _state: int = ActionState.IDLE
## 微调模式下强制显示判定盒，不用等出手那几帧。
var _hitbox_preview: bool = false

func _ready() -> void:
    _sprite = get_node_or_null(SPRITE_NODE) as SpriteBillboard
    _hitbox = get_node_or_null(HITBOX_NODE) as HitboxAdapter
    _hurtbox = get_node_or_null(HURTBOX_NODE) as HurtboxAdapter
    if _hitbox != null:
        _hitbox.candidate_sink = _on_broadphase_candidate

## 绑定领域运行时与外观资源。manifest 是整份素材清单，character_id 是角色 slug。
func bind(p_runtime: ActorRuntime, character_id: String, manifest: Dictionary) -> void:
    runtime = p_runtime
    actor_id = runtime.id if runtime != null else 0
    _character_id = character_id
    _sprite_dir = "res://assets/sprites/characters/%s" % character_id
    _manifest = manifest
    if _sprite != null:
        var characters: Variant = manifest.get("characters", {})
        if characters is Dictionary:
            var entry: Variant = (characters as Dictionary).get(character_id, {})
            if entry is Dictionary:
                _sprite.apply_metrics(float((entry as Dictionary).get("pixel_size", 0.0)))
    _is_dead = false
    _death_time = 0.0
    _death_fading = false
    _death_alpha = 1.0
    _last_anim = &""
    _candidates.clear()
    if _sprite != null:
        _sprite.set_alpha(1.0)
    visible = true
    if runtime == null:
        return
    var faction: StringName = runtime.faction
    collision_layer = CollisionLayers.body_layer_for(faction)
    collision_mask = CollisionLayers.body_mask_for(faction)
    if _hurtbox != null:
        _hurtbox.configure(actor_id, faction)
    if _hitbox != null:
        _hitbox.configure(actor_id, faction)
    _apply_hitbox_geometry()
    sync_from_runtime()

## 判定盒的尺寸与位置全部由 ActorRuntime 的近战参数推导，和窄相同源。
##
## 之前形状写死在 actor_view.tscn 里（2.4 x 1.6 x 1.8），领域层却用
## range=2.4 / lane=0.85 另一套数，两边必然对不上：实测出现过 2.67 m 的
## 「隔空命中」。现在盒子由 reach / lane_tolerance / hit_height 算出来，
## 再各方向加一圈 HITBOX_MARGIN，保证宽相是窄相的严格超集。
func _apply_hitbox_geometry() -> void:
    if _hitbox == null or runtime == null:
        return
    var shape_node: CollisionShape3D = _hitbox.get_node_or_null(HITBOX_SHAPE_NODE) as CollisionShape3D
    if shape_node == null:
        return
    var cfg: Dictionary = runtime.melee_config()
    var reach: float = maxf(float(cfg.get("range", GameConstants.MELEE_REACH)), 0.0)
    var lane: float = maxf(float(cfg.get("lane_tolerance", GameConstants.MELEE_LANE_TOLERANCE)), 0.0)
    var height: float = maxf(float(cfg.get("hit_height", GameConstants.MELEE_HIT_HEIGHT)), 0.1)
    var margin: float = maxf(float(cfg.get("margin", GameConstants.HITBOX_MARGIN)), 0.0)
    var body: float = GameConstants.BODY_RADIUS
    var box := BoxShape3D.new()
    # x：从身后 body 到身前 reach；z：纵深 ±lane；y：脚底到命中高度。
    # y 只在顶部留 margin：地面是硬边界，盒子不该钻到地板下面去。
    var box_height: float = height + margin
    box.size = Vector3(reach + body + margin * 2.0, box_height, lane * 2.0 + margin * 2.0)
    shape_node.shape = box
    # 中心只由 Area3D 的 position 决定。形状节点自己再带一个 y 偏移就会叠加：
    # .tscn 里是 (0, 0.9, 0)，Area 又被设到 0.86，盒子中心跑到 1.76 —— 整个浮在头顶。
    shape_node.position = Vector3.ZERO
    _hitbox_center_x = (reach - body) * 0.5
    _hitbox_height = box_height * 0.5

## 从领域运行时读回本帧结果。GameRoot 在每次 BattleSession.tick 之后调用。
func sync_from_runtime() -> void:
    if runtime == null:
        return
    var state: int = ActionState.IDLE
    if runtime.action != null:
        state = runtime.action.current_state()
    _apply_pose(runtime.plane_pos, runtime.height, runtime.facing, state)

## 权威映射：平面坐标 -> 世界坐标，状态 -> 动画，朝向 -> 翻转与攻击盒位置。
## output 只按字段读取（plane_pos / height / facing / state），不声明具体类型：
## 表现层不依赖 locomotion 的类型，字段契约见 ARCHITECTURE 4.6。
func apply_output(output: Variant) -> void:
    if output == null:
        return
    _apply_pose(output.plane_pos, output.height, output.facing, output.state)

func _apply_pose(plane_pos: Vector2, height: float, facing: int, state: int) -> void:
    _state = state
    position = PlaneMath.to_world(plane_pos, height)
    _facing = 1 if facing >= 0 else -1
    if _sprite != null:
        _sprite.set_facing(_facing)
    _update_animation(state)
    _update_hitbox(state)
    if state == ActionState.DEAD:
        _begin_death()

func flash(color: Color = Color.WHITE, duration: float = FLASH_SECONDS) -> void:
    _flash_color = color
    _flash_left = maxf(duration, 0.0)
    # 连着挨打时 _last_anim 已经是 hurt，_update_animation 会提前返回，
    # 动画就停在最后一帧不动。每次挨打强制重播，受击才有「被打了一下」的反馈。
    if _sprite != null and _last_anim == &"hurt":
        _sprite.restart()
    if _sprite == null:
        return
    var shown: Color = _flash_color
    shown.a = _sprite.modulate.a
    _sprite.modulate = shown

## 跳字锚点：身体上方一点，避免数字盖住角色。
func damage_number_position() -> Vector3:
    return global_position + Vector3.UP * DAMAGE_NUMBER_HEIGHT

func consume_candidates() -> Array[int]:
    var out: Array[int] = _candidates.duplicate()
    _candidates.clear()
    return out

func is_dead() -> bool:
    return _is_dead

func _process(delta: float) -> void:
    if _sprite != null:
        _sprite.tick(delta)
    _update_flash(delta)
    _update_death(delta)

func _update_flash(delta: float) -> void:
    if _flash_left <= 0.0:
        return
    _flash_left -= delta
    if _flash_left > 0.0 or _sprite == null:
        return
    # 只恢复 RGB，保留死亡淡出正在使用的 alpha。
    _sprite.modulate = Color(1.0, 1.0, 1.0, _sprite.modulate.a)

func _begin_death() -> void:
    if _is_dead:
        return
    _is_dead = true
    _death_time = 0.0
    _death_fading = false
    if _hitbox != null:
        _hitbox.set_active(false)
    if _hurtbox != null:
        _hurtbox.set_invulnerable(true)
    # 尸体不再参与软推挤，活着的角色可以直接穿过。
    collision_layer = 0
    _play_animation(&"death")

func _update_death(delta: float) -> void:
    if not _is_dead:
        return
    _death_time += delta
    if _death_fading:
        _death_alpha = maxf(0.0, _death_alpha - delta / DEATH_FADE_SECONDS)
        if _sprite != null:
            _sprite.set_alpha(_death_alpha)
        if _death_alpha <= 0.0:
            visible = false
        return
    var animation_done: bool = _sprite != null and _sprite.is_finished()
    if animation_done or _death_time >= DEATH_HOLD_SECONDS:
        _death_fading = true

func _update_animation(state: int) -> void:
    var anim_name: StringName = _animation_for_state(state)
    if anim_name == _last_anim:
        return
    _last_anim = anim_name
    _play_animation(anim_name)

func _play_animation(anim_name: StringName) -> void:
    if _sprite == null:
        return
    var data: Dictionary = _animation_data(anim_name)
    if data.is_empty():
        return
    _sprite.play_manifest(anim_name, data, _sprite_dir)

func _animation_for_state(state: int) -> StringName:
    # 格挡没有独立动作状态，靠 ActorRuntime 的按住标记叠加到待机/行走上。
    if runtime != null and runtime.is_guarding():
        var can_show_block: bool = state == ActionState.IDLE or state == ActionState.RUN
        if can_show_block:
            return &"block"
    match state:
        ActionState.IDLE:
            return &"idle"
        ActionState.RUN:
            return &"walk"
        ActionState.JUMP:
            return &"jump"
        ActionState.FALL:
            return &"fall"
        ActionState.LAND:
            return &"idle"
        ActionState.DASH:
            return &"dash"
        ActionState.ATTACK:
            var combo: int = 1
            if runtime != null and runtime.action != null:
                combo = clampi(runtime.action.combo_index() + 1, 1, 3)
            return StringName("attack%d" % combo)
        ActionState.SKILL:
            return &"attack1"
        ActionState.HURT:
            return &"hurt"
        ActionState.DEAD:
            return &"death"
    return &"idle"

func _animation_data(anim_name: StringName) -> Dictionary:
    var character: Dictionary = _character_manifest()
    var raw_anims: Variant = character.get("animations", {})
    var anims: Dictionary = raw_anims if raw_anims is Dictionary else {}
    if anims.has(String(anim_name)):
        return anims[String(anim_name)]
    for fallback: StringName in _fallbacks_for(anim_name):
        if anims.has(String(fallback)):
            return anims[String(fallback)]
    if anims.has("idle"):
        return anims["idle"]
    return {}

func _character_manifest() -> Dictionary:
    var raw_characters: Variant = _manifest.get("characters", {})
    if not (raw_characters is Dictionary):
        return {}
    var raw_character: Variant = (raw_characters as Dictionary).get(_character_id, {})
    return raw_character if raw_character is Dictionary else {}

## 素材包里没有的动作走最近似动画，保证任何角色都不会因为缺一张图集而僵住。
func _fallbacks_for(anim_name: StringName) -> Array:
    match anim_name:
        &"jump", &"fall", &"dash":
            return [&"walk", &"idle"]
        &"attack2", &"attack3":
            return [&"attack1", &"idle"]
        &"death":
            return [&"hurt", &"idle"]
        &"hurt", &"block":
            return [&"idle"]
    return [&"idle"]

func _update_hitbox(state: int) -> void:
    if _hitbox == null:
        return
    _hitbox.position = Vector3(_hitbox_center_x * float(_facing), _hitbox_height, 0.0)
    # 微调预览优先：待机状态下也要能看见盒子，否则只能等出手那几帧。
    var active: bool = _hitbox_preview and not _is_dead
    if not active and not _is_dead and runtime != null and runtime.action != null:
        var phase: int = runtime.action.attack_phase()
        # 只在判定帧打开。起手帧就打开的话，剑还收着、判定盒已经伸到 1.45 m，
        # 看起来就是「多了一把刀的距离」。后摇同理立刻关掉。
        # 代价：ACTIVE 首帧的重叠列表可能还没填好，宽相候选为空 ——
        # resolve_melee 遇到空候选会退化为全量扫描，所以不会漏伤害。
        active = state == ActionState.ATTACK and phase == ATTACK_PHASE_ACTIVE
    _hitbox.set_active(active)

## 调试用：melee_config 改完之后让盒子按新参数重算一遍。
## 正常流程只在 bind() 时算一次，因为参数不会变。
func refresh_hitbox() -> void:
    _apply_hitbox_geometry()
    _update_hitbox(_state)

## 调试用：无视攻击相位强制显示判定盒。
func set_hitbox_preview(on: bool) -> void:
    _hitbox_preview = on
    _update_hitbox(_state)

func _on_broadphase_candidate(attacker_id: int, target_id: int) -> void:
    if not _candidates.has(target_id):
        _candidates.append(target_id)
    if broadphase_sink.is_valid():
        broadphase_sink.call(attacker_id, target_id)
