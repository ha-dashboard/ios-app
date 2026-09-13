#!/bin/bash
set -euo pipefail
BLE_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BLE_PROJECT_DIR"
BLE_XCODE="${XCODE_PATH:-/Applications/Xcode.app}"
[[ -d "$BLE_XCODE" ]] || BLE_XCODE=/Applications/Xcode-beta.app
export DEVELOPER_DIR="$BLE_XCODE/Contents/Developer"
mkdir -p build/ble-proxy-receipts
xcrun --sdk macosx clang -Os -fobjc-arc -fmodules -framework Foundation -framework CFNetwork -framework Security \
    -I Vendor/Monocypher -I HADashboard/Bluetooth \
    HADashboard/Bluetooth/HABLEProto.m HADashboard/Bluetooth/HABLENoiseSession.m \
    HADashboard/Bluetooth/HABLEAPIServer.m Vendor/Monocypher/monocypher.c \
    -dynamiclib -o build/ble-proxy-receipts/libbleproto.dylib
build/ble-proxy-venv/bin/python scripts/test-ble-noise.py
