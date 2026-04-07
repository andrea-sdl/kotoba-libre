#!/usr/bin/env bash
set -euo pipefail

# This helper creates a clean source zip for the Firefox extension so it can be shared or uploaded.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/package-browser-extension.sh" firefox "$@"
