#!/usr/bin/env bash
set -euo pipefail

ORIG_CMD="./run-example.sh $*"

usage() {
  cat <<'EOF'
run-example.sh — run one of the gmlewis/cad showcase examples.

Usage:
  ./run-example.sh <example> [options...]
  ./run-example.sh <number>  [options...]     e.g. 02, 5, 06

Wrapper options (before or after the example):
  -o, --out <path>       Write the output named by <path>'s extension:
                        .step/.stp (or none) = STEP file (default: stdout when
                        no path is given), .stl = binary STL, .3mf =
                        OrcaSlicer 3MF, .png = four-view preview, and
                        .gltf/.urdf/.blend/.py = that format instead of STEP.
  --step <path>          Explicit STEP path; refuses a path whose extension
                        names another kind (= -o <path> for STEP).
  --stl [<path>]         Also write a binary STL (default: <step>.stl).
  --3mf [<path>]         Also write an OrcaSlicer-ready 3MF (default: <step>.3mf
                        or <example>.3mf in the current directory).
  --png [<path>]         Also render a four-view PNG preview (default: <step>.png).
  --view [<path>]        Write STEP to _build/solidcraft-view/<example>.step
                        (or <path>) and open it in SolidCraft with --up z.
                        With -o, opens that path instead.
  --headless, --no-open  Generate only; never open or raise SolidCraft. Writes
                        to /tmp/<example>.step (or the -o path) and prints it.
                        Agents must always use this instead of --view.
  -h, --help             Show this help and exit.

Every option that takes a path accepts it either as the next argument
(`--3mf out.3mf`) or inline after "=" (`--3mf=out.3mf`); both forms are
equivalent. A following argument is used as the path only when it does not
start with "-", and, before the example name, only when it has that option's
file extension (.3mf, .stl, .png, .step/.stp, .gltf, .urdf, .blend, .py), so
`./run-example.sh --view 02` still reads 02 as the example number.

-o/--out picks the output kind from the file extension, so `-o part.stl`
writes an STL and `-o scene.gltf` asks the example for glTF. `--step` is the
explicit STEP spelling and rejects another kind's extension. It may be
repeated for different kinds (`-o part.step -o part.stl -o part.3mf`), but
naming one kind twice with different paths is an error.

Every other option is forwarded to the example. Run
`./run-example.sh <number> -- --help` to see the example-specific options.

Examples:
  ./run-example.sh 02 --out actuator.step
  ./run-example.sh 02 --step actuator.step    # explicit STEP spelling
  ./run-example.sh 02 -o actuator.stl         # STL, chosen by extension
  ./run-example.sh 02 --out actuator.3mf      # 3MF, chosen by extension
  ./run-example.sh 02 -o actuator.gltf        # glTF, chosen by extension
  ./run-example.sh --3mf actuator.3mf 02      # same; options may come first
  ./run-example.sh 02 --view
  ./run-example.sh --headless 02              # generate only (agents)
  ./run-example.sh 05-galileo-quadruped --bundle /tmp/galileo_bundle
  ./run-example.sh 05 --urdf /tmp/galileo.urdf
  ./run-example.sh 06 --bundle /tmp/wheelchair_bundle
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

# Expand a leading "~" / "~/" (shells do not tilde-expand after "=" in flags
# like `--3mf=~/Downloads/foo.3mf`).
expand_tilde() {
  local p="$1"
  if [[ "$p" == "~" ]]; then
    printf '%s' "$HOME"
  elif [[ "$p" == "~/"* ]]; then
    printf '%s' "$HOME/${p#\~/}"
  else
    printf '%s' "$p"
  fi
}

# --- Argument parsing -------------------------------------------------------
# Wrapper options may come before or after the example, and every option that
# takes a path accepts it either inline ("--3mf=out.3mf") or as the next
# argument ("--3mf out.3mf"). An option given without a value keeps its
# default. Everything the wrapper does not own is forwarded to the example
# unchanged (example options take space-separated values too).
wrapper_value_exts() {
  case "$1" in
    -o | --out | --step | --package | -b | --bundle) printf '*' ;;
    --view) printf 'step stp' ;;
    -3mf | --3mf) printf '3mf' ;;
    -stl | --stl) printf 'stl' ;;
    -png | --png) printf 'png' ;;
    *) printf '' ;;
  esac
}

