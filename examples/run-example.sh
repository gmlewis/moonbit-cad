#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
run-example.sh — run one of the gmlewis/cad showcase examples.

Usage:
  ./run-example.sh <example> [options...]
  ./run-example.sh <number>  [options...]     e.g. 01, 1, 05

Wrapper options (before or after the example):
  --view[=<path>]        Write STEP to _build/solidcraft-view/<example>.step
                        (or <path>) and open it in SolidCraft with --up z.
                        With -o, opens that path instead.
  --headless, --no-open  Generate only; never open SolidCraft. Writes to
                        /tmp/<example>.step (or the -o path) and prints it.
                        Agents should always pass this instead of --view.
  -h, --help             Show this help and exit.

Every other option is forwarded to the example. Run
`./run-example.sh <number> -- --help` to see the example-specific options.

Examples:
  ./run-example.sh 01 --out bracket.step
  ./run-example.sh 01 --view
  ./run-example.sh --view 4
  ./run-example.sh --view 01
  ./run-example.sh --headless 01              # generate only (agents)
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

# Wrapper options may precede the example (`./run-example.sh --view 01`).
# Collect a leading run of wrapper options, then take the first remaining
# argument as the example and forward the collected options after it.
PREFIX_ARGS=()
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --view | --view=* | --headless | --no-open)
      PREFIX_ARGS+=("$1")
      shift
      ;;
    -o | --out)
      PREFIX_ARGS+=("$1")
      if [[ $# -ge 2 ]]; then
        PREFIX_ARGS+=("$2")
        shift 2
      else
        shift
      fi
      ;;
    -o=* | --out=*)
      PREFIX_ARGS+=("$1")
      shift
      ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "error: example name or number is missing." >&2
  usage >&2
  exit 2
fi

EXAMPLE_ARG="$1"
shift

# Users sometimes include an extra "--" out of habit.
if [[ $# -gt 0 && "${1:-}" == "--" ]]; then
  shift
fi

if [[ ${#PREFIX_ARGS[@]} -gt 0 ]]; then
  set -- "${PREFIX_ARGS[@]}" "$@"
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

EXAMPLE_NAME="$(basename "$EXAMPLE_PATH")"

# activate_solidcraft brings the SolidCraft window to the front. `open -a`
# usually does this, but when the app is already running it can add a tab in
# the background, so activate explicitly.
activate_solidcraft() {
  if command -v osascript >/dev/null 2>&1; then
    osascript -e 'tell application "SolidCraft" to activate' >/dev/null 2>&1 \
      || true
  fi
}

# open_in_solidcraft prefers SolidCraft's control-port MCP `open` with
# `--up z`. That suppresses the "Stand this part up?" dialog and reliably
# brings the new tab to the front. `open -a` is only the fallback: it opens the
# file as a tab but leaves the app on its Start screen (and may show the
# up-axis dialog), which is why --view previously appeared to do nothing.
open_in_solidcraft() {
  local step_path="$1"
  if [[ ! -s "$step_path" ]]; then
    echo "Error: no STEP was written at $step_path; cannot open it in SolidCraft." >&2
    exit 1
  fi
  local sc_helper="${SOLIDCRAFT_MCP_HELPER:-$HOME/.claude/skills/solidcraft-app/scripts/sc_mcp.py}"
  local output=""
  if [[ -f "$sc_helper" ]] && command -v python3 >/dev/null 2>&1 &&
    python3 -I "$sc_helper" port >/dev/null 2>&1; then
    echo "Opening $step_path in SolidCraft" >&2
    if output="$(python3 -I "$sc_helper" open "$step_path" --up z 2>&1)"; then
      activate_solidcraft
      return 0
    fi
    # A path outside the app's allow-list can still be opened with `open -a`;
    # every other failure (notably the 32-open-design cap) should be reported.
    if [[ "$output" != *"outside the folders"* ]]; then
      echo "Error: SolidCraft could not open $step_path:" >&2
      echo "$output" >&2
      echo "Close a SolidCraft tab and retry, or pass --headless to skip the app." >&2
      exit 1
    fi
    echo "Warning: $step_path is outside SolidCraft's allowed folders; falling back to 'open -a'." >&2
  fi
  if ! command -v open >/dev/null 2>&1; then
    echo "Error: the macOS 'open' command is unavailable." >&2
    exit 1
  fi
  echo "Opening $step_path in SolidCraft" >&2
  if ! open -a SolidCraft "$step_path"; then
    echo "Error: could not open SolidCraft. Is the app installed?" >&2
    echo "The STEP file is at: $step_path" >&2
    exit 1
  fi
  activate_solidcraft
}

FORWARD_ARGS=()
OUT_PATH=""
VIEW_REQUESTED=0
VIEW_PATH_ARG=""
VIEW_STEP=""
HEADLESS_REQUESTED=0
i=0
ARGS=("$@")
while (( i < ${#ARGS[@]} )); do
  arg="${ARGS[$i]}"
  case "$arg" in
    --view)
      VIEW_REQUESTED=1
      ;;
    --view=*)
      VIEW_REQUESTED=1
      VIEW_PATH_ARG="${arg#*=}"
      ;;
    --headless | --no-open)
      HEADLESS_REQUESTED=1
      ;;
    -o | --out)
      FORWARD_ARGS+=("$arg")
      if (( i + 1 < ${#ARGS[@]} )); then
        OUT_PATH="${ARGS[$((i + 1))]}"
        FORWARD_ARGS+=("$OUT_PATH")
        i=$((i + 1))
      fi
      ;;
    -o=* | --out=*)
      OUT_PATH="${arg#*=}"
      FORWARD_ARGS+=("$arg")
      ;;
    *)
      FORWARD_ARGS+=("$arg")
      ;;
  esac
  i=$((i + 1))
done

if (( VIEW_REQUESTED )); then
  if [[ -n "$VIEW_PATH_ARG" ]] && [[ -n "$OUT_PATH" ]]; then
    echo "Error: use either --view=<path> or -o <path>, not both." >&2
    exit 1
  fi
  if [[ -n "$VIEW_PATH_ARG" ]]; then
    VIEW_STEP="$VIEW_PATH_ARG"
    OUT_PATH="$VIEW_STEP"
    FORWARD_ARGS+=(-o "$VIEW_STEP")
  elif [[ -n "$OUT_PATH" ]]; then
    VIEW_STEP="$OUT_PATH"
  else
    # Keep the STEP under the repository (an allow-listed root for SolidCraft's
    # control port) and out of /tmp.
    mkdir -p "$ROOT_DIR/_build/solidcraft-view"
    VIEW_STEP="$ROOT_DIR/_build/solidcraft-view/$EXAMPLE_NAME.step"
    OUT_PATH="$VIEW_STEP"
    FORWARD_ARGS+=(-o "$VIEW_STEP")
  fi
  if [[ -z "$VIEW_STEP" || "$VIEW_STEP" == "-" ]]; then
    echo "Error: invalid view output path: $VIEW_STEP" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$VIEW_STEP")"
  # `-o` uses CreateNew; remove a previous view file first.
  rm -f "$VIEW_STEP"
fi

# --- Headless ---------------------------------------------------------------
# Agents pass --headless so the run never opens the owner's SolidCraft window.
# Without -o the STEP still goes to a predictable /tmp path that is printed.
if (( HEADLESS_REQUESTED )) && (( ! VIEW_REQUESTED )) && [[ -z "$OUT_PATH" ]]; then
  OUT_PATH="/tmp/$EXAMPLE_NAME.step"
  FORWARD_ARGS+=(-o "$OUT_PATH")
fi

if (( ${#FORWARD_ARGS[@]} )); then
  moon run --quiet --target native "$ROOT_DIR/$EXAMPLE_PATH" -- "${FORWARD_ARGS[@]}"
else
  moon run --quiet --target native "$ROOT_DIR/$EXAMPLE_PATH"
fi

if (( HEADLESS_REQUESTED )); then
  if [[ -n "$OUT_PATH" && -f "$OUT_PATH" ]]; then
    echo "Generated $OUT_PATH"
  fi
fi

if (( VIEW_REQUESTED )) && (( ! HEADLESS_REQUESTED )); then
  open_in_solidcraft "$VIEW_STEP"
fi
