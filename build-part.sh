#!/usr/bin/env bash
# build-part.sh — build one example's complete build package.
#
# The package lands in build/<example>/ and its START-HERE.html answers exactly
# three questions: what to 3D-print, what to buy, and how to assemble it.
set -euo pipefail

# Resolve the repository root from this script's own location (following
# symlinks) and work from there, so the script runs from any directory and
# build/<example>/ always lands under the repository root.
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
if ! cd "$SCRIPT_DIR"; then
  echo "error: cannot change to the repository root: $SCRIPT_DIR" >&2
  exit 2
fi

usage() {
  cat <<'EOF'
build-part.sh — build one example's complete build package.

Usage:
  ./build-part.sh [example] [options]

Runs from any directory; output always goes to <repo>/build/<example>/. For
example, `/path/to/moonbit-19-cad/build-part.sh 02` works from anywhere.

Examples:
  ./build-part.sh 01      # motorized wheel (1-stage 5.33:1 for Galileo X feet)
  ./build-part.sh 02      # planetary actuator (default)
  ./build-part.sh 03      # hip joint actuator (2-stage 28.4:1 A12)
  ./build-part.sh 04      # knee joint actuator (2-stage 28.4:1 A12)
  ./build-part.sh 05      # Galileo quadruped
  ./build-part.sh 06      # assistive scooter
  ./build-part.sh 07      # Roadrunner bipedal wheeled robot
  ./build-part.sh 08      # Ascento-inspired 4-bar wheeled bipedal robot (A12 + 4-elbow)
  ./build-part.sh 09      # FOX_BOT wheeled-quadruped (8x A12 + 4-elbow + TIRE-MOUNT-86.3 + 7in tire)
  ./build-part.sh 12      # RAIWAY large-wheeled bipedal robot (6x A12 + 20in wheels, 1140mm tall)

Options:
  --check-interferences        Run the exact SMLib solid-solid overlap check
  --min-overlap=MM3            Ignore overlaps below this volume (default 1.0)
  --exclude-pattern=REGEX      Body-name pattern for intentional contacts
  --meshes                     Export printable/*.3mf and printable/*.stl
  --3mf                        Export only printable/*.3mf (implied by --meshes)
  --fast                       With --meshes/--3mf, skip large gear cartridges
  -h, --help                   Show this help and exit

Every build also renders views/{iso,front,left,top,exploded}.png when
solidcraft-cli is on PATH, and START-HERE.html embeds them.

Everything is written to build/<example>/ under the repository root. Open
START-HERE.html first.
EOF
}

if [[ ! -d "examples" || ! -f "moon.mod" ]]; then
  echo "error: this does not look like the moonbit-19-cad repository root: $(pwd)" >&2
  exit 2
fi

CHECK_INTERFERENCES=0
MIN_OVERLAP=1.0
EXCLUDE_PATTERN=""
EXPORT_MESHES=0
MESH_FORMATS="3mf,stl"
FAST_MESHES=0
EXAMPLE=""
for arg in "$@"; do
  case "$arg" in
    -h | --help)
      usage
      exit 0
      ;;
    --check-interferences)
      CHECK_INTERFERENCES=1
      ;;
    --min-overlap=*)
      MIN_OVERLAP="${arg#*=}"
      ;;
    --exclude-pattern=*)
      EXCLUDE_PATTERN="${arg#*=}"
      ;;
    --meshes)
      EXPORT_MESHES=1
      MESH_FORMATS="3mf,stl"
      ;;
    --3mf)
      EXPORT_MESHES=1
      MESH_FORMATS="3mf"
      ;;
    --fast)
      FAST_MESHES=1
      ;;
    --)
      ;;
    -*)
      echo "error: unknown option: ${arg}" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "${EXAMPLE}" ]]; then
        echo "error: only one example may be given (got '${EXAMPLE}' and '${arg}')" >&2
        exit 2
      fi
      EXAMPLE="${arg}"
      ;;
  esac
done
EXAMPLE="${EXAMPLE:-02}"

# Discover the example directory the same way run-example.sh does, so a new
# examples/NN-* directory needs no edit here. Accepts a single digit (`8`), a
# two-digit number (`08`), or a full directory name (`08-wbr-biped`).
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
  echo "looked in: examples/${EXAMPLE} and examples/<NN>-*" >&2
  exit 2
fi
EXAMPLE_NAME="$(basename "${EXAMPLE_PATH}")"
# Output directory keeps the numeric prefix (08-wbr-biped -> build/08), or the
# whole name when the directory has no NN- prefix.
DIR="${EXAMPLE_NAME%%[-_]*}"
OUT="build/${DIR}"

echo "Building ${EXAMPLE} ..."
# `detailed` is the buildable level: it includes heat-set inserts, bearings,
# and the full fastener schedule. Use `--detail simplified` by hand for a
# lighter mock-up.
./run-example.sh "${EXAMPLE}" --headless --release --detail detailed --package "${OUT}"

# Every purchased part should carry a viable supplier link. This is a warning,
# not a build failure, so existing examples keep building while their link
# files are filled in. See .claude/skills/sourcing-parts/SKILL.md.
if [[ -f scripts/check_supplier_links.py ]]; then
  if ! python3 scripts/check_supplier_links.py "${OUT}"; then
    echo
    echo "warning: some purchased parts have no supplier link." >&2
    echo "See the checker output above and .claude/skills/sourcing-parts." >&2
  fi
fi

# Optional exact solid-solid interference check. Opt-in because a large
# assembly (hundreds of solids) can take a while; --exclude-pattern suppresses
# intentional fastener-in-hole or print-in-place contacts.
if (( CHECK_INTERFERENCES )); then
  CHECK_ARGS=(
    "${OUT}/assembly.step"
    --min-volume "${MIN_OVERLAP}"
    --json "${OUT}/interference.json"
  )
  if [[ -n "${EXCLUDE_PATTERN}" ]]; then
    CHECK_ARGS+=(--exclude-pattern "${EXCLUDE_PATTERN}")
  fi
  if ! python3 scripts/check_interference.py "${CHECK_ARGS[@]}"; then
    echo "error: interference check found unexpected overlaps." >&2
    echo "See ${OUT}/interference.json and adjust the design or --exclude-pattern." >&2
    exit 1
  fi
fi

# High-quality OCCT GLB + explode animation metadata for START-HERE.html.
if [[ -f scripts/step_to_glb.py && -f "${OUT}/assembly.step" ]]; then
  if ! python3 scripts/step_to_glb.py "${OUT}"; then
    echo "warning: OCCT GLB export failed; START-HERE.html will fall back to flat glTF." >&2
  fi
fi

# Multi-angle contact sheet referenced by START-HERE.html's visual overview.
# render_views.py warns and succeeds when solidcraft-cli is unavailable.
if [[ -f scripts/render_views.py ]]; then
  if ! python3 scripts/render_views.py "${OUT}"; then
    echo "warning: view rendering did not complete." >&2
  fi
fi

# Optional slicer-ready meshes. Parts are already laid flat by the CAD
# exporter; --fast skips the large print-in-place cartridges. --3mf narrows
# the formats to 3MF only, --meshes (the default when requested) writes both.
if (( EXPORT_MESHES )); then
  MESH_ARGS=("${OUT}" --formats "${MESH_FORMATS}")
  if (( FAST_MESHES )); then
    MESH_ARGS+=(--fast)
  fi
  if ! python3 scripts/export_printable_meshes.py "${MESH_ARGS[@]}"; then
    echo "warning: some mesh exports failed." >&2
  fi
fi

# Render the beginner guide as a self-contained HTML page so it opens with
# proper typography and tables in any browser.
START_HTML="${OUT}/START-HERE.md"
if command -v pandoc >/dev/null 2>&1; then
  ./scripts/md-view.sh "${OUT}/START-HERE.md" "${OUT}/START-HERE.html" >/dev/null
  ./scripts/md-view.sh "${OUT}/NAME-KEY.md" "${OUT}/NAME-KEY.html" >/dev/null
  START_HTML="${OUT}/START-HERE.html"
fi

if (( EXPORT_MESHES )); then
  MESH_LINE="  6. MESHES   ${OUT}/printable/       (${MESH_FORMATS} files)"
else
  MESH_LINE="  6. MESHES   rerun with --3mf (or --meshes) for slicer-ready files"
fi

cat <<EOF

Done. Everything you need is in: ${OUT}/

  1. PRINT    ${OUT}/printable/       (settings in print-list.csv)
  2. BUY      ${START_HTML}           (section 2)
  3. ASSEMBLE ${START_HTML}           (section 3)
  4. VIEW     ${OUT}/exploded.step    (exploded, color-coded)
  5. VIEWS    ${OUT}/views/           (iso, front, left, top, exploded PNGs)
${MESH_LINE}

Open it now:
  open ${START_HTML}
EOF

if [[ "${START_HTML}" == *.md ]]; then
  echo
  echo "Tip: install pandoc (brew install pandoc) for a rendered HTML page."
fi