# takes_next_value OPTION TOKEN EXAMPLE_KNOWN succeeds when TOKEN is OPTION's
# space-separated value. Value-less and unknown options never take one, so the
# next option, the example name, or a forwarded argument stays where it is.
takes_next_value() {
  local opt="$1" token="${2:-}" example_known="${3:-0}" exts tok_ext ext
  [[ -n "$token" && "$token" != -* ]] || return 1
  exts="$(wrapper_value_exts "$opt")"
  [[ -n "$exts" ]] || return 1
  [[ "$exts" == "*" ]] && return 0
  # Once the example is known this option cannot be confused with it, so any
  # bare token is its value. Before that, require the option's own file
  # extension so `--view 02` and `--3mf 05` keep reading the example number.
  (( example_known )) && return 0
  [[ "$token" == *.* ]] || return 1
  tok_ext="$(printf '%s' "${token##*.}" | tr '[:upper:]' '[:lower:]')"
  for ext in $exts; do
    [[ "$tok_ext" == "$ext" ]] && return 0
  done
  return 1
}

# path_ext PATH prints PATH's lower-case extension without the dot (empty when
# there is none). Only the final path component counts.
path_ext() {
  local base="${1##*/}"
  case "$base" in
    *.*) printf '%s' "${base##*.}" | tr '[:upper:]' '[:lower:]' ;;
    *) return 0 ;;
  esac
}

