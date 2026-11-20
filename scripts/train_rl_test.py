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

    def test_c99_header_matches_python_predict_including_spikes(self):
        if not shutil.which("cc"):
            self.skipTest("no C compiler on PATH")
        sys.path.insert(0, str(HERE))
        import numpy as np
        import train_rl

        for policy in ("linear", "mlp"):
            with tempfile.TemporaryDirectory() as td:
                td_path = Path(td)
                obs_dim, act_dim, hidden = 10, 4, 8
                rng = np.random.default_rng(7)
                theta = rng.normal(
                    0.0, 0.5, size=train_rl.theta_size(policy, obs_dim, act_dim, hidden)
                )
                mean = rng.normal(0.0, 1.0, size=obs_dim)
                std = rng.uniform(0.5, 2.0, size=obs_dim)
                payload = train_rl.structured_policy(
                    theta, policy, obs_dim, act_dim, hidden
                )
                payload["obs_mean"] = mean.tolist()
                payload["obs_std"] = std.tolist()
                train_rl.write_c_header(
                    td_path / "policy_weights.h", payload, obs_dim, act_dim
                )
                obs = rng.normal(0.0, 1.0, size=obs_dim).astype(np.float32)
                obs[0] = 50.0  # exercises [-10, 10] normalization clamp
                py_act = train_rl.predict(
                    theta,
                    train_rl.normalize_obs(obs, mean, std),
                    policy,
                    obs_dim,
                    act_dim,
                    hidden,
                )
                arr = ", ".join(train_rl.c_float(v) for v in obs)
                driver = td_path / "driver.c"
                driver.write_text(
                    "#include <stdio.h>\n"
                    '#include "policy_weights.h"\n'
                    "int main(void) {\n"
                    f"  float obs[RL_OBS_DIM] = {{{arr}}};\n"
                    "  float act[RL_ACT_DIM];\n"
                    "  rl_policy_step(obs, act);\n"
                    '  for (int i = 0; i < RL_ACT_DIM; ++i) printf("%.9g ", act[i]);\n'
                    '  printf("\\n");\n'
                    "  return 0;\n"
                    "}\n"
                )
                exe = td_path / "driver"
                subprocess.check_call(
                    ["cc", "-std=c99", "-O2", "-I", str(td_path), str(driver), "-lm", "-o", str(exe)]
                )
                out = subprocess.check_output([str(exe)], text=True).strip()
                c_act = np.array([float(x) for x in out.split()])
                max_err = float(np.max(np.abs(py_act - c_act)))
                self.assertLess(max_err, 1.0e-5, f"{policy} C99 parity err={max_err}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
