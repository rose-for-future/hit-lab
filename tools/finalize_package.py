#!/usr/bin/env python3
"""Package a finalized XHS text-image post into 发布包/<date>_<slug>/."""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif"}


def slugify(value: str) -> str:
    value = re.sub(r"\.[^.]+$", "", value)
    value = re.sub(r"^\d{4}-?\d{2}-?\d{2}[_-]?", "", value)
    value = re.sub(r"[^0-9A-Za-z\u4e00-\u9fff]+", "-", value).strip("-")
    return value[:80] or "post"


def date_from_path(draft: Path) -> str:
    text = f"{draft.parent.name} {draft.name}"
    match = re.search(r"(20\d{2})[-_]?(\d{2})[-_]?(\d{2})", text)
    if match:
        return "-".join(match.groups())
    return datetime.now().strftime("%Y-%m-%d")


def collect_images(folder: Path) -> list[Path]:
    return sorted(
        [p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXTS],
        key=lambda p: p.name.lower(),
    )


def copy_images(images: list[Path], dest: Path) -> list[Path]:
    dest.mkdir(parents=True, exist_ok=True)
    copied: list[Path] = []
    for idx, image in enumerate(images, start=1):
        clean_name = re.sub(r"^\d+[-_ ]*", "", image.name)
        target = dest / f"{idx:02d}-{clean_name}"
        shutil.copy2(image, target)
        copied.append(target)
    return copied


def render_manifest(
    package_dir: Path,
    draft: Path,
    post: Path,
    images: list[Path],
    image_count_warning: bool,
) -> str:
    rel_images = [p.relative_to(package_dir).as_posix() for p in images]
    image_lines = "\n".join(f"- `{item}`" for item in rel_images) or "- （无）"
    warning = "\n- 警告：图片少于 3 张，不满足当前小红书项目规则。\n" if image_count_warning else ""
    return f"""# 发布包

- 状态：ready_to_publish
- 平台：小红书
- 创建时间：{datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
- 来源稿：`{draft.as_posix()}`
- 正文：`{post.relative_to(package_dir).as_posix()}`
- 图片数量：{len(images)}
- 正文限制：1000 字以下
- 最少图片：3 张
{warning}
## 图片清单

{image_lines}

## 发布登记

- published_url：
- note_id：
- published_at：

## 复盘登记

- retro_due_at：
- report_path：
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a 发布包 from one finalized XHS draft.")
    parser.add_argument("draft", help="Path to the finalized Markdown draft.")
    parser.add_argument("--out-root", default="发布包", help="Output root directory. Default: 发布包")
    parser.add_argument("--overwrite", action="store_true", help="Overwrite an existing package directory.")
    args = parser.parse_args()

    project_root = Path.cwd()
    draft = Path(args.draft).expanduser()
    if not draft.is_absolute():
        draft = project_root / draft
    draft = draft.resolve()

    if not draft.is_file():
        print(f"error: draft not found: {draft}", file=sys.stderr)
        return 2
    if draft.suffix.lower() not in {".md", ".markdown", ".txt"}:
        print(f"error: draft must be markdown or text: {draft}", file=sys.stderr)
        return 2

    images = collect_images(draft.parent)
    if not images:
        print(f"error: no sibling images found in {draft.parent}", file=sys.stderr)
        return 3

    package_name = f"{date_from_path(draft)}_{slugify(draft.name)}"
    package_dir = (project_root / args.out_root / package_name).resolve()
    if package_dir.exists() and not args.overwrite:
        print(f"error: package already exists: {package_dir}", file=sys.stderr)
        print("rerun with --overwrite if this is intentional", file=sys.stderr)
        return 4
    if package_dir.exists():
        shutil.rmtree(package_dir)

    image_dir = package_dir / "images"
    package_dir.mkdir(parents=True, exist_ok=True)

    post = package_dir / "post.md"
    shutil.copy2(draft, post)
    copied_images = copy_images(images, image_dir)

    manifest = render_manifest(
        package_dir=package_dir,
        draft=draft,
        post=post,
        images=copied_images,
        image_count_warning=len(copied_images) < 3,
    )
    (package_dir / "manifest.md").write_text(manifest, encoding="utf-8")

    print(f"package: {package_dir}")
    print(f"post: {post}")
    print(f"images: {len(copied_images)}")
    if len(copied_images) < 3:
        print("warning: fewer than 3 images; current XHS profile expects at least 3")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
