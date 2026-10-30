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
# 训练场：标题界面按 T，或直接跑这个场景
& "D:\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe" --path . res://scenes/training.tscn
# 跑一段无界面对局，打印血量/位置
& "D:\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tools/sim_check.gd

# 截一张运行画面到 docs/screenshot.png
& "D:\Godot\4.7.1\Godot_v4.7.1-stable_win64_console.exe" --path . --script res://tools/capture.gd

# 素材：从原始包重建图集清单 / 归一化 / 重新生成 ASSET_SPEC
# 角色图和弹体图一起出（弹体在 pack 根目录的 Arrow/Magic(Projectile) 里）
python tools/build_asset_manifest.py "<Tiny RPG pack>/Characters(100x100)" assets/sprites/characters
python tools/normalize_sprites.py
# 只重算逐段判定数据（窗口 / 绕身判别），不重新裁剪图集
python tools/normalize_sprites.py --measure
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
15. **素材包的后缀不统一，而且大小写混用**：`Attack`（Priest / Skeleton Archer，没有编号）、
   `Attack3`（Swordsman，没有前导零）、`DEATH`（Wizard，全大写）、`Walk01`（Lancer /
   Knight Templar）。`build_asset_manifest.py` 原来只精确匹配 `Attack01/02/03`，
   这 6 个文件被整段丢掉 —— 表现是「牧师和骷髅弓手攻击时站着不动、枪兵走路滑行、
   法师死亡弹成受击帧」。现在后缀表统一转小写再做别名，`test_sprite_manifest.gd`
   盯着「每个角色都必须有 idle/walk/attack1/hurt/death」。
16. **归一化按包围盒高度会把长武器角色压小**：lancer 的包围盒 38 px 里有 14 px 是竖直
   举着的长枪，躯干只有 24 px，按包围盒算出来身高 1.14 m，比别人矮一大截（画面上就是
   「骑兵没长开」）。`normalize_sprites.py` 现在只在「躯干 < 包围盒 80%」时才改用躯干高度，
   普通角色口径完全不变 —— 实测只影响 lancer 和 armored_skeleton 两个。

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

动作状态机六条（`loco_action_machine.gd`，改之前先读）：
1. **输入按渲染帧锁存**，不能在逻辑步里直接读 `is_action_just_pressed`：固定步长下
   逻辑步一帧跑 0 次（高刷新率）或多次（追赶），顿帧 `time_scale=0` 时更是完全不跑，
   按下会整个消失。`InputAdapter.capture()` 在物理帧开头采一次，`_process` 在本帧
   没跑物理步时补采一次；`poll()` 消费并清空。物理帧采过就不能再采，`just_pressed`
   整帧为真，会重复触发。
2. **输入仲裁：优先级决定顺序，不决定生死。** 本帧没被消费的按下自动转入 `_pending`
   （最多保留 `PENDING_WINDOW` = 0.8 秒，要盖住最长的一套攻击），解锁后按
   攻击 > 跳跃 > 冲刺 依次兑现。同一帧按攻击+跳跃 = 先攻击、打完再跳，不会丢。
   技能不进这个队列（有独立槽位，且受状态门限制）。
3. **攻击连段是计数队列** `_combo_queue`：攻击期间每按一下加一（上限是剩余段数），
   恢复段一开始消费一段 —— 连按三下就打三段，不是「有/没有」。恢复段还可以用冲刺取消。
   0.29~0.46 秒的后摇不可取消会让每一次挥空都像卡住。
4. **技能只能在可行动状态起手**（IDLE/RUN/LAND/JUMP/FALL）。攻击/冲刺/受击/施法中
   一律拒绝，硬直还会 `caster.interrupt(&"hitstun")`。否则能在硬直里放技能，
   还能把自己攻击的判定帧取消掉。
5. **格挡只在地面可行动状态生效**，攻击/冲刺/受击中按住不白嫖减伤（耐力消耗尚未实现）。
6. **场地边界用 `PlaneMath.clamp_arena`**：横向夹到 `ARENA_HALF_WIDTH - BODY_RADIUS`，
   纵深夹到 lane 带。只夹 lane 玩家会一路走出场地。空中死亡继续受重力落地，不能悬空。
   攻击起手那一帧不继承跑动速度（否则会先滑出 0.1 m）。

判定盒（Area3D）四条：
1. 尺寸/位置由 `melee_config()` 的 range / lane_tolerance / hit_height 现算，
   **不许写死在 .tscn 里**——写死过一次，出现 2.67 m 隔空命中。
