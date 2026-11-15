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
  ./build-part.sh 01      # motorized wheel (multi-stage gearbox)
  ./build-part.sh 02      # planetary actuator (default)
  ./build-part.sh 05      # Galileo quadruped
  ./build-part.sh 06      # assistive scooter

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
  5 | 05) DIR="05" ;;
  6 | 06) DIR="06" ;;
  *) DIR="${EXAMPLE}" ;;
esac
OUT="build/${DIR}"

echo "Building ${EXAMPLE} ..."
# `detailed` is the buildable level: it includes heat-set inserts, bearings,
# and the full fastener schedule. Use `--detail simplified` by hand for a
# lighter mock-up.
./run-example.sh "${EXAMPLE}" --headless --detail detailed --package "${OUT}"

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
