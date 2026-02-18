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
#
# Options:
#   --no-build    Skip build, deploy existing .app
#   --dashboard X Override dashboard (default: living-room)
#   --default     Use default (overview) dashboard instead of living-room
#   --server URL  Override HA server URL
#   --kiosk       Start in kiosk mode
#   --no-kiosk    Disable kiosk mode

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
SIM_IPAD_NAME="${SIM_IPAD_NAME:-iPad (10th generation)}"
SIM_IPHONE_NAME="${SIM_IPHONE_NAME:-iPhone 15 Pro}"
SIM_IPAD_UDID="${SIM_IPAD_UDID:-}"
SIM_IPHONE_UDID="${SIM_IPHONE_UDID:-}"

# ── Xcode path (for devicectl/simctl commands) ────────────────────────
XCODE26="/Applications/Xcode.app"

# ── Parse arguments ─────────────────────────────────────────────────────
TARGET=""
NO_BUILD=false
KIOSK_MODE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        sim|iphone|mini5|mini4|ipad2|ipad2-usb|all)
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
        --dashboard)  HA_DASHBOARD="$2"; shift 2 ;;
        --default)    HA_DASHBOARD=""; shift ;;
        --kiosk)      KIOSK_MODE="YES"; shift ;;
        --no-kiosk)   KIOSK_MODE="NO"; shift ;;
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
    echo "  iphone         Physical iPhone (via devicectl)"
    echo "  mini5          iPad Mini 5 — iPadOS 26 (devicectl, WiFi)"
    echo "  mini4          iPad Mini 4 — iPadOS 15 (ios-deploy, WiFi)"
    echo "  ipad2          iPad 2 — iOS 9 (WiFi SSH, jailbroken)"
    echo "  ipad2-usb      iPad 2 — iOS 9 (Unraid USB fallback)"
    echo ""
    echo "Options:"
    echo "  --no-build     Skip build step"
    echo "  --server URL   Override HA server URL"
    echo "  --dashboard X  Set dashboard path (default: living-room)"
    echo "  --default      Use default overview dashboard"
    echo "  --kiosk        Start in kiosk mode (hides nav, disables sleep)"
    echo "  --no-kiosk     Disable kiosk mode"
    echo ""
    echo "Secrets are loaded from .env in project root."
    exit 1
fi

# ── "all" target: build once, deploy to every target ─────────────────
if [[ "$TARGET" == "all" ]]; then
    # Collect pass-through options (exclude target and --no-build)
    OPTS=()
    [[ -n "$KIOSK_MODE" ]] && OPTS+=($([ "$KIOSK_MODE" == "YES" ] && echo "--kiosk" || echo "--no-kiosk"))

    echo "🚀 Deploying to ALL targets..."
    echo ""

    # Deploy to each target; continue on failure so one target doesn't block the rest
    # Build order: sim first, then universal once for all physical devices
    FAILURES=()
    for DEPLOY_TARGET in "sim" "sim iphone --no-build" "iphone" "mini5 --no-build" "mini4 --no-build" "ipad2 --no-build"; do
        # shellcheck disable=SC2086
        "$0" $DEPLOY_TARGET ${OPTS[@]+"${OPTS[@]}"} 2>&1 || FAILURES+=("${DEPLOY_TARGET%% *}")
        echo ""
    done

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
    iphone|mini5|mini4|ipad2|ipad2-usb)
        if [[ "$NO_BUILD" == false ]]; then
            APP="$("$PROJECT_DIR/scripts/build.sh" device)"
        else
            APP="$PROJECT_DIR/build/universal/HA Dashboard.app"
        fi
        ;;
esac

if [ ! -d "$APP" ]; then
    echo "❌ Build failed — app not found at $APP"
    exit 1
fi
if [[ "$NO_BUILD" == false ]]; then
    echo "✅ Build succeeded: $(du -sh "$APP" | cut -f1) — $(lipo -archs "$APP/HA Dashboard" 2>/dev/null || echo "unknown")"
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
LAUNCH_ARGS=(-HAServerURL "$HA_SERVER" -HAAccessToken "$HA_TOKEN")
if [[ -n "$HA_DASHBOARD" ]]; then
    LAUNCH_ARGS+=(-HADashboard "$HA_DASHBOARD")
else
    LAUNCH_ARGS+=(-HADashboard "")
fi
if [[ -n "$KIOSK_MODE" ]]; then
    LAUNCH_ARGS+=(-HAKioskMode "$KIOSK_MODE")
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

        # Transfer to iPad
        echo "   Transferring to iPad ($IPAD2_IP)..."
        $IPAD_SCP "$APP_TAR" "root@${IPAD2_IP}:/tmp/HADashboard.app.tar.gz"

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

            # Refresh SpringBoard app cache
            uicache

            # Write preferences (NSUserDefaults reads from this plist)
            PREFS_DIR=/var/mobile/Library/Preferences
            PREFS=\$PREFS_DIR/$BUNDLE_ID.plist
            mkdir -p \$PREFS_DIR

            # Build plist manually (defaults command not available on minimal iOS 9)
            cat > \$PREFS <<PLISTEOF
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
    <key>HAServerURL</key>
    <string>$HA_SERVER</string>
    <key>HAAccessToken</key>
    <string>$HA_TOKEN</string>
    <key>HADashboard</key>
    <string>$HA_DASHBOARD</string>
    <key>HAKioskMode</key>
    <$([ \"$KIOSK_MODE\" = \"YES\" ] && echo true || echo false)/>
</dict>
</plist>
PLISTEOF
            chmod 644 \$PREFS
            chown mobile:mobile \$PREFS

            # Launch the app
            open $BUNDLE_ID
        "

        echo "✅ Deployed to iPad 2 (WiFi)"
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
