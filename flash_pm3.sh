#!/usr/bin/env bash
# ==============================================================================
# Script: flash_pm3.sh
# Purpose: Guarded firmware flasher for Proxmark3 Chinese Clone.
#          Ensures firmware binaries exist before attempting flashing,
#          and provides recovery instructions.
# Usage:   ./flash_pm3.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/pm3-source"
BOOTROM_ELF="${SOURCE_DIR}/bootrom/obj/bootrom.elf"
FULLIMAGE_ELF="${SOURCE_DIR}/armsrc/obj/fullimage.elf"
FLASH_ALL="${SOURCE_DIR}/pm3-flash-all"

# 1. Check if firmware has been compiled
if [[ ! -f "${BOOTROM_ELF}" || ! -f "${FULLIMAGE_ELF}" || ! -x "${FLASH_ALL}" ]]; then
    echo "[!] Error: ARM firmware images not found in ${SOURCE_DIR}." >&2
    echo "    You appear to be in client-only mode or haven't built firmware yet." >&2
    echo "" >&2
    echo "    To install the ARM cross-compiler and build firmware, run:" >&2
    echo "        sudo ./setup_proxmark3_prereqs.sh --full" >&2
    echo "        ./build_pm3.sh --all" >&2
    exit 1
fi

# 2. Detect serial port
PORT=""
if [[ -e "/dev/proxmark3" ]]; then
    PORT="/dev/proxmark3"
elif compgen -G "/dev/serial/by-id/*proxmark*" >/dev/null; then
    PORT="$(ls -1 /dev/serial/by-id/*proxmark* | head -n 1)"
elif compgen -G "/dev/ttyACM*" >/dev/null; then
    PORT="$(ls -1 /dev/ttyACM* | head -n 1)"
fi

echo "=========================================================="
echo " Proxmark3 Firmware Flasher"
echo " Target port: ${PORT:-Auto-detect}"
echo "=========================================================="
echo ""
echo "Safety Checklist:"
echo " 1. Ensure you compiled with the correct chip size (default: 512k, or --256k)."
echo " 2. Do NOT disconnect USB during the flash."
echo " 3. If flashing is ever interrupted:"
echo "    - Hold down the button on the board while plugging into USB."
echo "    - Run './pm3-flash-bootrom' inside 'pm3-source'."
echo "=========================================================="
echo ""
read -rp "Proceed with flashing firmware now? (y/N): " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
    echo "Flashing canceled."
    exit 0
fi

cd "${SOURCE_DIR}"
if [[ -n "${PORT}" ]]; then
    ./pm3-flash-all -p "${PORT}"
else
    ./pm3-flash-all
fi
