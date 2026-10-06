#!/usr/bin/env bash
# ==============================================================================
# Script: run_pm3.sh
# Purpose: Launch the compiled Proxmark3 client with automatic port detection.
# Usage:   ./run_pm3.sh [optional client arguments]
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/pm3-source"
PM3_LAUNCHER="${SOURCE_DIR}/pm3"

# Verify that client executable exists
if [[ ! -x "${PM3_LAUNCHER}" || ! -x "${SOURCE_DIR}/client/proxmark3" ]]; then
    echo "[!] Error: Compiled Proxmark3 client not found." >&2
    echo "    Run './build_pm3.sh' to compile the client first." >&2
    exit 1
fi

echo "[*] Launching Proxmark3 client..."
exec "${PM3_LAUNCHER}" "$@"