# repeat_or_fail LABEL CURRENT NEW reports an error when NEW names a different
# path for an output kind that already has one (CURRENT), returns 1 when it is
# the same path (a harmless repeat), and 0 when the kind has no path yet.
repeat_or_fail() {
  local label="$1" current="$2" new="$3" cur norm
  [[ -n "$current" ]] || return 0
  cur="$current"
  norm="$new"
  while [[ "$cur" == ./* ]]; do cur="${cur#./}"; done
  while [[ "$norm" == ./* ]]; do norm="${norm#./}"; done
  [[ "$cur" == "$norm" ]] && return 1
  echo "error: $label output already requested as $current (got $new)" >&2
  echo "       give each output kind at most one path" >&2
  exit 2
}

# route_output OPTION PATH FORCE_STEP sends an -o/--out/--step path to the
# output kind named by its extension: .step/.stp (or no extension) writes STEP,
# .stl/.3mf/.png derive that file from the STEP, and .gltf/.urdf/.blend/.py ask
# the example for that format instead of STEP. FORCE_STEP is 1 for --step,
# which rejects a path whose extension names another kind. Different kinds
# combine; repeating a kind with a different path is an error.
route_output() {
  local opt="$1" path="$2" force="$3" ext current fwd
  path="$(expand_tilde "$path")"
  ext="$(path_ext "$path")"
  if (( force )); then
    case "$ext" in
      stl | 3mf | png | gltf | urdf | blend | py)
        echo "error: $opt wants a STEP file, but $path ends in .$ext" >&2
        echo "       use -o $path to let the extension choose the output" >&2
        exit 2
        ;;
    esac
  fi
  case "$ext" in
    stl)
      if repeat_or_fail STL "$STL_OUT_ARG" "$path"; then
        STL_REQUESTED=1
        STL_OUT_ARG="$path"
      fi
      ;;
    3mf)
      if repeat_or_fail 3MF "$THREEMF_OUT_ARG" "$path"; then
        THREEMF_REQUESTED=1
        THREEMF_OUT_ARG="$path"
      fi
      ;;
    png)
      if repeat_or_fail PNG "$PNG_OUT_ARG" "$path"; then
        PNG_REQUESTED=1
        PNG_OUT_ARG="$path"
      fi
      ;;
    gltf | urdf | blend | py)
      # The example writes these instead of STEP; several may be combined.
      case "$ext" in
        gltf) current="$GLTF_OUT_ARG" fwd="--gltf" ;;
        urdf) current="$URDF_OUT_ARG" fwd="--urdf" ;;
        blend) current="$BLEND_OUT_ARG" fwd="--blend" ;;
        py) current="$BPY_OUT_ARG" fwd="--bpy" ;;
      esac
      if repeat_or_fail ".$ext" "$current" "$path"; then
        case "$ext" in
          gltf) GLTF_OUT_ARG="$path" ;;
          urdf) URDF_OUT_ARG="$path" ;;
          blend) BLEND_OUT_ARG="$path" ;;
          py) BPY_OUT_ARG="$path" ;;
        esac
        NO_STEP_OUTPUT=1
        FORWARD_ARGS+=("$fwd" "$path")
      fi
      ;;
    *)
      if repeat_or_fail STEP "$OUT_PATH" "$path"; then
        OUT_PATH="$path"
        FORWARD_ARGS+=(-o "$path")
      fi
      ;;
  esac
}

FORWARD_ARGS=()
OUT_PATH=""
PACKAGE_REQUESTED=0
VIEW_REQUESTED=0
VIEW_PATH_ARG=""
VIEW_STEP=""
STL_REQUESTED=0
STL_OUT_ARG=""
STL_OUT=""
THREEMF_REQUESTED=0
THREEMF_OUT_ARG=""
THREEMF_OUT=""
PNG_REQUESTED=0
PNG_OUT_ARG=""
PNG_OUT=""
GLTF_OUT_ARG=""
URDF_OUT_ARG=""
BLEND_OUT_ARG=""
BPY_OUT_ARG=""
HEADLESS_REQUESTED=0
RELEASE_MODE=0
NO_STEP_OUTPUT=0
EXAMPLE_ARG=""

ARGS=("$@")
i=0
while (( i < ${#ARGS[@]} )); do
  arg="${ARGS[$i]}"
  i=$((i + 1))
  opt="$arg"
  value=""
  inline=0
  if [[ "$arg" == -* && "$arg" == *=* ]]; then
    opt="${arg%%=*}"
    value="${arg#*=}"
    inline=1
  fi
  # "--" is a conventional no-op separator; never forward it.
  [[ "$opt" == "--" ]] && continue
  # The first bare token names the example.
  if [[ -z "$EXAMPLE_ARG" && "$opt" != -* ]]; then
    EXAMPLE_ARG="$arg"
    continue
  fi
  example_known=0
  if [[ -n "$EXAMPLE_ARG" ]]; then example_known=1; fi
  if (( ! inline )) && takes_next_value "$opt" "${ARGS[$i]:-}" "$example_known"; then
    value="${ARGS[$i]}"
    i=$((i + 1))
  fi
  case "$opt" in
    --release)
      RELEASE_MODE=1
      ;;
    --view)
      VIEW_REQUESTED=1
      if [[ -n "$value" ]]; then
        VIEW_PATH_ARG="$(expand_tilde "$value")"
      fi
      ;;
    -3mf | --3mf)
      THREEMF_REQUESTED=1
      if [[ -n "$value" ]]; then
        value="$(expand_tilde "$value")"
        if repeat_or_fail 3MF "$THREEMF_OUT_ARG" "$value"; then
          THREEMF_OUT_ARG="$value"
        fi
      fi
      ;;
    --headless | --no-open)
      HEADLESS_REQUESTED=1
      ;;
    --package | -b | --bundle)
      PACKAGE_REQUESTED=1
      FORWARD_ARGS+=("$opt")
      if [[ -n "$value" ]]; then
        FORWARD_ARGS+=("$value")
      fi
      ;;
    -stl | --stl)
      STL_REQUESTED=1
      if [[ -n "$value" ]]; then
        value="$(expand_tilde "$value")"
        if repeat_or_fail STL "$STL_OUT_ARG" "$value"; then
          STL_OUT_ARG="$value"
        fi
      fi
      ;;
    --png | -png)
      PNG_REQUESTED=1
      if [[ -n "$value" ]]; then
        value="$(expand_tilde "$value")"
        if repeat_or_fail PNG "$PNG_OUT_ARG" "$value"; then
          PNG_OUT_ARG="$value"
        fi
      fi
      ;;
    -o | --out | --step)
      if [[ -z "$value" ]]; then
        echo "error: $opt needs a path, e.g. $opt out.step" >&2
        exit 2
      fi
      if [[ "$opt" == "--step" ]]; then
        route_output "$opt" "$value" 1
      else
        route_output "$opt" "$value" 0
      fi
      ;;
    *)
      FORWARD_ARGS+=("$arg")
      ;;
  esac
done

if [[ -z "$EXAMPLE_ARG" ]]; then
  echo "error: example name or number is missing." >&2
  usage >&2
  exit 2
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
  if [[ ! -d "${MATCHES[0]}" ]]; then
    MATCHES=("$ROOT_DIR"/examples/"$NUM"_*)
  fi
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

# --- STEP -> STL ------------------------------------------------------------
# Mirrors moonbit-17-step's converter: SolidCraft's exporter first, OCCT
# (occt-draw or DRAWEXE) as the fallback. STL_DEFLECTION sets the fallback
# tessellation in mm (default 0.05).
find_occt() {
  local tool
  tool="$(command -v occt-draw 2>/dev/null || true)"
  if [[ -z "$tool" ]]; then
    tool="$(command -v DRAWEXE 2>/dev/null || true)"
  fi
  printf '%s' "$tool"
}

find_solidcraft() {
  if [[ -x "$HOME/tools/bin/solidcraft-cli" ]]; then
    printf '%s' "$HOME/tools/bin/solidcraft-cli"
    return 0
  fi
  command -v solidcraft-cli 2>/dev/null || true
}

# tcl_quote quotes a string for a TCL command.
tcl_quote() {
  local s="${1//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

step_to_stl() {
  local step_path="$1"
  local stl_path="$2"
  local deflection="${STL_DEFLECTION:-0.05}"
  local sc occt log

  sc="$(find_solidcraft)"
  if [[ -n "$sc" ]] && command -v python3 >/dev/null 2>&1; then
    if python3 - "$sc" "$step_path" "$stl_path" <<'PY'
import json, subprocess, sys, tempfile
from pathlib import Path
sc, step_p, stl_p = sys.argv[1], Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve()
script = [
    {"command": "file.insert_step", "params": {"path": str(step_p), "flatten": True}},
    {"command": "file.export_stl", "params": {"path": str(stl_p), "quality": "fine"}},
]
with tempfile.TemporaryDirectory() as td:
    sp = Path(td) / "s.json"
    sp.write_text(json.dumps(script))
    r = subprocess.run([sc, "run", str(sp), "--validation", "off", "--quiet"], capture_output=True, text=True, timeout=180)
    sys.exit(0 if r.returncode == 0 and stl_p.is_file() and stl_p.stat().st_size > 84 else 1)
PY
    then
      return 0
    fi
  fi

  occt="$(find_occt)"
  if [[ -z "$occt" ]]; then
    echo "Error: neither solidcraft-cli nor occt-draw/DRAWEXE found (checked ~/tools/bin and PATH)." >&2
    return 1
  fi

  if ! log="$(
    printf 'pload ALL\ntestreadstep %s a\nincmesh a %s\nwritestl a %s\nexit\n' \
      "$(tcl_quote "$step_path")" "$deflection" "$(tcl_quote "$stl_path")" \
      | "$occt" 2>&1
  )"; then
    echo "Error: OCCT failed while converting $step_path to STL." >&2
    printf '%s\n' "$log" | tail -n 5 >&2
    return 1
  fi
  if [[ ! -s "$stl_path" ]]; then
    echo "Error: OCCT produced no STL for $step_path." >&2
    printf '%s\n' "$log" | tail -n 5 >&2
    return 1
  fi
}

# Derive "<step basename>.<ext>" next to the STEP output, or fall back to the
# example name in the current directory.
sibling_output() {
  local ext="$1"
  if [[ -n "$OUT_PATH" ]]; then
    local dir base
    dir="$(dirname "$OUT_PATH")"
    base="$(basename "$OUT_PATH")"
    case "$base" in
      *.*) base="${base%.*}" ;;
    esac
    printf '%s/%s.%s' "$dir" "$base" "$ext"
  else
    printf '%s.%s' "$EXAMPLE_NAME" "$ext"
  fi
}

if (( VIEW_REQUESTED )); then
  if (( NO_STEP_OUTPUT )); then
    echo "Error: --view cannot be combined with --gltf, --urdf, --blend, or --bpy." >&2
    exit 1
  fi
  if [[ -n "$VIEW_PATH_ARG" ]] && [[ -n "$OUT_PATH" ]]; then
    echo "Error: use either --view <path> or -o <path>, not both." >&2
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
# Without -o (and without --package/--bundle), write to a predictable /tmp path.
if (( HEADLESS_REQUESTED )) && (( ! VIEW_REQUESTED )) && (( ! PACKAGE_REQUESTED )) && [[ -z "$OUT_PATH" ]]; then
  if (( NO_STEP_OUTPUT )); then
    echo "Error: --headless cannot be combined with --gltf, --urdf, --blend, or --bpy." >&2
    exit 1
  fi
  OUT_PATH="/tmp/$EXAMPLE_NAME.step"
  FORWARD_ARGS+=(-o "$OUT_PATH")
fi

# --- Derived outputs --------------------------------------------------------
# STL, 3MF, and PNG are converted from the generated STEP, so they need a STEP
# file even when no STEP path was requested.
if (( STL_REQUESTED || THREEMF_REQUESTED || PNG_REQUESTED )); then
  if (( NO_STEP_OUTPUT )); then
    echo "Error: --stl, --3mf, and --png need a STEP file, which --gltf, --urdf, --blend, and --bpy replace." >&2
    exit 1
  fi
  if (( PACKAGE_REQUESTED )); then
    echo "Error: --stl, --3mf, and --png cannot be combined with --package/--bundle." >&2
    exit 1
  fi
  if (( STL_REQUESTED )); then
    if [[ -n "$STL_OUT_ARG" ]]; then
      STL_OUT="$STL_OUT_ARG"
    else
      STL_OUT="$(sibling_output stl)"
    fi
  fi
  if (( THREEMF_REQUESTED )); then
    if [[ -n "$THREEMF_OUT_ARG" ]]; then
      THREEMF_OUT="$THREEMF_OUT_ARG"
    else
      THREEMF_OUT="$(sibling_output 3mf)"
    fi
  fi
  if (( PNG_REQUESTED )); then
    if [[ -n "$PNG_OUT_ARG" ]]; then
      PNG_OUT="$PNG_OUT_ARG"
    else
      PNG_OUT="$(sibling_output png)"
    fi
  fi
  if [[ -z "$OUT_PATH" ]]; then
    STEP_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cad-step-out.XXXXXX")"
    trap 'rm -rf "$STEP_TMP_DIR"' EXIT
    OUT_PATH="$STEP_TMP_DIR/$EXAMPLE_NAME.step"
    FORWARD_ARGS+=(-o "$OUT_PATH")
  fi
fi

RUN_PATH="$ROOT_DIR/$EXAMPLE_PATH"
if [[ -d "$RUN_PATH/cmd" ]]; then
  RUN_PATH="$RUN_PATH/cmd"
fi

MOON_RUN_FLAGS=(--quiet)
if (( RELEASE_MODE )); then
  MOON_RUN_FLAGS+=(--release)
fi

if (( ${#FORWARD_ARGS[@]} )); then
  moon run "${MOON_RUN_FLAGS[@]}" "$RUN_PATH" -- "${FORWARD_ARGS[@]}"
else
  moon run "${MOON_RUN_FLAGS[@]}" "$RUN_PATH"
fi

if (( HEADLESS_REQUESTED )); then
  if [[ -n "$OUT_PATH" && -f "$OUT_PATH" ]]; then
    echo "Generated $OUT_PATH"
  fi
fi

if (( VIEW_REQUESTED )) && (( ! HEADLESS_REQUESTED )); then
  open_in_solidcraft "$VIEW_STEP"
fi

if (( STL_REQUESTED )); then
  if [[ ! -s "$OUT_PATH" ]]; then
    echo "Error: no STEP was written at $OUT_PATH; cannot export STL." >&2
    exit 1
  fi
  if ! step_to_stl "$OUT_PATH" "$STL_OUT"; then
    echo "Error: failed to export STL from $OUT_PATH." >&2
    exit 1
  fi
  echo "Wrote $STL_OUT" >&2
fi

if (( THREEMF_REQUESTED )); then
  if [[ ! -s "$OUT_PATH" ]]; then
    echo "Error: no STEP was written at $OUT_PATH; cannot export 3MF." >&2
    exit 1
  fi
  if ! "$ROOT_DIR/scripts/step_to_3mf.py" "$OUT_PATH" "$THREEMF_OUT" --command "$ORIG_CMD" --repo-dir "$ROOT_DIR"; then
    echo "Error: failed to export 3MF from $OUT_PATH." >&2
    exit 1
  fi
  echo "Wrote $THREEMF_OUT" >&2
fi

if (( PNG_REQUESTED )); then
  if [[ ! -s "$OUT_PATH" ]]; then
    echo "Error: no STEP was written at $OUT_PATH; cannot render a PNG." >&2
    exit 1
  fi
  if ! python3 "$ROOT_DIR/scripts/render_step.py" "$OUT_PATH" "$PNG_OUT"; then
    echo "Error: failed to render a PNG preview of $OUT_PATH." >&2
    exit 1
  fi
  echo "Wrote $PNG_OUT" >&2
fi
