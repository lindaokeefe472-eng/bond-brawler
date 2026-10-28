## 角色图集播放器：一张横排图集 = 一段动画。
##
## 为什么不用 AnimationPlayer：帧数与循环标记都来自 manifest，
## 用 hframes + frame 直接推进既没有额外资源依赖，也能在无场景树的单测里验证循环语义。
class_name SpriteBillboard
extends Sprite3D

## manifest 不提供帧率，这里是唯一的播放速度来源（表现层手感参数）。
const DEFAULT_FPS: float = 12.0
## 归一化前的原始画布边长，仅用于缺数据时的兜底。
const ATLAS_FRAME_SIZE: float = 100.0

var _anim: StringName = &""
var _frames: int = 1
var _fps: float = DEFAULT_FPS
var _loop: bool = true
var _playing: bool = false
var _finished: bool = false
var _elapsed: float = 0.0
var _facing: int = 1
## 每个角色的内容高度不同（16~38 px），所以缩放由 manifest 逐角色给出。
var _pixel_size: float = 1.0 / GameConstants.PIXELS_PER_METER

func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	pixel_size = _pixel_size
	centered = true
	double_sided = true
	# 锚点由 manifest 的 offset 逐动作给出（见 tools/normalize_sprites.py），
	# 这里保持 0，缺数据时角色以帧中心对齐原点。
	offset = Vector2.ZERO
	vframes = 1
	if hframes < 1:
		hframes = 1
	frame = 0
	flip_h = _facing < 0

## 设定角色缩放。参数来自 manifest 的 pixel_size：角色内容高度 / 目标身高（1.8 m）。
func apply_metrics(pixel_size_value: float) -> void:
	if pixel_size_value <= 0.0:
		return
	_pixel_size = pixel_size_value
	pixel_size = pixel_size_value

## 直接播放一张图集纹理。atlas 为 null 时只保留帧表（数据缺失的降级路径）。
func play_atlas(anim_name: StringName, atlas: Texture2D, frames: int, loop: bool,
		fps: float = DEFAULT_FPS) -> void:
	var safe_frames: int = maxi(frames, 1)
	var same: bool = anim_name == _anim and atlas == texture and safe_frames == _frames
	if same:
		# 同一动画每帧都会被调用；重设 frame 会让它永远停在第 0 帧。
		_loop = loop
		return
	_anim = anim_name
	_frames = safe_frames
	_fps = maxf(fps, 0.001)
	_loop = loop
	_elapsed = 0.0
	_playing = true
	_finished = false
	texture = atlas
	vframes = 1
	hframes = safe_frames
	frame = 0
	visible = atlas != null

## 按 manifest 条目播放：{file, frames, loop}。
## 纹理加载失败时保留上一张纹理，只更新帧表，避免角色因为缺一张图就彻底消失。
func play_manifest(anim_name: StringName, data: Dictionary, sprite_dir: String) -> void:
	if data.is_empty():
		return
	var frames: int = int(data.get("frames", 1))
	var loop: bool = bool(data.get("loop", true))
	var atlas: Texture2D = texture
	var file_name: String = str(data.get("file", ""))
	if not file_name.is_empty():
		var path: String = sprite_dir.path_join(file_name)
		if ResourceLoader.exists(path):
			atlas = load(path) as Texture2D
	# 每个动作的包围盒不同，所以锚点也逐动作给出，保证脚底始终钉在原点。
	if data.has("offset"):
		var raw_offset: Variant = data["offset"]
		if raw_offset is Array and (raw_offset as Array).size() >= 2:
			offset = Vector2(float(raw_offset[0]), float(raw_offset[1]))
	play_atlas(anim_name, atlas, frames, loop)

## 推进播放。非循环动画停在最后一帧并置 finished，供死亡淡出等逻辑等待。
func tick(delta: float) -> void:
	if not _playing or _frames <= 1:
		return
	_elapsed += maxf(delta, 0.0)
	var steps: int = int(_elapsed * _fps)
	if steps <= 0:
		return
	_elapsed -= float(steps) / _fps
	var next_frame: int = frame + steps
	if _loop:
		frame = next_frame % _frames
		return
	if next_frame >= _frames - 1:
		frame = _frames - 1
		_playing = false
		_finished = true
	else:
		frame = next_frame

func set_facing(direction: int) -> void:
	_facing = 1 if direction >= 0 else -1
	flip_h = _facing < 0

func set_loop(loop: bool) -> void:
	_loop = loop

func restart() -> void:
	frame = 0
	_elapsed = 0.0
	_playing = true
	_finished = false

## 淡出只改 alpha，保留闪白时的 RGB，避免死亡瞬间又闪回白色。
func set_alpha(alpha: float) -> void:
	var color: Color = modulate
	color.a = clampf(alpha, 0.0, 1.0)
	modulate = color

func current_animation() -> StringName:
	return _anim

func current_frame() -> int:
	return frame

func frame_count() -> int:
	return _frames

func is_finished() -> bool:
	return _finished

func is_playing() -> bool:
	return _playing

func facing() -> int:
	return _facing
