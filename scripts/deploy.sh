#!/bin/bash
set -euo pipefail

# HA Dashboard — Build, Deploy & Launch
# Usage:
#   scripts/deploy.sh sim          # Build + run in iPad 10th gen simulator
#   scripts/deploy.sh sim iphone   # Build + run in iPhone 15 Pro simulator
#   scripts/deploy.sh iphone       # Build + deploy + launch on physical iPhone
#   scripts/deploy.sh mini5        # Build + deploy to iPad Mini 5 (WiFi, devicectl)
#   scripts/deploy.sh mini4        # Build + deploy to iPad Mini 4 (WiFi, ios-deploy)
#   scripts/deploy.sh ipad2        # Build + deploy to iPad 2 via WiFi SSH (jailbroken)
#   scripts/deploy.sh mac          # Build + launch Mac Catalyst app locally
#
# Options:
#   --no-build    Skip build step
#   --dashboard X Override dashboard (default: living-room)
#   --default     Use default (overview) dashboard instead of living-room
#   --server URL  Override HA server URL
#   --token TOKEN Override access token (for this launch only)
#   --kiosk       Start in kiosk mode
#   --no-kiosk    Disable kiosk mode
#   --reset       Clear credentials and start at login screen
#   --demo        Start in demo mode (no server needed)

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="${BUNDLE_ID:-com.hadashboard.app}"

# ── Load secrets from .env ────────────────────────────────────────────
ENV_FILE="$PROJECT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# ── Defaults (overridden by .env) ─────────────────────────────────────
HA_SERVER="${HA_SERVER:-}"
HA_TOKEN="${HA_TOKEN:-}"
HA_DASHBOARD="${HA_DASHBOARD:-living-room}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
ASC_KEY_ID="${ASC_KEY_ID:-}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-}"
ASC_KEY_PATH="${ASC_KEY_PATH:-}"

IPHONE_DEVICECTL_ID="${IPHONE_DEVICECTL_ID:-}"
IPHONE_UDID="${IPHONE_UDID:-}"
IPAD_MINI5_DEVICECTL_ID="${IPAD_MINI5_DEVICECTL_ID:-}"
IPAD_MINI5_UDID="${IPAD_MINI5_UDID:-}"
IPAD_MINI4_UDID="${IPAD_MINI4_UDID:-}"
IPAD2_UDID="${IPAD2_UDID:-}"
IPAD2_IP="${IPAD2_IP:-}"
IPAD2_SSH_PASS="${IPAD2_SSH_PASS:-alpine}"
UNRAID_HOST="${UNRAID_HOST:-}"
UNRAID_USER="${UNRAID_USER:-root}"

# Simulator UDIDs — looked up dynamically by name if not set in .env
SIM_IPAD_NAME="${SIM_IPAD_NAME:-iPad Pro 11 M4}"
SIM_IPHONE_NAME="${SIM_IPHONE_NAME:-iPhone 15 Pro}"
SIM_IPAD_UDID="${SIM_IPAD_UDID:-}"
SIM_IPHONE_UDID="${SIM_IPHONE_UDID:-}"
SIM_IOS93_UDID="${SIM_IOS93_UDID:-D9DCA298-C3D2-4B68-9501-E5279A1B96B6}"
SIM_IOS103_UDID="${SIM_IOS103_UDID:-1197AD51-2DD7-48B4-B1E5-2EFC3DCAD610}"

# ── Xcode path (for devicectl/simctl commands) ────────────────────────
XCODE26="/Applications/Xcode.app"

