#!/usr/bin/env python3
"""Live MuJoCo verification of the exported MJCF for examples 08 and 09.

Checks the simulation contract introduced in Phase 12:

* ``09-fox-bot`` loads with 8 actuators (4 hips + 4 wheels, rotors frozen),
  spawns clear of the floor (few contacts), holds its standing pose under
  gravity with tight closed-chain loops, and rolls forward on command.
* ``08-wbr-biped`` loads with 4 actuators and spawns cleanly.

Usage:
    python3 scripts/verify_mjcf_test.py
    python3 scripts/verify_mjcf_test.py --wbr /tmp/p12-08/mjcf/wbr_biped.xml \
        --fox /tmp/p12-09/mjcf/fox_bot.xml
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import mujoco
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
HOLD_STEPS = 500
ROLL_STEPS = 500
WHEEL_RAD_S = 4.0


def quat_roll_pitch_deg(q):
    w, x, y, z = q
    roll = math.atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y))
    pitch = math.asin(max(-1.0, min(1.0, 2.0 * (w * y - z * x))))
    return math.degrees(roll), math.degrees(pitch)


def loop_residual_mm(model, data):
    """Largest site-to-site gap over every connect constraint, in millimetres."""
    worst = 0.0
    for i in range(model.neq):
        site1 = model.eq_obj1id[i]
        site2 = model.eq_obj2id[i]
        if site1 < 0 or site2 < 0:
            continue
        gap = np.linalg.norm(data.site_xpos[site1] - data.site_xpos[site2]) * 1000.0
        worst = max(worst, float(gap))
    return worst


def actuator_groups(model):
    hips, wheels = [], []
    for i in range(model.nu):
        name = mujoco.mj_id2name(model, mujoco.mjtObj.mjOBJ_ACTUATOR, i) or ""
        (wheels if "wheel" in name else hips).append(i)
    return hips, wheels


def wheel_forward_signs(model, data, wheels):
    """+1 for a wheel whose joint axis is +Y in world, -1 when mirrored."""
    signs = []
    for i in wheels:
        joint = model.actuator_trnid[i, 0]
        body = model.jnt_bodyid[joint]
        axis = data.xmat[body].reshape(3, 3) @ model.jnt_axis[joint]
        signs.append(1.0 if axis[1] >= 0.0 else -1.0)
    return signs


def set_home_controls(model, data, hips, wheels):
    for i in hips:
        joint = model.actuator_trnid[i, 0]
        data.ctrl[i] = data.qpos[model.jnt_qposadr[joint]]
    for i in wheels:
        data.ctrl[i] = 0.0


def load(path: Path):
    model = mujoco.MjModel.from_xml_path(str(path))
    data = mujoco.MjData(model)
    mujoco.mj_resetDataKeyframe(model, data, 0)
    mujoco.mj_forward(model, data)
    return model, data


def check_wbr(path: Path) -> list[str]:
    failures = []
    model, data = load(path)
    hips, wheels = actuator_groups(model)
    if model.nu != 4:
        failures.append(f"08: nu={model.nu}, expected 4")
    if data.ncon > 8:
        failures.append(f"08: initial contacts {data.ncon} > 8")
    mujoco.mj_resetDataKeyframe(model, data, 0)
    set_home_controls(model, data, hips, wheels)
    max_loop = 0.0
    for _ in range(HOLD_STEPS):
        mujoco.mj_step(model, data)
        max_loop = max(max_loop, loop_residual_mm(model, data))
    if not np.isfinite(data.qpos).all():
        failures.append("08: non-finite state")
    if max_loop >= 2.0:
        failures.append(f"08: loop residual {max_loop:.2f} mm >= 2 mm")
    print(
        f"08 wbr_biped: nu={model.nu} initial_contacts<=8 "
        f"loop={max_loop:.3f} mm z={data.qpos[2]:.3f} m"
    )
    return failures


def check_fox(path: Path) -> list[str]:
    failures = []
    model, data = load(path)
    hips, wheels = actuator_groups(model)
    if model.nu != 8:
        failures.append(f"09: nu={model.nu}, expected 8 (4 hips + 4 wheels)")
    if len(hips) != 4 or len(wheels) != 4:
        failures.append(f"09: actuator split hips={len(hips)} wheels={len(wheels)}")
    if data.ncon > 8:
        failures.append(f"09: initial contacts {data.ncon} > 8")

    mujoco.mj_resetDataKeyframe(model, data, 0)
    set_home_controls(model, data, hips, wheels)
    max_loop = 0.0
    max_roll = 0.0
    max_pitch = 0.0
    for _ in range(HOLD_STEPS):
        mujoco.mj_step(model, data)
        max_loop = max(max_loop, loop_residual_mm(model, data))
        roll, pitch = quat_roll_pitch_deg(data.qpos[3:7])
        max_roll = max(max_roll, abs(roll))
        max_pitch = max(max_pitch, abs(pitch))
    chassis_z = float(data.qpos[2])
    if not np.isfinite(data.qpos).all():
        failures.append("09: non-finite state while holding stance")
    if chassis_z <= 0.25:
        failures.append(f"09: chassis_z {chassis_z:.3f} m <= 0.25 m")
    if max_roll >= 5.0 or max_pitch >= 5.0:
        failures.append(f"09: tilt roll={max_roll:.2f} pitch={max_pitch:.2f} deg")
    if max_loop >= 2.0:
        failures.append(f"09: loop residual {max_loop:.2f} mm >= 2 mm")

    x0 = float(data.qpos[0])
    signs = wheel_forward_signs(model, data, wheels)
    for index, sign in zip(wheels, signs):
        data.ctrl[index] = WHEEL_RAD_S * sign
    roll_loop = 0.0
    for _ in range(ROLL_STEPS):
        mujoco.mj_step(model, data)
        roll_loop = max(roll_loop, loop_residual_mm(model, data))
    delta_x = float(data.qpos[0]) - x0
    if not np.isfinite(data.qpos).all():
        failures.append("09: non-finite state while rolling")
    if delta_x <= 0.15:
        failures.append(f"09: forward delta_x {delta_x:.3f} m <= 0.15 m")
    if roll_loop >= 2.0:
        failures.append(f"09: loop residual while rolling {roll_loop:.2f} mm >= 2 mm")
    print(
        f"09 fox_bot: nu={model.nu} initial_contacts<=8 "
        f"stance z={chassis_z:.3f} m roll={max_roll:.2f} pitch={max_pitch:.2f} deg "
        f"loop={max_loop:.3f} mm roll_dx={delta_x:.3f} m "
        f"roll_loop={roll_loop:.3f} mm"
    )
    return failures


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--wbr",
        type=Path,
        default=ROOT / "build/08/bundle/mjcf/wbr_biped.xml",
        help="08-wbr-biped MJCF path",
    )
    parser.add_argument(
        "--fox",
        type=Path,
        default=ROOT / "build/09/bundle/mjcf/fox_bot.xml",
        help="09-fox-bot MJCF path",
    )
    args = parser.parse_args(argv)

    missing = [path for path in (args.wbr, args.fox) if not path.is_file()]
    if missing:
        for path in missing:
            print(f"error: missing {path}", file=sys.stderr)
        print(
            "Run ./build-part.sh 08 and ./build-part.sh 09 first.",
            file=sys.stderr,
        )
        return 2

    failures = []
    failures += check_wbr(args.wbr)
    failures += check_fox(args.fox)
    if failures:
        print("FAILED", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
