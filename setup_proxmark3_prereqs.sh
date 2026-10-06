#!/usr/bin/env bash
# ==============================================================================
# Script: setup_proxmark3_prereqs.sh
# Purpose: System preparation for Proxmark3:
#          - Adds user to 'dialout' group
#          - Installs udev rules (MODE=0666, TAG+=uaccess, blocks ModemManager)
#          - Installs native libraries for client compilation
#          - Optionally installs ARM cross-compiler toolchain (--full)
# Usage:
#   sudo ./setup_proxmark3_prereqs.sh         # Native client dependencies (fast)
#   sudo ./setup_proxmark3_prereqs.sh --full  # Includes ARM cross-compilers
# ==============================================================================

set -euo pipefail

# 1. Require root execution
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "[!] Error: Root privileges required." >&2
    echo "    Usage: sudo $0 [--full]" >&2
    exit 1
fi

INSTALL_CROSS=false
for arg in "$@"; do
    case "$arg" in
        --full|--cross-compile)
            INSTALL_CROSS=true
            ;;
        --help|-h)
            echo "Usage: sudo $0 [--full]"
            echo "  --full    Install ARM cross-compiler (gcc-arm-none-eabi) in addition"
            echo "            to native client libraries."
            exit 0
            ;;
        *)
            echo "[!] Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

ACTUAL_USER="${SUDO_USER:-$USER}"

echo "=========================================================="
echo " Proxmark3 System Preparation"
echo " Target user:      ${ACTUAL_USER}"
echo " Install ARM tool: ${INSTALL_CROSS}"
echo "=========================================================="

# 2. Add user to dialout group
echo "[*] Ensuring user '${ACTUAL_USER}' is in 'dialout' group..."
if id -nG "${ACTUAL_USER}" | grep -qw "dialout"; then
    echo "[+] User '${ACTUAL_USER}' is already in 'dialout'."
else
    usermod -aG dialout "${ACTUAL_USER}"
    echo "[+] User '${ACTUAL_USER}' added to 'dialout'."
fi

# 3. Base native packages for building the client
NATIVE_PKGS=(
    git
    build-essential
    pkg-config
    libreadline-dev
    liblz4-dev
    libbz2-dev
    libbluetooth-dev
    libssl-dev
    python3
)

CROSS_PKGS=(
    gcc-arm-none-eabi
    libnewlib-arm-none-eabi
)

PACKAGES=("${NATIVE_PKGS[@]}")
if [[ "${INSTALL_CROSS}" == "true" ]]; then
    PACKAGES+=("${CROSS_PKGS[@]}")
fi

echo "[*] Updating apt index and installing dependencies..."
apt update -y
apt install -y "${PACKAGES[@]}"

# 4. Install udev rules
echo "[*] Configuring /etc/udev/rules.d/77-pm3-usb-device.rules..."
cat << 'EOF' > /etc/udev/rules.d/77-pm3-usb-device.rules
# Proxmark3 RFID Instrument udev rules
# Prevents ModemManager from probing and grants user read/write access
ACTION!="add|change", GOTO="pm3_rules_end"
SUBSYSTEM!="usb|tty", GOTO="pm3_rules_end"

# Proxmark3 USB bootloader & CDC ACM device
ATTRS{idVendor}=="9ac4", ATTRS{idProduct}=="4b8f", ENV{ID_MM_CANDIDATE}="0", ENV{ID_MM_DEVICE_IGNORE}="1", GROUP="dialout", MODE="0666", TAG+="uaccess", SYMLINK+="proxmark3"
ATTRS{idVendor}=="2d2d", ATTRS{idProduct}=="504d", ENV{ID_MM_CANDIDATE}="0", ENV{ID_MM_DEVICE_IGNORE}="1", GROUP="dialout", MODE="0666", TAG+="uaccess", SYMLINK+="proxmark3"

LABEL="pm3_rules_end"
EOF

chmod 644 /etc/udev/rules.d/77-pm3-usb-device.rules

echo "[*] Reloading udev daemon..."
udevadm control --reload-rules
udevadm trigger

# 5. Apply immediate permissions to active device nodes
for dev in /dev/ttyACM* /dev/proxmark3; do
    if [[ -e "$dev" ]]; then
        echo "[+] Setting immediate 0666 permissions on connected node: $dev"
        chmod 666 "$dev" || true
    fi
done

echo ""
echo "=========================================================="
echo " System preparation complete!"
echo "=========================================================="
