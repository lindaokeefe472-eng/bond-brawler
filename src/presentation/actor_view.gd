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
const HITBOX_FORWARD_OFFSET: float = 1.2
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
    sync_from_runtime()

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
    _hitbox.position.x = HITBOX_FORWARD_OFFSET * float(_facing)
    var active: bool = false
    if not _is_dead and runtime != null and runtime.action != null:
        var phase: int = runtime.action.attack_phase()
        active = state == ActionState.ATTACK and phase == ATTACK_PHASE_ACTIVE
    _hitbox.set_active(active)

func _on_broadphase_candidate(attacker_id: int, target_id: int) -> void:
    if not _candidates.has(target_id):
        _candidates.append(target_id)
    if broadphase_sink.is_valid():
        broadphase_sink.call(attacker_id, target_id)
