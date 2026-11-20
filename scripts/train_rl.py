#!/usr/bin/env python3
"""Train an RL policy for a gmlewis/cad build package.

Default backend is Augmented Random Search (ARS), which needs only ``mujoco``
and ``numpy``. ``--algo ppo`` uses Gymnasium + Stable-Baselines3 when installed.

Examples:
    python3 scripts/train_rl.py --example 09 --iterations 15 --directions 8 \
        --top-k 4 --episode-steps 150
    ./train-rl.sh 09 --policy mlp --iterations 50
    python3 scripts/train_rl.py --example 09 --eval-only --out-dir build/09/rl
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

from rl_env import CadRlEnv  # noqa: E402


def resolve_build_dir(example: str | None, build_dir: str | None) -> Path:
    if build_dir:
        return Path(build_dir)
    if not example:
        raise SystemExit("error: pass --example or --build-dir")
    if example.isdigit():
        candidate = ROOT / "build" / f"{int(example):02d}"
        if candidate.is_dir():
            return candidate
        raise SystemExit(
            f"error: {candidate} is missing; run ./build-part.sh {example}"
        )
    if (ROOT / "build" / example).is_dir():
        return ROOT / "build" / example
    # Directory name such as 09-fox-bot.
    prefix = example.split("-", 1)[0]
    candidate = ROOT / "build" / prefix
    if candidate.is_dir():
        return candidate
    raise SystemExit(f"error: no build package for '{example}'")


# --------------------------------------------------------------------- policy
def theta_size(policy: str, obs_dim: int, act_dim: int, hidden: int) -> int:
    if policy == "linear":
        return act_dim * obs_dim + act_dim
    return hidden * obs_dim + hidden + act_dim * hidden + act_dim


def predict(theta, obs, policy: str, obs_dim: int, act_dim: int, hidden: int):
    if policy == "linear":
        weights = theta[: act_dim * obs_dim].reshape(act_dim, obs_dim)
        bias = theta[act_dim * obs_dim :]
        return np.tanh(weights @ obs + bias)
    offset = 0
    w1 = theta[offset : offset + hidden * obs_dim].reshape(hidden, obs_dim)
    offset += hidden * obs_dim
    b1 = theta[offset : offset + hidden]
    offset += hidden
    w2 = theta[offset : offset + act_dim * hidden].reshape(act_dim, hidden)
    offset += act_dim * hidden
    b2 = theta[offset : offset + act_dim]
    return np.tanh(w2 @ np.tanh(w1 @ obs + b1) + b2)


def structured_policy(theta, policy: str, obs_dim: int, act_dim: int, hidden: int):
    if policy == "linear":
        return {
            "policy": "linear",
            "W": theta[: act_dim * obs_dim].reshape(act_dim, obs_dim).tolist(),
            "b": theta[act_dim * obs_dim :].tolist(),
        }
    offset = 0
    w1 = theta[offset : offset + hidden * obs_dim].reshape(hidden, obs_dim)
    offset += hidden * obs_dim
    b1 = theta[offset : offset + hidden]
    offset += hidden
    w2 = theta[offset : offset + act_dim * hidden].reshape(act_dim, hidden)
    offset += act_dim * hidden
    b2 = theta[offset : offset + act_dim]
    return {
        "policy": "mlp",
        "hidden": hidden,
        "W1": w1.tolist(),
        "b1": b1.tolist(),
        "W2": w2.tolist(),
        "b2": b2.tolist(),
    }


def theta_from_policy(payload, obs_dim: int, act_dim: int):
    if payload["policy"] == "linear":
        return np.concatenate(
            [
                np.asarray(payload["W"], dtype=np.float64).reshape(-1),
                np.asarray(payload["b"], dtype=np.float64).reshape(-1),
            ]
        )
    hidden = int(payload.get("hidden", len(payload["b1"])))
    return np.concatenate(
        [
            np.asarray(payload["W1"], dtype=np.float64).reshape(hidden * obs_dim),
            np.asarray(payload["b1"], dtype=np.float64).reshape(hidden),
            np.asarray(payload["W2"], dtype=np.float64).reshape(act_dim * hidden),
            np.asarray(payload["b2"], dtype=np.float64).reshape(act_dim),
        ]
    )


def normalize_obs(obs, mean, std):
    return np.clip((obs - mean) / std, -10.0, 10.0)


# ------------------------------------------------------------------ evaluation
class Runner:
    def __init__(self, build_dir: Path, randomize: bool, episode_steps: int):
        self.env = CadRlEnv(
            build_dir, seed=0, randomize=randomize, episode_steps=episode_steps
        )
        self.obs_dim = self.env.obs_dim
        self.act_dim = self.env.act_dim
        self.episode_steps = episode_steps

    def rollout(self, theta, mean, std, policy, hidden, seed):
        env = self.env
        obs, _info = env.reset(seed=seed)
        total = 0.0
        forward = []
        steps = 0
        while True:
            action = predict(
                theta,
                normalize_obs(obs, mean, std),
                policy,
                self.obs_dim,
                self.act_dim,
                hidden,
            )
            obs, reward, terminated, truncated, info = env.step(action)
            total += reward
            forward.append(info["forward_vel"])
            steps += 1
            if terminated or truncated:
                break
        return total, float(np.mean(forward)) if forward else 0.0, steps

    def evaluate(self, theta, mean, std, policy, hidden, episodes, seed):
        returns = []
        forwards = []
        steps = []
        for episode in range(episodes):
            value, forward, count = self.rollout(
                theta, mean, std, policy, hidden, seed + episode
            )
            returns.append(value)
            forwards.append(forward)
            steps.append(count)
        return float(np.mean(returns)), float(np.mean(forwards)), float(np.mean(steps))


def collect_obs_stats(runner, episodes=2):
    observations = []
    env = runner.env
    for episode in range(episodes):
        obs, _info = env.reset(seed=1000 + episode)
        observations.append(obs.astype(np.float64))
        while True:
            obs, _r, terminated, truncated, _info = env.step(
                np.zeros(runner.act_dim, dtype=np.float64)
            )
            observations.append(obs.astype(np.float64))
            if terminated or truncated:
                break
    stacked = np.vstack(observations)
    mean = stacked.mean(axis=0)
    std = stacked.std(axis=0)
    std = np.where(std < 1.0e-3, 1.0, std)
    return mean, std


# -------------------------------------------------------------------- writing
def c_float(value):
    text = f"{float(value):.9g}"
    if "." not in text and "e" not in text and "E" not in text:
        text += ".0"
    return text + "f"


def write_c_header(path: Path, payload, obs_dim, act_dim):
    lines = [
        "/* Generated by gmlewis/cad scripts/train_rl.py */",
        "#ifndef RL_POLICY_WEIGHTS_H",
        "#define RL_POLICY_WEIGHTS_H",
        "",
        "#include <math.h>",
        "",
        f"#define RL_OBS_DIM {obs_dim}",
        f"#define RL_ACT_DIM {act_dim}",
        "",
        "static const float RL_OBS_MEAN[RL_OBS_DIM] = {"
        + ", ".join(c_float(v) for v in payload["obs_mean"])
        + "};",
        "static const float RL_OBS_STD[RL_OBS_DIM] = {"
        + ", ".join(c_float(v) for v in payload["obs_std"])
        + "};",
        "",
    ]
    if payload["policy"] == "linear":
        lines.append(
            "static const float RL_W[] = {"
            + ", ".join(c_float(v) for row in payload["W"] for v in row)
            + "};"
        )
        lines.append(
            "static const float RL_B[RL_ACT_DIM] = {"
            + ", ".join(c_float(v) for v in payload["b"])
            + "};"
        )
        lines += [
            "",
            "void rl_policy_step(const float *obs, float *act) {",
            "  float n[RL_OBS_DIM];",
            "  for (int i = 0; i < RL_OBS_DIM; ++i)",
            "    n[i] = (obs[i] - RL_OBS_MEAN[i]) / RL_OBS_STD[i];",
            "  for (int j = 0; j < RL_ACT_DIM; ++j) {",
            "    float acc = RL_B[j];",
            "    for (int i = 0; i < RL_OBS_DIM; ++i)",
            "      acc += RL_W[j * RL_OBS_DIM + i] * n[i];",
            "    act[j] = tanhf(acc);",
            "  }",
            "}",
        ]
    else:
        hidden = int(payload["hidden"])
        lines.append(f"#define RL_HIDDEN {hidden}")
        lines.append(
            "static const float RL_W1[] = {"
            + ", ".join(c_float(v) for row in payload["W1"] for v in row)
            + "};"
        )
        lines.append(
            "static const float RL_B1[RL_HIDDEN] = {"
            + ", ".join(c_float(v) for v in payload["b1"])
            + "};"
        )
        lines.append(
            "static const float RL_W2[] = {"
            + ", ".join(c_float(v) for row in payload["W2"] for v in row)
            + "};"
        )
        lines.append(
            "static const float RL_B2[RL_ACT_DIM] = {"
            + ", ".join(c_float(v) for v in payload["b2"])
            + "};"
        )
        lines += [
            "",
            "void rl_policy_step(const float *obs, float *act) {",
            "  float n[RL_OBS_DIM];",
            "  float h[RL_HIDDEN];",
            "  for (int i = 0; i < RL_OBS_DIM; ++i)",
            "    n[i] = (obs[i] - RL_OBS_MEAN[i]) / RL_OBS_STD[i];",
            "  for (int k = 0; k < RL_HIDDEN; ++k) {",
            "    float acc = RL_B1[k];",
            "    for (int i = 0; i < RL_OBS_DIM; ++i)",
            "      acc += RL_W1[k * RL_OBS_DIM + i] * n[i];",
            "    h[k] = tanhf(acc);",
            "  }",
            "  for (int j = 0; j < RL_ACT_DIM; ++j) {",
            "    float acc = RL_B2[j];",
            "    for (int k = 0; k < RL_HIDDEN; ++k)",
            "      acc += RL_W2[j * RL_HIDDEN + k] * h[k];",
            "    act[j] = tanhf(acc);",
            "  }",
            "}",
        ]
    lines += ["", "#endif", ""]
    path.write_text("\n".join(lines))


def save_policy(out_dir: Path, payload):
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "policy.json").write_text(json.dumps(payload, indent=2))
    write_c_header(
        out_dir / "policy_weights.h",
        payload,
        int(payload["obs_dim"]),
        int(payload["act_dim"]),
    )


# -------------------------------------------------------------------- training
def train_ars(args, runner, build_dir):
    rng = np.random.default_rng(args.seed)
    size = theta_size(args.policy, runner.obs_dim, runner.act_dim, args.hidden)
    theta = np.zeros(size, dtype=np.float64)
    mean, std = collect_obs_stats(runner)

    def evaluate(theta, episodes, seed):
        return runner.evaluate(
            theta,
            mean,
            std,
            args.policy,
            args.hidden,
            episodes,
            seed,
        )

    initial_return, initial_forward, initial_steps = evaluate(
        theta, args.eval_episodes, args.seed
    )
    best_return = initial_return
    best_theta = theta.copy()
    log_rows = []
    print(
        f"iteration 0: return={initial_return:.2f} forward={initial_forward:.3f} "
        f"survival={initial_steps * runner.env.control_dt:.2f}s"
    )
    log_rows.append(
        [0, initial_return, initial_return, initial_forward, initial_steps * runner.env.control_dt]
    )

    for iteration in range(1, args.iterations + 1):
        deltas = [
            rng.standard_normal(size) for _ in range(args.directions)
        ]
        rewards_plus = []
        rewards_minus = []
        for delta in deltas:
            plus_theta = theta + args.noise * delta
            minus_theta = theta - args.noise * delta
            plus_return, _f, _s = evaluate(plus_theta, args.episodes, args.seed)
            minus_return, _f, _s = evaluate(minus_theta, args.episodes, args.seed)
            rewards_plus.append(plus_return)
            rewards_minus.append(minus_return)
        scores = np.maximum(rewards_plus, rewards_minus)
        order = np.argsort(scores)[::-1][: args.top_k]
        sigma = float(np.std(np.concatenate([np.asarray(rewards_plus)[order], np.asarray(rewards_minus)[order]])))
        sigma = max(sigma, 0.1)
        step = np.zeros(size, dtype=np.float64)
        for index in order:
            step += (
                (rewards_plus[index] - rewards_minus[index]) * deltas[index]
            )
        theta = theta + (args.alpha / (len(order) * sigma)) * step

        mean_return, mean_forward, mean_steps = evaluate(
            theta, args.eval_episodes, args.seed
        )
        if mean_return > best_return:
            best_return = mean_return
            best_theta = theta.copy()
        survival = mean_steps * runner.env.control_dt
        print(
            f"iteration {iteration}: return={mean_return:.2f} "
            f"best={best_return:.2f} forward={mean_forward:.3f} "
            f"survival={survival:.2f}s"
        )
        log_rows.append([iteration, mean_return, best_return, mean_forward, survival])

    payload = {
        "algo": "ars",
        "obs_dim": runner.obs_dim,
        "act_dim": runner.act_dim,
        "obs_mean": mean.tolist(),
        "obs_std": std.tolist(),
        "meta": {
            "build_dir": str(build_dir),
            "kind": runner.env.task.get("kind", ""),
            "iterations": args.iterations,
            "directions": args.directions,
            "top_k": args.top_k,
            "noise": args.noise,
            "alpha": args.alpha,
            "seed": args.seed,
            "initial_return": initial_return,
            "final_return": log_rows[-1][1],
            "best_return": best_return,
        },
    }
    payload.update(
        structured_policy(
            best_theta, args.policy, runner.obs_dim, runner.act_dim, args.hidden
        )
    )
    save_policy(Path(args.out_dir), payload)
    with open(Path(args.out_dir) / "training_log.csv", "w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["iteration", "mean_return", "best_return", "forward_vel", "survival_s"])
        writer.writerows(log_rows)
    print(
        f"saved {args.out_dir}/policy.json and policy_weights.h "
        f"(initial {initial_return:.2f} -> best {best_return:.2f})"
    )
    return 0


def run_ppo(args, build_dir):
    try:
        import gymnasium  # noqa: F401
        from stable_baselines3 import PPO
    except ImportError:
        print(
            "PPO requires extra packages. Install them with:\n"
            "  pip install gymnasium stable-baselines3\n"
            "or use the zero-install ARS trainer: --algo ars",
            file=sys.stderr,
        )
        return 0
    env = CadRlEnv(
        build_dir,
        seed=args.seed,
        randomize=bool(args.randomize),
        episode_steps=args.episode_steps,
    ).as_gymnasium_env()
    model = PPO("MlpPolicy", env, seed=args.seed, verbose=1)
    model.learn(total_timesteps=args.iterations * max(1, args.directions) * 200)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    model.save(out_dir / "ppo_policy")
    print(f"saved {out_dir}/ppo_policy.zip")
    return 0


def evaluate_saved(args, build_dir):
    out_dir = Path(args.out_dir)
    policy_path = out_dir / "policy.json"
    if not policy_path.is_file():
        raise SystemExit(f"error: {policy_path} is missing")
    payload = json.loads(policy_path.read_text())
    runner = Runner(build_dir, randomize=bool(args.randomize), episode_steps=args.episode_steps)
    theta = theta_from_policy(payload, runner.obs_dim, runner.act_dim)
    mean = np.asarray(payload["obs_mean"], dtype=np.float64)
    std = np.asarray(payload["obs_std"], dtype=np.float64)
    mean_return, forward, steps = runner.evaluate(
        theta,
        mean,
        std,
        payload["policy"],
        int(payload.get("hidden", 0)),
        args.eval_episodes,
        args.seed,
    )
    result = {
        "policy": payload["policy"],
        "mean_return": mean_return,
        "mean_forward_vel": forward,
        "survival_s": steps * runner.env.control_dt,
        "finite": bool(np.isfinite(mean_return)),
    }
    print(json.dumps(result, indent=2))
    return 0 if result["finite"] else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--example")
    parser.add_argument("--build-dir")
    parser.add_argument("--algo", choices=["ars", "ppo"], default="ars")
    parser.add_argument("--policy", choices=["linear", "mlp"], default="linear")
    parser.add_argument("--hidden", type=int, default=32)
    parser.add_argument("--iterations", type=int, default=50)
    parser.add_argument("--directions", type=int, default=16)
    parser.add_argument("--top-k", type=int, default=8)
    parser.add_argument("--episodes", type=int, default=1)
    parser.add_argument("--eval-episodes", type=int, default=2)
    parser.add_argument("--episode-steps", type=int, default=None)
    parser.add_argument("--noise", type=float, default=0.05)
    parser.add_argument("--alpha", type=float, default=0.05)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--randomize", action="store_true")
    parser.add_argument("--eval-only", action="store_true")
    parser.add_argument("--out-dir")
    args = parser.parse_args(argv)

    build_dir = resolve_build_dir(args.example, args.build_dir)
    if args.out_dir is None:
        args.out_dir = str(build_dir / "rl")
    if args.episode_steps is None:
        # Use the task's own episode length when not overridden.
        task = json.loads((build_dir / "rl_task.json").read_text())
        args.episode_steps = max(
            1,
            int(
                round(
                    float(task.get("episode_len_s", 10.0))
                    / float(task.get("control_dt_s", 0.01))
                )
            ),
        )
    args.top_k = min(args.top_k, args.directions)

    if args.eval_only:
        return evaluate_saved(args, build_dir)
    if args.algo == "ppo":
        return run_ppo(args, build_dir)

    runner = Runner(build_dir, randomize=bool(args.randomize), episode_steps=args.episode_steps)
    return train_ars(args, runner, build_dir)


if __name__ == "__main__":
    sys.exit(main())
