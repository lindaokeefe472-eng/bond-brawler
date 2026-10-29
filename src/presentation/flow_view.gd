## 流程覆盖层：标题 / 暂停 / 结算。
##
## 必须是 PROCESS_MODE_ALWAYS —— 暂停时整棵场景树被冻结，只有 ALWAYS 的节点还能接按键，
## 否则按 Esc 就再也退不出暂停了。
class_name FlowView
extends CanvasLayer

const TITLE_TEXT: String = "BOND BRAWLER"
const DIMMER_COLOR: Color = Color(0.02, 0.02, 0.04, 0.72)

## 由 GameRoot 接上，视图自己不判断业务能不能跳转。
var on_start: Callable = Callable()
var on_toggle_pause: Callable = Callable()
var on_restart: Callable = Callable()
## func(channel: StringName, value: float)，由 GameRoot 接到音频总线上。
var on_volume_changed: Callable = Callable()

var _flow: SceneFlow = null
var _settings: SettingsModel = null
var _dimmer: ColorRect = null
var _title: Label = null
var _hint: Label = null
var _settings_box: HBoxContainer = null
var _volume_sliders: Dictionary = {}   # channel -> HSlider
var _language_label: Label = null

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func bind(flow: SceneFlow) -> void:
	_flow = flow
	render(flow)

## 设置模型接进来。音量现在只存值，音频总线在阶段 3 才建。
func bind_settings(model: SettingsModel) -> void:
	_settings = model
	for channel: StringName in SettingsModel.CHANNELS:
		var slider: HSlider = _volume_sliders.get(channel, null)
		if slider != null:
			slider.set_value_no_signal(model.volume(channel))
	_refresh_language()

## 按当前流程状态切换覆盖层。只渲染，不做状态判断。
func render(flow: SceneFlow) -> void:
	_flow = flow
	if flow == null:
		return
	match flow.state():
		SceneFlow.State.TITLE:
			_show(TITLE_TEXT, "Enter / 空格 开始    L 切换语言")
		SceneFlow.State.PAUSED:
			_show("暂停", "Esc 继续")
		SceneFlow.State.RESULT:
			_show("胜利" if flow.victory() else "战斗结束", "R 重来")
		_:
			_dimmer.visible = false
			_title.text = ""
			_hint.text = ""
	_settings_box.visible = flow.state() == SceneFlow.State.TITLE

func _show(title_text: String, hint_text: String) -> void:
	_dimmer.visible = true
	_title.text = title_text
	_hint.text = hint_text

func _unhandled_input(event: InputEvent) -> void:
	if _flow == null or not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	# 先拿到视口再回调：R 会 reload 场景，回调返回时本节点已经不在树上，
	# 那时 get_viewport() 是 null（Cannot call method on a null value）。
	var viewport: Viewport = get_viewport()
	match key.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if _flow.state() == SceneFlow.State.TITLE and on_start.is_valid():
				_consume(viewport)
				on_start.call()
		KEY_ESCAPE:
			if on_toggle_pause.is_valid():
				_consume(viewport)
				on_toggle_pause.call()
		KEY_R:
			if _flow.is_result() and on_restart.is_valid():
				_consume(viewport)
				on_restart.call()
		KEY_L:
			if _flow.state() == SceneFlow.State.TITLE and _settings != null:
				_settings.cycle_language()
				_refresh_language()
				_consume(viewport)

## 标记事件已处理。视口可能已经不在了（场景被 reload），所以要判空。
func _consume(viewport: Viewport) -> void:
	if viewport != null and is_instance_valid(viewport):
		viewport.set_input_as_handled()

func _build() -> void:
	_dimmer = ColorRect.new()
	_dimmer.name = "Dimmer"
	_dimmer.color = DIMMER_COLOR
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dimmer)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 48)
	box.add_child(_title)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.75))
	box.add_child(_hint)

	_settings_box = HBoxContainer.new()
	_settings_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_settings_box.add_theme_constant_override("separation", 10)
	_settings_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_settings_box)
	for channel: StringName in SettingsModel.CHANNELS:
		var label := Label.new()
		label.text = _channel_label(channel)
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
		_settings_box.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(96.0, 18.0)
		slider.value_changed.connect(func(value: float) -> void:
			if _settings != null:
				_settings.set_volume(channel, value)
			if on_volume_changed.is_valid():
				on_volume_changed.call(channel, value))
		_settings_box.add_child(slider)
		_volume_sliders[channel] = slider
	_language_label = Label.new()
	_language_label.add_theme_font_size_override("font_size", 14)
	_language_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	_settings_box.add_child(_language_label)

func _channel_label(channel: StringName) -> String:
	match channel:
		&"master":
			return "总音量"
		&"sfx":
			return "音效"
		&"bgm":
			return "音乐"
	return str(channel)

func _refresh_language() -> void:
	if _language_label == null or _settings == null:
		return
	_language_label.text = "语言：%s" % _settings.language_label()
