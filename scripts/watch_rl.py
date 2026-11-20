#!/usr/bin/env python3
"""Interactive MuJoCo 3D viewer for a gmlewis/cad example and trained RL policy.

On macOS, launch via ``./watch-rl.sh 09`` (which invokes ``mjpython`` so
``mujoco.viewer.launch_passive`` can open its native window). Pass ``--zero``
to hold the standing home pose with no policy, or ``--headless`` for a single
non-GUI rollout that prints JSON telemetry.

Examples:
    ./watch-rl.sh 09
    ./watch-rl.sh 09 --speed 0.5 --randomize
    ./watch-rl.sh 08
    ./watch-rl.sh 09 --zero
    python3 scripts/watch_rl.py --example 09 --headless --episode-steps 60
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from pathlib import Path

import mujoco
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from rl_env import CadRlEnv  # noqa: E402
import train_rl  # noqa: E402


def load_policy(policy_path: Path, obs_dim: int, act_dim: int):
    if not policy_path.is_file():
        raise SystemExit(
            f"error: {policy_path} is missing.\n"
            "Train a policy first (e.g. ./train-rl.sh 09) or pass --zero to hold home stance."
        )
    payload = json.loads(policy_path.read_text())
    theta = train_rl.theta_from_policy(payload, obs_dim, act_dim)
    mean = np.asarray(payload["obs_mean"], dtype=np.float64)
    std = np.asarray(payload["obs_std"], dtype=np.float64)
    policy_kind = str(payload.get("policy", "linear"))
    hidden = int(payload.get("hidden", 0))
    return theta, mean, std, policy_kind, hidden


def make_action_fn(args, build_dir: Path, env: CadRlEnv):
    if args.zero:
        zeros = np.zeros(env.act_dim, dtype=np.float64)
        return lambda _obs: zeros, "zero-hold"
    policy_path = (
        Path(args.policy_file)
        if args.policy_file
        else build_dir / "rl" / "policy.json"
    )
    theta, mean, std, policy_kind, hidden = load_policy(
        policy_path, env.obs_dim, env.act_dim
    )

    def act(obs):
        nobs = train_rl.normalize_obs(obs, mean, std)
        return train_rl.predict(theta, nobs, policy_kind, env.obs_dim, env.act_dim, hidden)

    return act, f"{policy_kind} ({policy_path})"


def run_headless(env: CadRlEnv, action_fn, seed: int) -> dict:
    obs, _info = env.reset(seed=seed)
    total_return = 0.0
    forward_vels = []
    steps = 0
    terminated = False
    truncated = False
    while True:
        act = action_fn(obs)
        obs, reward, terminated, truncated, info = env.step(act)
        total_return += reward
        forward_vels.append(info["forward_vel"])
        steps += 1
        if terminated or truncated:
            break
    return {
        "steps": steps,
        "return": total_return,
        "mean_forward_vel": float(np.mean(forward_vels)) if forward_vels else 0.0,
        "survival_s": steps * env.control_dt,
        "terminated": terminated,
        "truncated": truncated,
        "finite": bool(math.isfinite(total_return)),
    }


def run_interactive(env: CadRlEnv, action_fn, args, label: str) -> int:
    import mujoco.viewer

    speed = max(0.05, float(args.speed))
    seed = int(args.seed)
    episode = 1
    obs, _info = env.reset(seed=seed)
    ep_return = 0.0
    ep_fwd = []
    ep_steps = 0

    print(f"watch-rl: {env.build_dir.name} | policy: {label} | speed: {speed:g}x")
    print(
        "controls: double-click body + Ctrl+right-drag to push | "
        "Space: pause | Backspace: reset | Esc: quit"
    )

    with mujoco.viewer.launch_passive(env.model, env.data) as viewer:
        viewer.cam.distance = 1.6
        viewer.cam.elevation = -22.0
        viewer.cam.azimuth = 135.0
        while viewer.is_running():
            t0 = time.perf_counter()
            act = action_fn(obs)
            obs, reward, terminated, truncated, info = env.step(act)
            ep_return += reward
            ep_fwd.append(info["forward_vel"])
            ep_steps += 1

            if not args.no_follow:
                viewer.cam.lookat[:] = env.data.qpos[
                    env.root_qadr : env.root_qadr + 3
                ]

            if terminated or truncated:
                mean_v = float(np.mean(ep_fwd)) if ep_fwd else 0.0
                reason = "fell" if terminated else "reset"
                print(
                    f"episode {episode}: return={ep_return:.2f} "
                    f"forward={mean_v:.3f} m/s survival={ep_steps * env.control_dt:.2f}s "
                    f"({reason})"
                )
                episode += 1
                seed += 1
                obs, _info = env.reset(seed=seed)
                ep_return = 0.0
                ep_fwd = []
                ep_steps = 0

            viewer.sync()
            sleep_s = (env.control_dt / speed) - (time.perf_counter() - t0)
            if sleep_s > 0.0:
                time.sleep(sleep_s)
    return 0


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--example", help="Example number or directory name (e.g. 09)")
    parser.add_argument("--build-dir", help="Explicit build/<n> directory")
    parser.add_argument(
        "--policy-file", help="Path to policy.json (default <build-dir>/rl/policy.json)"
    )
    parser.add_argument(
        "--zero",
        action="store_true",
        help="Ignore policy.json and hold the standing home pose",
    )
    parser.add_argument(
        "--speed",
        type=float,
        default=1.0,
        help="Playback speed multiplier (e.g. 0.5 for half-speed slow motion)",
    )
    parser.add_argument(
        "--episode-steps",
        type=int,
        default=1000,
        help="Control steps per episode before auto-reset (default 1000 = 10 s)",
    )
    parser.add_argument(
        "--randomize",
        action="store_true",
        help="Enable domain randomization and random pushes during playback",
    )
    parser.add_argument(
        "--no-follow",
        action="store_true",
        help="Keep the camera fixed instead of tracking the robot chassis",
    )
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument(
        "--headless",
        action="store_true",
        help="Run one rollout without opening a GUI window and print JSON summary",
    )
    return parser.parse_args(argv)


def main(argv):
    args = parse_args(argv)
    build_dir = train_rl.resolve_build_dir(args.example, args.build_dir)
    env = CadRlEnv(
        build_dir,
        seed=args.seed,
        randomize=bool(args.randomize),
        episode_steps=args.episode_steps,
    )
    action_fn, label = make_action_fn(args, build_dir, env)
    if args.headless:
        result = run_headless(env, action_fn, args.seed)
        result["policy"] = label
        print(json.dumps(result, indent=2))
        return 0
    return run_interactive(env, action_fn, args, label)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
