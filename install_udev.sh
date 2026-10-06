#!/usr/bin/env bash
# ==============================================================================
# Script: install_udev.sh
# Purpose: Install Proxmark3 udev rules to configure USB permissions and
#          block ModemManager from interfering with the device serial port.
# Usage:   sudo ./install_udev.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/pm3-source"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "[!] Error: This script must be run with sudo." >&2
    echo "    Usage: sudo $0" >&2
    exit 1
fi

echo "=========================================================="
echo " Proxmark3 Udev Rules Installer"
echo "=========================================================="

RULES_SRC=""
if [[ -f "${SOURCE_DIR}/driver/77-pm3-usb-device.rules" ]]; then
    RULES_SRC="${SOURCE_DIR}/driver/77-pm3-usb-device.rules"
elif [[ -f "${SOURCE_DIR}/doc/77-pm3-usb-device.rules" ]]; then
    RULES_SRC="${SOURCE_DIR}/doc/77-pm3-usb-device.rules"
fi

if [[ -n "${RULES_SRC}" && -f "${RULES_SRC}" ]]; then
    echo "[*] Installing udev rules from ${RULES_SRC} to /etc/udev/rules.d/..."
    cp "${RULES_SRC}" /etc/udev/rules.d/77-pm3-usb-device.rules
else
    echo "[*] Creating /etc/udev/rules.d/77-pm3-usb-device.rules directly..."
    cat << 'EOF' > /etc/udev/rules.d/77-pm3-usb-device.rules
# Proxmark3 RFID Instrument udev rules
# Prevents ModemManager from probing and gives dialout group read/write access
ACTION!="add|change", GOTO="pm3_rules_end"
SUBSYSTEM!="usb|tty", GOTO="pm3_rules_end"

# Proxmark3 USB bootloader & CDC ACM device
ATTRS{idVendor}=="9ac4", ATTRS{idProduct}=="4b8f", ENV{ID_MM_CANDIDATE}="0", ENV{ID_MM_DEVICE_IGNORE}="1", GROUP="dialout", MODE="0660", SYMLINK+="proxmark3"
ATTRS{idVendor}=="2d2d", ATTRS{idProduct}=="504d", ENV{ID_MM_CANDIDATE}="0", ENV{ID_MM_DEVICE_IGNORE}="1", GROUP="dialout", MODE="0660", SYMLINK+="proxmark3"

LABEL="pm3_rules_end"
EOF
fi

chmod 644 /etc/udev/rules.d/77-pm3-usb-device.rules

echo "[*] Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger

echo "[+] Proxmark3 udev rules successfully installed and active!"
