#!/usr/bin/env bash
# build-part.sh — build one example's complete build package.
#
# The package lands in build/<example>/ and its START-HERE.html answers exactly
# three questions: what to 3D-print, what to buy, and how to assemble it.
set -euo pipefail

usage() {
  cat <<'EOF'
build-part.sh — build one example's complete build package.

Usage:
  ./build-part.sh [example]

Examples:
  ./build-part.sh 01      # motorized wheel (1-stage 5.33:1 for Galileo X feet)
  ./build-part.sh 02      # planetary actuator (default)
  ./build-part.sh 03      # hip joint actuator (2-stage 28.4:1 A12)
  ./build-part.sh 04      # knee joint actuator (2-stage 28.4:1 A12)
  ./build-part.sh 05      # Galileo quadruped
  ./build-part.sh 06      # assistive scooter
  ./build-part.sh 07      # Roadrunner bipedal wheeled robot
  ./build-part.sh 08      # Ascento-inspired 4-bar wheeled bipedal robot (A12 + 4-elbow)

Everything is written to build/<example>/. Open START-HERE.html first.
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

if [[ ! -d "examples" ]]; then
  echo "error: run this from the repository root." >&2
  exit 2
fi

EXAMPLE="${1:-02}"

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

# Render the beginner guide as a self-contained HTML page so it opens with
# proper typography and tables in any browser.
START_HTML="${OUT}/START-HERE.md"
if command -v pandoc >/dev/null 2>&1; then
  ./scripts/md-view.sh "${OUT}/START-HERE.md" "${OUT}/START-HERE.html" >/dev/null
  ./scripts/md-view.sh "${OUT}/NAME-KEY.md" "${OUT}/NAME-KEY.html" >/dev/null
  START_HTML="${OUT}/START-HERE.html"
fi

cat <<EOF

Done. Everything you need is in: ${OUT}/

  1. PRINT    ${OUT}/printable/       (settings in print-list.csv)
  2. BUY      ${START_HTML}           (section 2)
  3. ASSEMBLE ${START_HTML}           (section 3)
  4. VIEW     ${OUT}/exploded.step    (exploded, color-coded)

Open it now:
  open ${START_HTML}
EOF

if [[ "${START_HTML}" == *.md ]]; then
  echo
  echo "Tip: install pandoc (brew install pandoc) for a rendered HTML page."
fi
