# Bond Brawler · 项目须知

2.5D 横版清版动作游戏（Castle Crashers 式）。Godot 4.7 / GDScript。
六边形架构：领域层纯 `RefCounted`，引擎只做适配器。

## 先读这三份

1. `docs/ARCHITECTURE.md` —— 依赖方向、上下文边界、**接口契约**
2. `docs/CONVENTIONS.md` —— 命名、缩进、并行开发的目录所有权
3. `ASSET_SPEC.md` —— 素材尺寸、归一化规则、动画帧表
4. `docs/testing.md` —— GdUnit4 用法、断言表、分层纪律

## 常用命令

```bash
# 跑测试（GdUnit4 6.2.2，headless，带文件锁可并发）—— 全量
bash tools/test.sh
# 只跑某个上下文
bash tools/test.sh res://tests/unit/combat

# 架构约束检查
python -I tools/check_architecture.py

# GDScript 静态检查（编辑器 Errors 面板里的那几类噪音警告）
python -I tools/lint_gdscript.py

# 新增脚本后刷新 class_name 缓存（tools/test.sh 已内置）
& "D:\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --import

# 判定盒微调：游戏里按 F4（详见下文「判定盒微调」）
# 跑一段无界面对局，打印血量/位置
& "D:\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tools/sim_check.gd

# 截一张运行画面到 docs/screenshot.png
& "D:\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe" --path . --script res://tools/capture.gd

# 素材：从原始包重建图集清单 / 归一化 / 重新生成 ASSET_SPEC
python tools/build_asset_manifest.py "<Tiny RPG pack>/Characters(100x100)" assets/sprites/characters
python tools/normalize_sprites.py
python -I tools/gen_asset_spec.py
```

## 硬规则（违反即返工）

- 领域层（`src/*/domain/`）不得出现 `Node` / `SceneTree` / `Engine` / `Input` / `Time` / `Area3D` / `CharacterBody3D`。
- 伤害数字只由领域层产生；`Area3D` 只做宽相。
- 新增领域逻辑必须带单元测试，`tools/test.sh` 必须保持退出码 0。
- 数值不得硬编码，放 `data/` 或 `GameConstants`。
- 只在 `src/bootstrap/` 里 `new` 具体实现（`CompositionRoot` 装配，`GameRoot` 消费）。
- **Tab 缩进**。Godot 的 `--import` 会把脚本里的空格缩进自动改回 Tab，用空格等于每次导入都产生一堆无意义 diff。
- 浮点用 `assert_almost_eq`，`Vector2` 分量是 32 位。

## 踩过的坑（别重复踩）

1. **素材留白**：原始图集角色只占 100x100 画布的 20~30 px。必须跑 `normalize_sprites.py`，
   否则角色只有 0.4 m 高。新增角色后要重跑。
2. **Sprite3D offset 方向**：`offset.y` 正方向与世界 Y 同向（向上）。写反角色会整只埋进地面。
3. **背景板 Z**：相机在 +Z 朝 -Z 看，背景板必须在 `LANE_MIN` 之后（`BACKDROP_Z = -4.5`），
   否则整块背景把角色挡住。
4. **Vector2 是 32 位**：和 `float` 常量用 `==` 比较会失败。
5. **测试串行**：多进程同时 `--import` 会打架，统一走 `tools/test.sh`（目录锁）。
6. **GdUnit4 拒绝 headless**：必须加 `--ignoreHeadlessMode`（`tools/test.sh` 已内置）。
   它这么做是因为 headless 下 Godot 不传输 `InputEvent`；我们的测试直接喂
   `LocoInputFrame`，不走真实输入，所以不受影响。
7. **浮点断言**：GdUnit4 的 `is_equal` 对 float 是精确比较，浮点一律用
   `assert_float(x).is_equal_approx(y, eps)`。
8. **分析器警告查不到**：`UNUSED_PARAMETER` / `SHADOWED_VARIABLE` 这类警告只在
   编辑器 Errors 面板里显示，命令行 `--import` 不会打印（脚本缓存没失效就不重编译）。
   所以用 `python -I tools/lint_gdscript.py` 兜底，提交前跑一遍。
9. **类缓存**：删掉 `.godot/` 后直接跑游戏会报一堆 "Identifier XXX not declared"，
   因为 `global_script_class_cache.cfg` 还没生成。先 `--import` 再跑。
10. **贴图锚点不是包围盒中心**：角色几乎都单手持械，刀剑会把包围盒中心拽到武器上
   （knight 偏 0.43 m、skeleton 0.39 m）。`normalize_sprites.py` 取「列高 ≥ 最高列一半」
   的列的中点当水平锚点。锚点偏了，判定盒看起来就往角色正前方错开半个身位。
11. **打开项目左上角只有 Main**：场地和相机是运行时建的，但四个角色槽位
   （`main.tscn` 的 `ActorSlots`）是**预置**在场景里的，`GameRoot` 用 `_take_slot()`
   复用它们。`ActorView` / `SpriteBillboard` 是 `@tool`，编辑器里自己加载 idle 贴图，
   否则打开项目就是一片空白。加角色时两边都要动：`main.tscn` 加槽位 + `ENEMY_CHARACTERS`。
12. **`@tool` 的边界**：编辑器里非 `@tool` 脚本的属性**不可写**（`Invalid assignment`），
   方法也调不了（`placeholder instance`）。所以 `_ready()` 里对 `HitboxAdapter` 的
   `candidate_sink` 赋值必须 `if not Engine.is_editor_hint()` 挡掉。
