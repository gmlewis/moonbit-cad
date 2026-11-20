#!/usr/bin/env python3
"""Tests for scripts/rl_env.py.

Loads the generated build/08 and build/09 packages and checks the Gym-style
reset/step contract, finite observations, and domain randomization.

Usage:
    python3 scripts/rl_env_test.py
"""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))


def load_env_module():
    spec = importlib.util.spec_from_file_location("rl_env", HERE / "rl_env.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class RlEnvTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rl_env = load_env_module()

    def test_reset_and_rollout_are_finite(self):
        for name in ("09", "08"):
            env = self.rl_env.CadRlEnv(ROOT / "build" / name, randomize=False)
            obs, info = env.reset(seed=0)
            self.assertEqual(obs.shape, (env.obs_dim,))
            self.assertEqual(obs.dtype, np.float32)
            self.assertTrue(np.isfinite(obs).all())
            self.assertIn("base_z", info)
            self.assertEqual(env.action_low.shape, (env.act_dim,))
            self.assertEqual(env.action_high.shape, (env.act_dim,))
            rng = np.random.default_rng(0)
            for _ in range(100):
                obs, reward, terminated, truncated, info = env.step(
                    rng.uniform(-1.0, 1.0, env.act_dim)
                )
                self.assertTrue(np.isfinite(obs).all())
                self.assertTrue(np.isfinite(reward))
                self.assertIsInstance(terminated, bool)
                self.assertIsInstance(truncated, bool)
                if terminated or truncated:
                    break

    def test_domain_randomization_changes_mass_and_friction(self):
        env = self.rl_env.CadRlEnv(ROOT / "build" / "09", randomize=True)
        env.reset(seed=1)
        mass_a = env.model.body_mass.copy()
        friction_a = env.model.geom_friction.copy()
        env.reset(seed=2)
        mass_b = env.model.body_mass.copy()
        friction_b = env.model.geom_friction.copy()
        self.assertFalse(np.allclose(mass_a, mass_b))
        self.assertFalse(np.allclose(friction_a, friction_b))
        for _ in range(20):
            obs, reward, terminated, truncated, _info = env.step(
                np.zeros(env.act_dim)
            )
            self.assertTrue(np.isfinite(obs).all())
            self.assertTrue(np.isfinite(reward))
            if terminated or truncated:
                break

    def test_deterministic_mode_keeps_the_model_defaults(self):
        env = self.rl_env.CadRlEnv(ROOT / "build" / "08", randomize=False)
        env.reset(seed=3)
        self.assertTrue(np.allclose(env.model.body_mass, env._base_mass))
        self.assertTrue(np.allclose(env.model.body_inertia, env._base_inertia))

    def test_unseeded_reset_advances_rng_and_scales_inertia_and_velocity_bias(self):
        env = self.rl_env.CadRlEnv(ROOT / "build" / "09", randomize=True)
        obs_a, _ = env.reset(seed=10)
        mass_a = env.model.body_mass.copy()
        inertia_a = env.model.body_inertia.copy()
        bias_a = env.model.actuator_biasprm.copy()
        # Unseeded reset must draw a fresh domain-randomization sample.
        obs_b, _ = env.reset()
        self.assertFalse(np.allclose(mass_a, env.model.body_mass))
        self.assertFalse(np.allclose(inertia_a, env.model.body_inertia))
        self.assertFalse(np.allclose(bias_a[:, 2], env.model.actuator_biasprm[:, 2]))
        # obs_noise_std > 0 must perturb observations across resets.
        self.assertFalse(np.allclose(obs_a, obs_b))

    def test_nested_termination_limits_and_single_step_push(self):
        env = self.rl_env.CadRlEnv(ROOT / "build" / "09", randomize=True, episode_steps=50)
        max_tilt, min_z = env._termination_limits()
        self.assertAlmostEqual(max_tilt, 55.0)
        self.assertAlmostEqual(min_z, 0.2)
        env.reset(seed=5)
        # Force push to fire on step 0 and confirm xfrc_applied is cleared
        # immediately after the step so only 1x impulse is delivered.
        env.push_time_s = 0.0
        env.step(np.zeros(env.act_dim))
        self.assertTrue(env.push_applied)
        self.assertTrue(
            np.allclose(env.data.xfrc_applied[env.root_body], 0.0)
        )

    def test_body_frame_velocity_and_target_vel_reward(self):
        env = self.rl_env.CadRlEnv(ROOT / "build" / "08", randomize=False)
        env.reset(seed=0)
        # Rotate robot 90 deg about Z (facing +Y) and move +1 m/s along world +Y.
        env.data.qpos[env.root_qadr + 3 : env.root_qadr + 7] = [
            np.cos(np.pi / 4.0),
            0.0,
            0.0,
            np.sin(np.pi / 4.0),
        ]
        env.data.qvel[env.root_dadr : env.root_dadr + 3] = [0.0, 1.0, 0.0]
        obs, rot = env._observation()
        # obs[7:10] is body_lin_vel * base_lin_vel_scale (0.5): forward body_vx = +1.0 -> +0.5
        self.assertAlmostEqual(float(obs[7]), 0.5, places=4)
        self.assertAlmostEqual(float(obs[8]), 0.0, places=4)
        # Moving at target_vel_x_mps (0.5 m/s) in body +X must score higher
        # than standing still (0.0 m/s) or overshooting (1.5 m/s).
        env.data.qvel[env.root_dadr : env.root_dadr + 3] = [0.0, 0.5, 0.0]
        r_target = env._reward(np.zeros(env.act_dim), rot)
        env.data.qvel[env.root_dadr : env.root_dadr + 3] = [0.0, 0.0, 0.0]
        r_still = env._reward(np.zeros(env.act_dim), rot)
        env.data.qvel[env.root_dadr : env.root_dadr + 3] = [0.0, 1.5, 0.0]
        r_overshoot = env._reward(np.zeros(env.act_dim), rot)
        self.assertGreater(r_target, r_still)
        self.assertGreater(r_target, r_overshoot)


if __name__ == "__main__":
    unittest.main(verbosity=2)
