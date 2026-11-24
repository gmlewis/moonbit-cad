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

# If rendering START-HERE.md, embed the high-quality OCCT assembly.glb (base64)
# and explode.json when present (falling back to assembly.gltf) so the
# interactive animated Three.js 3D viewer works even over file://.
if [[ "$(basename "$IN")" == "START-HERE.md" ]]; then
  python3 - "$OUT" "$IN_DIR" <<'PY'
import base64, pathlib, sys
html_path = pathlib.Path(sys.argv[1])
in_dir = pathlib.Path(sys.argv[2])
html = html_path.read_text(encoding="utf-8")

tags = []
glb_path = in_dir / "assembly.glb"
gltf_path = in_dir / "assembly.gltf"
explode_path = in_dir / "explode.json"

if glb_path.exists() and 'id="embedded-assembly-glb"' not in html:
    b64 = base64.b64encode(glb_path.read_bytes()).decode("ascii")
    tags.append(f'<script id="embedded-assembly-glb" type="text/plain">{b64}</script>\n')
elif gltf_path.exists() and 'id="embedded-assembly-gltf"' not in html:
    gltf = gltf_path.read_text(encoding="utf-8").replace("</script", "<\\/script")
    tags.append(f'<script id="embedded-assembly-gltf" type="application/json">{gltf}</script>\n')

if explode_path.exists() and 'id="embedded-explode-json"' not in html:
    exp = explode_path.read_text(encoding="utf-8").replace("</script", "<\\/script")
    tags.append(f'<script id="embedded-explode-json" type="application/json">{exp}</script>\n')

if tags:
    blob = "".join(tags)
    if '<script type="module">' in html:
        html = html.replace('<script type="module">', blob + '<script type="module">', 1)
    elif "</body>" in html:
        html = html.replace("</body>", blob + "</body>", 1)
    html_path.write_text(html, encoding="utf-8")
PY
fi

printf '%s\n' "$OUT"
