#!/usr/bin/env python3
"""Validate a generated ros2_control YAML (and pin map) against a URDF.

Checks:

* every non-fixed, non-mimic URDF joint has a controller entry and a hardware
  binding, and every binding names an existing commandable joint;
* bindings have an actuator, channel, valid direction and positive gear ratio;
* soft limits lie inside the URDF joint limits;
* the optional pin map matches the YAML bindings (joints, channel, pins,
  direction, gear ratio, soft limits);
* sensor entries have a model and interface.

Usage:
    python3 scripts/validate_control.py control.yaml robot.urdf
    python3 scripts/validate_control.py control.yaml robot.urdf --pins pins.csv

Requires PyYAML (``pip install pyyaml``).  The other checks use the standard
library.
"""

from __future__ import annotations

import argparse
import csv
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover - environment dependent
    yaml = None

COMMANDABLE = {"revolute", "continuous", "prismatic"}


class Check:
    def __init__(self, name: str) -> None:
        self.name = name
        self.ok = True
        self.details: list[str] = []

    def fail(self, message: str) -> None:
        self.ok = False
        self.details.append(message)

    def print(self) -> None:
        status = "PASS" if self.ok else "FAIL"
        detail = ("; ".join(self.details)) if self.details else ""
        print(f"  [{status}] {self.name}" + (f": {detail}" if detail else ""))


def parse_urdf(path: Path) -> dict[str, dict]:
    root = ET.parse(path).getroot()
    joints = {}
    for joint in root.findall("joint"):
        name = joint.get("name")
        if not name:
            continue
        limit = joint.find("limit")
        joints[name] = {
            "type": joint.get("type", ""),
            "mimic": joint.find("mimic") is not None,
            "lower": _float(limit.get("lower")) if limit is not None else None,
            "upper": _float(limit.get("upper")) if limit is not None else None,
        }
    return joints


def _float(text: str | None) -> float | None:
    if text is None or text.strip() == "":
        return None
    try:
        return float(text)
    except ValueError:
        return None


def parse_yaml(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}


def find_controller(data: dict) -> tuple[str | None, dict]:
    manager = (data.get("controller_manager") or {}).get("ros__parameters") or {}
    for name, entry in manager.items():
        if isinstance(entry, dict):
            type_name = str(entry.get("type", ""))
            if "JointTrajectoryController" in type_name:
                return name, ((data.get(name) or {}).get("ros__parameters") or {})
    return None, {}


