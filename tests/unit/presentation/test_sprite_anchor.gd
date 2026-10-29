## 贴图身体中轴必须落在角色原点上 —— 那是碰撞胶囊、受击盒、判定盒共同的基准。
##
## 回归：normalize_sprites.py 曾用「包围盒中心」当水平锚点，而这套素材的角色
## 普遍单手持械，刀剑把包围盒中心拽到武器上。knight 差 0.43 m、skeleton 0.39 m、
## armored_orc 0.32 m，画面上就是判定盒整体偏向角色正前方半个身位。
extends GdUnitTestSuite

const MANIFEST_PATH: String = "res://assets/sprites/characters/manifest.json"
const CHAR_DIR: String = "res://assets/sprites/characters"
const IN_PLAY: Array = ["knight", "orc", "skeleton", "armored_orc"]
## 贴图 1 px ≈ 0.09 m，留两个像素的余量。
const TOLERANCE_M: float = 0.20
const ALPHA_MIN: float = 0.03

func before(_do_skip := not FileAccess.file_exists(MANIFEST_PATH),
		_skip_reason := "需要本地 assets/sprites/，见 README「数据与素材」") -> void:
	pass

func test_body_center_maps_to_actor_origin() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	assert_object(manifest).is_not_null()
	for slug: String in IN_PLAY:
		var entry: Dictionary = (manifest["characters"] as Dictionary)[slug]
		var center_x: float = _body_center_world_x(slug, entry)
		assert_float(absf(center_x)).override_failure_message(
				"%s 的身体中轴偏离原点 %.2f m，判定盒会和角色错开" % [slug, center_x]
			).is_less_equal(TOLERANCE_M)

## 躯干中轴换算到世界的 x。规则与 tools/normalize_sprites.py 的 body_anchor_x 一致：
## 列高 >= 最高列一半的列算躯干，武器列又细又矮会被滤掉。
func _body_center_world_x(slug: String, entry: Dictionary) -> float:
	var idle: Dictionary = (entry["animations"] as Dictionary)["idle"]
	var frames: int = int(idle.get("frames", 1))
	var frame_size: Array = idle.get("frame_size", [1, 1])
	var w: int = int(frame_size[0])
	var h: int = int(frame_size[1])
	var pixel_size: float = float(entry.get("pixel_size", 0.0))
	var offset: Array = idle.get("offset", [0.0, 0.0])
	var path: String = CHAR_DIR.path_join(slug).path_join(str(idle.get("file", "")))
	var img: Image = Image.load_from_file(path)
	if img == null or img.get_width() != w * frames or img.get_height() != h:
		return 0.0
	var columns: Array[int] = []
	columns.resize(w)
	columns.fill(0)
	for x: int in range(w):
		var tallest: int = 0
		for f: int in range(frames):
			var n: int = 0
			for y: int in range(h):
				if img.get_pixel(x + f * w, y).a > ALPHA_MIN:
					n += 1
			tallest = maxi(tallest, n)
		columns[x] = tallest
	var peak: int = 0
	for x: int in range(w):
		peak = maxi(peak, columns[x])
	if peak <= 0:
		return 0.0
	var first: int = -1
	var last: int = -1
	for x: int in range(w):
		if columns[x] * 2 >= peak:
			if first < 0:
				first = x
			last = x
	var center_px: float = (float(first) + float(last) + 1.0) * 0.5
	return ((center_px - float(w) * 0.5) + float(offset[0])) * pixel_size
