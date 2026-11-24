#!/usr/bin/env python3
"""Generate vector drawing sheets for a gmlewis/cad build package.

For every fabricated link in a package produced by ``--package``, this script:

* measures the link's STEP part,
* asks SolidCraft to export front, top, right, and isometric DXF views
  (near-orthographic cameras at a large distance),
* composes an A3 drawing sheet as SVG with a title block, part data, and print
  settings, and
* converts the sheet to PDF when Inkscape is available.

Requires ``solidcraft-cli`` on PATH.  Inkscape is optional; without it the SVG
sheets are still written.  Everything it needs is in this repository; no
sibling checkout is required.

Usage:
    python3 scripts/make_drawings.py build/03
    python3 scripts/make_drawings.py build/03 --out build/03/drawings
    python3 scripts/make_drawings.py build/03 --all --link base_flange
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SHEET_W = 420.0  # A3 landscape, mm
SHEET_H = 297.0
MARGIN = 8.0
VIEW_BOXES = {
    "front": (16.0, 16.0, 188.0, 104.0),
    "top": (216.0, 16.0, 188.0, 104.0),
    "right": (16.0, 130.0, 188.0, 104.0),
    "iso": (216.0, 130.0, 188.0, 104.0),
}
VIEW_LABELS = {
    "front": "FRONT (XZ)",
    "top": "TOP (XY)",
    "right": "RIGHT (YZ)",
    "iso": "ISOMETRIC",
}
VIEW_CAMERAS = {
    "front": (0.0, 0.0),
    "top": (0.0, math.pi / 2.0),
    "right": (-math.pi / 2.0, 0.0),
    "iso": (math.pi / 4.0, math.atan(1.0 / math.sqrt(2.0))),
}
LARGE_DISTANCE = 1_000_000.0  # mm: near-orthographic projection
FOV = 0.5  # radians


def find_executable(name: str) -> str | None:
    return shutil.which(name)


def run_command(command: list[str], what: str) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        message = (result.stdout + result.stderr).strip()
        raise RuntimeError(f"{what} failed:\n{message}")
    return result


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.is_file():
        return []
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def measure_bbox(step: Path, solidcraft: str) -> tuple[tuple[float, float, float], float]:
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = Path(tmpdir) / "eval.json"
        run_command(
            [
                solidcraft,
                "eval",
                "--in",
                str(step),
                "--json-out",
                str(result_path),
            ],
            f"measuring {step.name}",
        )
        data = json.loads(result_path.read_text(encoding="utf-8"))
    points = []
    for body in data.get("bodies", []):
        box = body.get("bbox")
        if box:
            points.append(box["min"])
            points.append(box["max"])
    if not points:
        raise RuntimeError(f"no bodies found in {step}")
    mins = [min(p[i] for p in points) for i in range(3)]
    maxs = [max(p[i] for p in points) for i in range(3)]
    center = tuple((mins[i] + maxs[i]) / 2.0 for i in range(3))
    size = max(maxs[i] - mins[i] for i in range(3))
    return center, size


def export_dxf_views(
    step: Path, out_dir: Path, center: tuple[float, float, float], solidcraft: str
) -> dict[str, Path]:
    script = []
    paths: dict[str, Path] = {}
    for view, (yaw, pitch) in VIEW_CAMERAS.items():
        path = out_dir / f"{view}.dxf"
        paths[view] = path
        script.append(
            {
                "command": "file.export_view_dxf",
                "params": {
                    "path": str(path),
                    "camera": {
                        "target": list(center),
                        "yaw": yaw,
                        "pitch": pitch,
                        "distance": LARGE_DISTANCE,
                        "fov": FOV,
                    },
                },
            }
        )
    script_path = out_dir / "views.json"
    script_path.write_text(json.dumps(script), encoding="utf-8")
    run_command(
        [solidcraft, "run", str(script_path), "--in", str(step), "--quiet"],
        f"exporting DXF views for {step.name}",
    )
    return {view: path for view, path in paths.items() if path.is_file()}


def _number(text: str) -> float | None:
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def parse_dxf(path: Path) -> list[list[tuple[float, float]]]:
    """Extracts LINE, LWPOLYLINE, POLYLINE/VERTEX, CIRCLE, and ARC entities."""
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    pairs: list[tuple[str, str]] = []
    for i in range(0, len(lines) - 1, 2):
        pairs.append((lines[i].strip(), lines[i + 1].strip()))
    entities: list[tuple[str, list[tuple[str, str]]]] = []
    i = 0
    while i < len(pairs):
        code, value = pairs[i]
        if code == "0":
            entity_type = value
            i += 1
            data: list[tuple[str, str]] = []
            while i < len(pairs) and pairs[i][0] != "0":
                data.append(pairs[i])
                i += 1
            entities.append((entity_type, data))
        else:
            i += 1

    polylines: list[list[tuple[float, float]]] = []

    def code_value(data, code):
        for c, v in data:
            if c == code:
                return v
        return None

    def lwpolyline_points(data) -> list[tuple[float, float]]:
        points = []
        x = None
        for c, v in data:
            if c == "10":
                x = _number(v)
            elif c == "20" and x is not None:
                y = _number(v)
                if y is not None:
                    points.append((x, y))
                x = None
        flags = _number(code_value(data, "70") or "0") or 0
        if points and int(flags) & 1:
            points.append(points[0])
        return points

    pending_polyline: list[tuple[float, float]] | None = None
    for entity_type, data in entities:
        if entity_type == "LINE":
            x1 = _number(code_value(data, "10"))
            y1 = _number(code_value(data, "20"))
            x2 = _number(code_value(data, "11"))
            y2 = _number(code_value(data, "21"))
            if None not in (x1, y1, x2, y2):
                polylines.append([(x1, y1), (x2, y2)])
        elif entity_type == "LWPOLYLINE":
            points = lwpolyline_points(data)
            if len(points) >= 2:
                polylines.append(points)
        elif entity_type == "POLYLINE":
            pending_polyline = []
        elif entity_type == "VERTEX" and pending_polyline is not None:
            x = _number(code_value(data, "10"))
            y = _number(code_value(data, "20"))
            if None not in (x, y):
                pending_polyline.append((x, y))
        elif entity_type in ("SEQEND", "ENDSEC"):
            if pending_polyline and len(pending_polyline) >= 2:
                polylines.append(pending_polyline)
            pending_polyline = None
        elif entity_type == "CIRCLE":
            cx = _number(code_value(data, "10"))
            cy = _number(code_value(data, "20"))
            radius = _number(code_value(data, "40"))
            if None not in (cx, cy, radius) and radius > 0:
                steps = 72
                polylines.append(
                    [
                        (
                            cx + radius * math.cos(2.0 * math.pi * k / steps),
                            cy + radius * math.sin(2.0 * math.pi * k / steps),
                        )
                        for k in range(steps + 1)
                    ]
                )
        elif entity_type == "ARC":
            cx = _number(code_value(data, "10"))
            cy = _number(code_value(data, "20"))
            radius = _number(code_value(data, "40"))
            start = _number(code_value(data, "50"))
            end = _number(code_value(data, "51"))
            if None not in (cx, cy, radius, start, end):
                sweep = (end - start) % 360.0
                steps = max(8, int(sweep / 5.0))
                polylines.append(
                    [
                        (
                            cx
                            + radius
                            * math.cos(math.radians(start + sweep * k / steps)),
                            cy
                            + radius
                            * math.sin(math.radians(start + sweep * k / steps)),
                        )
                        for k in range(steps + 1)
                    ]
                )
    return polylines


def xml_escape(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def fit_text(text: str, max_chars: int) -> str:
    """Keeps a title-block line inside the sheet width."""
    if len(text) <= max_chars:
        return text
    return text[: max_chars - 3].rstrip(", ;") + "..."


def fit_polylines(
    polylines: list[list[tuple[float, float]]],
    box: tuple[float, float, float, float],
    padding: float = 8.0,
) -> list[list[tuple[float, float]]]:
    xs = [x for line in polylines for x, _ in line]
    ys = [y for line in polylines for _, y in line]
    if not xs or not ys:
        return []
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    width, height = max_x - min_x, max_y - min_y
    x0, y0, w, h = box
    usable_w = max(1.0, w - 2.0 * padding)
    usable_h = max(1.0, h - 2.0 * padding)
    scale = min(usable_w / max(width, 1e-6), usable_h / max(height, 1e-6))
    off_x = x0 + (w - width * scale) / 2.0
    off_y = y0 + (h - height * scale) / 2.0
    return [
        [
            (off_x + (x - min_x) * scale, off_y + (max_y - y) * scale)
            for x, y in line
        ]
        for line in polylines
    ]


def sheet_svg(
    link: str,
    sheet_index: int,
    parts: list[dict[str, str]],
    settings: dict[str, str] | None,
    views: dict[str, list[list[tuple[float, float]]]],
) -> str:
    out = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        (
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{SHEET_W}mm" '
            f'height="{SHEET_H}mm" viewBox="0 0 {SHEET_W} {SHEET_H}">'
        ),
        '<rect x="0" y="0" width="100%" height="100%" fill="white"/>',
    ]
    out.append(
        f'<rect x="{MARGIN}" y="{MARGIN}" width="{SHEET_W - 2 * MARGIN}" '
        f'height="{SHEET_H - 2 * MARGIN}" fill="none" stroke="black" '
        'stroke-width="0.5"/>'
    )
    for view, box in VIEW_BOXES.items():
        x0, y0, w, h = box
        out.append(
            f'<rect x="{x0}" y="{y0}" width="{w}" height="{h}" fill="none" '
            'stroke="#999999" stroke-width="0.2"/>'
        )
        out.append(
            f'<text x="{x0 + 2}" y="{y0 + 5}" font-family="Helvetica, Arial, sans-serif" '
            f'font-size="3.6" font-weight="bold">{VIEW_LABELS[view]}</text>'
        )
        fitted = fit_polylines(views.get(view, []), box, padding=9.0)
        for line in fitted:
            points = " ".join(f"{x:.3f},{y:.3f}" for x, y in line)
            out.append(
                f'<polyline points="{points}" fill="none" stroke="black" '
                'stroke-width="0.25" stroke-linejoin="round"/>'
            )
        if not fitted:
            out.append(
                f'<text x="{x0 + w / 2}" y="{y0 + h / 2}" text-anchor="middle" '
                'font-family="Helvetica, Arial, sans-serif" font-size="4" '
                'fill="#777777">NO GEOMETRY</text>'
            )

    # Title block.
    tx, ty, tw, th = 216.0, 244.0, 188.0, 44.0
    out.append(
        f'<rect x="{tx}" y="{ty}" width="{tw}" height="{th}" fill="none" '
        'stroke="black" stroke-width="0.5"/>'
    )
    for offset in (10.0, 20.0, 30.0):
        out.append(
            f'<line x1="{tx}" y1="{ty + offset}" x2="{tx + tw}" '
            f'y2="{ty + offset}" stroke="#999999" stroke-width="0.2"/>'
        )
    descriptions = []
    materials = []
    processes = []
    quantities = 0
    for part in parts:
        description = part.get("description", "").strip()
        if description and description not in descriptions:
            descriptions.append(description)
        material = part.get("material", "").strip()
        process = part.get("process", "").strip()
        if material and material not in materials:
            materials.append(material)
        if process and process not in processes:
            processes.append(process)
        quantities += int(float(part.get("quantity", "0") or 0))
    part_numbers = ", ".join(
        part.get("part_number", "").strip() for part in parts if part.get("part_number")
    )
    title_lines = [
        link,
        part_numbers or "(no part number)",
        "; ".join(descriptions) or "(no description)",
        f"{', '.join(materials) or '-'} / {', '.join(processes) or '-'}",
        f"QTY {quantities}   SHEET {sheet_index:02d}   SCALE NTS",
    ]
    for index, line in enumerate(title_lines):
        weight = "bold" if index == 0 else "normal"
        size = 4.6 if index == 0 else 3.2
        max_chars = 64 if index == 0 else 92
        out.append(
            f'<text x="{tx + 2.5}" y="{ty + 7.0 + index * 8.5}" '
            f'font-family="Helvetica, Arial, sans-serif" font-size="{size}" '
            f'font-weight="{weight}">{xml_escape(fit_text(line, max_chars))}</text>'
        )

    # Notes.
    nx, ny = 16.0, 244.0
    notes = [
        "NOTES:",
        "Orthographic views exported from the STEP model.",
        "Model and sheet units: mm.  Sheet: A3.  Not to scale.",
    ]
    if settings:
        if settings.get("orientation"):
            notes.append(f"Print orientation: {settings['orientation']}.")
        layer = settings.get("layer_height_mm", "")
        infill = settings.get("infill_percent", "")
        if layer or infill:
            notes.append(f"Layer height: {layer or '-'} mm.  Infill: {infill or '-'}%.")
        if settings.get("notes"):
            notes.append(settings["notes"])
    for index, note in enumerate(notes):
        weight = "bold" if index == 0 else "normal"
        out.append(
            f'<text x="{nx}" y="{ny + 5.0 + index * 5.0}" '
            f'font-family="Helvetica, Arial, sans-serif" font-size="3.2" '
            f'font-weight="{weight}">{xml_escape(note)}</text>'
        )
    out.append(
        f'<text x="{SHEET_W - MARGIN - 2}" y="{SHEET_H - MARGIN - 2}" '
        'text-anchor="end" font-family="Helvetica, Arial, sans-serif" '
        'font-size="2.6" fill="#555555">gmlewis/cad</text>'
    )
    out.append("</svg>")
    return "\n".join(out) + "\n"


def write_pdf(svg_path: Path, pdf_path: Path) -> bool:
    vc = find_executable("vectorcraft-cli")
    if vc:
        result = subprocess.run(
            [vc, "run", "--in", str(svg_path), "--export", str(pdf_path)],
            capture_output=True,
        )
        if result.returncode == 0 and pdf_path.is_file():
            return True
    inkscape = find_executable("inkscape")
    if not inkscape:
        return False
    result = subprocess.run(
        [inkscape, f"--export-filename={pdf_path}", str(svg_path)],
        capture_output=True,
    )
    return result.returncode == 0 and pdf_path.is_file()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate vector drawing sheets for a build package."
    )
    parser.add_argument("package", help="build package directory (from --package)")
    parser.add_argument(
        "--out", help="drawings output directory (default: <package>/drawings)"
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="draw purchased-only links too (default: fabricated links only)",
    )
    parser.add_argument(
        "--link",
        action="append",
        default=[],
        help="draw only this link (repeatable)",
    )
    args = parser.parse_args()

    package = Path(args.package)
    parts_dir = package / "bundle" / "parts"
    if not parts_dir.is_dir():
        print(f"Error: no bundle/parts directory in {package}", file=sys.stderr)
        return 1
    solidcraft = find_executable("solidcraft-cli")
    if not solidcraft:
        print(
            "Error: solidcraft-cli is not on PATH. It is required for DXF export.",
            file=sys.stderr,
        )
        return 1
    out_dir = Path(args.out) if args.out else package / "drawings"
    out_dir.mkdir(parents=True, exist_ok=True)

    bom = {row["part_number"]: row for row in read_csv(package / "bom.csv")}
    print_list = {
        row["part_number"]: row for row in read_csv(package / "print-list.csv")
    }
    links = {row["link"]: row for row in read_csv(package / "link-parts.csv")}

    rows = []
    sheet_index = 0
    for step in sorted(parts_dir.glob("*.step")):
        link = step.stem
        if args.link and link not in args.link:
            continue
        link_row = links.get(link)
        fabricated = link_row is not None and link_row.get("fabricated") == "true"
        if not fabricated and not args.all:
            continue
        part_numbers = []
        if link_row and link_row.get("part_numbers"):
            part_numbers = [
                value.strip()
                for value in link_row["part_numbers"].split(";")
                if value.strip()
            ]
        if not part_numbers and link in bom:
            part_numbers = [link]
        part_rows = [bom[number] for number in part_numbers if number in bom]
        settings = None
        for number in part_numbers:
            if number in print_list:
                settings = print_list[number]
                break
        try:
            center, _ = measure_bbox(step, solidcraft)
            with tempfile.TemporaryDirectory() as tmpdir:
                dxf_paths = export_dxf_views(step, Path(tmpdir), center, solidcraft)
                views = {
                    view: parse_dxf(path) for view, path in dxf_paths.items()
                }
                dxf_dir = out_dir / "dxf"
                dxf_dir.mkdir(parents=True, exist_ok=True)
                dxf_names = []
                for view, path in dxf_paths.items():
                    name = f"{link}-{view}.dxf"
                    shutil.copyfile(path, dxf_dir / name)
                    dxf_names.append((view, name))
        except Exception as exc:  # noqa: BLE001 - report and continue
            print(f"  skip {link}: {exc}", file=sys.stderr)
            continue
        if not any(views.values()):
            print(f"  skip {link}: no drawable edges", file=sys.stderr)
            continue
        sheet_index += 1
        svg_text = sheet_svg(link, sheet_index, part_rows, settings, views)
        svg_path = out_dir / f"{link}.svg"
        svg_path.write_text(svg_text, encoding="utf-8")
        pdf_path = out_dir / f"{link}.pdf"
        has_pdf = write_pdf(svg_path, pdf_path)
        rows.append((
            sheet_index,
            link,
            part_numbers,
            settings,
            svg_path,
            has_pdf,
            dxf_names,
        ))
        print(f"  [{sheet_index:02d}] {link}")

    index = ["# Drawings", "", f"Generated from `{package}`.", ""]
    index.append("| Sheet | Link | Parts | Process | SVG | PDF | DXF |")
    index.append("| --- | --- | --- | --- | --- | --- | --- |")
    for sheet, link, numbers, settings, svg_path, has_pdf, dxf_names in rows:
        pdf_link = f"[PDF]({svg_path.stem}.pdf)" if has_pdf else "-"
        dxf_links = " ".join(
            f"[{view}](dxf/{name})" for view, name in dxf_names
        ) or "-"
        process = settings.get("process", "") if settings else ""
        index.append(
            f"| {sheet:02d} | `{link}` | {', '.join(numbers) or '-'} | "
            f"{process or '-'} | [SVG]({svg_path.name}) | {pdf_link} | {dxf_links} |"
        )
    if not rows:
        index.append("| - | - | - | - | - | - | no fabricated links |")
    index.append("")
    index.append(
        "Orthographic views are exported from the STEP model; sheets are A3, "
        "units mm, not to scale.  The four DXF views for each sheet are in `dxf/`."
    )
    (out_dir / "index.md").write_text("\n".join(index) + "\n", encoding="utf-8")
    print(f"Wrote {len(rows)} drawing sheet(s) to {out_dir}")
    if not find_executable("vectorcraft-cli") and not find_executable("inkscape"):
        print("Note: neither vectorcraft-cli nor Inkscape was found; SVG sheets were kept, PDFs skipped.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
