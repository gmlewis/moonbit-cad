#!/usr/bin/env bash
# md-view.sh — render a Markdown file as a self-contained, styled HTML page.
#
# Usage:
#   ./scripts/md-view.sh FILE.md [OUT.html]
#
# Prints the output path. The CSS is embedded in the HTML, so the page is
# self-contained and opens beautifully in any browser.
set -euo pipefail

usage() {
  cat <<'EOF'
md-view.sh — render Markdown as a styled, self-contained HTML page.

Usage:
  ./scripts/md-view.sh FILE.md [OUT.html]

The output defaults to FILE.html next to the input.
Requires pandoc:  brew install pandoc
EOF
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

IN="$1"
OUT="${2:-${IN%.md}.html}"

if [[ ! -f "$IN" ]]; then
  echo "error: no such Markdown file: ${IN}" >&2
  exit 2
fi

if ! command -v pandoc >/dev/null 2>&1; then
  echo "error: pandoc is required to render Markdown." >&2
  echo "Install it with:  brew install pandoc" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$(dirname "$OUT")"
mkdir -p "$OUT_DIR"

pandoc "$IN" \
  -o "$OUT" \
  --standalone \
  --embed-resources \
  --css "$SCRIPT_DIR/md-view.css" \
  --metadata title="$(basename "$IN" .md)" \
  --metadata lang=en

printf '%s\n' "$OUT"
