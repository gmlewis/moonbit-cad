#!/usr/bin/env bash
# watch-rl.sh — open an interactive 3D MuJoCo viewer for an example & RL policy.
#
# Usage:
#   ./watch-rl.sh 09                  # watch trained build/09/rl/policy.json
#   ./watch-rl.sh 09 --zero           # hold standing home pose (no policy needed)
#   ./watch-rl.sh 09 --speed 0.5      # half-speed slow motion
#   ./watch-rl.sh 08 --randomize      # watch 08-wbr-biped with random pushes
#
# Uses mjpython on macOS when available (required for MuJoCo's native viewer).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
  echo "usage: ./watch-rl.sh <example> [watch_rl.py options...]" >&2
  exit 2
fi

ARG="$1"
shift

if [[ "$ARG" =~ ^[0-9]+$ ]]; then
  NUM="$(printf "%02d" $((10#$ARG)))"
else
  if [[ ! -d "$ROOT/examples/$ARG" ]]; then
    echo "error: example not found: $ARG" >&2
    exit 2
  fi
  NUM="$(basename "$ARG" | cut -d- -f1)"
fi

BUILD="$ROOT/build/$NUM"
if [[ ! -f "$BUILD/rl_task.json" ]]; then
  echo "watch-rl: build/$NUM is missing rl_task.json; building the package …" >&2
  "$ROOT/run-example.sh" "$NUM" --headless --release --package "$BUILD" >/dev/null
fi

HEADLESS=0
for opt in "$@"; do
  if [[ "$opt" == "--headless" ]]; then
    HEADLESS=1
  fi
done

PYTHON_BIN="python3"
if [[ "$HEADLESS" -eq 0 ]] && command -v mjpython >/dev/null 2>&1; then
  PYTHON_BIN="mjpython"
fi

exec "$PYTHON_BIN" "$ROOT/scripts/watch_rl.py" --example "$NUM" "$@"
