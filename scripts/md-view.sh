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

IN_DIR="$(dirname "$IN")"
pandoc "$IN" \
  -o "$OUT" \
  --standalone \
  --embed-resources \
  --resource-path "$IN_DIR" \
  --css "$SCRIPT_DIR/md-view.css" \
  --metadata title="$(basename "$IN" .md)" \
  --metadata lang=en

# If rendering START-HERE.md and assembly.gltf exists alongside it, embed the
# glTF JSON so the interactive Three.js 3D viewer works even over file://.
if [[ "$(basename "$IN")" == "START-HERE.md" && -f "$IN_DIR/assembly.gltf" ]]; then
  python3 - "$OUT" "$IN_DIR/assembly.gltf" <<'PY'
import sys
html_path, gltf_path = sys.argv[1], sys.argv[2]
html = open(html_path, "r", encoding="utf-8").read()
gltf = open(gltf_path, "r", encoding="utf-8").read().replace("</script", "<\\/script")
tag = f'<script id="embedded-assembly-gltf" type="application/json">{gltf}</script>\n'
if 'id="embedded-assembly-gltf"' not in html:
    if "<script type=\"module\">" in html:
        html = html.replace("<script type=\"module\">", tag + "<script type=\"module\">", 1)
    elif "</body>" in html:
        html = html.replace("</body>", tag + "</body>", 1)
    open(html_path, "w", encoding="utf-8").write(html)
PY
fi

printf '%s\n' "$OUT"
