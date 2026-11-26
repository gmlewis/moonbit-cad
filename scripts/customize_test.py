#!/usr/bin/env python3
"""Tests for scripts/customize.py.

Runs the real ``08-wbr-biped --help`` and checks that the parameter parser
turns its numeric and enum options into UI-ready slider definitions.

Usage:
    python3 scripts/customize_test.py
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CUSTOMIZE = HERE / "customize.py"


def load_customize():
    spec = importlib.util.spec_from_file_location("customize", CUSTOMIZE)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class CustomizeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.customize = load_customize()
        proc = subprocess.run(
            [str(ROOT / "run-example.sh"), "8", "--", "--help"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr)
        cls.help_text = proc.stdout
        cls.params = {p["name"]: p for p in cls.customize.parse_help(cls.help_text)}

    def test_extracts_numeric_sliders(self):
        self.assertIn("scale", self.params)
        scale = self.params["scale"]
        self.assertEqual(scale["kind"], "number")
        self.assertAlmostEqual(scale["default"], 1.0)
        self.assertAlmostEqual(scale["min"], 0.65)
        self.assertAlmostEqual(scale["max"], 2.0)
        self.assertAlmostEqual(scale["step"], 0.01)

        tolerance = self.params["tolerance"]
        self.assertEqual(tolerance["kind"], "number")
        self.assertAlmostEqual(tolerance["default"], 0.2)
        self.assertAlmostEqual(tolerance["min"], 0.02)
        self.assertAlmostEqual(tolerance["max"], 0.5)

    def test_extracts_pose_enum(self):
        self.assertIn("pose", self.params)
        pose = self.params["pose"]
        self.assertEqual(pose["kind"], "enum")
        self.assertEqual(pose["options"], ["standing", "crouched", "tall", "pitched"])
        self.assertEqual(pose["default"], "standing")

    def test_skips_output_paths_and_sentinel_defaults(self):
        for name in ("package", "out", "assembly", "detail", "hipDeg"):
            self.assertNotIn(name, self.params)

    def test_zero_defaults_use_reference_hints(self):
        crank = self.params["crankLength"]
        self.assertEqual(crank["kind"], "number")
        self.assertAlmostEqual(crank["default"], 0.0)
        self.assertGreater(crank["max"], 128.0)

    def test_build_command_forwards_values(self):
        example = self.customize.discover_example("8")
        self.assertEqual(example.name, "08-wbr-biped")
        values = {
            "scale": 1.3,
            "tolerance": 0.15,
            "pose": "crouched",
        }
        command = self.customize.build_command(
            example,
            list(self.params.values()),
            values,
            Path("/tmp/test-package"),
        )
        self.assertIn("--scale", command)
        self.assertIn("1.3", command)
        self.assertIn("--pose", command)
        self.assertIn("crouched", command)
        self.assertIn("--headless", command)
        self.assertIn("--release", command)

    def test_build_command_rejects_out_of_range(self):
        example = self.customize.discover_example("8")
        with self.assertRaises(ValueError):
            self.customize.build_command(
                example,
                list(self.params.values()),
                {"scale": 9.0},
                Path("/tmp/test-package"),
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
