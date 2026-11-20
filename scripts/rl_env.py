#!/usr/bin/env python3
"""Gymnasium-style MuJoCo environment driven by a build package's rl_task.json.

Requires only ``mujoco`` and ``numpy``. The observation/action/reward contract
comes from ``<build_dir>/rl_task.json``; the model is the same MJCF written by
``--package``.

    env = CadRlEnv("build/09")
    obs, info = env.reset(seed=0)
    obs, reward, terminated, truncated, info = env.step(env.action_space_sample())
"""

from __future__ import annotations

import json
import math
from pathlib import Path

import mujoco
import numpy as np

DEFAULT_OBS_SCALES = {
    "base_z": 1.0,
    "projected_gravity": 1.0,
    "base_ang_vel": 0.25,
    "base_lin_vel": 0.5,
    "joint_pos": 1.0,
    "joint_vel": 0.05,
    "prev_action": 1.0,
}


def quat_to_matrix(q):
    w, x, y, z = q
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


def tilt_deg(rotation):
    """Angle between the base +Z axis and world +Z, in degrees."""
    return math.degrees(math.acos(max(-1.0, min(1.0, float(rotation[2, 2])))))


class CadRlEnv:
    """Observation/action/reward environment for a gmlewis/cad build package."""

    def __init__(
        self,
        build_dir,
        seed=0,
        randomize=True,
        episode_steps=None,
        obs_scales=None,
    ):
        self.build_dir = Path(build_dir)
        self.task_path = self.build_dir / "rl_task.json"
        if not self.task_path.is_file():
            raise FileNotFoundError(
                f"{self.task_path} missing; run ./build-part.sh with a component "
                "that declares an RlTaskSpec"
            )
        self.task = json.loads(self.task_path.read_text())
        self.model = mujoco.MjModel.from_xml_path(
            str(self.build_dir / self.task["mjcf_path"])
        )
        self.data = mujoco.MjData(self.model)
        self.randomize = bool(randomize)
        self.rng = np.random.default_rng(seed)
        self.seed = int(seed)
        self.control_dt = float(self.task.get("control_dt_s", 0.01))
        self.episode_len_s = float(self.task.get("episode_len_s", 10.0))
        self.episode_steps = (
            int(episode_steps)
            if episode_steps is not None
            else max(1, int(round(self.episode_len_s / self.control_dt)))
        )
        self.substeps = max(
            1, int(round(self.control_dt / float(self.model.opt.timestep)))
        )
        self.obs_scales = dict(DEFAULT_OBS_SCALES)
        if obs_scales:
            self.obs_scales.update(obs_scales)

        self._resolve_actuators()
        self._resolve_free_joint()
        self._save_model_defaults()

        self.obs_dim = 10 + 3 * len(self.actuators)
        self.act_dim = len(self.actuators)
        self.action_low = np.full(self.act_dim, -1.0, dtype=np.float32)
        self.action_high = np.full(self.act_dim, 1.0, dtype=np.float32)
        self.step_count = 0
        self.time_s = 0.0
        self.prev_action = np.zeros(self.act_dim, dtype=np.float64)
        self.push_time_s = None
        self.push_applied = False

    # ------------------------------------------------------------------ setup
    def _resolve_actuators(self):
        self.actuators = []
        home = self.task.get("home_qpos", {})
        for entry in self.task.get("actuators", []):
            joint = entry["joint"]
            jid = mujoco.mj_name2id(self.model, mujoco.mjtObj.mjOBJ_JOINT, joint)
            if jid < 0:
                raise ValueError(f"rl_task joint '{joint}' is missing from the MJCF")
            matches = np.where(self.model.actuator_trnid[:, 0] == jid)[0]
            if len(matches) == 0:
                raise ValueError(f"no MJCF actuator drives joint '{joint}'")
            self.actuators.append(
                {
                    "joint": joint,
                    "kind": entry.get("kind", "motor"),
                    "actuator": int(matches[0]),
                    "qadr": int(self.model.jnt_qposadr[jid]),
                    "dadr": int(self.model.jnt_dofadr[jid]),
                    "home": float(home.get(joint, 0.0)),
                    "ctrl_min": float(entry.get("ctrl_min", -1.0)),
                    "ctrl_max": float(entry.get("ctrl_max", 1.0)),
                    "scale": float(entry.get("scale", 1.0)),
                }
            )
        if not self.actuators:
            raise ValueError("rl_task.json declares no actuators")

    def _resolve_free_joint(self):
        self.free_joint = -1
        for jid in range(self.model.njnt):
            if self.model.jnt_type[jid] == mujoco.mjtJoint.mjJNT_FREE:
                self.free_joint = jid
                break
        if self.free_joint < 0:
            raise ValueError("robot has no free joint (floating base)")
        self.root_body = int(self.model.jnt_bodyid[self.free_joint])
        self.root_qadr = int(self.model.jnt_qposadr[self.free_joint])
        self.root_dadr = int(self.model.jnt_dofadr[self.free_joint])

    def _save_model_defaults(self):
        self._base_mass = self.model.body_mass.copy()
        self._base_friction = self.model.geom_friction.copy()
        self._base_gain = self.model.actuator_gainprm.copy()
        self._base_bias = self.model.actuator_biasprm.copy()
        self._friction_geoms = []
        for gid in range(self.model.ngeom):
            name = (
                mujoco.mj_id2name(self.model, mujoco.mjtObj.mjOBJ_GEOM, gid) or ""
            ).lower()
            if name == "floor" or "tire" in name or "wheel" in name:
                self._friction_geoms.append(gid)

    # ------------------------------------------------------------ randomization
    def _apply_domain_randomization(self):
        rand = self.task.get("domain_rand", {})
        mass_range = rand.get("mass_scale_range", [1.0, 1.0])
        friction_range = rand.get("friction_range", [1.0, 1.0])
        kp_range = rand.get("kp_scale_range", [1.0, 1.0])
        mass_scale = float(self.rng.uniform(mass_range[0], mass_range[1]))
        friction_scale = float(self.rng.uniform(friction_range[0], friction_range[1]))
        kp_scale = float(self.rng.uniform(kp_range[0], kp_range[1]))
        self.model.body_mass[1:] = self._base_mass[1:] * mass_scale
        for gid in self._friction_geoms:
            self.model.geom_friction[gid, 0] = (
                self._base_friction[gid, 0] * friction_scale
            )
        for aid in range(self.model.nu):
            self.model.actuator_gainprm[aid, 0] = (
                self._base_gain[aid, 0] * kp_scale
            )
            if abs(self._base_bias[aid, 1]) > 0.0:
                self.model.actuator_biasprm[aid, 1] = (
                    self._base_bias[aid, 1] * kp_scale
                )
        mujoco.mj_setConst(self.model, self.data)

    # --------------------------------------------------------------- obs/reward
    def _projected_gravity(self):
        q = self.data.qpos[self.root_qadr + 3 : self.root_qadr + 7]
        rotation = quat_to_matrix(q)
        return rotation.T @ np.array([0.0, 0.0, -1.0])

    def _observation(self):
        rotation = quat_to_matrix(
            self.data.qpos[self.root_qadr + 3 : self.root_qadr + 7]
        )
        base_z = np.array([self.data.qpos[self.root_qadr + 2]])
        gravity = self._projected_gravity() * self.obs_scales["projected_gravity"]
        ang_vel = (
            self.data.qvel[self.root_dadr + 3 : self.root_dadr + 6]
            * self.obs_scales["base_ang_vel"]
        )
        lin_vel = (
            self.data.qvel[self.root_dadr : self.root_dadr + 3]
            * self.obs_scales["base_lin_vel"]
        )
        joint_pos = np.array(
            [
                (self.data.qpos[a["qadr"]] - a["home"]) * self.obs_scales["joint_pos"]
                for a in self.actuators
            ]
        )
        joint_vel = np.array(
            [
                self.data.qvel[a["dadr"]] * self.obs_scales["joint_vel"]
                for a in self.actuators
            ]
        )
        obs = np.concatenate(
            [
                base_z * self.obs_scales["base_z"],
                gravity,
                ang_vel,
                lin_vel,
                joint_pos,
                joint_vel,
                self.prev_action * self.obs_scales["prev_action"],
            ]
        )
        return np.clip(obs, -10.0, 10.0).astype(np.float32), rotation

    def _map_action(self, action):
        action = np.clip(np.asarray(action, dtype=np.float64), -1.0, 1.0)
        for index, actuator in enumerate(self.actuators):
            value = action[index]
            if actuator["kind"] == "position":
                target = actuator["home"] + value * actuator["scale"]
            else:
                target = value * actuator["scale"]
            target = max(actuator["ctrl_min"], min(actuator["ctrl_max"], target))
            self.data.ctrl[actuator["actuator"]] = target
        return action

    def _reward(self, action, rotation):
        weights = self.task.get("rewards", {})
        lin_vel_x = float(self.data.qvel[self.root_dadr])
        base_z = float(self.data.qpos[self.root_qadr + 2])
        target_z = float(self.task.get("target_base_height_m", base_z))
        upright = float(rotation[2, 2])
        forward = float(weights.get("forward_vel", 1.0)) * lin_vel_x
        height = float(weights.get("target_height", 1.0)) * math.exp(
            -((base_z - target_z) / 0.15) ** 2
        )
        upright_term = float(weights.get("upright", 1.0)) * upright
        energy = float(weights.get("energy", 0.0)) * float(
            np.mean(np.square(action))
        )
        smoothness = float(weights.get("smoothness", 0.0)) * float(
            np.mean(np.square(action - self.prev_action))
        )
        alive = float(weights.get("alive", 0.0))
        return forward + height + upright_term + energy + smoothness + alive

    # --------------------------------------------------------------------- API
    def reset(self, seed=None):
        if seed is not None:
            self.seed = int(seed)
        self.rng = np.random.default_rng(self.seed)
        self.model.body_mass[:] = self._base_mass
        self.model.geom_friction[:] = self._base_friction
        self.model.actuator_gainprm[:] = self._base_gain
        self.model.actuator_biasprm[:] = self._base_bias
        if self.randomize:
            self._apply_domain_randomization()
        mujoco.mj_resetDataKeyframe(self.model, self.data, 0)
        mujoco.mj_forward(self.model, self.data)
        self.prev_action = np.zeros(self.act_dim, dtype=np.float64)
        self.step_count = 0
        self.time_s = 0.0
        self.push_applied = False
        push = float(self.task.get("domain_rand", {}).get("push_impulse_ns", 0.0))
        if self.randomize and push > 0.0:
            self.push_time_s = float(
                self.rng.uniform(0.2, 0.8) * self.episode_steps * self.control_dt
            )
        else:
            self.push_time_s = None
        self.data.xfrc_applied[self.root_body, :] = 0.0
        # Hold the home pose until the policy acts.
        for actuator in self.actuators:
            target = 0.0 if actuator["kind"] != "position" else actuator["home"]
            target = max(actuator["ctrl_min"], min(actuator["ctrl_max"], target))
            self.data.ctrl[actuator["actuator"]] = target
        obs, _rotation = self._observation()
        return obs, {
            "time_s": 0.0,
            "base_z": float(self.data.qpos[self.root_qadr + 2]),
            "forward_vel": float(self.data.qvel[self.root_dadr]),
        }

    def step(self, action):
        action = self._map_action(action)
        push = float(self.task.get("domain_rand", {}).get("push_impulse_ns", 0.0))
        if self.push_time_s is not None:
            just_before = self.time_s <= self.push_time_s
            just_after = self.time_s + self.control_dt > self.push_time_s
            if just_before and just_after and not self.push_applied and push > 0.0:
                direction = self.rng.normal(size=2)
                norm = max(1.0e-9, float(np.linalg.norm(direction)))
                force = push / self.control_dt
                self.data.xfrc_applied[self.root_body, 0] = (
                    direction[0] / norm * force
                )
                self.data.xfrc_applied[self.root_body, 1] = (
                    direction[1] / norm * force
                )
                self.push_applied = True
            elif self.push_applied and self.time_s >= self.push_time_s + self.control_dt:
                self.data.xfrc_applied[self.root_body, :] = 0.0

        for _ in range(self.substeps):
            mujoco.mj_step(self.model, self.data)

        self.step_count += 1
        self.time_s += self.control_dt
        obs, rotation = self._observation()
        reward = self._reward(action, rotation)
        tilt = tilt_deg(rotation)
        base_z = float(self.data.qpos[self.root_qadr + 2])
        finite = bool(np.isfinite(self.data.qpos).all() and np.isfinite(reward))
        terminated = (
            not finite
            or tilt > float(self.task.get("termination_tilt_deg", 88.0))
            or base_z < float(self.task.get("termination_min_z_m", -1.0))
        )
        truncated = self.step_count >= self.episode_steps
        self.prev_action = action
        info = {
            "time_s": self.time_s,
            "base_z": base_z,
            "forward_vel": float(self.data.qvel[self.root_dadr]),
            "tilt_deg": tilt,
            "survival_s": self.time_s,
        }
        return obs, float(reward), bool(terminated), bool(truncated), info

    def action_space_sample(self):
        return self.rng.uniform(self.action_low, self.action_high).astype(np.float32)

    def as_gymnasium_env(self):
        """Optional Gymnasium wrapper; returns None when gymnasium is absent."""
        try:
            import gymnasium as gym
            from gymnasium import spaces
        except ImportError:
            return None

        env = self

        class GymWrapper(gym.Env):
            metadata = {"render_modes": []}

            def __init__(self):
                super().__init__()
                self.observation_space = spaces.Box(
                    low=-10.0, high=10.0, shape=(env.obs_dim,), dtype=np.float32
                )
                self.action_space = spaces.Box(
                    low=-1.0, high=1.0, shape=(env.act_dim,), dtype=np.float32
                )

            def reset(self, *, seed=None, options=None):
                obs, info = env.reset(seed=seed)
                return obs, info

            def step(self, action):
                return env.step(action)

        return GymWrapper()
