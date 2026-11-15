#!/usr/bin/env python3
"""Check that every purchased BOM line in a build package has a supplier link.

Usage:
    python3 scripts/check_supplier_links.py build/01
    python3 scripts/check_supplier_links.py build/01/bom.csv
    python3 scripts/check_supplier_links.py build/01 --quiet

The BOM is written by examples/common/output.mbt (--package / --bom). A line
with process == "purchased" must have a real supplier and a supplier URL; the
unlinked default is supplier "generic" with an empty URL.

Exit status: 0 when every purchased line is linked, 1 when any link is missing.
No network access is used; use the sourcing-parts skill to research the links.
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


def find_bom(path: Path) -> Path:
    if path.is_dir():
        return path / "bom.csv"
    return path


def is_purchased(row: dict[str, str]) -> bool:
    return row.get("process", "").strip().lower() == "purchased"


def is_linked(row: dict[str, str]) -> bool:
    supplier = row.get("supplier", "").strip()
    url = row.get("supplier_url", "").strip()
    return supplier not in ("", "generic") and url not in ("", "-")


def example_hint(build_dir: Path) -> str:
    name = build_dir.name
    root = Path.cwd() / "examples"
    matches = sorted(root.glob(f"{name}_*")) + sorted(root.glob(f"{name}-*"))
    if matches:
        return str(matches[0] / "supplier-links.txt")
    return "examples/<example>/supplier-links.txt"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", help="build directory or bom.csv path")
    parser.add_argument("--quiet", action="store_true", help="only print failures")
    args = parser.parse_args(argv)

    bom_path = find_bom(Path(args.path))
    if not bom_path.is_file():
        print(f"error: BOM not found: {bom_path}", file=sys.stderr)
        return 2

    with bom_path.open(newline="") as handle:
        rows = list(csv.DictReader(handle))

    purchased = [row for row in rows if is_purchased(row)]
    missing = [row for row in purchased if not is_linked(row)]
    if missing:
        print(f"Missing purchase links in {bom_path}:")
        for row in missing:
            print(
                "  - "
                f"{row.get('part_number', '?')} "
                f"(qty {row.get('quantity', '?')}): "
                f"{row.get('description', '')}"
            )
        build_dir = bom_path.parent
        print()
        print(f"Add them to {example_hint(build_dir)}")
        print("Format: part_number | supplier | supplier_url | notes | unit_cost_usd")
        print("Then rebuild: ./build-part.sh " + build_dir.name)
        print("Guide: .claude/skills/sourcing-parts/SKILL.md")
        return 1

    if not args.quiet:
        print(
            f"OK: all {len(purchased)} purchased BOM lines in {bom_path} "
            "have a supplier and URL."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
