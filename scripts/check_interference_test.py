#!/usr/bin/env python3
"""Tests for scripts/check_interference.py.

Each test builds a tiny two-box STEP file with solidcraft-cli, then runs the
checker as a subprocess and inspects its exit status, table, and JSON summary.

Usage:
    python3 scripts/check_interference_test.py
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
CHECKER = HERE / "check_interference.py"


def make_boxes(tool: str, directory: Path, dx: float) -> Path:
    """Write two 10 mm boxes with their +X corners separated by ``dx`` mm."""
    directory.mkdir(parents=True, exist_ok=True)
    step = directory / "boxes.step"
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
                "length": 10,
                "width": 10,
                "height": 10,
                "corner": [dx, 0, 0],
                "body_name": "box_b",
            },
        },
        {
            "command": "file.export_step",
            "params": {"path": str(step), "bodies": ["box_a", "box_b"]},
        },
    ]
    script_path = directory / "make-boxes.json"
    script_path.write_text(json.dumps(script))
    proc = subprocess.run(
        [tool, "run", str(script_path), "--validation", "off", "--quiet"],
        capture_output=True,
        text=True,
        timeout=300,
    )
    if proc.returncode != 0 or not step.is_file():
        raise RuntimeError(
            "could not create test boxes: " + (proc.stderr or proc.stdout)
        )
    return step


def run_checker(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(CHECKER), *args],
        capture_output=True,
        text=True,
        timeout=300,
    )


class CheckInterferenceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.tool = shutil.which("solidcraft-cli")
        if cls.tool is None:
            raise unittest.SkipTest("solidcraft-cli is not on PATH")
        cls.tmp = tempfile.TemporaryDirectory(prefix="interf-test-")
        cls.dir = Path(cls.tmp.name)
        cls.separated = make_boxes(cls.tool, cls.dir / "separated", 20.0)
        cls.overlap = make_boxes(cls.tool, cls.dir / "overlap", 5.0)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.tmp.cleanup()

    def test_separated_boxes_pass(self) -> None:
        summary = self.dir / "separated.json"
        result = run_checker(str(self.separated), "--json", str(summary))
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        data = json.loads(summary.read_text())
        self.assertEqual(data["interferences"], [])
        self.assertEqual(data["checked"], 2)

    def test_overlapping_boxes_fail_with_volume(self) -> None:
        summary = self.dir / "overlap.json"
        result = run_checker(
            str(self.overlap),
            "--min-volume",
            "400",
            "--json",
            str(summary),
        )
        self.assertNotEqual(result.returncode, 0, result.stdout)
        data = json.loads(summary.read_text())
        self.assertEqual(len(data["interferences"]), 1)
        hit = data["interferences"][0]
        self.assertAlmostEqual(hit["volume_mm3"], 500.0, delta=0.5)
        center = hit["center"]
        self.assertAlmostEqual(center[0], 7.5, delta=0.01)
        self.assertAlmostEqual(center[1], 5.0, delta=0.01)
        self.assertAlmostEqual(center[2], 5.0, delta=0.01)
        self.assertIn("box_a", result.stdout)
        self.assertIn("box_b", result.stdout)

    def test_exclude_pattern_skips_matching_pair(self) -> None:
        summary = self.dir / "excluded.json"
        result = run_checker(
            str(self.overlap),
            "--min-volume",
            "400",
            "--exclude-pattern",
            "box_b",
            "--json",
            str(summary),
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        data = json.loads(summary.read_text())
        self.assertEqual(data["interferences"], [])
        self.assertGreaterEqual(data["excluded_count"], 1)

    def test_min_volume_ignores_small_overlap(self) -> None:
        summary = self.dir / "min-volume.json"
        result = run_checker(
            str(self.overlap),
            "--min-volume",
            "600",
            "--json",
            str(summary),
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
        data = json.loads(summary.read_text())
        self.assertEqual(data["interferences"], [])

    def test_missing_step_file_is_a_usage_error(self) -> None:
        result = run_checker(str(self.dir / "missing.step"))
        self.assertEqual(result.returncode, 2)
        self.assertIn("not found", (result.stderr + result.stdout).lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
