## 设置模型：音量与语言。
##
## 现在只是把值存住：音频总线在阶段 3 才建，本地化在阶段 6 才接 TranslationServer。
## 先有模型和 UI，后面接实现时不用再动界面。
class_name SettingsModel
extends RefCounted

const LANGUAGES: Array[StringName] = [&"zh", &"en"]
const CHANNELS: Array[StringName] = [&"master", &"sfx", &"bgm"]

var language: StringName = &"zh"

var _volumes: Dictionary = {
	&"master": 0.8,
	&"sfx": 0.8,
	&"bgm": 0.6,
}

func volume(channel: StringName) -> float:
	return float(_volumes.get(channel, 0.0))

func set_volume(channel: StringName, value: float) -> void:
	if not _volumes.has(channel):
		return
	_volumes[channel] = clampf(value, 0.0, 1.0)

## 语言名给 UI 用。真接 TranslationServer 时换成 tr() 的 key。
func language_label() -> String:
	match language:
		&"en":
			return "English"
	return "中文"

func set_language(code: StringName) -> bool:
	if not LANGUAGES.has(code):
		return false
	language = code
	return true

func cycle_language() -> StringName:
	var index: int = LANGUAGES.find(language)
	language = LANGUAGES[(index + 1) % LANGUAGES.size()]
	return language