13. **事件发出来没人接 = 静默空转**：`combat_pipeline` 对 projectile / volley 模板跳过直接伤害，
   指望「弹体命中时再结算」，但当时全项目没有任何地方生成弹体 —— 28 个技能放出去
   既没伤害也没画面。凡是「发事件、等别人处理」的地方，都要有一条契约测试盯着。
14. **`Sprite3D.flip_h` 只翻 UV，不翻四边形**：`offset` 是四边形的平移，翻转时不会跟着镜像。
   所以 `SpriteBillboard` 必须按朝向把 `offset.x` 取反，否则一转身角色就滑到锚点另一侧
   （实测 knight 差 0.85 m）。`test_sprite_billboard.gd::test_offset_mirrors_with_facing` 守着。

## 控制效果语义（踩过坑，别再改回去）

| 状态 | 锁移动 | 锁动作 | 备注 |
|---|---|---|---|
| `root` | ✅（移速 0） | ❌ | 定身只是动不了，刀照挥。锁动作会让「被定住又打不了」变得不可玩 |
| `slow` | 移速 ×0.6 | ❌ | |
| `paralyze` | ✅ | ✅ | 硬控，2.4s |
| `sleep` | ✅ | ✅ | 硬控，3.5s，**挨打必须立刻醒** |

硬直（HURT）四条：
1. 只有真的吃到伤害才进硬直；霸体 / 无敌帧不进。
2. 硬直后 0.35 秒免疫窗口内只吃击退不吃硬直，否则三个敌人能轮流把玩家锁死。
3. **硬直分敌我**：玩家 0.12~0.22 秒（保持操作响应），敌人 0.28~0.36 秒
   （`hurt` 动画 4 帧 @12fps ≈ 0.33 秒，短了动画会被直接截断，看起来像没有受击反应）。
4. 连着挨打要重播受击动画（`ActorView.flash()` 里 `_sprite.restart()`），
   否则 `_last_anim` 已是 hurt，`_update_animation` 会提前返回，动画停在最后一帧。

判定盒（Area3D）四条：
1. 尺寸/位置由 `melee_config()` 的 range / lane_tolerance / hit_height 现算，
   **不许写死在 .tscn 里**——写死过一次，出现 2.67 m 隔空命中。
2. `monitoring` 常开（物理引擎要一帧才填重叠列表），但**形状只在起手+判定帧启用**，
   否则调试视图里会一直挂着一个方框。
3. `HITBOX_MARGIN` 只覆盖浮点误差（0.06），不是「手感余量」，别调大。
4. **中心只由 Area3D 的 position 决定**，形状节点必须留在原点。两处各带一个 y 偏移
   会叠加（0.9 + 0.86 = 1.76），整个盒子浮到头顶，看着完全没对上角色。
   盒子的 y 从脚底起算，margin 只往顶部放，别钻到地板下面。
5. **前伸和判定窗口逐角色**，都从图集算进 manifest（`normalize_sprites.py`）：
   - `melee_reach`：attack1 里武器挥得最远的那一帧，相对身体锚点的米数。
     共用一个 reach 的话，长枪和短斧必然有一个对不上（knight 2.04 / orc 2.14 /
     armored_orc 1.98，差一倍）。
   - `melee_windup` / `melee_active`：武器真正伸出去的那几帧的时间段。
   - 手改表在 `data/melee.json`（可选），优先级：melee.json → manifest → GameConstants。
     F4 调完按 P 打印的 JSON 直接粘进 `characters` 段。
     原来所有角色共用 0.17~0.27 s，很多角色那一段还停在「武器收着」的帧上，
     判定盒就会在武器没挥出去的时候亮着 —— 看起来就是盒子比武器大一圈。

## 判定盒微调（F4）

游戏里按 **F4** 进入微调：战斗冻结，选中的角色**强制显示**攻击盒（不用等出手），
左上角出现数值面板。平时（仅调试构建）左上角常驻一行 `F3 碰撞形状  F4 判定盒微调`。

| 键 | 作用 |
|---|---|
| Tab | 换角色 |
| ← → | 前伸 `range` ±0.05 |
| ↑ ↓ | 纵深 `lane_tolerance` ±0.05 |
| PgUp / PgDn | 高度 `hit_height` ±0.05 |
| `,` `.` | 余量 `margin` ±0.01 |
| P | 打印可粘回 `data/` 的 JSON |
| R | 复位到启动值 |
| F4 | 退出 |

窄相读的是同一份 `melee_config()`，所以调完「看到的范围」就是「打得到的范围」。
调完自动写 `user://melee_tuning.json`，下次启动自动套用（headless 不读，避免污染用例）。

**不要在编辑器里拖 CollisionShape3D**：几何每次 `bind()` 都按参数重算，改了也会被覆盖。

## 当前状态

可运行：组合根装配 → 玩家 + 3 个敌人 → 动作状态机 → 技能相位 → 窄相命中 → 伤害管线 →
打击感反馈（顿帧/震屏/闪白/跳字）→ 波次与存档快照。
387 个测试（GdUnit4，58 个 suite）全绿，架构检查通过。
刷怪表和 AI 性格来自 data/stages.json（StageRepository），缺数据时退回内置兜底表。
HUD 走 presenter + view-model；场景流程（标题/暂停/结算）是纯状态机。
音效走 IAudio 端口 + AudioDirector，占位音效由 tools/gen_placeholder_sfx.py 合成，映射在 assets/audio/cues.json。
存档走 ISaveRepository 端口 + SaveStore（原子写 + 版本信封 + 损坏回退），
业务快照在 SaveService（含版本迁移）；天赋加成由 TalentService 折成 CombatModifier。
其中 4 个是场景端到端（真跑 main.tscn），10 个是领域端到端。

待接入：真实关卡美术与视差背景、音效、联机同步、天赋 UI。
