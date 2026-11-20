#!/usr/bin/env bash
# train-rl.sh — build an example package if needed, then train an RL policy.
#
# Usage:
#   ./train-rl.sh 09
#   ./train-rl.sh 09 --iterations 15 --directions 8 --top-k 4 --episode-steps 150
#   ./train-rl.sh 08 --policy mlp
#
# All arguments after the example are forwarded to scripts/train_rl.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -lt 1 ]]; then
  echo "usage: ./train-rl.sh <example> [train_rl.py options...]" >&2
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
  echo "train-rl: build/$NUM is missing rl_task.json; building the package …" >&2
  "$ROOT/run-example.sh" "$NUM" --headless --release --package "$BUILD" >/dev/null
fi

exec python3 "$ROOT/scripts/train_rl.py" --example "$NUM" --out-dir "$BUILD/rl" "$@"
