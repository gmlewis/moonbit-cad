#!/usr/bin/env python3
"""Convert a build package's printable STEP files to slicer-ready 3MF and STL.

Each ``printable/*.step`` is imported into a headless SolidCraft session and
exported next to it with ``file.export_3mf`` and ``file.export_stl``
(``lay_on_print_faces: true``, ``quality: fine``). The parts are already laid
flat at ``z = 0`` by the CAD exporter, so the meshes need no further cleanup.

Usage:
    python3 scripts/export_printable_meshes.py build/08
    python3 scripts/export_printable_meshes.py build/08 --formats 3mf
    python3 scripts/export_printable_meshes.py build/08 --fast

``--fast`` skips large print-in-place gear cartridges (and any STEP over 20 MB)
so development builds stay quick.

Exit status: 0 when every requested conversion succeeds, 1 when any fails, 2
for a missing build directory or invalid arguments.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

FORMATS = ("3mf", "stl")
FAST_MAX_BYTES = 20 * 1024 * 1024
EXPORT_COMMANDS = {
    "3mf": "file.export_3mf",
    "stl": "file.export_stl",
}


def find_solidcraft() -> str | None:
    return shutil.which("solidcraft-cli")


def export_one(
    tool: str,
    step: Path,
    formats: list[str],
    quality: str,
    timeout: float,
) -> tuple[list[Path], list[Path], str]:
    """Export one STEP; return (written, failed, error detail)."""
    script: list[dict] = [
        {
            "command": "file.insert_step",
            "params": {"path": str(step), "flatten": True},
        }
    ]
    outputs: dict[str, Path] = {}
    for fmt in formats:
        out = step.with_suffix("." + fmt)
        outputs[fmt] = out
        out.unlink(missing_ok=True)
        script.append(
            {
                "command": EXPORT_COMMANDS[fmt],
                "params": {
                    "path": str(out),
                    "lay_on_print_faces": True,
                    "quality": quality,
                },
            }
        )

    with tempfile.TemporaryDirectory(prefix="sc-mesh-export-") as tmp:
        script_path = Path(tmp) / "script.json"
        results_path = Path(tmp) / "results.json"
        script_path.write_text(json.dumps(script, indent=2))
        try:
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
        except subprocess.TimeoutExpired:
            return [], list(outputs.values()), f"timed out after {timeout:g} s"
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout).strip()
            return [], list(outputs.values()), f"solidcraft-cli: {detail}"

    written: list[Path] = []
    failed: list[Path] = []
    for out in outputs.values():
        if out.is_file() and out.stat().st_size > 0:
            written.append(out)
        else:
            failed.append(out)
    return written, failed, ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert printable STEP files to 3MF and STL.",
    )
    parser.add_argument("build_dir", type=Path, help="build/<example> directory")
    parser.add_argument(
        "--formats",
        default="3mf,stl",
        help="comma-separated output formats: 3mf, stl (default both)",
    )
    parser.add_argument(
        "--quality",
        choices=("standard", "fine", "finest"),
        default="fine",
        help="mesh chord quality (default fine)",
    )
    parser.add_argument(
        "--fast",
        action="store_true",
        help="skip print-in-place cartridges and STEP files over 20 MB",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=1800.0,
        help="per-part timeout in seconds (default 1800)",
    )
    args = parser.parse_args(argv)

    formats = [part.strip().lower() for part in args.formats.split(",") if part.strip()]
    if not formats or any(fmt not in FORMATS for fmt in formats):
        print(
            f"error: --formats must be a comma-separated subset of "
            f"{', '.join(FORMATS)}",
            file=sys.stderr,
        )
        return 2

    build_dir = args.build_dir
    if not build_dir.is_dir():
        print(f"error: build directory not found: {build_dir}", file=sys.stderr)
        return 2
    printable = build_dir / "printable"
    if not printable.is_dir():
        print(f"error: no printable/ directory in {build_dir}", file=sys.stderr)
        return 2
    steps = sorted(printable.glob("*.step"))
    if not steps:
        print(f"error: no *.step files in {printable}", file=sys.stderr)
        return 2

    tool = find_solidcraft()
    if tool is None:
        print(
            "warning: solidcraft-cli is not on PATH; skipping mesh exports",
            file=sys.stderr,
        )
        return 0

    written: list[Path] = []
    failed: list[Path] = []
    skipped: list[Path] = []
    for step in steps:
        if args.fast and (
            "CARTRIDGE" in step.name or step.stat().st_size > FAST_MAX_BYTES
        ):
            skipped.append(step)
            continue
        part_written, part_failed, detail = export_one(
            tool,
            step,
            formats,
            args.quality,
            args.timeout,
        )
        written.extend(part_written)
        failed.extend(part_failed)
        if detail:
            print(f"warning: {step.name}: {detail}", file=sys.stderr)
        elif part_failed:
            names = ", ".join(path.name for path in part_failed)
            print(f"warning: {step.name}: missing output ({names})", file=sys.stderr)

    for path in written:
        size_kb = path.stat().st_size / 1024.0
        print(f"  {path} ({size_kb:.1f} KiB)")
    if skipped:
        print(f"Skipped {len(skipped)} file(s) with --fast.")
    if failed:
        print(
            f"error: {len(failed)} of {len(written) + len(failed)} export(s) failed",
            file=sys.stderr,
        )
        return 1
    print(f"Exported {len(written)} mesh file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
