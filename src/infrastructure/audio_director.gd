## 音效适配器：建总线、管播放器池、防叠音。
##
## 只认 IAudio 的契约和 AudioLibrary 的数据，不碰任何战斗逻辑 ——
## 换音效资源或改并发上限都不用动上层。
class_name AudioDirector
extends IAudio

## 全局播放器上限。超了就不再分配，避免刷屏技能把混音器打爆。
const MAX_VOICES: int = 24
const MIN_DB: float = -60.0

var _library: AudioLibrary = null
## 播放器要挂到场景树上才会被音频服务器处理；测试里传 null 只验逻辑。
var _root: Node = null
var _streams: Dictionary = {}      # cue -> AudioStream
var _players: Array[AudioStreamPlayer] = []
var _bus_index: Dictionary = {}    # bus name -> AudioServer bus index
var _last_played: Dictionary = {}  # cue -> 上次播放的时间戳
var _time: float = 0.0
var _plays: int = 0
var _debounced: int = 0

func configure(library: AudioLibrary, root: Node = null) -> void:
	_library = library
	_root = root
	_ensure_buses()
	_streams.clear()

## 建总线。已经存在的同名总线直接复用，避免热重载时重复添加。
func _ensure_buses() -> void:
	if _library == null:
		return
	for bus_name: StringName in _library.buses():
		_bus_index[bus_name] = _ensure_bus(bus_name)

func _ensure_bus(bus_name: StringName) -> int:
	var existing: int = AudioServer.get_bus_index(String(bus_name))
	if existing >= 0:
		return existing
	var index: int = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, String(bus_name))
	AudioServer.set_bus_send(index, "Master")
	return index

func play(cue: StringName, _position: Vector2 = Vector2.ZERO) -> void:
	if _library == null or not _library.has_cue(cue):
		return
	var entry: Dictionary = _library.cue(cue)
	if not _accept(cue, entry):
		_debounced += 1
		return
	var player: AudioStreamPlayer = _acquire()
	if player == null:
		return
	var stream: AudioStream = _stream_for(cue, entry)
	if stream == null:
		return
	player.stream = stream
	player.bus = str(entry.get("bus", AudioLibrary.DEFAULT_BUS))
	player.volume_db = float(entry.get("volume_db", 0.0))
	var jitter: float = maxf(float(entry.get("pitch_jitter", 0.0)), 0.0)
	player.pitch_scale = 1.0 if jitter <= 0.0 else 1.0 + randf_range(-jitter, jitter)
	player.play()
	_last_played[cue] = _time
	_plays += 1

## 防叠音：同一 cue 在 debounce 窗口内只放一次。
func _accept(cue: StringName, entry: Dictionary) -> bool:
	var debounce: float = maxf(float(entry.get("debounce", 0.0)), 0.0)
	if debounce <= 0.0 or not _last_played.has(cue):
		return true
	return _time - float(_last_played[cue]) >= debounce

func _stream_for(cue: StringName, entry: Dictionary) -> AudioStream:
	if _streams.has(cue):
		return _streams[cue] as AudioStream
	var path: String = str(entry.get("file", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	# CACHE_MODE_IGNORE：我们自己缓存到 _streams 就够了，
	# 交给引擎缓存会在退出时留下「resources still in use」告警。
	var stream: AudioStream = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
	if stream != null:
		_streams[cue] = stream
	return stream

func _acquire() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _players:
		if not player.playing:
			return player
	if _players.size() >= MAX_VOICES:
		return null
	var created := AudioStreamPlayer.new()
	created.name = "Voice%d" % _players.size()
	if _root != null:
		_root.add_child(created)
	_players.append(created)
	return created

func set_bus_volume(bus_name: StringName, value: float) -> void:
	var index: int = int(_bus_index.get(bus_name, -1))
	if index < 0:
		index = _ensure_bus(bus_name)
		_bus_index[bus_name] = index
	var linear: float = clampf(value, 0.0, 1.0)
	AudioServer.set_bus_volume_db(index, MIN_DB if linear <= 0.0 else linear_to_db(linear))

func active_voices() -> int:
	var count: int = 0
	for player: AudioStreamPlayer in _players:
		if player.playing:
			count += 1
	return count

func play_count() -> int:
	return _plays

func debounce_count() -> int:
	return _debounced

## 推进内部时钟。debounce 用它算间隔；由 GameRoot 每帧调用。
func tick(delta: float) -> void:
	_time += maxf(delta, 0.0)

## 释放池里的播放器（测试清理用）。
func dispose() -> void:
	for player: AudioStreamPlayer in _players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
			# 退出时用 free() 而不是 queue_free()：延迟释放赶不上资源检查。
			player.free()
	_players.clear()
	_streams.clear()
