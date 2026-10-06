#!/usr/bin/env bash
# ==============================================================================
# Script: quick_setup.sh
# Purpose: Foolproof, automated orchestrator for Proxmark3 Easy (Chinese Clone):
#          - Detects missing OS packages, compilers, and udev rules
#          - Builds client and performs non-interactive board diagnostic
#          - Detects factory protocol mismatches and seamlessly guides through
#            cross-compilation and flashing
# Usage:
#   ./quick_setup.sh         # Smart interactive wizard (Recommended)
#   ./quick_setup.sh --all   # Directly build client + ARM firmware and offer flash
#   ./quick_setup.sh --256k  # Target 256k microcontroller (when compiling firmware)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FULL_BUILD=false
CHIP_SIZE="512"

# Parse CLI options
for arg in "$@"; do
    case "$arg" in
        --all|--firmware)
            FULL_BUILD=true
            ;;
        --256k)
            CHIP_SIZE="256"
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --all       Directly cross-compile ARM firmware and offer to flash."
            echo "  --256k      Configure for 256k microcontroller (AT91SAM7S256)."
            echo "  Default     Smart wizard: tests board first and flashes only if needed."
            exit 0
            ;;
        *)
            echo "[!] Unknown option: $arg" >&2
            echo "    Run '$0 --help' for options." >&2
            exit 1
            ;;
    esac
done

echo "=========================================================="
echo " Proxmark3 Easy (Clone) Setup"
echo " Target Microcontroller: ${CHIP_SIZE} kB"
echo "=========================================================="

# ------------------------------------------------------------------------------
# Function: Ensure System Prereqs & Udev Rules
# ------------------------------------------------------------------------------
ensure_prereqs() {
    local need_cross="${1:-false}"
    local need_sudo=false

    if ! pkg-config --version >/dev/null 2>&1 || [[ ! -f "/etc/udev/rules.d/77-pm3-usb-device.rules" ]]; then
        need_sudo=true
    fi

    if [[ "${need_cross}" == "true" ]] && ! command -v arm-none-eabi-gcc >/dev/null 2>&1; then
        need_sudo=true
    fi

    if [[ "${need_sudo}" == "true" ]]; then
        echo ""
        echo "[*] System dependencies or udev permissions missing."
        echo "    Requesting sudo once to configure system..."
        if [[ "${need_cross}" == "true" ]]; then
            sudo "${SCRIPT_DIR}/setup_proxmark3_prereqs.sh" --full
        else
            sudo "${SCRIPT_DIR}/setup_proxmark3_prereqs.sh"
        fi
    else
        echo "[+] System toolchains and udev rules are verified and active."
    fi
}

# ------------------------------------------------------------------------------
# Function: Cross-compile and Flash Board
# ------------------------------------------------------------------------------
build_and_flash_firmware() {
    echo ""
    echo "[*] Step: Preparing ARM cross-compilation toolchain..."
    ensure_prereqs true

    echo ""
    echo "[*] Step: Compiling matching bootloader and OS firmware..."
    local build_opts=("--all")
    if [[ "${CHIP_SIZE}" == "256" ]]; then
        build_opts+=("--256k")
    fi
    "${SCRIPT_DIR}/build_pm3.sh" "${build_opts[@]}"

    echo ""
    read -rp "Firmware compiled! Proceed with flashing to your Proxmark3 now? [Y/n]: " DO_FLASH
    DO_FLASH="${DO_FLASH:-y}"
    if [[ "${DO_FLASH}" =~ ^[Yy]$ ]]; then
        "${SCRIPT_DIR}/flash_pm3.sh"
        echo ""
        echo "[*] Re-running diagnostic to verify new firmware..."
        "${SCRIPT_DIR}/check_pm3.sh" || true
    else
        echo "[*] Flashing skipped. You can flash anytime by running './flash_pm3.sh'."
    fi
}

# ==============================================================================
# MAIN WORKFLOW
# ==============================================================================

if [[ "${FULL_BUILD}" == "true" ]]; then
    # Direct full build requested
    build_and_flash_firmware
else
    # Smart client-first workflow
    echo ""
    echo "[*] Step 1: Checking base system dependencies..."
    ensure_prereqs false

    echo ""
    echo "[*] Step 2: Ensuring native PC client is compiled..."
    if [[ ! -x "${SCRIPT_DIR}/pm3-source/client/proxmark3" || ! -x "${SCRIPT_DIR}/pm3-source/pm3" ]]; then
        "${SCRIPT_DIR}/build_pm3.sh" --client-only
    else
        echo "[+] Client binary already built and ready."
    fi

    echo ""
    echo "[*] Step 3: Performing non-interactive board handshake..."
    DIAG_CODE=0
    "${SCRIPT_DIR}/check_pm3.sh" || DIAG_CODE=$?

    case "${DIAG_CODE}" in
        0)
            echo ""
            echo "=========================================================="
            echo " [+] Proxmark3 is configured and ready."
            echo "=========================================================="
            echo "Launch the client anytime with:"
            echo "    ./run_pm3.sh"
            echo ""
            read -rp "Would you like to open the client now? [Y/n]: " LAUNCH_NOW
            LAUNCH_NOW="${LAUNCH_NOW:-y}"
            if [[ "${LAUNCH_NOW}" =~ ^[Yy]$ ]]; then
                exec "${SCRIPT_DIR}/run_pm3.sh"
            fi
            ;;
        3)
            echo ""
            echo "[!] Protocol mismatch detected between client and board."
            echo "    The board is running older factory firmware."
            read -rp "Would you like to automatically cross-compile and flash the board now? [Y/n]: " FIX_NOW
            FIX_NOW="${FIX_NOW:-y}"
            if [[ "${FIX_NOW}" =~ ^[Yy]$ ]]; then
                build_and_flash_firmware
            else
                echo "Skipped. Run './quick_setup.sh --all' whenever you are ready."
            fi
            ;;
        2)
            echo ""
            echo "[!] The device port is currently open in another session."
            echo "    Exit your existing client session to run diagnostics."
            ;;
        *)
            echo ""
            echo "[!] Device not detected on USB."
            echo "    Plug in your Proxmark3 and run './quick_setup.sh' again."
            ;;
    esac
fi