# ── Parse arguments ─────────────────────────────────────────────────────
TARGET=""
NO_BUILD=false
KIOSK_MODE=""
RESET_MODE=false
DEMO_MODE=""
TOKEN_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        sim|sim-ios93|sim-ios103|iphone|mini5|mini4|ipad2|ipad2-usb|mac|all)
            if [[ -z "$TARGET" ]]; then
                TARGET="$1"
            else
                if [[ "$TARGET" == "sim" && "$1" == "iphone" ]]; then
                    TARGET="sim-iphone"
                fi
            fi
            shift ;;
        --no-build)   NO_BUILD=true; shift ;;
        --server)     HA_SERVER="$2"; shift 2 ;;
        --token)      TOKEN_OVERRIDE="$2"; shift 2 ;;
        --dashboard)  HA_DASHBOARD="$2"; shift 2 ;;
        --default)    HA_DASHBOARD=""; shift ;;
        --kiosk)      KIOSK_MODE="YES"; shift ;;
        --no-kiosk)   KIOSK_MODE="NO"; shift ;;
        --reset)      RESET_MODE=true; shift ;;
        --demo)       DEMO_MODE="YES"; shift ;;
        *)            echo "❌ Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    echo "Usage: scripts/deploy.sh <sim|iphone|mini5|mini4|ipad2> [options]"
    echo ""
    echo "Targets:"
    echo "  all            Deploy to all targets (builds once, deploys everywhere)"
    echo "  sim            iPad simulator (iPad 10th gen)"
    echo "  sim iphone     iPhone simulator (iPhone 15 Pro)"
    echo "  sim-ios93      iOS 9.3 iPad Pro simulator (RosettaSim, x86_64)"
    echo "  sim-ios103     iOS 10.3 iPad Pro 10.5\" simulator (RosettaSim, x86_64)"
    echo "  iphone         Physical iPhone (via devicectl)"
    echo "  mini5          iPad Mini 5 — iPadOS 26 (devicectl, WiFi)"
    echo "  mini4          iPad Mini 4 — iPadOS 15 (ios-deploy, WiFi)"
    echo "  ipad2          iPad 2 — iOS 9 (WiFi SSH, jailbroken)"
    echo "  ipad2-usb      iPad 2 — iOS 9 (Unraid USB fallback)"
    echo "  mac            Mac Catalyst (local Mac, fullscreen)"
    echo ""
    echo "Options:"
    echo "  --no-build     Skip build step"
    echo "  --server URL   Override HA server URL"
    echo "  --token TOKEN  Override access token (this launch only)"
    echo "  --dashboard X  Set dashboard path (default: living-room)"
    echo "  --default      Use default overview dashboard"
    echo "  --kiosk        Start in kiosk mode (hides nav, disables sleep)"
    echo "  --no-kiosk     Disable kiosk mode"
    echo "  --reset        Clear credentials, start at login screen"
    echo "  --demo         Start in demo mode (no server needed)"
    echo ""
    echo "Secrets are loaded from .env in project root."
    exit 1
fi

