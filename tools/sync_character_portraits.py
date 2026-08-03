#!/usr/bin/env python3
"""Copy pre-keyed character portraits into the Godot project."""

from __future__ import annotations

import shutil
from pathlib import Path

SRC_DIR = Path(__file__).resolve().parents[1] / "2D_Assets" / "Characters"
DST_DIR = Path(__file__).resolve().parents[1] / "godot" / "assets" / "characters"

IMPORT_TEMPLATE = """[remap]

importer="texture"
type="CompressedTexture2D"
uid="{uid}"
path="res://.godot/imported/{filename}-{hash}.ctex"
metadata={{
"vram_texture": false
}}

[deps]

source_file="res://assets/characters/{filename}"
dest_files=["res://.godot/imported/{filename}-{hash}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
"""

UIDS = {
	"pig": "uid://econcharpig01",
	"donkey": "uid://econchardonkey",
	"hen": "uid://econcharhen001",
	"horse": "uid://econcharhorse",
	"goat": "uid://econchargoat01",
	"sheep": "uid://econcharsheep",
}


def main() -> None:
	DST_DIR.mkdir(parents=True, exist_ok=True)
	for src in sorted(SRC_DIR.glob("*.png")):
		name = src.stem.lower()
		dst = DST_DIR / f"{name}.png"
		shutil.copy2(src, dst)
		import_path = dst.with_suffix(dst.suffix + ".import")
		filename = f"{name}.png"
		content = IMPORT_TEMPLATE.format(
			uid=UIDS.get(name, f"uid://econchar{name}"),
			filename=filename,
			hash=name,
		)
		import_path.write_text(content, encoding="utf-8")
		print(f"synced {src.name} -> {dst}")


if __name__ == "__main__":
	main()
