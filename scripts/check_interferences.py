#!/usr/bin/env python3
"""Exact pairwise interference check for a URDF bundle's per-link STEP files.

The component collision package uses conservative oriented bounding boxes.
This tool answers the complementary question: which placed *solids* actually
share positive volume? It loads every per-link STEP from a bundle's `parts/`
directory into Open CASCADE and calls ``bcommon`` on each pair of links,
reporting the common volume and its bounding box.

This is a development-time check. The library and generated files have no
Python or Open CASCADE dependency.

Usage:
    python3 scripts/check_interferences.py --parts-dir DIR [--min-volume MM3]
    python3 scripts/check_interferences.py a.step b.step ...
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

MASS_RE = re.compile(r"Mass\s*:\s*([-+0-9.eE]+)")
PAIR_RE = re.compile(r"PAIR\|([^|]+)\|(\S+)")


def draw_tool() -> str | None:
    return shutil.which("occt-draw") or shutil.which("DRAWEXE")


def tcl_path(path: Path) -> str:
    return str(path).replace("\\", "\\\\").replace('"', '\\"')


def parse_pairs(text: str) -> dict[tuple[str, str], float]:
    """Returns the vprops mass recorded after each PAIR marker.

    ``flush stdout`` after each marker keeps Tcl output ordered with the C++
    command output. A pair with an empty intersection may omit its vprops
    record; it then defaults to zero.
    """
    result: dict[tuple[str, str], float] = {}
    current: tuple[str, str] | None = None
    for raw in text.splitlines():
        pair = PAIR_RE.search(raw)
        if pair:
            current = (pair.group(1), pair.group(2))
            result.setdefault(current, 0.0)
            continue
        mass = MASS_RE.search(raw)
        if mass and current is not None:
            result[current] = float(mass.group(1))
    return result


def check(files: list[Path], min_volume: float, timeout: int) -> int:
    tool = draw_tool()
    if tool is None:
        print("error: neither occt-draw nor DRAWEXE is on PATH", file=sys.stderr)
        return 2
    commands = ["pload ALL"]
    names: list[str] = []
    for index, path in enumerate(files):
        name = f"link{index}"
        names.append(name)
        commands.append(f'testreadstep "{tcl_path(path)}" {name}')
    pairs: list[tuple[str, str]] = []
    for i in range(len(files)):
        for j in range(i + 1, len(files)):
            result = f"r{i}_{j}"
            commands.append(f'puts "PAIR|{files[i].stem}|{files[j].stem}"')
            commands.append("flush stdout")
            commands.append(f"bcommon {result} {names[i]} {names[j]}")
            commands.append(f"vprops {result}")
            pairs.append((files[i].stem, files[j].stem))
    try:
        proc = subprocess.run(
            [tool, "-b"],
            input="\n".join(commands) + "\n",
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        print(f"error: OCCT timed out after {timeout} s", file=sys.stderr)
        return 2

    output = proc.stdout + proc.stderr
    found = parse_pairs(output)
    rows = [(a, b, found.get((a, b), 0.0)) for a, b in pairs]

    hits = [row for row in rows if row[2] > min_volume]
    hits.sort(key=lambda row: row[2], reverse=True)
    print(f"interference check: {len(files)} links, {len(pairs)} pairs")
    if not hits:
        print("OK: no positive-volume overlap above "
              f"{min_volume:g} mm^3")
        return 0
    for name_a, name_b, volume in hits:
        print(f"OVERLAP {volume:10.3f} mm^3  {name_a} <-> {name_b}")
    print(f"FAILED: {len(hits)} overlapping link pair(s)")
    return 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="*", type=Path, help="STEP files")
    parser.add_argument(
        "--parts-dir",
        type=Path,
        help="directory of per-link STEP files (bundle/parts)",
    )
    parser.add_argument(
        "--min-volume",
        type=float,
        default=0.01,
        help="minimum common volume in mm^3 to report (default 0.01)",
    )
    parser.add_argument(
        "--timeout", type=int, default=1800, help="OCCT timeout in seconds"
    )
    args = parser.parse_args(argv)
    files = list(args.files)
    if args.parts_dir is not None:
        files.extend(sorted(args.parts_dir.glob("*.step")))
    if len(files) < 2:
        parser.error("provide at least two STEP files (or --parts-dir)")
    return check(files, args.min_volume, args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
