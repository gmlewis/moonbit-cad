#!/usr/bin/env python3
"""Tests for scripts/train_rl.py.

Runs a very short ARS training pass on build/09, checks the exported policy
files, compiles the C header when a C compiler is available, and evaluates the
saved policy.

Usage:
    python3 scripts/train_rl_test.py
"""

from __future__ import annotations

import json
import math
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
TRAINER = HERE / "train_rl.py"


class TrainRlTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out_dir = Path(tempfile.mkdtemp(prefix="cad-rl-test-"))

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.out_dir, ignore_errors=True)

    def run_trainer(self, *args):
        command = [
            sys.executable,
            str(TRAINER),
            "--example",
            "09",
            "--out-dir",
            str(self.out_dir),
            *args,
        ]
        return subprocess.run(
            command, cwd=ROOT, capture_output=True, text=True, timeout=900
        )

    def test_ars_smoke_training_and_policy_export(self):
        proc = self.run_trainer(
            "--iterations",
            "3",
            "--directions",
            "4",
            "--top-k",
            "2",
            "--episode-steps",
            "60",
            "--seed",
            "1",
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        policy_path = self.out_dir / "policy.json"
        header_path = self.out_dir / "policy_weights.h"
        log_path = self.out_dir / "training_log.csv"
        self.assertTrue(policy_path.is_file())
        self.assertTrue(header_path.is_file())
        self.assertTrue(log_path.is_file())
        payload = json.loads(policy_path.read_text())
        self.assertEqual(payload["policy"], "linear")
        self.assertIn("W", payload)
        self.assertIn("obs_mean", payload)
        self.assertIn("initial_return", payload["meta"])

        if shutil.which("cc"):
            probe = self.out_dir / "probe.c"
            probe.write_text(
                '#include "policy_weights.h"\n'
                "int main(void) {\n"
                "  float obs[RL_OBS_DIM] = {0};\n"
                "  float act[RL_ACT_DIM];\n"
                "  rl_policy_step(obs, act);\n"
                "  return 0;\n"
                "}\n"
            )
            check = subprocess.run(
                [
                    "cc",
                    "-std=c99",
                    "-fsyntax-only",
                    "-I",
                    str(self.out_dir),
                    str(probe),
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(check.returncode, 0, check.stderr)

    def test_eval_only_reports_finite_return(self):
        if not (self.out_dir / "policy.json").is_file():
            setup = self.run_trainer(
                "--iterations",
                "1",
                "--directions",
                "2",
                "--top-k",
                "1",
                "--episode-steps",
                "30",
                "--seed",
                "1",
            )
            self.assertEqual(setup.returncode, 0, setup.stderr)
        proc = self.run_trainer(
            "--eval-only",
            "--episode-steps",
            "60",
            "--seed",
            "2",
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        result = json.loads(proc.stdout)
        self.assertTrue(result["finite"])
        self.assertTrue(math.isfinite(result["mean_return"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
