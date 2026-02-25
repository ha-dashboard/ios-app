#!/bin/bash
# Captures screenshots of each test-harness view from the iOS simulator in both themes.
# Uses -HAViewIndex and -HAThemeMode launch arguments to iterate programmatically.
#
# Usage: ./capture-ios.sh [--theme gradient|light|both] [--token <access_token>]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load env vars
if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a; source "$PROJECT_DIR/.env"; set +a
fi

SIM_ID="${SIM_IPAD_UDID:-}"
APP_ID="${BUNDLE_ID:-com.example.hadashboard}"
APP_PATH="$(find ~/Library/Developer/Xcode/DerivedData/HADashboard-*/Build/Products/Debug-iphonesimulator -name 'HA Dashboard.app' -type d 2>/dev/null | head -1)"

if [[ -z "$SIM_ID" ]]; then
    echo "❌ SIM_IPAD_UDID not set. Add it to .env"
    exit 1
fi

# Parse arguments
THEME_ARG="both"
ACCESS_TOKEN=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --theme) THEME_ARG="$2"; shift 2 ;;
        --token) ACCESS_TOKEN="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Try reading token from file if not provided
if [ -z "$ACCESS_TOKEN" ] && [ -f /tmp/ha-test-token.txt ]; then
    ACCESS_TOKEN="$(cat /tmp/ha-test-token.txt)"
fi

if [ -z "$ACCESS_TOKEN" ]; then
    echo "No access token. Provide --token or run the HA auth flow first."
    exit 1
fi

if [ -z "$APP_PATH" ]; then
    echo "App not found. Build first: xcodebuild build -scheme HADashboard ..."
    exit 1
fi

# Theme modes: 1=gradient (dark), 3=light
if [ "$THEME_ARG" = "both" ]; then
    THEMES=("gradient:1" "light:3")
elif [ "$THEME_ARG" = "gradient" ]; then
    THEMES=("gradient:1")
elif [ "$THEME_ARG" = "light" ]; then
    THEMES=("light:3")
else
    echo "Unknown theme: $THEME_ARG (use gradient, light, or both)"
    exit 1
fi

# Install latest build
xcrun simctl install "$SIM_ID" "$APP_PATH" 2>&1

for theme_pair in "${THEMES[@]}"; do
    THEME_NAME="${theme_pair%%:*}"
    THEME_MODE="${theme_pair##*:}"
    OUTPUT_DIR="$SCRIPT_DIR/../screenshots/app/$THEME_NAME"
    mkdir -p "$OUTPUT_DIR"

    echo ""
    echo "=== Theme: $THEME_NAME (mode $THEME_MODE) ==="

    for pair in "0:lighting" "1:climate" "2:sensors" "3:security" "4:media" "5:vacuums" "6:inputs" "7:entities"; do
        idx="${pair%%:*}"
        view="${pair##*:}"
        echo "  View $idx: $view"

        xcrun simctl terminate "$SIM_ID" "$APP_ID" 2>/dev/null || true
        sleep 1

        xcrun simctl launch "$SIM_ID" "$APP_ID" \
            -HAServerURL "http://localhost:8124" \
            -HAAccessToken "$ACCESS_TOKEN" \
            -HADashboard "test-harness" \
            -HAViewIndex "$idx" \
            -HAThemeMode "$THEME_MODE" > /dev/null 2>&1

        sleep 6

        xcrun simctl io "$SIM_ID" screenshot "$OUTPUT_DIR/view-$view.png" --type png 2>/dev/null
        echo "    Saved: view-$view.png"
    done

    echo "  Theme '$THEME_NAME': $(ls "$OUTPUT_DIR"/view-*.png 2>/dev/null | wc -l) screenshots"
done

xcrun simctl terminate "$SIM_ID" "$APP_ID" 2>/dev/null || true
echo ""
echo "Done."