2. `monitoring` 常开（物理引擎要一帧才填重叠列表），但**形状只在起手+判定帧启用**，
   否则调试视图里会一直挂着一个方框。
3. `HITBOX_MARGIN` 只覆盖浮点误差（0.06），不是「手感余量」，别调大。
4. **中心只由 Area3D 的 position 决定**，形状节点必须留在原点。两处各带一个 y 偏移
   会叠加（0.9 + 0.86 = 1.76），整个盒子浮到头顶，看着完全没对上角色。
   盒子的 y 从脚底起算，margin 只往顶部放，别钻到地板下面。
5. **整个 ACTIVE 窗口每帧都在判**，不是只在「进入 ACTIVE」那一帧。
   判定帧有十来帧，目标晚两帧走进盒子却一滴血不掉，是最难查的一类手感问题。
   同一目标一次挥击只吃一次，靠 `ActorRuntime._attack_hit_ids` 去重
   （`test_melee_window.gd` 盯着）。
6. **技能射程也要换算**。数据里的 `range` 是原游戏尺度，必须乘 `MELEE_RANGE_SCALE`
   换算到本项目（角色统一 1.8 m）。之前只有普攻换了，技能直接用原始值 ——
   一个写着「近战」的技能能隔 4.3 米瞬发打人，`hydro` 更能打到 17 米外。
   瞬发技能（没有弹体）还要夹到 `SKILL_INSTANT_REACH_CAP`：没有可见弹道却打得到
   六七米外，玩家只会觉得「隔空挨打」。有弹道的弹体技能只换算、不夹取。
7. **前伸和判定窗口逐角色**，都从图集算进 manifest（`normalize_sprites.py`）：
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

**调 range 会写进「当前这一段」的 reach**：三段连击各有各的前伸，`attack_config()`
用逐段 `reach` 盖掉基础 `range`。只改基础值的话判定盒原地不动，F4 等于白调。
复位（R）会同时还原基础值和每一段的 reach。存档里写的是 `reach`、运行时叫 `range`，
`set_melee_param` 负责换算 —— 两个键互通，别在一处只改一个。

**不要在编辑器里拖 CollisionShape3D**：几何每次 `bind()` 都按参数重算，改了也会被覆盖。

## 普攻形态（近战 / 远程）

`data/melee.json` 里 `attack = "projectile"` 的角色，普攻不做扇形判定，而是在 ACTIVE
首帧发一发弹体 —— 弓手、骷髅弓手、法师、牧师。参数看 `projectile` 段
（speed 米/秒、range 米、radius 命中半径）。

- 唯一判断口是 `ActorRuntime.is_ranged_attack()`；`BattleSession._resolve_hits` 据此二选一，
  近战那条路完全不受影响（`test_ranged_basic_attack.gd` 两边都盯着）。
- 弹体和技能弹体走同一条流水线，所以命中结算、顿帧、跳字、音效全都自动复用。
- 训练场面板对这类角色显示的是**弹体射程**，判定谓词也换成
  「正前方 + 射程内 + 横向偏移 < 命中半径 + 身位半径」。
- 弹体贴图来自素材包（`assets/sprites/projectiles/`，manifest 的 `projectiles` 段），
  由 `projectile.sprite` 指定 slug。没指定或素材缺失时退回按属性上色的方块。
  多帧特效（法术）按 12 fps 循环，单帧的箭不动；朝向由速度方向决定。

**`data/` 不随仓库分发**，新克隆的仓库里所有角色都会退回近战 —— 这是预期行为，
远程配置在本地 `data/melee.json`（`test_melee_data.gd` 校验字段）。

## 逐段普攻（atk1 / atk2 / atk3 各打各的）

三段连击以前共用第 1 段的参数：前伸、时序、判定形状全都一样，动作播的却是不同的
挥砍 —— 长枪第三段看着是横扫，判定还是第一段那一下。现在每段可以不同：

- **参数来源**：manifest 的 `attacks[step]`（图集量出来的 `reach` / `windup` / `active` /
  `back` / `sweep`）← `data/melee.json` 的 `attacks[step]` 覆盖（`kind` / `radius` /
  `projectile`）。合并后进 spec 的 `melee.attacks`，`GameRoot._attack_steps()` 负责。
- **唯一读取口**：`ActorRuntime.attack_config(step)`（`step <= 0` 取当前段），
  基础 `melee_config()` + 逐段覆盖，`reach` 在这里换算成 `range`。
