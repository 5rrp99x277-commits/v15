#!/usr/bin/env bash
set -euo pipefail

: "${PICO_SDK_PATH:?Set PICO_SDK_PATH to your pico-sdk path}"

cmake -S . -B build -DPICO_BOARD=pico
cmake --build build -j

echo
echo "UF2 files:"
find build -type f -name "*.uf2" -print