# ── Retry helper ─────────────────────────────────────────────────────
SELF="$0"
deploy_with_retry() {
    local max_retries=3
    local attempt=1
    while [[ $attempt -le $max_retries ]]; do
        # shellcheck disable=SC2086
        if "$SELF" "$@" 2>&1; then
            return 0
        fi
        if [[ $attempt -lt $max_retries ]]; then
            echo "⚠️  Attempt $attempt/$max_retries failed, retrying..."
            sleep 2
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

# ── "all" target: build all first, then deploy in parallel ───────────
if [[ "$TARGET" == "all" ]]; then
    # Collect pass-through options (exclude target and --no-build)
    OPTS=()
    [[ -n "$KIOSK_MODE" ]] && OPTS+=($([ "$KIOSK_MODE" == "YES" ] && echo "--kiosk" || echo "--no-kiosk"))
    [[ "$RESET_MODE" == true ]] && OPTS+=(--reset)
    [[ -n "$DEMO_MODE" ]] && OPTS+=(--demo)
    [[ -n "$TOKEN_OVERRIDE" ]] && OPTS+=(--token "$TOKEN_OVERRIDE")

    echo "🚀 Deploying to ALL targets..."
    echo ""

    # ── Phase 1: Build all variants ──────────────────────────────────
    echo "── Phase 1: Building ──────────────────────────────────────"
    echo "   Building simulator (arm64)..."
    "$PROJECT_DIR/scripts/build.sh" sim > /dev/null
    echo "   ✅ Simulator build complete"

    echo "   Building device (universal armv7+arm64)..."
    "$PROJECT_DIR/scripts/build.sh" device > /dev/null
    echo "   ✅ Device build complete"

    echo "   Building rosettasim (x86_64, iOS 9+)..."
    "$PROJECT_DIR/scripts/build.sh" rosettasim > /dev/null
    echo "   ✅ RosettaSim build complete"

    echo "   Building mac (Catalyst, arm64)..."
    "$PROJECT_DIR/scripts/build.sh" mac > /dev/null
    echo "   ✅ Mac Catalyst build complete"
    echo ""

    # ── Phase 2: Deploy in parallel with retries ─────────────────────
    echo "── Phase 2: Deploying (parallel, up to 3 retries) ───────"
    LOGDIR=$(mktemp -d)
    PIDS=()
    LABELS=()

    deploy_bg() {
        local label="$1"; shift
        deploy_with_retry "$@" > "$LOGDIR/$label.log" 2>&1 &
        PIDS+=($!)
        LABELS+=("$label")
    }

    deploy_bg "sim"         sim         --no-build ${OPTS[@]+"${OPTS[@]}"}
    deploy_bg "sim-iphone"  sim iphone  --no-build ${OPTS[@]+"${OPTS[@]}"}
    deploy_bg "sim-ios93"   sim-ios93   --no-build ${OPTS[@]+"${OPTS[@]}"}
    deploy_bg "sim-ios103"  sim-ios103  --no-build ${OPTS[@]+"${OPTS[@]}"}
    deploy_bg "iphone"      iphone      --no-build ${OPTS[@]+"${OPTS[@]}"}
    deploy_bg "mini5"       mini5       --no-build ${OPTS[@]+"${OPTS[@]}"}
    deploy_bg "mini4"       mini4       --no-build ${OPTS[@]+"${OPTS[@]}"}
    deploy_bg "ipad2"       ipad2       --no-build ${OPTS[@]+"${OPTS[@]}"}
    deploy_bg "mac"         mac         --no-build ${OPTS[@]+"${OPTS[@]}"}

    # Wait for all deploys and collect results
    FAILURES=()
    for i in "${!LABELS[@]}"; do
        if wait "${PIDS[$i]}"; then
            echo "   ✅ ${LABELS[$i]}"
        else
            echo "   ❌ ${LABELS[$i]} (see log below)"
            FAILURES+=("${LABELS[$i]}")
        fi
    done

    # Print logs for failures
    for label in "${FAILURES[@]}"; do
        echo ""
        echo "── $label deploy log ──────────────────────────────────"
        cat "$LOGDIR/$label.log"
        echo "────────────────────────────────────────────────────────"
    done
    rm -rf "$LOGDIR"

    echo ""
    if [[ ${#FAILURES[@]} -eq 0 ]]; then
        echo "✅ All targets deployed"
    else
        echo "⚠️  Deployed with failures: ${FAILURES[*]}"
        exit 1
    fi
    exit 0
fi

# ── Build ─────────────────────────────────────────────────────────────
# Calls scripts/build.sh which outputs the path to the built .app
case "$TARGET" in
    sim|sim-iphone)
        if [[ "$NO_BUILD" == false ]]; then
            APP="$("$PROJECT_DIR/scripts/build.sh" sim)"
        else
            APP="$PROJECT_DIR/build/sim/Build/Products/Debug-iphonesimulator/HA Dashboard.app"
        fi
        ;;
    sim-ios93|sim-ios103)
        if [[ "$NO_BUILD" == false ]]; then
            APP="$("$PROJECT_DIR/scripts/build.sh" rosettasim)"
        else
            APP="$PROJECT_DIR/build/rosettasim/Build/Products/Debug-iphonesimulator/HA Dashboard.app"
        fi
        ;;
    iphone|mini5|mini4|ipad2|ipad2-usb)
        if [[ "$NO_BUILD" == false ]]; then
            APP="$("$PROJECT_DIR/scripts/build.sh" device)"
        else
            APP="$PROJECT_DIR/build/universal/HA Dashboard.app"
        fi
        ;;
    mac)
        if [[ "$NO_BUILD" == false ]]; then
            APP="$("$PROJECT_DIR/scripts/build.sh" mac)"
        else
            APP="$PROJECT_DIR/build/mac/Build/Products/Debug-maccatalyst/HA Dashboard.app"
        fi
        ;;
esac

if [ ! -d "$APP" ]; then
    echo "❌ Build failed — app not found at $APP"
    exit 1
fi
if [[ "$NO_BUILD" == false ]]; then
    # Catalyst binary is at Contents/MacOS/, iOS binary is at the app root
    BINARY="$APP/HA Dashboard"
    [[ -f "$APP/Contents/MacOS/HA Dashboard" ]] && BINARY="$APP/Contents/MacOS/HA Dashboard"
    echo "✅ Build succeeded: $(du -sh "$APP" | cut -f1) — $(lipo -archs "$BINARY" 2>/dev/null || echo "unknown")"
