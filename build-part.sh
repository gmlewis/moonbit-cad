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
case "${EXAMPLE}" in
  1 | 01) DIR="01" ;;
  2 | 02) DIR="02" ;;
  3 | 03) DIR="03" ;;
  4 | 04) DIR="04" ;;
  5 | 05) DIR="05" ;;
  6 | 06) DIR="06" ;;
  7 | 07) DIR="07" ;;
  *) DIR="${EXAMPLE}" ;;
esac
OUT="build/${DIR}"

echo "Building ${EXAMPLE} ..."
# `detailed` is the buildable level: it includes heat-set inserts, bearings,
# and the full fastener schedule. Use `--detail simplified` by hand for a
# lighter mock-up.
./run-example.sh "${EXAMPLE}" --headless --detail detailed --package "${OUT}"

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