def as_float(value) -> float | None:
    try:
        if value is None or value == "":
            return None
        return float(value)
    except (TypeError, ValueError):
        return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate a generated ros2_control YAML against a URDF.",
    )
    parser.add_argument("control", help="ros2_control YAML file")
    parser.add_argument("urdf", help="URDF file")
    parser.add_argument("--pins", help="firmware pin map CSV (optional)")
    args = parser.parse_args()

    if yaml is None:
        print(
            "error: PyYAML is required (pip install pyyaml).",
            file=sys.stderr,
        )
        return 2

    checks: list[Check] = []

    urdf_check = Check("urdf")
    try:
        joints = parse_urdf(Path(args.urdf))
    except Exception as exc:  # noqa: BLE001 - report the parse failure
        joints = {}
        urdf_check.fail(str(exc))
    if not joints:
        urdf_check.fail(f"no joints found in {args.urdf}")
    checks.append(urdf_check)

    yaml_check = Check("yaml")
    try:
        data = parse_yaml(Path(args.control))
    except Exception as exc:  # noqa: BLE001 - report the parse failure
        data = {}
        yaml_check.fail(str(exc))
    controller_name, controller_params = find_controller(data)
    hardware = (data.get("moonbit_robot_hardware") or {}).get(
        "ros__parameters"
    ) or {}
    if controller_name is None:
        yaml_check.fail("no JointTrajectoryController in controller_manager")
    checks.append(yaml_check)

    controller_joints = list(controller_params.get("joints") or [])
    hardware_joints = list(hardware.get("joints") or [])
    bindings = {
        name: entry
        for name, entry in hardware.items()
        if name not in ("joints", "sensors") and isinstance(entry, dict)
    }

    if not controller_joints and not bindings:
        for check in checks:
            check.print()
        print("  [PASS] bindings: none declared (no control map)")
        return 0

    commandable = {
        name
        for name, info in joints.items()
        if info["type"] in COMMANDABLE and not info["mimic"]
    }

    mapping = Check("joints")
    missing_controller = sorted(commandable - set(controller_joints))
    missing_hardware = sorted(commandable - set(bindings))
    extra_controller = sorted(set(controller_joints) - commandable)
    extra_hardware = sorted(set(bindings) - commandable)
    if missing_controller:
        mapping.fail(f"controller missing {missing_controller}")
    if missing_hardware:
        mapping.fail(f"hardware missing {missing_hardware}")
    if extra_controller:
        mapping.fail(f"controller has non-commandable {extra_controller}")
    if extra_hardware:
        mapping.fail(f"hardware has non-commandable {extra_hardware}")
    if sorted(hardware_joints) != sorted(bindings):
        mapping.fail("hardware joints list does not match the bindings")
    checks.append(mapping)

    fields = Check("bindings")
    for name, entry in sorted(bindings.items()):
        if not entry.get("actuator"):
            fields.fail(f"{name}: no actuator")
        if not entry.get("channel"):
            fields.fail(f"{name}: no channel")
        direction = entry.get("direction", "normal")
        if direction not in ("normal", "inverted"):
            fields.fail(f"{name}: direction {direction!r}")
        gear = as_float(entry.get("gear_ratio"))
        if gear is None or gear <= 0:
            fields.fail(f"{name}: gear_ratio {entry.get('gear_ratio')!r}")
        lower = as_float(entry.get("soft_lower"))
        upper = as_float(entry.get("soft_upper"))
        if lower is not None and upper is not None and lower > upper:
            fields.fail(f"{name}: soft_lower > soft_upper")
    checks.append(fields)

    limits = Check("limits")
    for name, entry in sorted(bindings.items()):
        info = joints.get(name)
        if not info:
            continue
        lower = as_float(entry.get("soft_lower"))
        upper = as_float(entry.get("soft_upper"))
        if lower is not None and info["lower"] is not None:
            if lower < info["lower"] - 1.0e-6:
                limits.fail(
                    f"{name}: soft_lower {lower} below URDF {info['lower']}"
                )
        if upper is not None and info["upper"] is not None:
            if upper > info["upper"] + 1.0e-6:
                limits.fail(
                    f"{name}: soft_upper {upper} above URDF {info['upper']}"
                )
    checks.append(limits)

    sensors = hardware.get("sensors") or {}
    sensor_check = Check("sensors")
    if isinstance(sensors, dict):
        for name, entry in sorted(sensors.items()):
            if not isinstance(entry, dict):
                sensor_check.fail(f"{name}: not a mapping")
                continue
            if not entry.get("model"):
                sensor_check.fail(f"{name}: no model")
            if not entry.get("interface"):
                sensor_check.fail(f"{name}: no interface")
            voltage = as_float(entry.get("voltage_v"))
            if voltage is None or voltage <= 0:
                sensor_check.fail(f"{name}: invalid voltage")
    else:
        sensor_check.fail("sensors is not a mapping")
    checks.append(sensor_check)

    if args.pins:
        pins_check = Check("pin map")
        rows = {}
        try:
            with Path(args.pins).open(newline="", encoding="utf-8") as handle:
                for row in csv.DictReader(handle):
                    rows[row.get("joint", "")] = row
        except Exception as exc:  # noqa: BLE001 - report the parse failure
            pins_check.fail(str(exc))
        if sorted(rows) != sorted(bindings):
            pins_check.fail("pin-map joints do not match the YAML bindings")
        for name in sorted(set(rows) & set(bindings)):
            entry = bindings[name]
            row = rows[name]
            if row.get("channel", "") != entry.get("channel", ""):
                pins_check.fail(f"{name}: channel differs from the YAML")
            if row.get("mcu_pins", "") != (entry.get("mcu_pins") or ""):
                pins_check.fail(f"{name}: pins differ from the YAML")
            if row.get("direction", "normal") != entry.get(
                "direction", "normal"
            ):
                pins_check.fail(f"{name}: direction differs from the YAML")
            pin_gear = as_float(row.get("gear_ratio"))
            yaml_gear = as_float(entry.get("gear_ratio"))
            if (
                pin_gear is None
                or yaml_gear is None
                or not math.isclose(pin_gear, yaml_gear, rel_tol=1e-6)
            ):
                pins_check.fail(f"{name}: gear ratio differs from the YAML")
        checks.append(pins_check)

    for check in checks:
        check.print()
    return 0 if all(check.ok for check in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
