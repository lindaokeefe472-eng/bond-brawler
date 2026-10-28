# 测试规范（testing）

测试框架：**GdUnit4 6.2.2**（`addons/gdUnit4/`），Godot 4.7.1。

## 为什么用 GdUnit4 而不是自己写

自研 runner 能跑，但缺三样东西：失败信息定位、测试场景（`auto_free` / `scene_runner`）、
CI 报告（JUnit XML）。GdUnit4 v6.2.x 官方声明支持 4.7 / 4.7.1，实测 headless 可用。

## 运行

```bash
bash tools/test.sh                                  # 全量
bash tools/test.sh res://tests/unit/combat          # 单目录
bash tools/test.sh res://tests/e2e res://tests/unit # 多目录
```

`tools/test.sh` 内置目录锁：多个进程/agent 同时调用会排队，避免 `reports/` 与
`.godot/` 缓存竞争。**不要**直接调 `GdUnitCmdTool.gd`。

底层命令：

```bash
godot --headless --path . -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
      -a res://tests -c --ignoreHeadlessMode
```

- `-c` 关闭 fail-fast，跑完全部再汇总。
- `--ignoreHeadlessMode` 必须加：GdUnit4 默认拒绝 headless，但我们的测试全部是纯领域逻辑，
  不依赖 `InputEvent` 传输。

报告输出到 `reports/report_N/`（`results.xml` + `index.html`），已加入 `.gitignore`。

## 写测试

```gdscript
extends GdUnitTestSuite

func before_test() -> void:
    ...

func after_test() -> void:
    ...

func test_行为_预期() -> void:
    assert_float(actual).override_failure_message("为什么这条断言重要").is_equal_approx(1.0, 0.001)
```

| 需求 | 断言 |
|---|---|
| 整数相等 | `assert_int(a).is_equal(b)` |
| 浮点相等 | `assert_float(a).is_equal_approx(b, eps)` ← **禁止用 `is_equal` 比浮点** |
| 布尔 | `assert_bool(v).is_true()` / `.is_false()` |
| 非空 | `assert_object(v).is_not_null()` |
| 数组内容 | `assert_array(a).is_equal(b)` / `.contains(v)` |
| 字典键 | `assert_dict(d).contains_key(k)` |
| 区间 | `assert_float(a).is_between(lo, hi)` |
| 大小 | `assert_float(a).is_less(b)` / `.is_greater(b)` |

## 分层

| 层 | 位置 | 约束 |
|---|---|---|
| 单元 | `tests/unit/<context>/` | 纯 GDScript，不加载场景，不依赖 `SceneTree` |
| 领域端到端 | `tests/e2e/test_battle_loop.gd` | 用组合根装配整局，不依赖渲染 |
| **场景端到端** | `tests/e2e/test_scene_boot.gd` | 真的跑 `main.tscn`，验证节点装配、贴图、相机、AI 出手 |

场景端到端用 GdUnit4 的 `scene_runner`：

```gdscript
var runner := scene_runner("res://scenes/main.tscn")
await runner.simulate_frames(40)
assert_int(runner.scene().get("_session").actor_ids().size()).is_equal(4)
```

它补的是领域测试覆盖不到的那一层：节点有没有装对、Sprite3D 有没有贴图、
`pixel_size` 有没有从 manifest 应用、相机有没有生效。

## 两个必须遵守的纪律

1. **一个源文件一个测试文件**：`src/combat/domain/damage_calculator.gd`
   → `tests/unit/combat/test_damage_calculator.gd`。
2. **订阅要退订**：`bus.subscribe(type, func(e): self.xxx(e))` 会形成
   `self -> bus -> lambda -> self` 的引用环，RefCounted 永远不回收。
   在 `after_test()` 里调 `bus.clear()`，或者让 lambda 只捕获 `WeakRef`。

## CI

退出码 0 = 全绿。新增领域逻辑必须伴随测试；改领域逻辑前先跑一遍。
