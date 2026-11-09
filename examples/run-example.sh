#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
run-example.sh — run one of the gmlewis/cad showcase examples.

Usage:
  ./run-example.sh <example> [options...]
  ./run-example.sh <number>  [options...]     e.g. 01, 1, 05

Examples:
  ./run-example.sh 01 --out bracket.step
  ./run-example.sh 05-galileo-quadruped --bundle /tmp/galileo_bundle
  ./run-example.sh 05 -- --urdf /tmp/galileo.urdf
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

case "$1" in
  -h | --help | help)
    usage
    exit 0
    ;;
esac

EXAMPLE_ARG="$1"
shift

# Users sometimes include an extra "--" out of habit.
if [[ $# -gt 0 && "${1:-}" == "--" ]]; then
  shift
fi

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

EXAMPLE_PATH="$EXAMPLE_ARG"
if [[ "$EXAMPLE_ARG" =~ ^[0-9]+$ ]]; then
  NUM="$(printf "%02d" $((10#$EXAMPLE_ARG)))"
  MATCHES=("$ROOT_DIR"/examples/"$NUM"-*)
  if [[ -d "${MATCHES[0]}" ]]; then
    EXAMPLE_PATH="examples/$(basename "${MATCHES[0]}")"
  fi
elif [[ "$EXAMPLE_ARG" != */* ]]; then
  EXAMPLE_PATH="examples/$EXAMPLE_ARG"
fi

if [[ ! -d "$ROOT_DIR/$EXAMPLE_PATH" ]]; then
  echo "error: example not found: $EXAMPLE_ARG" >&2
  echo "looked in: $ROOT_DIR/$EXAMPLE_PATH" >&2
  exit 1
fi

if (( $# > 0 )); then
  exec moon run --quiet --target native "$ROOT_DIR/$EXAMPLE_PATH" -- "$@"
else
  exec moon run --quiet --target native "$ROOT_DIR/$EXAMPLE_PATH"
fi
