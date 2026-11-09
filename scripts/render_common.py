"""Shared rendering helpers for the CAD example scripts.

Everything here uses only the Python standard library plus external
executables.  Nothing is imported from a sibling repository, so the scripts
work when this repository is cloned on its own.

External tools:
  * OCCT ``DRAWEXE`` (or ``occt-draw``) for ``render_step.py``
  * ``solidcraft-cli`` for ``render_solidcraft.py``
  * Inkscape for compositing the four views into one PNG
  * ``sips`` (macOS), ``magick`` or ``convert`` for OCCT's PPM -> PNG
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path
from xml.sax.saxutils import escape

DEFAULT_CELL_W = 512
DEFAULT_CELL_H = 512


def find_executable(*names: str) -> str | None:
    """Return the first of ``names`` found on PATH."""
    for name in names:
        found = shutil.which(name)
        if found:
            return found
    return None


def find_occt() -> str | None:
    """Locate OCCT's DRAWEXE."""
    return find_executable("occt-draw", "DRAWEXE", "draw")


def find_solidcraft() -> str | None:
    """Locate the SolidCraft CLI."""
    return find_executable("solidcraft-cli", "SolidCraft")


def find_inkscape() -> str | None:
    """Locate Inkscape."""
    return find_executable("inkscape")


def _ppm_to_png(ppm: Path, png: Path) -> bool:
    """Convert a PPM to PNG with the first available converter."""
    sips = find_executable("sips")
    if sips:
        result = subprocess.run(
            [sips, "-s", "format", "png", str(ppm), "--out", str(png)],
            capture_output=True,
        )
        return result.returncode == 0 and png.is_file()

    converter = find_executable("magick", "convert")
    if converter:
        result = subprocess.run(
            [converter, str(ppm), str(png)],
            capture_output=True,
        )
        return result.returncode == 0 and png.is_file()

    return False