fi

# ── Per-target dashboard defaults (override with --dashboard) ──────────
# Only apply defaults if user didn't explicitly set --dashboard
if [[ "$HA_DASHBOARD" == "living-room" ]]; then
    case "$TARGET" in
        mini5)    HA_DASHBOARD="dashboard-landing" ;;
        mini4)    HA_DASHBOARD="living-room" ;;
        ipad2|ipad2-usb)  HA_DASHBOARD="dashboard-office"; KIOSK_MODE="${KIOSK_MODE:-YES}" ;;
        # sim, sim-iphone, iphone: keep living-room
    esac
fi

# ── Launch args ─────────────────────────────────────────────────────────
# --reset takes priority: clear credentials first, then don't inject server/token
if [[ "$RESET_MODE" == true ]]; then
    LAUNCH_ARGS=(-HAClearCredentials YES)
else
    # Use token override if provided, otherwise fall back to .env token
    EFFECTIVE_TOKEN="${TOKEN_OVERRIDE:-$HA_TOKEN}"
    LAUNCH_ARGS=(-HAServerURL "$HA_SERVER" -HAAccessToken "$EFFECTIVE_TOKEN")
fi
if [[ -n "$HA_DASHBOARD" ]]; then
    LAUNCH_ARGS+=(-HADashboard "$HA_DASHBOARD")
else
    LAUNCH_ARGS+=(-HADashboard "")
fi
if [[ -n "$KIOSK_MODE" ]]; then
    LAUNCH_ARGS+=(-HAKioskMode "$KIOSK_MODE")
fi
if [[ -n "$DEMO_MODE" ]]; then
    LAUNCH_ARGS+=(-HADemoMode "$DEMO_MODE")
fi

