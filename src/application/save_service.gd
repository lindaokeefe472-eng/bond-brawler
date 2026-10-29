## 存档服务：把「要存什么」和「存到哪」分开。
##
## SaveStore 只管写盘（原子写 + 版本信封 + 损坏回退）；这里只管业务快照
## ——关卡进度、天赋、设置——以及版本迁移。换存储介质不影响上层。
class_name SaveService
extends RefCounted

const SLOT: String = "main"
## 业务快照版本。加字段就 +1，并在 migrate() 里补默认值。
const DTO_VERSION: int = 2

var _repo: ISaveRepository = null

func _init(repo: ISaveRepository = null) -> void:
	_repo = repo

func has_save() -> bool:
	return _repo != null and _repo.has_slot(SLOT)

## 组一份完整快照。三个来源都可能为空（比如还没做关卡），缺了就存默认值。
func build_snapshot(stage: StageProgress, talents: TalentTree, settings: SettingsModel) -> Dictionary:
	return {
		"version": DTO_VERSION,
		"stage": stage.snapshot() if stage != null else {},
		"talents": talents.snapshot() if talents != null else {},
		"settings": _settings_snapshot(settings),
	}

func save(stage: StageProgress, talents: TalentTree, settings: SettingsModel) -> bool:
	if _repo == null:
		return false
	return _repo.save_slot(SLOT, build_snapshot(stage, talents, settings))

## 读档。没有存档、或者存档损坏，都返回空字典 —— 由调用方决定开新档。
func load_snapshot() -> Dictionary:
	if _repo == null or not _repo.has_slot(SLOT):
		return {}
	var raw: Dictionary = _repo.load_slot(SLOT)
	if raw.is_empty():
		return {}
	return migrate(raw)

## 把快照写回各个子系统。缺字段一律保持原样，不覆盖成空。
func apply_snapshot(snapshot: Dictionary, stage: StageProgress, talents: TalentTree,
		settings: SettingsModel) -> void:
	if snapshot.is_empty():
		return
	var raw_stage: Variant = snapshot.get("stage", {})
	if stage != null and raw_stage is Dictionary and not (raw_stage as Dictionary).is_empty():
		stage.restore(raw_stage)
	var raw_talents: Variant = snapshot.get("talents", {})
	if talents != null and raw_talents is Dictionary and not (raw_talents as Dictionary).is_empty():
		talents.restore(raw_talents)
	var raw_settings: Variant = snapshot.get("settings", {})
	if settings != null and raw_settings is Dictionary:
		_apply_settings(raw_settings, settings)

## 旧版本补默认值。v1 只有天赋，没有 stage / settings。
static func migrate(raw: Dictionary) -> Dictionary:
	var out: Dictionary = raw.duplicate(true)
	var version: int = int(out.get("version", 1))
	if version < 2:
		if not out.has("stage"):
			out["stage"] = {}
		if not out.has("settings"):
			out["settings"] = {}
	out["version"] = DTO_VERSION
	return out

static func _settings_snapshot(settings: SettingsModel) -> Dictionary:
	if settings == null:
		return {}
	var volumes: Dictionary = {}
	for channel: StringName in SettingsModel.CHANNELS:
		volumes[String(channel)] = settings.volume(channel)
	return {"volumes": volumes, "language": String(settings.language)}

static func _apply_settings(raw: Dictionary, settings: SettingsModel) -> void:
	var volumes: Variant = raw.get("volumes", {})
	if volumes is Dictionary:
		for channel: StringName in SettingsModel.CHANNELS:
			if (volumes as Dictionary).has(String(channel)):
				settings.set_volume(channel, float((volumes as Dictionary)[String(channel)]))
	var language: Variant = raw.get("language", null)
	if language is String:
		settings.set_language(StringName(language))
