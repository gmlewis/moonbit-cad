#!/usr/bin/env bash
# build-part.sh — build one example's complete build package.
#
# The package lands in build/<example>/ and its START-HERE.md answers exactly
# three questions: what to 3D-print, what to buy, and how to assemble it.
set -euo pipefail

usage() {
  cat <<'EOF'
build-part.sh — build one example's complete build package.

Usage:
  ./build-part.sh [example]

Examples:
  ./build-part.sh 02      # planetary actuator (default)
  ./build-part.sh 05      # Galileo quadruped
  ./build-part.sh 06      # assistive scooter

Everything is written to build/<example>/. Open START-HERE.md first.
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

cat <<EOF

Done. Everything you need is in: ${OUT}/

  1. PRINT   ${OUT}/printable/       (settings in print-list.csv)
  2. BUY     ${OUT}/START-HERE.md    (section 2)
  3. ASSEMBLE ${OUT}/START-HERE.md   (section 3)

Open ${OUT}/START-HERE.md first.
EOF