# ── Deploy + Launch ─────────────────────────────────────────────────────
case "$TARGET" in
    sim|sim-iphone)
        if [[ "$TARGET" == "sim-iphone" ]]; then
            SIM_UDID="$SIM_IPHONE_UDID"
            SIM_NAME="$SIM_IPHONE_NAME"
        else
            SIM_UDID="$SIM_IPAD_UDID"
            SIM_NAME="$SIM_IPAD_NAME"
        fi

        # Look up simulator UDID by name if not explicitly set
        if [[ -z "$SIM_UDID" ]]; then
            export DEVELOPER_DIR="$XCODE26/Contents/Developer"
            SIM_UDID=$(xcrun simctl list devices available -j 2>/dev/null | \
                python3 -c "import sys,json; devs=[d for rt in json.load(sys.stdin)['devices'].values() for d in rt if d['name']=='$SIM_NAME' and d['isAvailable']]; print(devs[0]['udid'] if devs else '')" 2>/dev/null || true)
            if [[ -z "$SIM_UDID" ]]; then
                echo "❌ Simulator '$SIM_NAME' not found. Set SIM_IPAD_UDID or SIM_IPHONE_UDID in .env"
                exit 1
            fi
        fi

        echo "📱 Deploying to simulator: $SIM_NAME ($SIM_UDID)"
        export DEVELOPER_DIR="$XCODE26/Contents/Developer"

        BOOT_STATE=$(xcrun simctl list devices | grep "$SIM_UDID" | grep -o '(Booted)\|(Shutdown)' | tr -d '()')
        if [[ "$BOOT_STATE" != "Booted" ]]; then
            echo "   Booting simulator..."
            xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
            open -a Simulator
            sleep 3
        fi

        echo "   Installing..."
        xcrun simctl install "$SIM_UDID" "$APP"

        echo "   Launching with dashboard: ${HA_DASHBOARD:-default}..."
        xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
        xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" "${LAUNCH_ARGS[@]}"

        echo "✅ Running on $SIM_NAME"
        ;;

    sim-ios93|sim-ios103)
        # Legacy iOS simulator via RosettaSim (x86_64)
        RSCTL="$HOME/Projects/rosetta/src/build/rosettasim-ctl"

        if [[ "$TARGET" == "sim-ios93" ]]; then
            LEGACY_UDID="$SIM_IOS93_UDID"
            LEGACY_LABEL="iOS 9.3"
        else
            LEGACY_UDID="$SIM_IOS103_UDID"
            LEGACY_LABEL="iOS 10.3"
        fi

        if [[ ! -x "$RSCTL" ]]; then
            echo "❌ rosettasim-ctl not found at $RSCTL"
            exit 1
        fi

        echo "📱 Deploying to $LEGACY_LABEL simulator ($LEGACY_UDID)"

        # Boot if needed
        BOOT_STATE=$("$RSCTL" list 2>/dev/null | grep "$LEGACY_UDID" | grep -o "Booted\|Shutdown" || echo "Unknown")
        if [[ "$BOOT_STATE" != "Booted" ]]; then
            echo "   Booting..."
            "$RSCTL" boot "$LEGACY_UDID"
            open -a Simulator
            sleep 5
        fi

        echo "   Installing..."
        "$RSCTL" terminate "$LEGACY_UDID" "$BUNDLE_ID" 2>/dev/null || true
        "$RSCTL" install "$LEGACY_UDID" "$APP" 2>&1 | tail -1

        # Write credentials to the app's NSUserDefaults plist on disk
        # (rosettasim-ctl launch doesn't support launch args)
        DEVICE_DIR="$HOME/Library/Developer/CoreSimulator/Devices/$LEGACY_UDID"
        DATA_CONTAINER=$("$RSCTL" appinfo "$LEGACY_UDID" "$BUNDLE_ID" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('dataContainer',''))" 2>/dev/null || true)
        if [[ -n "$DATA_CONTAINER" ]]; then
            PREFS_DIR="$DATA_CONTAINER/Library/Preferences"
        else
            PREFS_DIR=$(find "$DEVICE_DIR/data/Containers/Data/Application" -name "$BUNDLE_ID.plist" -path "*/Preferences/*" -exec dirname {} \; 2>/dev/null | head -1)
            if [[ -z "$PREFS_DIR" ]]; then
                LATEST_CONTAINER=$(ls -td "$DEVICE_DIR/data/Containers/Data/Application/"*/ 2>/dev/null | head -1)
                if [[ -n "$LATEST_CONTAINER" ]]; then
                    PREFS_DIR="$LATEST_CONTAINER/Library/Preferences"
                    mkdir -p "$PREFS_DIR"
                fi
            fi
        fi

        if [[ -n "$PREFS_DIR" ]]; then
            echo "   Writing preferences..."
            PLIST="$PREFS_DIR/$BUNDLE_ID.plist"
            defaults write "$PLIST" HAServerURL -string "$HA_SERVER"
            defaults write "$PLIST" HAAccessToken -string "${TOKEN_OVERRIDE:-$HA_TOKEN}"
            defaults write "$PLIST" HADashboard -string "$HA_DASHBOARD"
            [[ -n "$KIOSK_MODE" ]] && defaults write "$PLIST" HAKioskMode -bool "$([ "$KIOSK_MODE" = "YES" ] && echo true || echo false)"
            [[ -n "$DEMO_MODE" ]] && defaults write "$PLIST" HADemoMode -bool true
            [[ "$RESET_MODE" == true ]] && defaults write "$PLIST" HAClearCredentials -bool true
        else
            echo "   ⚠️  Could not find preferences directory — app will use cached credentials"
        fi

        echo "   Launching..."
        "$RSCTL" launch "$LEGACY_UDID" "$BUNDLE_ID" 2>&1 | tail -1

        echo "✅ Running on $LEGACY_LABEL simulator"
        ;;

    iphone)
        echo "📱 Deploying to iPhone..."
        export DEVELOPER_DIR="$XCODE26/Contents/Developer"

        echo "   Installing..."
        xcrun devicectl device install app \
            --device "$IPHONE_DEVICECTL_ID" \
            "$APP" 2>&1 | tail -3

        echo "   Launching with dashboard: ${HA_DASHBOARD:-default}..."
        xcrun devicectl device process launch \
            --device "$IPHONE_DEVICECTL_ID" \
            --terminate-existing \
            -- "$BUNDLE_ID" \
            "${LAUNCH_ARGS[@]}" 2>&1 | tail -3

        echo "✅ Running on iPhone"
        ;;

    mini5)
        echo "📱 Deploying to iPad Mini 5 (WiFi via devicectl)..."
        export DEVELOPER_DIR="$XCODE26/Contents/Developer"

        echo "   Installing..."
        xcrun devicectl device install app \
            --device "$IPAD_MINI5_DEVICECTL_ID" \
            "$APP" 2>&1 | tail -3

        echo "   Launching with dashboard: ${HA_DASHBOARD:-default}..."
        xcrun devicectl device process launch \
            --device "$IPAD_MINI5_DEVICECTL_ID" \
            --terminate-existing \
            -- "$BUNDLE_ID" \
            "${LAUNCH_ARGS[@]}" 2>&1 | tail -3

        echo "✅ Running on iPad Mini 5"
        ;;

    mini4)
        if ! command -v ios-deploy &>/dev/null; then
            echo "❌ ios-deploy not found. Install: brew install ios-deploy"
            exit 1
        fi

        echo "📱 Deploying to iPad Mini 4 (ios-deploy + pymobiledevice3)..."
        export DEVELOPER_DIR="$XCODE26/Contents/Developer"

        echo "   Installing..."
        ios-deploy --bundle "$APP" --id "$IPAD_MINI4_UDID" --nostart 2>&1 | tail -5

        # Launch via pymobiledevice3 DVT (bypasses debugserver breakpoint issue)
        if command -v pymobiledevice3 &>/dev/null; then
            echo "   Launching with dashboard: ${HA_DASHBOARD:-default}..."
            pymobiledevice3 developer dvt launch --kill-existing \
                --udid "$IPAD_MINI4_UDID" \
                "$BUNDLE_ID ${LAUNCH_ARGS[*]}" 2>&1
            echo "✅ Running on iPad Mini 4"
        else
            echo "⚠️  pymobiledevice3 not found — install with: pip install pymobiledevice3"
            echo "✅ Installed on iPad Mini 4 (tap app icon to launch)"
        fi
        ;;

    ipad2)
        echo "📱 Deploying to iPad 2 via WiFi SSH ($IPAD2_IP)..."

        if [[ -z "$IPAD2_IP" ]]; then
            echo "❌ IPAD2_IP not set in .env"
            exit 1
        fi

        IPAD_SSH="sshpass -p ${IPAD2_SSH_PASS} ssh -o StrictHostKeyChecking=no -o HostkeyAlgorithms=ssh-rsa root@${IPAD2_IP}"
        IPAD_SCP="sshpass -p ${IPAD2_SSH_PASS} scp -o StrictHostKeyChecking=no -o HostkeyAlgorithms=ssh-rsa"

        # Verify iPad is reachable
        if ! $IPAD_SSH "echo ok" &>/dev/null; then
            echo "❌ Cannot SSH to iPad at $IPAD2_IP"
            echo "   Ensure iPad is jailbroken, OpenSSH is installed, and WiFi is connected"
            exit 1
        fi

        # Tar the .app preserving structure (scp -r doesn't handle symlinks well)
        APP_TAR="$PROJECT_DIR/build/HADashboard.app.tar.gz"
        echo "   Packaging .app..."
        tar -czf "$APP_TAR" -C "$(dirname "$APP")" "$(basename "$APP")"

        # Generate preferences plist locally (avoids nested quoting issues in SSH)
        IPAD2_PLIST="$PROJECT_DIR/build/ipad2-prefs.plist"
        IPAD2_KIOSK_BOOL=$([ "$KIOSK_MODE" = "YES" ] && echo "true" || echo "false")
        cat > "$IPAD2_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
