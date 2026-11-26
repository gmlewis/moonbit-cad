#!/usr/bin/env python3
"""Render a STEP file to a four-view *shaded* PNG preview with SolidCraft.

Uses ``solidcraft-cli snapshot`` for each view (headless, no GUI needed) and
Inkscape to composite the four shaded images into one 2x2 sheet.  Everything
it needs is in this repository; no sibling checkout is required.

Requires ``solidcraft-cli`` on PATH and Inkscape.  If Inkscape is missing, the
isometric view alone is written.

Usage:
    python3 scripts/render_solidcraft.py model.step preview.png
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from pathlib import Path

_scripts_dir = Path(__file__).resolve().parent
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

from render_common import (  # noqa: E402
    composite_views,
    copy_iso_fallback,
    find_solidcraft,
    render_solidcraft_view,
)

VIEWS = ["iso", "top", "front", "right"]

LABELS = {
    "iso": "ISOMETRIC",
    "top": "TOP (XY)",
    "front": "FRONT (XZ)",
    "right": "RIGHT (YZ)",
}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render a STEP file to a shaded four-view PNG preview.",
    )
    parser.add_argument("step", help="input STEP file")
    parser.add_argument("png", help="output PNG file")
    parser.add_argument(
        "--width", type=int, default=512, help="width of each view (default 512)"
    )
    parser.add_argument(
        "--height", type=int, default=512, help="height of each view (default 512)"
    )
    args = parser.parse_args()

    step_path = Path(args.step)
    if not step_path.is_file():
        print(f"Error: STEP file not found: {step_path}", file=sys.stderr)
        return 1

    out_path = Path(args.png)
    if not out_path.parent.is_dir():
        print(
            f"Error: output directory does not exist: {out_path.parent}",
            file=sys.stderr,
        )
        return 1

    solidcraft = find_solidcraft()
    if not solidcraft:
        print(
            "Error: solidcraft-cli is not on PATH. "
            "Install SolidCraft to render shaded previews.",
            file=sys.stderr,
        )
        return 1

    with tempfile.TemporaryDirectory() as tmpdir:
        views: dict[str, str] = {}
        for view in VIEWS:
            png_path = Path(tmpdir) / f"{view}.png"
            if not render_solidcraft_view(
                solidcraft,
                step_path,
                png_path,
                view,
                cell_w=args.width,
                cell_h=args.height,
            ):
                print(f"Error: failed to render the {view} view.", file=sys.stderr)
                return 1
            views[view] = str(png_path)

        if composite_views(
            views,
            out_path,
            LABELS,
            cell_w=args.width,
            cell_h=args.height,
        ):
            return 0

        copy_iso_fallback(views, out_path)
        print(
            "Note: compositing failed; wrote the isometric view only "
            "(install Inkscape for the four-view sheet).",
            file=sys.stderr,
        )
        return 0


if __name__ == "__main__":
    sys.exit(main())
