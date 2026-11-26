#!/usr/bin/env python3
"""Headless exact solid-solid interference check for one STEP assembly.

The component collision package uses conservative oriented bounding boxes.
This script asks SolidCraft's SMLib kernel which *solids* actually share
positive volume. It imports the assembly with ``file.insert_step`` (flattened
to one body per solid) and runs ``inspect.interference``, then filters the
result by volume and an optional body-name pattern for intentional contacts
(fastener-in-hole, welded inserts, print-in-place gear cartridges).

Usage:
    python3 scripts/check_interference.py build/08/assembly.step
    python3 scripts/check_interference.py model.step --min-volume 1.0
    python3 scripts/check_interference.py model.step \
        --exclude-pattern "fastener|bolt|screw|gear_cartridge" \
        --json /tmp/interference.json --budget-s 240

Exit status: 0 when no unexpected overlap exceeds --min-volume, 1 when it
does, 2 for a missing file, missing tool, or kernel error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def find_solidcraft() -> str | None:
    home_bin = Path.home() / "tools" / "bin" / "solidcraft-cli"
    if home_bin.is_file() and os.access(home_bin, os.X_OK):
        return str(home_bin)
    return shutil.which("solidcraft-cli")


def run_inspection(
    tool: str,
    step: Path,
    budget_s: float,
    timeout: float,
) -> dict:
    """Import ``step`` and return the ``inspect.interference`` result."""
    script = [
        {
            "command": "file.insert_step",
            "params": {"path": str(step), "flatten": True},
        },
        {
            "command": "inspect.interference",
            "params": {"budget_s": budget_s},
        },
    ]
    with tempfile.TemporaryDirectory(prefix="sc-interference-") as tmp:
        script_path = Path(tmp) / "script.json"
        results_path = Path(tmp) / "results.json"
        script_path.write_text(json.dumps(script, indent=2))
        proc = subprocess.run(
            [
                tool,
                "run",
                str(script_path),
                "--validation",
                "off",
                "--quiet",
                "--results",
                "--json-out",
                str(results_path),
            ],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout).strip()
            raise RuntimeError(
                f"solidcraft-cli failed (exit {proc.returncode}): {detail}"
            )
        if not results_path.is_file():
            raise RuntimeError("solidcraft-cli wrote no results JSON")
        results = json.loads(results_path.read_text())
    for result in reversed(results):
        if isinstance(result, dict) and "interferences" in result:
            return result
    raise RuntimeError("no inspect.interference result in solidcraft-cli output")


def filter_hits(
    result: dict,
    min_volume: float,
    pattern: re.Pattern[str] | None,
) -> tuple[list[dict], int]:
    """Return (unexpected hits, excluded count) above ``min_volume``."""
    hits: list[dict] = []
    excluded = 0
    for hit in result.get("interferences", []):
        volume = float(hit.get("volume_mm3", 0.0))
        if volume <= min_volume:
            continue
        name_a = str(hit.get("a", ""))
        name_b = str(hit.get("b", ""))
        if pattern is not None and (
            pattern.search(name_a) or pattern.search(name_b)
        ):
            excluded += 1
            continue
        hits.append(hit)
    hits.sort(key=lambda hit: -float(hit.get("volume_mm3", 0.0)))
    return hits, excluded


def format_center(center: object) -> str:
    if not isinstance(center, (list, tuple)) or len(center) != 3:
        return "(?, ?, ?)"
    return "({:.2f}, {:.2f}, {:.2f})".format(
        float(center[0]), float(center[1]), float(center[2])
    )


def print_table(
    step: Path,
    result: dict,
    hits: list[dict],
    min_volume: float,
) -> None:
    checked = int(result.get("checked", 0))
    print(f"Interference check: {step}")
    print(
        f"  {checked} solid bod{'y' if checked == 1 else 'ies'} checked; "
        f"{len(hits)} unexpected overlap(s) above {min_volume:g} mm^3"
    )
    if hits:
        print()
        print(
            f"  {'BODY A':<26} {'BODY B':<26} "
            f"{'OVERLAP mm^3':>14}  CENTER (x, y, z)"
        )
        print("  " + "-" * 92)
        for hit in hits:
            name_a = str(hit.get("a", "?"))
            name_b = str(hit.get("b", "?"))
            volume = float(hit.get("volume_mm3", 0.0))
            print(
                f"  {name_a:<26.26} {name_b:<26.26} "
                f"{volume:14.3f}  {format_center(hit.get('center'))}"
            )
    unchecked = result.get("unchecked", [])
    if unchecked:
        print(f"\n  warning: {len(unchecked)} pair(s) could not be checked:")
        for entry in unchecked[:10]:
            print(
                f"    - {entry.get('a')} <-> {entry.get('b')}: "
                f"{entry.get('reason')}"
            )
        if len(unchecked) > 10:
            print(f"    ... {len(unchecked) - 10} more")
    if result.get("truncated"):
        skipped = int(result.get("skipped_pairs", 0))
        print(f"\n  warning: {skipped} pair(s) skipped at the pair limit")
    if result.get("budget_exceeded"):
        print("\n  warning: the time budget ran out; results are partial")


def write_summary(
    path: Path,
    step: Path,
    result: dict,
    hits: list[dict],
    excluded: int,
    min_volume: float,
    exclude_pattern: str,
) -> None:
    summary = {
        "step": str(step),
        "checked": int(result.get("checked", 0)),
        "min_volume_mm3": min_volume,
        "exclude_pattern": exclude_pattern,
        "interferences": hits,
        "excluded_count": excluded,
        "unchecked": result.get("unchecked", []),
        "truncated": bool(result.get("truncated", False)),
        "budget_exceeded": bool(result.get("budget_exceeded", False)),
    }
    path.write_text(json.dumps(summary, indent=2) + "\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Headless exact solid-solid interference check for a STEP assembly.",
    )
    parser.add_argument("step", type=Path, help="STEP assembly to check")
    parser.add_argument(
        "--min-volume",
        type=float,
        default=1.0,
        help="report overlaps above this volume in mm^3 (default 1.0)",
    )
    parser.add_argument(
        "--exclude-pattern",
        default="",
        help="regular expression; pairs with a matching body name are intentional "
        "(for example 'fastener|bolt|screw|gear_cartridge')",
    )
    parser.add_argument("--json", type=Path, help="write the filtered summary JSON")
    parser.add_argument(
        "--budget-s",
        type=float,
        default=120.0,
        help="inspect.interference time budget in seconds (default 120)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=3600.0,
        help="hard subprocess timeout in seconds (default 3600)",
    )
    args = parser.parse_args(argv)

    step = args.step
    if not step.is_file():
        print(f"error: STEP file not found: {step}", file=sys.stderr)
        return 2

    try:
        pattern = (
            re.compile(args.exclude_pattern, re.IGNORECASE)
            if args.exclude_pattern
            else None
        )
    except re.error as error:
        print(f"error: invalid --exclude-pattern: {error}", file=sys.stderr)
        return 2

    tool = find_solidcraft()
    if tool is None:
        print("error: solidcraft-cli is not on PATH", file=sys.stderr)
        return 2

    try:
        result = run_inspection(tool, step, args.budget_s, args.timeout)
    except subprocess.TimeoutExpired:
        print(
            f"error: solidcraft-cli timed out after {args.timeout:g} s",
            file=sys.stderr,
        )
        return 2
    except (RuntimeError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    hits, excluded = filter_hits(result, args.min_volume, pattern)
    print_table(step, result, hits, args.min_volume)
    if args.json is not None:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        write_summary(
            args.json,
            step,
            result,
            hits,
            excluded,
            args.min_volume,
            args.exclude_pattern,
        )
        print(f"\n  summary written to {args.json}")
    return 1 if hits else 0


if __name__ == "__main__":
    raise SystemExit(main())