$(if [ "$RESET_MODE" = "true" ]; then
    echo "    <key>HAClearCredentials</key>"
    echo "    <true/>"
else
    echo "    <key>HAServerURL</key>"
    echo "    <string>${HA_SERVER}</string>"
    echo "    <key>HAAccessToken</key>"
    echo "    <string>${EFFECTIVE_TOKEN}</string>"
fi)
    <key>HADashboard</key>
    <string>${HA_DASHBOARD}</string>
    <key>HAKioskMode</key>
    <${IPAD2_KIOSK_BOOL}/>
$([ -n "$DEMO_MODE" ] && echo "    <key>HADemoMode</key>" && echo "    <true/>")
</dict>
</plist>
EOF

        # Transfer to iPad
        echo "   Transferring to iPad ($IPAD2_IP)..."
        $IPAD_SCP "$APP_TAR" "root@${IPAD2_IP}:/tmp/HADashboard.app.tar.gz"
        $IPAD_SCP "$IPAD2_PLIST" "root@${IPAD2_IP}:/tmp/ha-prefs.plist"

        # Install: extract to /Applications, refresh SpringBoard, write prefs, launch
        echo "   Installing..."
        $IPAD_SSH "
            # Extract app to /Applications
            cd /Applications
            rm -rf 'HA Dashboard.app'
            tar xzf /tmp/HADashboard.app.tar.gz
            rm /tmp/HADashboard.app.tar.gz

            # Re-sign with ldid (jailbreak code signing)
            which ldid >/dev/null 2>&1 && ldid -S 'HA Dashboard.app/HA Dashboard'

            # Kill the app if running (ensures NSUserDefaults cache is flushed)
            killall 'HA Dashboard' 2>/dev/null || true

            # Refresh SpringBoard app cache
            uicache

            # Move preferences plist into place (transferred via SCP)
            # Delete old plist first to avoid stale keys (e.g. HAClearCredentials)
            PREFS_DIR=/var/mobile/Library/Preferences
            mkdir -p \$PREFS_DIR
            rm -f \$PREFS_DIR/$BUNDLE_ID.plist
            mv /tmp/ha-prefs.plist \$PREFS_DIR/$BUNDLE_ID.plist
            chmod 644 \$PREFS_DIR/$BUNDLE_ID.plist
            chown mobile:mobile \$PREFS_DIR/$BUNDLE_ID.plist

            # Flush the preferences daemon cache so NSUserDefaults reads the new plist
            killall cfprefsd 2>/dev/null || true

            # Clear any previous startup log
            rm -f /tmp/ha-launch.log

            # Give SpringBoard time to finish processing uicache
            sleep 2

            # Launch the app
            open $BUNDLE_ID
        "

        # Wait for app to start (or crash) then fetch startup log
        echo "   Waiting for startup log..."
        sleep 8
        echo ""
        echo "── /tmp/ha-launch.log ──────────────────────────────────"
        $IPAD_SSH "cat /tmp/ha-launch.log 2>/dev/null || echo '(no log file found)'"
        echo "────────────────────────────────────────────────────────"
        echo ""
        echo "✅ Deployed to iPad 2 (WiFi)"
        ;;

    mac)
        echo "🖥  Deploying to Mac (Catalyst)..."

        # Write launch args to NSUserDefaults for the app's bundle ID
        if [[ "$RESET_MODE" == true ]]; then
            defaults write "$BUNDLE_ID" HAClearCredentials -bool true
        else
            EFFECTIVE_TOKEN="${TOKEN_OVERRIDE:-$HA_TOKEN}"
            defaults write "$BUNDLE_ID" HAServerURL -string "$HA_SERVER"
            defaults write "$BUNDLE_ID" HAAccessToken -string "$EFFECTIVE_TOKEN"
        fi
        defaults write "$BUNDLE_ID" HADashboard -string "$HA_DASHBOARD"
        [[ -n "$KIOSK_MODE" ]] && defaults write "$BUNDLE_ID" HAKioskMode -bool "$([ "$KIOSK_MODE" = "YES" ] && echo true || echo false)"
        [[ -n "$DEMO_MODE" ]] && defaults write "$BUNDLE_ID" HADemoMode -bool true

        # Kill existing instance if running
        killall "HA Dashboard" 2>/dev/null || true
        sleep 0.5

        echo "   Launching with dashboard: ${HA_DASHBOARD:-default}..."
        open "$APP"

        echo "✅ Running on Mac"
        ;;

    ipad2-usb)
        echo "📱 Deploying to iPad 2 via Unraid USB ($UNRAID_HOST)..."

        if [[ -z "$UNRAID_HOST" ]]; then
            echo "❌ UNRAID_HOST not set in .env"
            exit 1
        fi

        # Package as IPA
        IPA="$PROJECT_DIR/build/HADashboard.ipa"
        rm -rf /tmp/ipa_payload
        mkdir -p /tmp/ipa_payload/Payload
        cp -R "$APP" "/tmp/ipa_payload/Payload/"
        (cd /tmp/ipa_payload && zip -qr "$IPA" Payload/)
        echo "   Packaged IPA: $(du -sh "$IPA" | cut -f1)"

        # Transfer to Unraid
        echo "   Transferring to $UNRAID_HOST..."
        sshpass -p "${UNRAID_PASS:-}" scp -o StrictHostKeyChecking=no \
            -o PreferredAuthentications=password \
            "$IPA" "$UNRAID_USER@$UNRAID_HOST:/tmp/HADashboard.ipa"

        # Transfer developer disk image if not already on server
        DDI_DIR="/Applications/Xcode-13.2.1.app/Contents/Developer/Platforms/iPhoneOS.platform/DeviceSupport/9.3"
        sshpass -p "${UNRAID_PASS:-}" ssh -o StrictHostKeyChecking=no \
            -o PreferredAuthentications=password \
            "$UNRAID_USER@$UNRAID_HOST" 'test -f /tmp/ios-ddi/DeveloperDiskImage.dmg && echo EXISTS || echo MISSING' 2>/dev/null | grep -q EXISTS
        if [[ $? -ne 0 ]] && [[ -f "$DDI_DIR/DeveloperDiskImage.dmg" ]]; then
            echo "   Uploading developer disk image..."
            sshpass -p "${UNRAID_PASS:-}" ssh -o StrictHostKeyChecking=no \
                -o PreferredAuthentications=password \
                "$UNRAID_USER@$UNRAID_HOST" 'mkdir -p /tmp/ios-ddi'
            sshpass -p "${UNRAID_PASS:-}" scp -o StrictHostKeyChecking=no \
                -o PreferredAuthentications=password \
                "$DDI_DIR/DeveloperDiskImage.dmg" "$DDI_DIR/DeveloperDiskImage.dmg.signature" \
                "$UNRAID_USER@$UNRAID_HOST:/tmp/ios-ddi/"
        fi

        # Install via Docker + libimobiledevice
        echo "   Installing on iPad 2..."
        sshpass -p "${UNRAID_PASS:-}" ssh -o StrictHostKeyChecking=no \
            -o PreferredAuthentications=password \
            "$UNRAID_USER@$UNRAID_HOST" '
