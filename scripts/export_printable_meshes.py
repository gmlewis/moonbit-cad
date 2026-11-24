#!/usr/bin/env python3
"""Convert printable STEP files to slicer-ready 3MF (with provenance) and STL.

Each ``printable/*.step`` (or a single ``.step`` file) is imported into a
headless SolidCraft session and exported next to it with ``file.export_3mf``
and/or ``file.export_stl`` (``lay_on_print_faces: true``, ``quality: fine``).

Every generated ``.3mf`` archive is enriched with:
  * Standard 3MF ``<metadata>`` tags inside ``3D/3dmodel.model`` (Title,
    Application, CreationDate, Description with exact MoonBit command & git
    commit).
  * ``Metadata/provenance.json`` storing the exact MoonBit command / argv,
    parameters, git commit/branch/dirty status, UTC timestamp, source STEP
    SHA-256, and mesh export settings so any part can be reproduced later.

Usage:
    python3 scripts/export_printable_meshes.py build/08
    python3 scripts/export_printable_meshes.py build/08 --formats 3mf
    python3 scripts/export_printable_meshes.py build/08 --fast
    python3 scripts/export_printable_meshes.py path/to/part.step --command "moon run ..."
    python3 scripts/export_printable_meshes.py --inspect path/to/part.3mf

Exit status: 0 when every requested conversion succeeds, 1 when any fails, 2
for a missing input or invalid arguments.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

FORMATS = ("3mf", "stl")
FAST_MAX_BYTES = 20 * 1024 * 1024
EXPORT_COMMANDS = {
    "3mf": "file.export_3mf",
    "stl": "file.export_stl",
}
PROVENANCE_MEMBER = "Metadata/provenance.json"
MODEL_NS = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"


def find_solidcraft() -> str | None:
    home_bin = Path.home() / "tools" / "bin" / "solidcraft-cli"
    if home_bin.is_file() and os.access(home_bin, os.X_OK):
        return str(home_bin)
    return shutil.which("solidcraft-cli")


def _git_info(cwd: Path) -> dict[str, object]:
    """Best-effort git commit/branch/dirty metadata for provenance."""
    info: dict[str, object] = {}

    def run_git(*args: str) -> str:
        try:
            proc = subprocess.run(
                ["git", *args],
                cwd=str(cwd),
                capture_output=True,
                text=True,
                timeout=5,
            )
            if proc.returncode == 0:
                return proc.stdout.strip()
        except Exception:  # noqa: BLE001
            pass
        return ""

    commit = run_git("rev-parse", "HEAD")
    if commit:
        info["commit"] = commit
        info["short_commit"] = commit[:12]
    branch = run_git("rev-parse", "--abbrev-ref", "HEAD")
    if branch:
        info["branch"] = branch
    status = run_git("status", "--porcelain")
    if commit:
        info["dirty"] = bool(status)
    return info


def _sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def build_provenance(
    step_path: Path,
    quality: str,
    build_dir: Path | None = None,
    command_override: str | None = None,
) -> dict[str, object]:
    """Builds the structured provenance dictionary for one exported mesh."""
    now_utc = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    prov: dict[str, object] = {
        "schema_version": 1,
        "created_utc": now_utc,
        "source_step": step_path.name,
        "source_step_sha256": _sha256_file(step_path),
        "mesh_export": {
            "tool": "solidcraft-cli",
            "quality": quality,
            "lay_on_print_faces": True,
        },
    }

    # Load build-level provenance.json written by MoonBit if present.
    candidates: list[Path] = []
    if build_dir is not None:
        candidates.append(build_dir / "provenance.json")
    candidates.append(step_path.parent / "provenance.json")
    candidates.append(step_path.parent.parent / "provenance.json")
    for cand in candidates:
        if cand.is_file():
            try:
                loaded = json.loads(cand.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    for k in (
                        "component",
                        "command",
                        "argv",
                        "elephant_foot_chamfer_mm",
                        "parameters",
                    ):
                        if k in loaded and loaded[k] not in (None, ""):
                            prov[k] = loaded[k]
                break
            except Exception:  # noqa: BLE001
                pass

    if command_override:
        prov["command"] = command_override

    repo_dir = Path(__file__).resolve().parent.parent
    git_meta = _git_info(repo_dir)
    if git_meta:
        prov["git"] = git_meta
    return prov


def _wrap_multibody_assembly(
    root: ET.Element, ns: str, assembly_name: str
) -> bool:
    """Groups multiple top-level <build><item> entries into a single composite
    <object><components>...</components></object> so OrcaSlicer / Bambu Studio /
    PrusaSlicer load multi-body prints (such as print-in-place gear cartridges)
    pre-assembled automatically without double-extrusion conflict warnings."""
    resources = root.find(f"{{{ns}}}resources")
    build = root.find(f"{{{ns}}}build")
    if resources is None or build is None:
        return False
    items = list(build.findall(f"{{{ns}}}item"))
    if len(items) <= 1:
        return False

    used_ids: set[int] = set()
    for obj in resources.findall(f"{{{ns}}}object"):
        raw_id = obj.attrib.get("id")
        if raw_id and raw_id.isdigit():
            used_ids.add(int(raw_id))
    assembly_id = str((max(used_ids) if used_ids else 0) + 1)

    asm_obj = ET.SubElement(
        resources,
        f"{{{ns}}}object",
        {"id": assembly_id, "type": "model", "name": assembly_name},
    )
    comps = ET.SubElement(asm_obj, f"{{{ns}}}components")
    for item in items:
        comp_attrib: dict[str, str] = {"objectid": item.attrib["objectid"]}
        if "transform" in item.attrib:
            comp_attrib["transform"] = item.attrib["transform"]
        ET.SubElement(comps, f"{{{ns}}}component", comp_attrib)
        build.remove(item)

    ET.SubElement(build, f"{{{ns}}}item", {"objectid": assembly_id})
    return True


def inject_3mf_provenance(three_mf_path: Path, prov: dict[str, object]) -> None:
    """Embeds ``Metadata/provenance.json``, 3MF ``<metadata>`` XML tags, and
    wraps multi-body ``<build>`` items into a single composite assembly."""
    ET.register_namespace("", MODEL_NS)

    tmp_path = three_mf_path.with_suffix(".3mf.tmp")
    with (
        zipfile.ZipFile(three_mf_path, "r") as zin,
        zipfile.ZipFile(tmp_path, "w", compression=zipfile.ZIP_DEFLATED) as zout,
    ):
        for item in zin.infolist():
            if item.filename == PROVENANCE_MEMBER:
                continue
            data = zin.read(item.filename)
            if item.filename == "3D/3dmodel.model":
                try:
                    root = ET.fromstring(data)
                    ns = MODEL_NS
                    if root.tag.startswith("{") and "}" in root.tag:
                        ns = root.tag[1 : root.tag.index("}")]
                        ET.register_namespace("", ns)

                    def set_meta(name: str, value: str) -> None:
                        tag = f"{{{ns}}}metadata"
                        for existing in root.findall(tag):
                            if existing.attrib.get("name") == name:
                                existing.text = value
                                return
                        el = ET.Element(tag, {"name": name})
                        el.text = value
                        root.insert(0, el)

                    desc_parts = []
                    if prov.get("command"):
                        desc_parts.append(f"Command: {prov['command']}")
                    git_info = prov.get("git")
                    if isinstance(git_info, dict) and git_info.get("short_commit"):
                        dirty = " (dirty)" if git_info.get("dirty") else ""
                        desc_parts.append(
                            f"Git: {git_info['short_commit']}{dirty}"
                        )
                    if prov.get("elephant_foot_chamfer_mm") is not None:
                        desc_parts.append(
                            f"BottomChamferMM: {prov['elephant_foot_chamfer_mm']}"
                        )
                    set_meta("Title", str(prov.get("source_step", three_mf_path.stem)))
                    set_meta("Application", "moonbit-19-cad / solidcraft-cli")
                    set_meta("CreationDate", str(prov.get("created_utc", "")))
                    if desc_parts:
                        set_meta("Description", " | ".join(desc_parts))
                    _wrap_multibody_assembly(root, ns, three_mf_path.stem)
                    data = ET.tostring(root, encoding="utf-8", xml_declaration=True)
                except ET.ParseError:
                    pass
            zout.writestr(item, data)
        zout.writestr(
            PROVENANCE_MEMBER,
            (json.dumps(prov, indent=2, sort_keys=True) + "\n").encode("utf-8"),
        )
    tmp_path.replace(three_mf_path)


def read_3mf_provenance(three_mf_path: Path) -> dict[str, object] | None:
    """Reads ``Metadata/provenance.json`` from a ``.3mf`` archive, if present."""
    with zipfile.ZipFile(three_mf_path, "r") as zf:
        if PROVENANCE_MEMBER not in zf.namelist():
            return None
        return json.loads(zf.read(PROVENANCE_MEMBER).decode("utf-8"))


def export_one(
    tool: str,
    step: Path,
    formats: list[str],
    quality: str,
    timeout: float,
    build_dir: Path | None = None,
    command_override: str | None = None,
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
    for fmt, out in outputs.items():
        if out.is_file() and out.stat().st_size > 0:
            if fmt == "3mf":
                prov = build_provenance(
                    step,
                    quality=quality,
                    build_dir=build_dir,
                    command_override=command_override,
                )
                inject_3mf_provenance(out, prov)
            written.append(out)
        else:
            failed.append(out)
    return written, failed, ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Convert printable STEP file(s) to 3MF (with embedded MoonBit "
            "provenance metadata) and/or STL."
        ),
    )
    parser.add_argument(
        "target",
        type=Path,
        help="build/<example> directory, a single .step file, or a .3mf with --inspect",
    )
    parser.add_argument(
        "--inspect",
        action="store_true",
        help="print embedded provenance metadata from a .3mf file and exit",
    )
    parser.add_argument(
        "--command",
        default=None,
        help="override the MoonBit command recorded in .3mf provenance metadata",
    )
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

    if args.inspect:
        if not args.target.is_file():
            print(f"error: file not found: {args.target}", file=sys.stderr)
            return 2
        prov = read_3mf_provenance(args.target)
        if prov is None:
            print(
                f"no {PROVENANCE_MEMBER} metadata found in {args.target}",
                file=sys.stderr,
            )
            return 1
        print(json.dumps(prov, indent=2, sort_keys=True))
        return 0

    formats = [part.strip().lower() for part in args.formats.split(",") if part.strip()]
    if not formats or any(fmt not in FORMATS for fmt in formats):
        print(
            f"error: --formats must be a comma-separated subset of "
            f"{', '.join(FORMATS)}",
            file=sys.stderr,
        )
        return 2

    target = args.target
    build_dir: Path | None = None
    if target.is_file() and target.suffix.lower() in (".step", ".stp"):
        steps = [target]
    elif target.is_dir():
        build_dir = target
        printable = target / "printable"
        if not printable.is_dir():
            print(f"error: no printable/ directory in {target}", file=sys.stderr)
            return 2
        steps = sorted(printable.glob("*.step"))
        if not steps:
            print(f"error: no *.step files in {printable}", file=sys.stderr)
            return 2
    else:
        print(f"error: build directory or STEP file not found: {target}", file=sys.stderr)
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
            build_dir=build_dir,
            command_override=args.command,
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
