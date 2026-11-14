#!/usr/bin/env python3
"""Exact pairwise interference check for a URDF bundle's per-link STEP files.

The component collision package uses conservative oriented bounding boxes.
This tool answers the complementary question: which placed *solids* actually
share positive volume? It loads every per-link STEP from a bundle's `parts/`
directory into Open CASCADE, explodes each link into its solids, and calls
``bcommon`` on every solid pair.

Checking solids rather than compounds matters: a multi-solid link is a
compound, and ``bcommon`` on a compound can report a spurious common volume
from internal faces that no pair of solids actually shares. Solid-level
comparison is the exact answer.

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
PAIR_RE = re.compile(r"PAIR\|([^|]+)\|([^|]+)\|(\d+)\|(\d+)")
SOLID_COUNT_RE = re.compile(r"\bSOLID\s*:\s*(\d+)")


def draw_tool() -> str | None:
    return shutil.which("occt-draw") or shutil.which("DRAWEXE")


def tcl_path(path: Path) -> str:
    return str(path).replace("\\", "\\\\").replace('"', '\\"')


def run_draw(commands: list[str], timeout: int) -> str:
    tool = draw_tool()
    if tool is None:
        raise RuntimeError("neither occt-draw nor DRAWEXE is on PATH")
    proc = subprocess.run(
        [tool, "-b"],
        input="\n".join(commands) + "\n",
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return proc.stdout + proc.stderr


def solid_counts(files: list[Path], timeout: int) -> list[int]:
    commands = ["pload ALL"]
    for index, path in enumerate(files):
        commands.append(f'testreadstep "{tcl_path(path)}" link{index}')
        commands.append(f"nbshapes link{index}")
    output = run_draw(commands, timeout)
    counts = [int(value) for value in SOLID_COUNT_RE.findall(output)]
    if len(counts) < len(files):
        # A single-solid body still has one entry; if the count line is absent,
        # fall back to treating the link as one shape.
        counts += [1] * (len(files) - len(counts))
    return counts


def check(files: list[Path], min_volume: float, timeout: int) -> int:
    try:
        counts = solid_counts(files, timeout)
    except RuntimeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    commands = ["pload ALL"]
    for index, path in enumerate(files):
        commands.append(f'testreadstep "{tcl_path(path)}" link{index}')
        commands.append(f"explode link{index} So")

    pair_count = 0
    for i in range(len(files)):
        for j in range(i + 1, len(files)):
            pair_count += 1
            for si in range(1, counts[i] + 1):
                for sj in range(1, counts[j] + 1):
                    result = f"r{i}_{j}_{si}_{sj}"
                    commands.append(
                        f'puts "PAIR|{files[i].stem}|{files[j].stem}|{si}|{sj}"'
                    )
                    commands.append("flush stdout")
                    commands.append(f"bcommon {result} link{i}_{si} link{j}_{sj}")
                    commands.append(f"vprops {result}")

    try:
        output = run_draw(commands, timeout)
    except subprocess.TimeoutExpired:
        print(f"error: OCCT timed out after {timeout} s", file=sys.stderr)
        return 2

    results: dict[tuple[str, str, int, int], float] = {}
    current: tuple[str, str, int, int] | None = None
    for raw in output.splitlines():
        pair = PAIR_RE.search(raw)
        if pair:
            current = (
                pair.group(1),
                pair.group(2),
                int(pair.group(3)),
                int(pair.group(4)),
            )
            results.setdefault(current, 0.0)
            continue
        mass = MASS_RE.search(raw)
        if mass and current is not None:
            results[current] = float(mass.group(1))

    hits = [
        (name_a, name_b, si, sj, volume)
        for (name_a, name_b, si, sj), volume in results.items()
        if volume > min_volume
    ]
    hits.sort(key=lambda row: row[4], reverse=True)

    print(f"interference check: {len(files)} links, {pair_count} link pairs")
    if not hits:
        print("OK: no positive-volume overlap above "
              f"{min_volume:g} mm^3")
        return 0
    for name_a, name_b, si, sj, volume in hits:
        print(
            f"OVERLAP {volume:10.3f} mm^3  "
            f"{name_a}[solid {si}] <-> {name_b}[solid {sj}]"
        )
    print(f"FAILED: {len(hits)} overlapping solid pair(s)")
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
