## 打击感总控：顿帧、震屏、闪白、跳字、全屏闪与音效请求。
##
## 注意：GDScript 是单继承，无法同时 extends Node 和 IFeedbackSink。
## 这里按 IFeedbackSink 的签名逐条实现（鸭子类型），组合根可以把它当 IFeedbackSink 注入。
class_name FeedbackDirector
extends Node

const FLASH_SECONDS: float = 0.09
const SCREEN_FLASH_LAYER: int = 100

var _camera: CameraRig = null
var _numbers: DamageNumberPool = null
var _views: Dictionary = {}
var _saved_time_scale: float = 1.0
## 多次顿帧重叠时只让最后一次负责恢复，避免先结束的那次提前解开时间。
var _hitstop_token: int = 0
var _overlay_layer: CanvasLayer = null
var _overlay: ColorRect = null
var _overlay_left: float = 0.0
var _overlay_total: float = 0.0
var _overlay_color: Color = Color.WHITE
var _sfx_requests: int = 0
var _last_sfx_cue: StringName = &""
var _last_sfx_position: Vector2 = Vector2.ZERO

func _ready() -> void:
    # 顿帧期间 time_scale 为 0，本节点仍要能处理跳字与全屏闪。
    process_mode = Node.PROCESS_MODE_ALWAYS

func configure(camera: CameraRig, numbers: DamageNumberPool) -> void:
    _camera = camera
    _numbers = numbers

func register_actor_view(actor_id: int, view: ActorView) -> void:
    _views[actor_id] = view

func unregister_actor_view(actor_id: int) -> void:
    _views.erase(actor_id)

## 顿帧：把全局时间冻结 duration 秒，用忽略 time_scale 的计时器恢复。
func hit_stop(duration: float) -> void:
    if duration <= 0.0 or not is_inside_tree():
        return
    # 只在「当前没被冻住」时记录原值，否则第二次顿帧会把 0 当成原值。
    if Engine.time_scale > 0.0:
        _saved_time_scale = Engine.time_scale
    Engine.time_scale = 0.0
    _hitstop_token += 1
    var token: int = _hitstop_token
    var timer: SceneTreeTimer = get_tree().create_timer(duration, true, false, true)
    await timer.timeout
    if token != _hitstop_token:
        return
    Engine.time_scale = _saved_time_scale

func camera_shake(strength: float, duration: float = 0.0) -> void:
    if _camera == null:
        return
    _camera.add_trauma(strength, duration)

func hit_flash(actor_id: int, color: Color = Color.WHITE) -> void:
    var view: ActorView = _views.get(actor_id, null)
    if view == null or not is_instance_valid(view):
        return
    view.flash(color, FLASH_SECONDS)

func damage_number(actor_id: int, amount: int, kind: StringName = &"normal") -> void:
    if _numbers == null:
        return
    var view: ActorView = _views.get(actor_id, null)
    if view == null or not is_instance_valid(view):
        return
    _numbers.spawn(view.damage_number_position(), amount, kind)

## 全屏闪：真实实现是一层 CanvasLayer 上的 ColorRect，按 duration 线性淡出。
func screen_flash(color: Color, duration: float) -> void:
    if duration <= 0.0 or not is_inside_tree():
        return
    _ensure_overlay()
    if _overlay == null:
        return
    _overlay_color = color
    _overlay_left = duration
    _overlay_total = duration
    _overlay.color = color

## 音效占位：记录请求供后续 AudioDirector 消费，不在这里加载音频资源。
func play_sfx(cue: StringName, position: Vector2 = Vector2.ZERO) -> void:
    _sfx_requests += 1
    _last_sfx_cue = cue
    _last_sfx_position = position

func sfx_request_count() -> int:
    return _sfx_requests

func last_sfx_cue() -> StringName:
    return _last_sfx_cue

func _process(delta: float) -> void:
    if _numbers != null:
        _numbers.tick(delta)
    _tick_overlay(delta)

func _tick_overlay(delta: float) -> void:
    if _overlay == null or _overlay_total <= 0.0:
        return
    _overlay_left = maxf(0.0, _overlay_left - delta)
    var ratio: float = _overlay_left / _overlay_total
    var color: Color = _overlay_color
    color.a = _overlay_color.a * clampf(ratio, 0.0, 1.0)
    _overlay.color = color

func _ensure_overlay() -> void:
    if _overlay != null:
        return
    _overlay_layer = CanvasLayer.new()
    _overlay_layer.name = "ScreenFlash"
    _overlay_layer.layer = SCREEN_FLASH_LAYER
    add_child(_overlay_layer)
    _overlay = ColorRect.new()
    _overlay.name = "FlashRect"
    _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _overlay.color = Color(1.0, 1.0, 1.0, 0.0)
    _overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    _overlay_layer.add_child(_overlay)

func _exit_tree() -> void:
    _hitstop_token += 1
    if Engine.time_scale <= 0.0:
        Engine.time_scale = _saved_time_scale