- **形态 `kind`**：`melee`（扇形，`PlaneMath.in_cone`）/ `aoe`（绕身半径，身后也吃）/
  `ranged`（发弹体）。逐段 `kind` > 角色级 `attack = "projectile"` > `melee`。
  `CombatPipeline.resolve_basic_attack()` 按 `kind` 分派，`ActorView` 的判定盒也跟着变
  （范围段画成以角色为中心的方盒，远程段只标出手点）。
- **「哪一段是范围」由图集量，不许手猜**：`normalize_sprites.py` 的 `attack_sweep()`
  取挥击峰（前伸最大那帧）**之后**武器向后伸得最远的米数；≥ 1.5 m 且 ≥ 峰值的 60%
  才判绕身。只看峰值之后是因为蓄力时武器也举在身后（greatsword 2.11 m），那不是横扫。
  实测只有 4 段成立：armored_axeman 2 / armored_skeleton 2 / elite_orc 2 / orc_rider 3。
  **别按「第 3 段一般是范围」手填** —— 之前就是这么错的（knight / greatsword 三段都不是）。
  改了判别规则后跑 `python tools/normalize_sprites.py --measure` 回填 manifest，
  不用重跑整条素材流水线（`main()` 会就地裁剪图集，只能对原始素材跑一次）。
- **动作机**：`attack_windup` / `attack_active` 本来就是数组，按下标取当前段。
- `data/melee.json` 里 `attacks` 的 `kind` / `radius` 由 `test_melee_data.gd` 校验；
  合并逻辑和三种形态的判定由 `test_attack_shapes.gd` 盯着，逐角色形态由
  `test_training_mode.gd::test_attack_step_shapes_match_the_art` 盯着。

## 训练场（`scenes/training.tscn`）

标题界面按 **T** 进入，也可以直接跑这个场景。一个可换角色的玩家 + 一个站桩靶子。

| 键 | 作用 |
|---|---|
| Q / E | 玩家角色 上一个 / 下一个（素材清单里的 20 个全在） |
| Z / C | 站桩角色 上一个 / 下一个 |
| `[` `]` | 站桩沿 x 挪远 / 挪近 0.1 m |
| `;` `'` | 站桩沿纵深挪 0.1 m |
| G | 站桩归位 |
| H | 清空「上次命中 / 累计伤害 / 命中次数」 |
| Esc | 暂停（暂停界面按 T 回主菜单） |

面板上三行是关键数据：**距离**、**判定**（和窄相同一个 `PlaneMath.in_cone`，
它说「打得到」就一定打得到）、**上次命中距离**。核对「这个角色到底能打多远」时看后两个。

实现上的三条契约（改之前先读 `training_root.gd` 的类注释）：
1. 站桩**不传 brain_profile**（`null`），`BattleSession._run_ai` 会整只跳过它 —— 不移动、不还手。
2. 站桩每帧被 `_pin_dummy()` 钉回指定坐标，击退和推挤都推不走，量出来的距离才稳定。
3. 靶子 2000 血 + 停手 1.5 秒回满（按**领域时钟** `_session.time()` 计时，
   不按 `_process` 的 delta —— headless 下 delta 接近 0，按它算会得到不可复现的结果）。

换角色是**重建 ActorRuntime**，不是换贴图：前伸、判定窗口、图集路径都是建号时算进 spec 的。
重建时必须同时清掉 `_views` / `FeedbackDirector` / `HitboxTuner` 里的旧登记，
`HitboxTuner.unregister()` 就是干这个的。

## 当前状态

可运行：组合根装配 → 玩家 + 3 个敌人 → 动作状态机 → 技能相位 → 窄相命中 → 伤害管线 →
打击感反馈（顿帧/震屏/闪白/跳字）→ 波次与存档快照。
453 个测试（GdUnit4，67 个 suite）全绿，架构检查通过。
刷怪表和 AI 性格来自 data/stages.json（StageRepository），缺数据时退回内置兜底表。
训练场是独立场景（TrainingRoot 继承 GameRoot，只重写刷怪），用来量命中范围与伤害。
HUD 走 presenter + view-model；场景流程（标题/暂停/结算）是纯状态机。
音效走 IAudio 端口 + AudioDirector，占位音效由 tools/gen_placeholder_sfx.py 合成，映射在 assets/audio/cues.json。
存档走 ISaveRepository 端口 + SaveStore（原子写 + 版本信封 + 损坏回退），
业务快照在 SaveService（含版本迁移）；天赋加成由 TalentService 折成 CombatModifier。
其中 4 个是场景端到端（真跑 main.tscn），10 个是领域端到端。

待接入：真实关卡美术与视差背景、音效、联机同步、天赋 UI。
