#!/usr/bin/env bash
# view-md.sh — render a Markdown file and open it in the default browser.
#
# Usage:
#   ./view-md.sh FILE.md
#   ./view-md.sh build/02/START-HERE.md
#
# The rendered HTML sits next to the source file. It is self-contained, so
# sharing the .html file also works.
set -euo pipefail

usage() {
  cat <<'EOF'
view-md.sh — render Markdown and open it in the default browser.

Usage:
  ./view-md.sh FILE.md [OUT.html]

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$("$SCRIPT_DIR/scripts/md-view.sh" "$@")"

if command -v open >/dev/null 2>&1; then
  open "$OUT"
else
  echo "Rendered: $OUT" >&2
fi
