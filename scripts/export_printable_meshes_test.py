#!/usr/bin/env python3
"""Tests for scripts/export_printable_meshes.py.

Builds a 10 mm STEP cube with solidcraft-cli, converts it to 3MF and STL, and
validates the resulting archives/meshes.

Usage:
    python3 scripts/export_printable_meshes_test.py
"""

from __future__ import annotations

import json
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXPORTER = HERE / "export_printable_meshes.py"


def make_cube(tool: str, directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    step = directory / "CUBE.step"
    script = [
        {
            "command": "solid.box",
            "params": {
                "length": 10,
                "width": 10,
                "height": 10,
                "corner": [0, 0, 0],
                "body_name": "cube",
            },
        },
        {"command": "file.export_step", "params": {"path": str(step)}},
    ]
    script_path = directory / "make-cube.json"
    script_path.write_text(json.dumps(script))
    proc = subprocess.run(
        [tool, "run", str(script_path), "--validation", "off", "--quiet"],
        capture_output=True,
        text=True,
        timeout=300,
    )
    if proc.returncode != 0 or not step.is_file():
        raise RuntimeError("could not create cube: " + (proc.stderr or proc.stdout))
    return step


class ExportPrintableMeshesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tool = shutil.which("solidcraft-cli")
        if cls.tool is None:
            raise unittest.SkipTest("solidcraft-cli is not on PATH")
        cls.tmp = tempfile.TemporaryDirectory(prefix="mesh-export-test-")
        cls.build = Path(cls.tmp.name) / "build"
        cls.printable = cls.build / "printable"
        make_cube(cls.tool, cls.printable)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tmp.cleanup()

    def test_exports_valid_3mf_and_stl(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(EXPORTER),
                str(self.build),
                "--formats",
                "3mf,stl",
            ],
            capture_output=True,
            text=True,
            timeout=300,
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        three_mf = self.printable / "CUBE.3mf"
        stl = self.printable / "CUBE.stl"
        self.assertTrue(three_mf.is_file(), result.stdout)
        self.assertTrue(stl.is_file(), result.stdout)
        self.assertGreater(three_mf.stat().st_size, 0)
        self.assertGreater(stl.stat().st_size, 0)

        with zipfile.ZipFile(three_mf) as archive:
            self.assertIsNone(archive.testzip())
            self.assertIn("3D/3dmodel.model", archive.namelist())
            self.assertIn("Metadata/provenance.json", archive.namelist())
            prov = json.loads(archive.read("Metadata/provenance.json").decode("utf-8"))
            self.assertEqual(prov["source_step"], "CUBE.step")
            self.assertEqual(prov["mesh_export"]["quality"], "fine")
            self.assertTrue(prov["source_step_sha256"])

        data = stl.read_bytes()
        self.assertGreaterEqual(len(data), 84)
        triangles = struct.unpack("<I", data[80:84])[0]
        self.assertGreater(triangles, 0)

    def test_single_step_and_inspect_command_provenance(self) -> None:
        cmd = "moon run examples/02-planetary-actuator -- --package build/02 --tolerance 0.15"
        step = self.printable / "CUBE.step"
        result = subprocess.run(
            [
                sys.executable,
                str(EXPORTER),
                str(step),
                "--formats",
                "3mf",
                "--command",
                cmd,
            ],
            capture_output=True,
            text=True,
            timeout=300,
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        three_mf = self.printable / "CUBE.3mf"
        insp = subprocess.run(
            [sys.executable, str(EXPORTER), "--inspect", str(three_mf)],
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(insp.returncode, 0, insp.stderr or insp.stdout)
        prov = json.loads(insp.stdout)
        self.assertEqual(prov["command"], cmd)
        self.assertEqual(prov["source_step"], "CUBE.step")

    def test_multibody_3mf_is_preassembled(self) -> None:
        import xml.etree.ElementTree as ET

        step = self.printable / "TWOBOX.step"
        script = [
            {
                "command": "solid.box",
                "params": {
                    "length": 10,
                    "width": 10,
                    "height": 10,
                    "corner": [0, 0, 0],
                    "body_name": "box_a",
                },
            },
            {
                "command": "solid.box",
                "params": {
                    "length": 6,
                    "width": 6,
                    "height": 10,
                    "corner": [8, 2, 0],
                    "body_name": "box_b",
                },
            },
            {"command": "file.export_step", "params": {"path": str(step)}},
        ]
        script_path = self.printable / "make-twobox.json"
        script_path.write_text(json.dumps(script))
        proc = subprocess.run(
            [self.tool, "run", str(script_path), "--validation", "off", "--quiet"],
            capture_output=True,
            text=True,
            timeout=300,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr or proc.stdout)

        result = subprocess.run(
            [sys.executable, str(EXPORTER), str(step), "--formats", "3mf"],
            capture_output=True,
            text=True,
            timeout=300,
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        three_mf = self.printable / "TWOBOX.3mf"
        with zipfile.ZipFile(three_mf) as archive:
            root = ET.fromstring(archive.read("3D/3dmodel.model"))
        ns = root.tag[1 : root.tag.index("}")]
        build_items = root.findall(f"{{{ns}}}build/{{{ns}}}item")
        self.assertEqual(len(build_items), 1)
        asm_id = build_items[0].attrib["objectid"]
        asm_obj = next(
            o
            for o in root.findall(f"{{{ns}}}resources/{{{ns}}}object")
            if o.attrib.get("id") == asm_id
        )
        comps = asm_obj.findall(f"{{{ns}}}components/{{{ns}}}component")
        self.assertEqual(len(comps), 2)

    def test_missing_build_directory_is_a_usage_error(self) -> None:
        result = subprocess.run(
            [sys.executable, str(EXPORTER), str(Path(self.tmp.name) / "nope")],
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("not found", (result.stderr + result.stdout).lower())

    def test_unknown_format_is_a_usage_error(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(EXPORTER),
                str(self.build),
                "--formats",
                "obj",
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
