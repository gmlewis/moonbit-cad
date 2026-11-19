#!/usr/bin/env bash
# simulate.sh — step an example's generated MuJoCo MJCF model under gravity.
#
# Usage:
#   ./scripts/simulate.sh <example> [--steps N] [--headless]
#
# Requires Python MuJoCo (`python3 -m pip install mujoco`). The build package
# must already exist (`./build-part.sh <example>`).
set -euo pipefail

usage() {
  cat <<'EOF'
simulate.sh — load and step a build package's MuJoCo MJCF model.

Usage:
  ./scripts/simulate.sh <example> [--steps N] [--headless]

Examples:
  ./scripts/simulate.sh 08
  ./scripts/simulate.sh 08-wbr-biped --steps 1000

The model is read from build/<example>/bundle/mjcf/*.xml. --headless is
accepted for symmetry with the other scripts; no window is ever opened.
Requires Python MuJoCo:  python3 -m pip install mujoco
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

EXAMPLE="$1"
shift

STEPS=500
while [[ $# -gt 0 ]]; do
  case "$1" in
    --steps)
      if [[ $# -lt 2 ]]; then
        echo "error: --steps needs a value" >&2
        exit 2
      fi
      STEPS="$2"
      shift 2
      ;;
    --steps=*)
      STEPS="${1#*=}"
      shift
      ;;
    --headless)
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d examples ]]; then
  echo "error: run this from the repository root." >&2
  exit 2
fi

# Resolve the example directory the same way build-part.sh does.
resolve_example_dir() {
  local arg="$1" num match
  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    num="$(printf "%02d" $((10#$arg)))"
    match="$(compgen -G "examples/${num}-*" | sort | head -n 1 || true)"
    if [[ -z "$match" ]]; then
      match="$(compgen -G "examples/${num}_*" | sort | head -n 1 || true)"
    fi
    if [[ -n "$match" ]]; then
      printf '%s\n' "$match"
      return 0
    fi
    return 1
  fi
  if [[ -d "examples/${arg}" ]]; then
    printf '%s\n' "examples/${arg}"
    return 0
  fi
  return 1
}

if ! EXAMPLE_PATH="$(resolve_example_dir "${EXAMPLE}")"; then
  echo "error: example not found: ${EXAMPLE}" >&2
  exit 2
fi
EXAMPLE_NAME="$(basename "${EXAMPLE_PATH}")"
DIR="${EXAMPLE_NAME%%[-_]*}"
MJCF_DIR="build/${DIR}/bundle/mjcf"
XML="$(ls "${MJCF_DIR}"/*.xml 2>/dev/null | sort | head -n 1 || true)"
if [[ -z "${XML}" ]]; then
  echo "error: no MJCF model in ${MJCF_DIR}" >&2
  echo "build the package first:  ./build-part.sh ${EXAMPLE}" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required to run MuJoCo." >&2
  exit 2
fi

if ! python3 -c 'import mujoco' >/dev/null 2>&1; then
  cat >&2 <<'EOF'
MuJoCo for Python is not installed.

Install it with:
  python3 -m pip install mujoco

Then re-run this script. The generated MJCF is still valid and can be opened
in the MuJoCo viewer or loaded by any MuJoCo binding.
EOF
  exit 0
fi

python3 - "${XML}" "${STEPS}" <<'PY'
import os
import sys

import mujoco

xml_path = sys.argv[1]
steps = int(sys.argv[2])

model = mujoco.MjModel.from_xml_path(xml_path)
data = mujoco.MjData(model)
mujoco.mj_forward(model, data)


def vec(v):
    return "(" + ", ".join(f"{x:.4f}" for x in v) + ")"


mass = float(sum(model.body_mass))
com0 = [float(x) for x in data.subtree_com[0]]
qpos0 = [float(x) for x in data.qpos]

print(f"Model:       {os.path.basename(xml_path)}")
print(f"Bodies:      {model.nbody}")
print(f"DOF:         {model.nv}")
print(f"Total mass:  {mass:.4f} kg")
print(f"CoM (t=0):   {vec(com0)} m")
print(f"qpos (t=0):  {vec(qpos0)}")
print()

for _ in range(max(steps, 0)):
    mujoco.mj_step(model, data)

mujoco.mj_forward(model, data)
com1 = [float(x) for x in data.subtree_com[0]]
qpos1 = [float(x) for x in data.qpos]
print(f"After {steps} step(s) at dt={model.opt.timestep:g} s:")
print(f"CoM:         {vec(com1)} m")
print(f"qpos:        {vec(qpos1)}")
print(f"Contacts:    {data.ncon}")
if model.nu:
    print(f"Controls:    {vec([float(x) for x in data.ctrl])}")
PY