mkdir -p /tmp/ios-lockdown
docker run --rm --privileged \
  -v /dev/bus/usb:/dev/bus/usb \
  -v /tmp/HADashboard.ipa:/tmp/HADashboard.ipa \
  -v /tmp/ios-lockdown:/var/lib/lockdown \
  -v /tmp/ios-ddi:/tmp/ddi \
  ubuntu:22.04 bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update > /dev/null 2>&1
    apt-get install -y usbmuxd libimobiledevice-utils ideviceinstaller > /dev/null 2>&1
    usbmuxd -f &
    sleep 3
    UDID=\$(idevice_id -l 2>/dev/null | head -1)
    if [ -z \"\$UDID\" ]; then
      echo \"❌ No iOS device found on USB\"
      exit 1
    fi
    echo \"   Device: \$UDID\"

    # Ensure device is paired
    if ! idevicepair validate 2>/dev/null; then
      echo \"   Pairing (tap Trust on iPad if prompted)...\"
      idevicepair pair 2>&1 || true
      sleep 5
      idevicepair validate 2>/dev/null || echo \"⚠️  Not paired — tap Trust on iPad, then retry\"
    fi

    # Install app
    ideviceinstaller -i /tmp/HADashboard.ipa 2>&1 | grep -E \"(Install:|ERROR|DONE|Copying)\"

    # Mount developer disk image if available
    if [ -f /tmp/ddi/DeveloperDiskImage.dmg ]; then
      if ! ideviceimagemounter -l 2>&1 | grep -q \"ImagePresent: true\"; then
        echo \"   Mounting developer disk image...\"
        ideviceimagemounter /tmp/ddi/DeveloperDiskImage.dmg /tmp/ddi/DeveloperDiskImage.dmg.signature 2>&1
      fi
    else
      echo \"   ⚠️  No developer disk image at /tmp/ddi/\"
    fi

    # Launch the app with credentials and dashboard args
    echo \"   Launch args: '"${LAUNCH_ARGS[*]}"'\"
    idevicedebug run '"$BUNDLE_ID"' '"${LAUNCH_ARGS[*]}"' 2>&1 &
    DBGPID=\\\$!
    sleep 5
    kill \\\$DBGPID 2>/dev/null || true
  "
'

        echo "✅ Deployed to iPad 2 (USB)"
        ;;
esac
