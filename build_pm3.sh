#!/usr/bin/env bash
# ==============================================================================
# Script: build_pm3.sh
# Purpose: Modular builder for RfidResearchGroup Proxmark3 (Iceman):
#          - Client-Only mode: Compiles native Linux client using host GCC (Fast)
#          - Full mode: Compiles both client and ARM on-chip firmware for clones
# Usage:
#   ./build_pm3.sh               # Auto-detects: builds client (or all if cross-compiler present)
#   ./build_pm3.sh --client-only # Explicitly build host client only (no cross-compiler needed)
#   ./build_pm3.sh --all         # Build both client and ARM firmware for clone (PM3GENERIC)
#   ./build_pm3.sh --all --256k  # Build both for 256k microcontroller (AT91SAM7S256)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/pm3-source"

# Mode defaults
BUILD_TARGET="auto"
CHIP_SIZE="512"

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --client-only)
            BUILD_TARGET="client"
            shift
            ;;
        --all|--firmware)
            BUILD_TARGET="all"
            shift
            ;;
        --256k)
            CHIP_SIZE="256"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --client-only   Compile host PC client only (no ARM cross-compiler required)."
            echo "  --all           Compile both host client and ARM firmware for clone (PM3GENERIC)."
            echo "  --256k          Target 256k microcontroller when building firmware."
            echo "  --help, -h      Show this help message."
            exit 0
            ;;
        *)
            echo "[!] Unknown option: $1" >&2
            echo "    Run '$0 --help' for available options." >&2
            exit 1
            ;;
    esac
done

# If auto, check if ARM cross-compiler is available
if [[ "${BUILD_TARGET}" == "auto" ]]; then
    if command -v arm-none-eabi-gcc >/dev/null 2>&1; then
        BUILD_TARGET="all"
    else
        BUILD_TARGET="client"
    fi
fi

echo "=========================================================="
echo " Proxmark3 Build System"
echo " Target:          ${BUILD_TARGET}"
if [[ "${BUILD_TARGET}" == "all" ]]; then
    echo " Platform:        PM3GENERIC (Chinese Clone)"
    echo " Microcontroller: ${CHIP_SIZE} kB"
fi
echo "=========================================================="

# 1. Dependency Validation
REQUIRED_NATIVE=("git" "make" "gcc" "pkg-config")
for tool in "${REQUIRED_NATIVE[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[!] Error: Missing required host tool: $tool" >&2
        echo "    Run 'sudo ./setup_proxmark3_prereqs.sh' first." >&2
        exit 1
    fi
done

if [[ "${BUILD_TARGET}" == "all" ]]; then
    if ! command -v arm-none-eabi-gcc >/dev/null 2>&1; then
        echo "[!] Error: arm-none-eabi-gcc is required to build firmware." >&2
        echo "    Run 'sudo ./setup_proxmark3_prereqs.sh --full' to install it," >&2
        echo "    or use './build_pm3.sh --client-only' to build just the client." >&2
        exit 1
    fi
fi

# 2. Source Tree Management
if [[ ! -d "${SOURCE_DIR}" ]]; then
    echo "[*] Cloning official RfidResearchGroup/proxmark3 repository..."
    git clone https://github.com/RfidResearchGroup/proxmark3.git "${SOURCE_DIR}"
else
    echo "[*] Source repository present at ${SOURCE_DIR}."
fi

# 3. Configure Platform Settings
cd "${SOURCE_DIR}"
if [[ ! -f "Makefile.platform" ]]; then
    cp Makefile.platform.sample Makefile.platform
fi

# Configure for Chinese clone (PM3GENERIC)
sed -i 's/^PLATFORM=.*/PLATFORM=PM3GENERIC/' Makefile.platform

if [[ "${CHIP_SIZE}" == "256" ]]; then
    if grep -q "^PLATFORM_SIZE=" Makefile.platform; then
        sed -i 's/^PLATFORM_SIZE=.*/PLATFORM_SIZE=256/' Makefile.platform
    else
        echo "PLATFORM_SIZE=256" >> Makefile.platform
    fi
else
    sed -i 's/^PLATFORM_SIZE=256/#PLATFORM_SIZE=256/' Makefile.platform
fi

# 4. Compilation
echo "[*] Building target '${BUILD_TARGET}' using $(nproc) parallel jobs..."
make clean
make -j"$(nproc)" "${BUILD_TARGET}"

echo ""
echo "=========================================================="
echo " Build finished successfully!"
echo " Client binary: ${SOURCE_DIR}/client/proxmark3"
echo " Launcher:      ${SOURCE_DIR}/pm3"
if [[ "${BUILD_TARGET}" == "all" ]]; then
    echo " Bootloader:    ${SOURCE_DIR}/bootrom/obj/bootrom.elf"
    echo " Fullimage(OS): ${SOURCE_DIR}/armsrc/obj/fullimage.elf"
fi
echo "=========================================================="
echo ""
echo "Next step:"
echo " Test communication with your board:"
echo "     ./run_pm3.sh"
echo ""