def render_occt_view(
    occt_bin: str,
    step_path: Path,
    png_path: Path,
    view_cmd: str,
    cell_w: int = DEFAULT_CELL_W,
    cell_h: int = DEFAULT_CELL_H,
    timeout: int = 120,
) -> bool:
    """Render one OCCT DRAWEXE view of ``step_path`` to ``png_path``."""
    ppm_path = png_path.with_suffix(".ppm")
    # Braces make the paths single Tcl words, so spaces in them are safe.
    step_abs = step_path.resolve()
    ppm_abs = ppm_path.resolve()
    draw_commands = f"""
pload ALL
vinit V -width {cell_w} -height {cell_h}
vbackground -color WHITE
ReadStep D {{{step_abs}}}
XDisplay D
vsetdispmode 1
{view_cmd}
vfit
vlight clear
vlight add directional -dir -1 -1 -1 -color WHITE
vlight add ambient -color WHITE
vfit
vdump {{{ppm_abs}}}
vclose ALL
exit
"""
    try:
        # DRAWEXE needs stdin (not a script file) so the macOS Cocoa event
        # loop is initialised.
        subprocess.run(
            [occt_bin],
            input=draw_commands,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if ppm_path.is_file():
            ok = _ppm_to_png(ppm_path, png_path)
            ppm_path.unlink(missing_ok=True)
            return ok
    except Exception as exc:  # noqa: BLE001 - report and let the caller fall back
        print(f"      OCCT view failed: {exc}")
    return False


def render_solidcraft_view(
    solidcraft_bin: str,
    step_path: Path,
    png_path: Path,
    view: str,
    cell_w: int = DEFAULT_CELL_W,
    cell_h: int = DEFAULT_CELL_H,
    timeout: int = 600,
) -> bool:
    """Render one shaded SolidCraft snapshot of ``step_path`` to ``png_path``."""
    cmd = [
        solidcraft_bin,
        "snapshot",
        "--in",
        str(step_path),
        "--out",
        str(png_path),
        "--view",
        view,
        "--no-grid",
        "--no-axes",
        "--width",
        str(cell_w),
        "--height",
        str(cell_h),
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return result.returncode == 0 and png_path.is_file()
    except Exception as exc:  # noqa: BLE001 - report and let the caller fall back
        print(f"      SolidCraft view failed: {exc}")
        return False


def _svg_composite(
    views: dict[str, str],
    labels: dict[str, str],
    cell_w: int,
    cell_h: int,
) -> str:
    """Build the 2x2 SVG that places four view PNGs together."""
    canvas_w = 2 * cell_w
    canvas_h = 2 * cell_h
    cells = [
        ("iso", 0, 0),
        ("top", cell_w, 0),
        ("front", 0, cell_h),
        ("right", cell_w, cell_h),
    ]
    parts = [
        (
            f'<svg width="{canvas_w}" height="{canvas_h}" '
            f'viewBox="0 0 {canvas_w} {canvas_h}" '
            'xmlns="http://www.w3.org/2000/svg" '
            'xmlns:xlink="http://www.w3.org/1999/xlink">'
        ),
        f'<rect width="{canvas_w}" height="{canvas_h}" fill="#ffffff"/>',
    ]
    for key, x, y in cells:
        if key not in views:
            continue
        parts.append(
            f'<image x="{x}" y="{y}" width="{cell_w}" height="{cell_h}" '
            f'xlink:href="{escape(views[key])}"/>'
        )
    parts += [
        (
            f'<line x1="{cell_w}" y1="0" x2="{cell_w}" y2="{canvas_h}" '
            'stroke="#eeeeee" stroke-width="2"/>'
        ),
        (
            f'<line x1="0" y1="{cell_h}" x2="{canvas_w}" y2="{cell_h}" '
            'stroke="#eeeeee" stroke-width="2"/>'
        ),
        (
            f'<rect x="0" y="0" width="{canvas_w}" height="{canvas_h}" '
            'fill="none" stroke="#cccccc" stroke-width="4"/>'
        ),
    ]
    for key, x, y in cells:
        if key not in labels:
            continue
        parts += [
            f'<g transform="translate({x + 10}, {y + 10})">',
            '<rect width="130" height="30" rx="4" fill="white" '
            'fill-opacity="0.8"/>',
            '<text x="65" y="21" font-family="sans-serif" font-size="16" '
            'font-weight="bold" fill="#333333" text-anchor="middle">'
            f"{escape(labels[key])}</text>",
            "</g>",
        ]
    parts.append(
        f'<text x="{canvas_w - 10}" y="{canvas_h - 10}" '
        'font-family="sans-serif" font-size="12" fill="#bbbbbb" '
        'text-anchor="end">gmlewis/cad</text>'
    )
    parts.append("</svg>")
    return "\n".join(parts)


def composite_views(
    views: dict[str, str],
    output_png: Path,
    labels: dict[str, str],
    cell_w: int = DEFAULT_CELL_W,
    cell_h: int = DEFAULT_CELL_H,
) -> bool:
    """Composite four view PNGs into one 2x2 PNG with Inkscape."""
    inkscape = find_inkscape()
    if not inkscape:
        return False
    svg_text = _svg_composite(views, labels, cell_w, cell_h)
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".svg", delete=False, encoding="utf-8"
    ) as tmp_svg:
        tmp_svg.write(svg_text)
        tmp_svg_path = tmp_svg.name
    try:
        result = subprocess.run(
            [inkscape, f"--export-filename={output_png}", tmp_svg_path],
            capture_output=True,
        )
        return result.returncode == 0 and output_png.is_file()
    except Exception as exc:  # noqa: BLE001 - report and let the caller fall back
        print(f"      Compositing failed: {exc}")
        return False
    finally:
        Path(tmp_svg_path).unlink(missing_ok=True)


def copy_iso_fallback(views: dict[str, str], output_png: Path) -> None:
    """Write the isometric view alone when no compositor is available."""
    iso = views.get("iso")
    if iso:
        shutil.copyfile(iso, output_png)
