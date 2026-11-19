#!/usr/bin/env bash
# customize.sh — open the local parameter customizer for one example.
#
# Usage:
#   ./customize.sh 08
#   ./customize.sh 08 --port 9000 --no-open
#
# All arguments are forwarded to scripts/customize.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$ROOT/scripts/customize.py" "$@"
