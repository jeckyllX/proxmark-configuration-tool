#!/usr/bin/env bash
# ==============================================================================
# Script: check_pm3.sh
# Purpose: Non-interactive hardware & firmware diagnostic utility:
#          - Detects connected Proxmark3 device
#          - Checks if device port is currently claimed by another process
#          - Queries on-chip microcontroller architecture (AT91SAM7S512 vs 256)
#          - Detects protocol / capabilities mismatches between client & board
# Usage:   ./check_pm3.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/pm3-source"
PM3_LAUNCHER="${SOURCE_DIR}/pm3"

echo "=========================================================="
echo " Proxmark3 Hardware & Firmware Diagnostic"
echo "=========================================================="

# 1. Verify client is built
if [[ ! -x "${PM3_LAUNCHER}" || ! -x "${SOURCE_DIR}/client/proxmark3" ]]; then
    echo "[!] Error: Client binary not found." >&2
    echo "    Run './build_pm3.sh --client-only' to build the client first." >&2
    exit 1
fi

# 2. Port detection
PORT=""
if [[ -e "/dev/proxmark3" ]]; then
    PORT="/dev/proxmark3"
elif compgen -G "/dev/serial/by-id/*proxmark*" >/dev/null; then
    PORT="$(ls -1 /dev/serial/by-id/*proxmark* | head -n 1)"
elif compgen -G "/dev/ttyACM*" >/dev/null; then
    PORT="$(ls -1 /dev/ttyACM* | head -n 1)"
fi

if [[ -z "${PORT}" ]]; then
    echo "[!] No Proxmark3 device detected on USB."
    echo "    Please plug in the device and verify with 'lsusb'."
    exit 1
fi

echo "[+] Detected device on port: ${PORT}"

# 3. Check if serial port is locked by another process
LOCKED_PID="$(fuser "${PORT}" 2>/dev/null || true)"
if [[ -n "${LOCKED_PID}" ]]; then
    echo ""
    echo "[!] Warning: The port ${PORT} is currently in use by process PID ${LOCKED_PID}."
    echo "    (You probably have an active 'pm3' interactive terminal open)."
    echo "    To run this diagnostic, exit the active client session first."
    exit 2
fi

# 4. Perform non-interactive hardware handshake
echo "[*] Querying hardware configuration and capabilities..."
OUTPUT="$("${PM3_LAUNCHER}" -p "${PORT}" -c "hw version" 2>&1 || true)"

# 5. Evaluate handshake result
if echo "${OUTPUT}" | grep -q "Capabilities structure version sent by Proxmark3 is not the one expected"; then
    echo ""
    echo "=========================================================="
    echo " [!] FIRMWARE / PROTOCOL MISMATCH DETECTED"
    echo "=========================================================="
    echo " The board is running an older factory firmware build that"
    echo " does not match the modern client protocol."
    echo ""
    echo " Resolution:"
    echo " Cross-compile and flash the matching firmware:"
    echo "     ./quick_setup.sh --all"
    echo "     ./flash_pm3.sh"
    echo "=========================================================="
    exit 3
fi

if echo "${OUTPUT}" | grep -q "cannot communicate with the Proxmark3"; then
    echo "[!] Error: Failed to communicate with Proxmark3."
    echo "    Raw client output:"
    echo "${OUTPUT}"
    exit 1
fi

echo ""
echo "=========================================================="
echo " [+] HARDWARE & FIRMWARE STATUS: HEALTHY & MATCHED"
echo "=========================================================="

# Extract key hardware specs if present in output
CHIP="$(echo "${OUTPUT}" | grep -iE "Chip|ARM" | head -n 2 || true)"
PLATFORM="$(echo "${OUTPUT}" | grep -iE "Target platform|Platform" | head -n 2 || true)"
OS_VERSION="$(echo "${OUTPUT}" | grep -iE "OS image|Version" | head -n 2 || true)"

if [[ -n "${CHIP}" ]]; then
    echo "${CHIP}"
fi
if [[ -n "${PLATFORM}" ]]; then
    echo "${PLATFORM}"
fi
if [[ -n "${OS_VERSION}" ]]; then
    echo "${OS_VERSION}"
fi

echo ""
echo "You can launch the interactive client anytime with:"
echo "    ./run_pm3.sh"
echo "=========================================================="
