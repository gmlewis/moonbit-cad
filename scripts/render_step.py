#!/usr/bin/env python3
"""Render a STEP file to a four-view PNG preview.

This is the single-file companion to the shaded SolidCraft previewer
(``render_solidcraft.py``).  It renders isometric, top, front and side views
with OCCT ``DRAWEXE`` and composites them with Inkscape.  Everything it needs
is in this repository; no sibling checkout is required.

Requires OCCT (``occt-draw`` or ``DRAWEXE``), Inkscape, and either macOS
``sips`` or ImageMagick (``magick``/``convert``) to convert PPM to PNG.

Usage:
    python3 scripts/render_step.py model.step preview.png
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
    find_occt,
    render_occt_view,
)

VIEWS = [
    ("iso", "vviewparams -proj 1 -1 1 -up 0 0 1"),
    ("top", "vtop"),
    ("front", "vfront"),
    ("right", "vleft"),
]

LABELS = {
    "iso": "ISOMETRIC",
    "top": "TOP (XY)",
    "front": "FRONT (XZ)",
    "right": "SIDE (YZ)",
}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Render a STEP file to a four-view PNG preview.",
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

    occt = find_occt()
    if not occt:
        print(
            "Error: neither occt-draw nor DRAWEXE is on PATH. "
            "Install OpenCASCADE to render previews.",
            file=sys.stderr,
        )
        return 1

    with tempfile.TemporaryDirectory() as tmpdir:
        views: dict[str, str] = {}
        for suffix, view_cmd in VIEWS:
            png_path = Path(tmpdir) / f"{suffix}.png"
            if not render_occt_view(
                occt,
                step_path,
                png_path,
                view_cmd,
                cell_w=args.width,
                cell_h=args.height,
            ):
                print(f"Error: failed to render the {suffix} view.", file=sys.stderr)
                return 1
            views[suffix] = str(png_path)

        if composite_views(
            views,
            out_path,
            LABELS,
            cell_w=args.width,
            cell_h=args.height,
        ):
            return 0

        # No compositor: still produce a useful preview.
        copy_iso_fallback(views, out_path)
        print(
            "Note: compositing failed; wrote the isometric view only "
            "(install Inkscape for the four-view sheet).",
            file=sys.stderr,
        )
        return 0


if __name__ == "__main__":
    sys.exit(main())
