# -*- coding: utf-8 -*-
"""从 Tiny RPG Character Asset Pack 抽取角色图集与弹体图，规范化命名并生成清单。

用法:
    python tools/build_asset_manifest.py "<pack>/Characters(100x100)" assets/sprites/characters

产出:
    assets/sprites/characters/<slug>/<slug>_<action>.png
    assets/sprites/characters/manifest.json
    assets/sprites/projectiles/<slug>.png

弹体素材在 pack 根目录的 Arrow(Projectile) / Magic(Projectile) 里，
和角色图集是兄弟目录 —— 所以这里从角色目录往上找。
"""
import json
import os
import shutil
import struct
import sys

FRAME = 100  # 图集单帧边长（像素）

# 后缀（小写） -> 动作名。值为 None 表示「认得，但本项目暂时不用」。
#
# 这套素材包的后缀并不统一，而且大小写混用：
#   Priest / Skeleton Archer 的攻击叫 "Attack"（没有编号）
#   Swordsman 的第三段叫 "Attack3"（没有前导零）
#   Wizard 的死亡叫 "DEATH"（全大写）
#   Knight Templar / Lancer 有两套步态 "Walk01" / "Walk02"
# 原来只精确匹配 Attack01/02/03 且区分大小写，这 6 个动作被整段丢掉：
# 表现就是「牧师和骷髅弓手攻击时站着不动、枪兵和圣殿骑士走路时不动、
# 法师死亡直接弹成受击帧」。
SUFFIX_MAP = {
    "idle": "idle",
    "walk": "walk",
    "walk01": "walk",
    "walk02": None,
    "attack": "attack1",
    "attack01": "attack1",
    "attack02": "attack2",
    "attack03": "attack3",
    "attack3": "attack3",
    "block": "block",
    "hurt": "hurt",
    "death": "death",
    "heal": None,
}

# 弹体图：(pack 内相对路径, slug)。相对的是 pack 根目录（角色目录的上一级）。
PROJECTILE_SOURCES = [
    ("Arrow(Projectile)/Arrow01(100x100).png", "arrow01"),
    ("Arrow(Projectile)/Arrow02(100x100).png", "arrow02"),
    ("Arrow(Projectile)/Arrow03(100x100).png", "arrow03"),
    ("Magic(Projectile)/Priest-Attack_effect.png", "priest_attack"),
    ("Magic(Projectile)/Priest-Heal_Effect.png", "priest_heal"),
    ("Magic(Projectile)/Wizard-Attack01_Effect.png", "wizard_attack01"),
    ("Magic(Projectile)/Wizard-Attack02_Effect.png", "wizard_attack02"),
]


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(26)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a png: %s" % path)
    w, h = struct.unpack(">II", head[16:24])
    return w, h


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    pack_root = sys.argv[1]
    out_dir = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    manifest = {"frame_size": FRAME, "characters": {}}
    for name in sorted(os.listdir(pack_root)):
        char_dir = os.path.join(pack_root, name, name)
        if not os.path.isdir(char_dir):
            continue
        slug = name.lower().replace(" ", "_")
        dest = os.path.join(out_dir, slug)
        os.makedirs(dest, exist_ok=True)
        entry = {"display_name": name, "animations": {}, "shadow": None}

        for fname in sorted(os.listdir(char_dir)):
            if not fname.lower().endswith(".png"):
                continue
            stem = fname[:-4]
            prefix = name + "-"
            if not stem.startswith(prefix):
                continue
            suffix = stem[len(prefix):]
            key = suffix.strip().lower()
            if key not in SUFFIX_MAP:
                continue
            action = SUFFIX_MAP[key]
            if action is None:
                continue
            src = os.path.join(char_dir, fname)
            w, h = png_size(src)
            target_name = "%s_%s.png" % (slug, action)
            shutil.copyfile(src, os.path.join(dest, target_name))
            entry["animations"][action] = {
                "file": target_name,
                "frames": w // FRAME,
                "frame_size": FRAME,
                "loop": action in ("idle", "walk", "block"),
            }

        shadow_dir = os.path.join(char_dir, "Shadow sprites")
        if os.path.isdir(shadow_dir):
            for fname in sorted(os.listdir(shadow_dir)):
                if fname.lower().endswith(".png") and "Shadow" in fname and "death" not in fname.lower():
                    target_name = "%s_shadow.png" % slug
                    shutil.copyfile(os.path.join(shadow_dir, fname), os.path.join(dest, target_name))
                    entry["shadow"] = target_name
                    break

        if entry["animations"]:
            manifest["characters"][slug] = entry

    _copy_projectiles(os.path.dirname(os.path.abspath(pack_root)), out_dir, manifest)

    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)

    print("characters:", len(manifest["characters"]))
    for slug, e in manifest["characters"].items():
        print("  %-10s %s" % (slug, ", ".join("%s x%d" % (k, v["frames"]) for k, v in e["animations"].items())))
    return 0


def _copy_projectiles(pack_parent, out_dir, manifest):
    """把弹体图拷到 assets/sprites/projectiles/，并在清单里登记。

    之前这里只有角色，弹体在表现层被画成一个白方块 —— 素材包里其实有箭和法术特效。
    用 100x100 的版本：32x32 是同一张图的缩小版，内容像素完全一样，
    统一按 100 画布切帧，normalize_sprites.py 才能用同一套 load_frames。
    """
    dest_dir = os.path.join(os.path.dirname(os.path.abspath(out_dir)), "projectiles")
    os.makedirs(dest_dir, exist_ok=True)
    entries = {}
    for rel, slug in PROJECTILE_SOURCES:
        src = os.path.join(pack_parent, rel.replace("/", os.sep))
        if not os.path.isfile(src):
            print("  ! 缺少弹体素材: %s" % src)
            continue
        width, _height = png_size(src)
        target = "%s.png" % slug
        shutil.copyfile(src, os.path.join(dest_dir, target))
        entries[slug] = {
            "file": target,
            "frames": max(1, width // FRAME),
            "loop": True,
        }
    manifest["projectiles"] = entries
    print("projectiles:", len(entries))
    for slug, e in entries.items():
        print("  %-18s x%d" % (slug, e["frames"]))


if __name__ == "__main__":
    sys.exit(main())
