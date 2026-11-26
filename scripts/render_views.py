#!/usr/bin/env python3
"""Render a build package's multi-angle contact sheet with SolidCraft.

Given a build directory containing ``assembly.step`` (and an optional
``exploded.step``), write:

    <build_dir>/views/iso.png
    <build_dir>/views/front.png
    <build_dir>/views/left.png
    <build_dir>/views/top.png
    <build_dir>/views/exploded.png

The images are referenced by ``START-HERE.html``'s "Visual overview" gallery.
If ``solidcraft-cli`` is not on PATH, the script prints a warning and succeeds,
so a build without SolidCraft still completes.

Usage:
    python3 scripts/render_views.py build/08
    python3 scripts/render_views.py build/08 --width 1280 --height 960
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ORTHO_VIEWS = ["iso", "front", "left", "top"]


def find_solidcraft() -> str | None:
    return shutil.which("solidcraft-cli")


def render(
    tool: str,
    step: Path,
    out: Path,
    view: str,
    width: int,
    height: int,
    timeout: float,
) -> bool:
    """Render one snapshot atomically; return False after printing a warning."""
    out.parent.mkdir(parents=True, exist_ok=True)
    temporary = out.with_name(out.name + ".tmp")
    temporary.unlink(missing_ok=True)
    command = [
        tool,
        "snapshot",
        "--in",
        str(step),
        "--out",
        str(temporary),
        "--view",
        view,
        "--no-grid",
        "--no-axes",
        "--width",
        str(width),
        "--height",
        str(height),
    ]
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        print(f"warning: {view} render timed out after {timeout:g} s", file=sys.stderr)
        temporary.unlink(missing_ok=True)
        return False
    except OSError as error:
        print(f"warning: could not run solidcraft-cli: {error}", file=sys.stderr)
        temporary.unlink(missing_ok=True)
        return False
    if result.returncode != 0 or not temporary.is_file():
        detail = (result.stderr or result.stdout).strip()
        print(
            f"warning: {view} render failed"
            + (f": {detail}" if detail else ""),
            file=sys.stderr,
        )
        temporary.unlink(missing_ok=True)
        return False
    os.replace(temporary, out)
    return True


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Render a build package's multi-angle contact sheet.",
    )
    parser.add_argument("build_dir", type=Path, help="build/<example> directory")
    parser.add_argument("--width", type=int, default=1024, help="image width (default 1024)")
    parser.add_argument("--height", type=int, default=768, help="image height (default 768)")
    parser.add_argument(
        "--timeout",
        type=float,
        default=900.0,
        help="per-image timeout in seconds (default 900)",
    )
    args = parser.parse_args(argv)

    build_dir = args.build_dir
    assembly = build_dir / "assembly.step"
    if not assembly.is_file():
        print(f"error: no assembly.step in {build_dir}", file=sys.stderr)
        return 2

    tool = find_solidcraft()
    if tool is None:
        print(
            "warning: solidcraft-cli is not on PATH; skipping view renders",
            file=sys.stderr,
        )
        return 0

    views_dir = build_dir / "views"
    written: list[Path] = []
    for view in ORTHO_VIEWS:
        out = views_dir / f"{view}.png"
        if render(tool, assembly, out, view, args.width, args.height, args.timeout):
            written.append(out)

    exploded = build_dir / "exploded.step"
    if exploded.is_file():
        out = views_dir / "exploded.png"
        if render(tool, exploded, out, "iso", args.width, args.height, args.timeout):
            written.append(out)
    else:
        print(
            f"note: no {exploded.name}; skipping the exploded render",
            file=sys.stderr,
        )

    if written:
        print("Rendered views:")
        for path in written:
            print(f"  {path}")
    else:
        print("warning: no views were rendered", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
