#!/bin/bash
set -euo pipefail

# HA Dashboard — Build, Deploy & Launch
# Usage:
#   scripts/deploy.sh sim          # Build + run in iPad 10th gen simulator
#   scripts/deploy.sh sim iphone   # Build + run in iPhone 15 Pro simulator
#   scripts/deploy.sh iphone       # Build + deploy + launch on physical iPhone
#   scripts/deploy.sh mini5        # Build + deploy to iPad Mini 5 (CoreDevice/MobileDevice WiFi)
#   scripts/deploy.sh mini4        # Build + deploy to iPad Mini 4 (MobileDevice WiFi)
#   scripts/deploy.sh ipadpro      # Build + deploy + launch on physical iPad Pro
#   scripts/deploy.sh ipad2        # Build + deploy to iPad 2 via WiFi SSH (jailbroken)
#   scripts/deploy.sh ipad3        # Build + deploy to iPad 3 via WiFi SSH (jailbroken)
#   scripts/deploy.sh mac          # Build + launch Mac Catalyst app locally
#
# Options:
#   --no-build    Skip build step
#   --dry-run     Resolve configuration and targets without building or deploying
#   --dashboard X Override dashboard (default: living-room)
#   --default     Use default (overview) dashboard instead of living-room
#   --server URL  Override HA server URL
#   --token-file X Read an access-token override from X without putting it in argv
#   --kiosk       Start in kiosk mode
#   --no-kiosk    Disable kiosk mode
#   --reset       Clear credentials and start at login screen
#   --demo        Start in demo mode (no server needed)

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="${BUNDLE_ID:-com.hadashboard.app}"
_SENSITIVE_PREFS_FILE=""
_CLEANUP_DIRS=()

cleanup_sensitive_files() {
    if [[ -n "$_SENSITIVE_PREFS_FILE" && -f "$_SENSITIVE_PREFS_FILE" ]]; then
        rm -f "$_SENSITIVE_PREFS_FILE"
    fi
    local cleanup_dir
    for cleanup_dir in ${_CLEANUP_DIRS[@]+"${_CLEANUP_DIRS[@]}"}; do
        case "$cleanup_dir" in
            "$PROJECT_DIR"/build/*.deploy.*|/tmp/hadashboard-*)
                [[ -d "$cleanup_dir" ]] && rm -rf "$cleanup_dir"
                ;;
        esac
    done
}
trap cleanup_sensitive_files EXIT

# ── Load secrets from .env ────────────────────────────────────────────
ENV_FILE="$PROJECT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    # A linked worktree's common Git directory belongs to the main checkout.
    # Reuse its ignored .env without copying or printing any secret values.
    GIT_COMMON_DIR=$(git -C "$PROJECT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    if [[ -n "$GIT_COMMON_DIR" && "$(basename "$GIT_COMMON_DIR")" == ".git" ]]; then
        COMMON_CHECKOUT_ENV="$(dirname "$GIT_COMMON_DIR")/.env"
        if [[ -f "$COMMON_CHECKOUT_ENV" ]]; then
            ENV_FILE="$COMMON_CHECKOUT_ENV"
        fi
    fi
fi
if [[ -f "$ENV_FILE" ]]; then
    # Do not export the complete secret file into every build/install process.
    # Fleet children source the same file independently.
    source "$ENV_FILE"
fi

# ── Defaults (overridden by .env) ─────────────────────────────────────
HA_SERVER="${HA_SERVER:-}"
HA_TOKEN="${HA_TOKEN:-}"
ENV_HA_TOKEN="$HA_TOKEN"
unset HA_TOKEN
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
IPAD_PRO_DEVICECTL_ID="${IPAD_PRO_DEVICECTL_ID:-}"
IPAD2_UDID="${IPAD2_UDID:-}"
IPAD2_IP="${IPAD2_IP:-}"
IPAD2_SSH_PASS="${IPAD2_SSH_PASS:-alpine}"
IPAD3_UDID="${IPAD3_UDID:-}"
IPAD3_IP="${IPAD3_IP:-}"
IPAD3_SSH_PASS="${IPAD3_SSH_PASS:-alpine}"
IPAD4_UDID="${IPAD4_UDID:-}"
IPAD4_IP="${IPAD4_IP:-}"
IPAD4_SSH_PASS="${IPAD4_SSH_PASS:-alpine}"
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
XCODE26="${XCODE_PATH:-/Applications/Xcode.app}"
if [[ ! -d "$XCODE26" && -d "/Applications/Xcode-beta.app" ]]; then
    XCODE26="/Applications/Xcode-beta.app"
fi

# ── Parse arguments ─────────────────────────────────────────────────────
TARGET=""
NO_BUILD=false
DRY_RUN=false
KIOSK_MODE=""
RESET_MODE=false
DEMO_MODE=""
TOKEN_OVERRIDE=""
TOKEN_FILE=""
SERVER_OVERRIDE_SET=false
DASHBOARD_OVERRIDE_SET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        sim|sim-ios93|sim-ios103|iphone|mini5|mini4|ipadpro|ipad-pro|ipad2|ipad2-usb|ipad3|ipad4|ipad4-usb|mac|all)
            if [[ -z "$TARGET" ]]; then
                TARGET="$1"
            else
                if [[ "$TARGET" == "sim" && "$1" == "iphone" ]]; then
                    TARGET="sim-iphone"
                fi
            fi
            shift ;;
        --no-build)   NO_BUILD=true; shift ;;
        --dry-run)    DRY_RUN=true; shift ;;
        --server)     HA_SERVER="$2"; SERVER_OVERRIDE_SET=true; shift 2 ;;
        --token)
            echo "❌ --token is intentionally unsupported because it exposes the HA token in process arguments"
            echo "   Put HA_TOKEN in .env or use --token-file PATH"
            exit 1 ;;
        --token-file) TOKEN_FILE="$2"; shift 2 ;;
        --dashboard)  HA_DASHBOARD="$2"; DASHBOARD_OVERRIDE_SET=true; shift 2 ;;
        --default)    HA_DASHBOARD=""; DASHBOARD_OVERRIDE_SET=true; shift ;;
        --kiosk)      KIOSK_MODE="YES"; shift ;;
        --no-kiosk)   KIOSK_MODE="NO"; shift ;;
        --reset)      RESET_MODE=true; shift ;;
        --demo)       DEMO_MODE="YES"; shift ;;
        *)            echo "❌ Unknown argument: $1"; exit 1 ;;
    esac
done

[[ "$TARGET" == "ipad-pro" ]] && TARGET="ipadpro"

if [[ -n "$TOKEN_FILE" ]]; then
    if [[ ! -f "$TOKEN_FILE" ]]; then
        echo "❌ Token file not found: $TOKEN_FILE"
        exit 1
    fi
    IFS= read -r TOKEN_OVERRIDE < "$TOKEN_FILE" || true
elif [[ -n "${HADASHBOARD_TOKEN_OVERRIDE:-}" ]]; then
    TOKEN_OVERRIDE="$HADASHBOARD_TOKEN_OVERRIDE"
fi
unset HADASHBOARD_TOKEN_OVERRIDE 2>/dev/null || true

if [[ -z "$TARGET" ]]; then
    echo "Usage: scripts/deploy.sh <all|sim|sim-ios93|sim-ios103|iphone|mini5|mini4|ipadpro|ipad2|ipad3|ipad4|mac> [options]"
    echo ""
    echo "Targets:"
    echo "  all            Deploy to all targets (builds once, deploys everywhere)"
    echo "  sim            iPad simulator (iPad 10th gen)"
    echo "  sim iphone     iPhone simulator (iPhone 15 Pro)"
    echo "  sim-ios93      iOS 9.3 iPad Pro simulator (RosettaSim, x86_64)"
    echo "  sim-ios103     iOS 10.3 iPad Pro 10.5\" simulator (RosettaSim, x86_64)"
    echo "  iphone         Physical iPhone (via devicectl)"
    echo "  mini5          iPad Mini 5 — iPadOS 26 (CoreDevice/MobileDevice WiFi)"
    echo "  mini4          iPad Mini 4 — iPadOS 15 (WiFi, ideviceinstaller)"
    echo "  ipadpro        Physical iPad Pro (configured ID or one reachable physical iPad Pro)"
    echo "  ipad2          iPad 2 — iOS 9 (WiFi SSH, jailbroken)"
    echo "  ipad2-usb      iPad 2 — iOS 9 (Unraid USB fallback)"
    echo "  ipad3          iPad 3 — (WiFi SSH, jailbroken)"
    echo "  ipad4          iPad 4 — iOS 10 (WiFi SSH, jailbroken)"
    echo "  ipad4-usb      iPad 4 — iOS 10 (Unraid USB, signed)"
    echo "  mac            Mac Catalyst (local Mac, fullscreen)"
    echo ""
    echo "Options:"
    echo "  --no-build     Skip build step"
    echo "  --dry-run      Resolve fleet/configuration only; no build, install, or launch"
    echo "  --server URL   Override HA server URL"
    echo "  --token-file X Read access-token override from X (never forwarded in argv)"
    echo "  --dashboard X  Set dashboard path (default: living-room)"
    echo "  --default      Use default overview dashboard"
    echo "  --kiosk        Start in kiosk mode (hides nav, disables sleep)"
    echo "  --no-kiosk     Disable kiosk mode"
    echo "  --reset        Clear credentials, start at login screen"
    echo "  --demo         Start in demo mode (no server needed)"
    echo ""
    echo "Secrets are loaded from the worktree .env, or the main checkout .env when absent."
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

resolve_ipad_pro_id() {
    if [[ -n "$IPAD_PRO_DEVICECTL_ID" ]]; then
        printf '%s\n' "$IPAD_PRO_DEVICECTL_ID"
        return 0
    fi

    if [[ ! -d "$XCODE26" ]]; then
        return 1
    fi

    local device_line
    local candidate
    local candidates=()
    while IFS= read -r device_line; do
        candidate=$(printf '%s\n' "$device_line" | awk '{
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/) {
                    print $i
                    exit
                }
            }
        }')
        [[ -n "$candidate" ]] && candidates+=("$candidate")
    done < <(
        DEVELOPER_DIR="$XCODE26/Contents/Developer" xcrun devicectl list devices 2>/dev/null |
            awk '/iPad Pro/ && /physical/'
    )

    if [[ ${#candidates[@]} -eq 1 ]]; then
        printf '%s\n' "${candidates[0]}"
        return 0
    fi
    if [[ ${#candidates[@]} -gt 1 ]]; then
        echo "❌ More than one physical iPad Pro is visible; set IPAD_PRO_DEVICECTL_ID" >&2
    fi
    return 1
}

resolve_coredevice_hardware_udid() {
    local coredevice_id="$1"
    local details_dir
    local details_json
    COREDEVICE_HARDWARE_UDID=""
    [[ -n "$coredevice_id" && -d "$XCODE26" ]] || return 1

    details_dir=$(mktemp -d /tmp/hadashboard-coredevice-details.XXXXXX)
    _CLEANUP_DIRS+=("$details_dir")
    details_json="$details_dir/device.json"
    if ! DEVELOPER_DIR="$XCODE26/Contents/Developer" \
        xcrun devicectl device info details \
            --device "$coredevice_id" \
            --json-output "$details_json" >/dev/null 2>&1; then
        return 1
    fi
    COREDEVICE_HARDWARE_UDID=$(plutil -extract result.properties.hardware.udid raw "$details_json" 2>/dev/null || true)
    [[ -n "$COREDEVICE_HARDWARE_UDID" ]]
}

artifact_sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

verify_profile_contains_udids() {
    local app="$1"
    shift
    local profile="$app/embedded.mobileprovision"
    local profile_dir
    local profile_plist
    local provisioned_devices
    local required_udid

    if [[ ! -f "$profile" ]]; then
        echo "❌ Universal app has no embedded development provisioning profile"
        return 1
    fi
    profile_dir=$(mktemp -d /tmp/hadashboard-profile-check.XXXXXX)
    _CLEANUP_DIRS+=("$profile_dir")
    profile_plist="$profile_dir/profile.plist"
    if ! security cms -D -i "$profile" > "$profile_plist" 2>/dev/null; then
        echo "❌ Could not decode the universal app's provisioning profile"
        return 1
    fi
    provisioned_devices=$(plutil -extract ProvisionedDevices json -o - "$profile_plist" 2>/dev/null || true)
    if [[ -z "$provisioned_devices" ]]; then
        echo "❌ Embedded profile is not a device development profile"
        return 1
    fi
    for required_udid in "$@"; do
        if ! printf '%s\n' "$provisioned_devices" | grep -Fiq "\"$required_udid\""; then
            echo "❌ Embedded profile excludes a required fleet device"
            return 1
        fi
    done
}

collect_fleet_targets() {
    # `all` is the active six-target product fleet. Older iPad 2/3 endpoints
    # remain explicit targets so stale-but-configured hosts cannot sink every
    # current fleet deployment.
    FLEET_TARGETS=(iphone mini5 mini4 ipad4)

    IPAD_PRO_DEVICECTL_ID=$(resolve_ipad_pro_id || true)
    if [[ -n "$IPAD_PRO_DEVICECTL_ID" ]]; then
        FLEET_TARGETS+=(ipadpro)
    fi
    FLEET_TARGETS+=(mac)
}

if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run only — no build, install, launch, or remote connection will run."
    echo "Environment: $ENV_FILE"
    if [[ "$TARGET" == "all" ]]; then
        collect_fleet_targets
        echo "Fleet targets: ${FLEET_TARGETS[*]}"
        [[ -n "$IPHONE_DEVICECTL_ID" ]] && echo "  iPhone: configured" || echo "  iPhone: missing IPHONE_DEVICECTL_ID"
        if [[ -n "$IPAD_MINI5_DEVICECTL_ID" || -n "$IPAD_MINI5_UDID" ]]; then
            echo "  iPad Mini 5: configured"
        else
            echo "  iPad Mini 5: missing CoreDevice ID and MobileDevice UDID"
        fi
        [[ -n "$IPAD_MINI4_UDID" ]] && echo "  iPad Mini 4: configured" || echo "  iPad Mini 4: missing IPAD_MINI4_UDID"
        [[ -n "$IPAD4_IP" ]] && echo "  iPad 4: configured" || echo "  iPad 4: missing IPAD4_IP"
        if [[ -n "$IPAD_PRO_DEVICECTL_ID" ]] && resolve_coredevice_hardware_udid "$IPAD_PRO_DEVICECTL_ID"; then
            echo "  iPad Pro: uniquely resolved with an Xcode signing UDID"
        else
            echo "  iPad Pro: unresolved, ambiguous, or missing its signing UDID"
        fi
        echo "  Mac Catalyst: local"
    else
        echo "Target: $TARGET"
    fi
    exit 0
fi

# ── "all" target: one fleet build, then per-target evidence ──────────
if [[ "$TARGET" == "all" ]]; then
    RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    EVIDENCE_DIR="$PROJECT_DIR/build/deploy-evidence/$RUN_ID"
    mkdir -p "$EVIDENCE_DIR"

    # Collect only non-secret pass-through options. A token-file override is
    # inherited through the environment and never copied into child argv.
    OPTS=()
    if [[ "$KIOSK_MODE" == "YES" ]]; then
        OPTS+=(--kiosk)
    elif [[ "$KIOSK_MODE" == "NO" ]]; then
        OPTS+=(--no-kiosk)
    fi
    [[ "$RESET_MODE" == true ]] && OPTS+=(--reset)
    [[ -n "$DEMO_MODE" ]] && OPTS+=(--demo)
    [[ "$SERVER_OVERRIDE_SET" == true ]] && OPTS+=(--server "$HA_SERVER")
    if [[ "$DASHBOARD_OVERRIDE_SET" == true ]]; then
        if [[ -n "$HA_DASHBOARD" ]]; then
            OPTS+=(--dashboard "$HA_DASHBOARD")
        else
            OPTS+=(--default)
        fi
    fi
    # Resolve every signed target before the expensive build. Xcode's
    # destination accepts the hardware UDID, not devicectl's CoreDevice UUID.
    collect_fleet_targets
    export IPAD_PRO_DEVICECTL_ID
    if [[ -z "$IPAD_PRO_DEVICECTL_ID" ]] || \
       ! resolve_coredevice_hardware_udid "$IPAD_PRO_DEVICECTL_ID"; then
        echo "❌ Fleet deployment requires one resolvable physical iPad Pro"
        echo "   Set IPAD_PRO_DEVICECTL_ID if more than one is visible"
        exit 1
    fi
    IPAD_PRO_SIGNING_UDID="$COREDEVICE_HARDWARE_UDID"

    IPHONE_PROFILE_UDID="$IPHONE_UDID"
    if [[ -z "$IPHONE_PROFILE_UDID" && -n "$IPHONE_DEVICECTL_ID" ]] && \
       resolve_coredevice_hardware_udid "$IPHONE_DEVICECTL_ID"; then
        IPHONE_PROFILE_UDID="$COREDEVICE_HARDWARE_UDID"
    fi
    MINI5_PROFILE_UDID="$IPAD_MINI5_UDID"
    if [[ -z "$MINI5_PROFILE_UDID" && -n "$IPAD_MINI5_DEVICECTL_ID" ]] && \
       resolve_coredevice_hardware_udid "$IPAD_MINI5_DEVICECTL_ID"; then
        MINI5_PROFILE_UDID="$COREDEVICE_HARDWARE_UDID"
    fi
    if [[ -z "$IPHONE_PROFILE_UDID" || -z "$MINI5_PROFILE_UDID" || \
          -z "$IPAD_MINI4_UDID" || -z "$IPAD4_UDID" ]]; then
        echo "❌ Fleet UDIDs are incomplete; configure iPhone, both Minis, and iPad 4"
        exit 1
    fi
    PROFILE_REQUIRED_UDIDS=(
        "$IPHONE_PROFILE_UDID"
        "$MINI5_PROFILE_UDID"
        "$IPAD_MINI4_UDID"
        "$IPAD4_UDID"
        "$IPAD_PRO_SIGNING_UDID"
    )

    echo "🚀 Deploying one exact build across the configured physical fleet..."
    echo "   Evidence: $EVIDENCE_DIR"
    echo ""

    # ── Phase 1: Build the two fleet artifacts once ──────────────────
    echo "── Phase 1: Building ──────────────────────────────────────"
    if [[ "$NO_BUILD" == false ]]; then
        echo "   Building device (universal armv7+arm64)..."
        DEVICE_APP=$(HADASHBOARD_FORCE_SIGNING_STYLE=automatic \
            HADASHBOARD_FORCE_SIGNING_DEVICE_ID="$IPAD_PRO_SIGNING_UDID" \
            "$PROJECT_DIR/scripts/build.sh" device 2> "$EVIDENCE_DIR/build-device.log")
        echo "   ✅ Device build complete"

        echo "   Building mac (Catalyst, arm64)..."
        MAC_APP=$("$PROJECT_DIR/scripts/build.sh" mac 2> "$EVIDENCE_DIR/build-mac.log")
        echo "   ✅ Mac Catalyst build complete"
    else
        DEVICE_APP="${HADASHBOARD_DEVICE_APP:-$PROJECT_DIR/build/universal/HA Dashboard.app}"
        MAC_APP="${HADASHBOARD_MAC_APP:-$PROJECT_DIR/build/mac/Build/Products/Debug-maccatalyst/HA Dashboard.app}"
        echo "   Reusing existing fleet artifacts (--no-build)"
    fi

    DEVICE_BINARY="$DEVICE_APP/HA Dashboard"
    MAC_BINARY="$MAC_APP/Contents/MacOS/HA Dashboard"
    if [[ ! -f "$DEVICE_BINARY" || ! -f "$MAC_BINARY" ]]; then
        echo "❌ One or more fleet artifacts are missing; see $EVIDENCE_DIR"
        exit 1
    fi
    if ! verify_profile_contains_udids "$DEVICE_APP" "${PROFILE_REQUIRED_UDIDS[@]}"; then
        echo "   No device deployment was attempted"
        exit 1
    fi
    echo "   ✅ Embedded profile covers every signed fleet target"
    HADASHBOARD_EXPECTED_DEVICE_SHA256=$(artifact_sha256 "$DEVICE_BINARY")
    HADASHBOARD_EXPECTED_MAC_SHA256=$(artifact_sha256 "$MAC_BINARY")
    export HADASHBOARD_DEVICE_APP="$DEVICE_APP"
    export HADASHBOARD_MAC_APP="$MAC_APP"
    export HADASHBOARD_EXPECTED_DEVICE_SHA256
    export HADASHBOARD_EXPECTED_MAC_SHA256

    {
        echo "run_id=$RUN_ID"
        echo "git_commit=$(git -C "$PROJECT_DIR" rev-parse HEAD)"
        echo "worktree_change_count=$(git -C "$PROJECT_DIR" status --porcelain | wc -l | tr -d ' ')"
        echo "device_app=$DEVICE_APP"
        echo "device_binary_sha256=$HADASHBOARD_EXPECTED_DEVICE_SHA256"
        echo "mac_app=$MAC_APP"
        echo "mac_binary_sha256=$HADASHBOARD_EXPECTED_MAC_SHA256"
        echo "profile_verified_device_count=${#PROFILE_REQUIRED_UDIDS[@]}"
        echo "targets=${FLEET_TARGETS[*]}"
    } > "$EVIDENCE_DIR/manifest.txt"
    echo ""

    # ── Phase 2: Deploy in parallel with retries ─────────────────────
    echo "── Phase 2: Deploying (parallel, up to 3 retries) ───────"
    PIDS=()
    LABELS=()

    deploy_bg() {
        local label="$1"; shift
        deploy_with_retry "$@" > "$EVIDENCE_DIR/$label.log" 2>&1 &
        PIDS+=($!)
        LABELS+=("$label")
    }

    if [[ -n "$TOKEN_OVERRIDE" ]]; then
        export HADASHBOARD_TOKEN_OVERRIDE="$TOKEN_OVERRIDE"
    fi
    for fleet_target in "${FLEET_TARGETS[@]}"; do
        deploy_bg "$fleet_target" "$fleet_target" --no-build ${OPTS[@]+"${OPTS[@]}"}
    done
    unset HADASHBOARD_TOKEN_OVERRIDE 2>/dev/null || true

    # Wait for all deploys and collect results
    FAILURES=()
    for i in "${!LABELS[@]}"; do
        if wait "${PIDS[$i]}"; then
            echo "   ✅ ${LABELS[$i]}"
            echo "${LABELS[$i]}=success" >> "$EVIDENCE_DIR/manifest.txt"
        else
            echo "   ❌ ${LABELS[$i]} (see log below)"
            FAILURES+=("${LABELS[$i]}")
            echo "${LABELS[$i]}=failed" >> "$EVIDENCE_DIR/manifest.txt"
        fi
    done

    # Print logs for failures
    for label in ${FAILURES[@]+"${FAILURES[@]}"}; do
        echo ""
        echo "── $label deploy log ──────────────────────────────────"
        cat "$EVIDENCE_DIR/$label.log"
        echo "────────────────────────────────────────────────────────"
    done

    echo ""
    if [[ ${#FAILURES[@]} -eq 0 ]]; then
        echo "✅ All configured targets deployed; evidence retained at $EVIDENCE_DIR"
    else
        echo "⚠️  Deployed with failures: ${FAILURES[*]+"${FAILURES[*]}"}"
        echo "   Evidence retained at $EVIDENCE_DIR"
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
    iphone|mini5|mini4|ipadpro|ipad2|ipad2-usb|ipad3|ipad4|ipad4-usb)
        if [[ "$NO_BUILD" == false ]]; then
            APP="$("$PROJECT_DIR/scripts/build.sh" device)"
        else
            APP="${HADASHBOARD_DEVICE_APP:-$PROJECT_DIR/build/universal/HA Dashboard.app}"
        fi
        ;;
    mac)
        if [[ "$NO_BUILD" == false ]]; then
            APP="$("$PROJECT_DIR/scripts/build.sh" mac)"
        else
            APP="${HADASHBOARD_MAC_APP:-$PROJECT_DIR/build/mac/Build/Products/Debug-maccatalyst/HA Dashboard.app}"
        fi
        ;;
esac

if [ ! -d "$APP" ]; then
    echo "❌ Build failed — app not found at $APP"
    exit 1
fi

# A fleet run exports the digest of each build it created. Every --no-build
# child verifies the same executable before installing or launching it.
if [[ "$TARGET" == "mac" ]]; then
    ARTIFACT_BINARY="$APP/Contents/MacOS/HA Dashboard"
    EXPECTED_ARTIFACT_SHA256="${HADASHBOARD_EXPECTED_MAC_SHA256:-}"
else
    ARTIFACT_BINARY="$APP/HA Dashboard"
    EXPECTED_ARTIFACT_SHA256="${HADASHBOARD_EXPECTED_DEVICE_SHA256:-}"
fi
if [[ -n "$EXPECTED_ARTIFACT_SHA256" ]]; then
    ACTUAL_ARTIFACT_SHA256=$(artifact_sha256 "$ARTIFACT_BINARY")
    if [[ "$ACTUAL_ARTIFACT_SHA256" != "$EXPECTED_ARTIFACT_SHA256" ]]; then
        echo "❌ Refusing deployment: the shared artifact changed after the fleet build"
        exit 1
    fi
    echo "✅ Exact fleet artifact verified: $ACTUAL_ARTIFACT_SHA256"
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
        ipad3)            HA_DASHBOARD="living-room"; KIOSK_MODE="${KIOSK_MODE:-YES}" ;;
        ipad4|ipad4-usb)   HA_DASHBOARD="living-room"; KIOSK_MODE="${KIOSK_MODE:-YES}" ;;
        # sim, sim-iphone, iphone: keep living-room
    esac
fi

# ── Launch args ─────────────────────────────────────────────────────────
# The Home Assistant token is deliberately never a process argument. Signed
# device and Catalyst upgrades retain their Keychain; writable legacy targets
# receive it through a protected plist written from stdin below.
EFFECTIVE_TOKEN="${TOKEN_OVERRIDE:-$ENV_HA_TOKEN}"
if [[ "$RESET_MODE" == true ]]; then
    LAUNCH_ARGS=(-HAClearCredentials YES)
else
    LAUNCH_ARGS=(-HAServerURL "$HA_SERVER")
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

USB_LAUNCH_ARGS=("${LAUNCH_ARGS[@]}")

write_ha_token_to_plist() {
    local plist_path="$1"
    if [[ -z "$EFFECTIVE_TOKEN" ]]; then
        return 0
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "❌ python3 is required to write HAAccessToken without exposing it in argv"
        return 1
    fi
    printf '%s' "$EFFECTIVE_TOKEN" | python3 -c '
import os
import plistlib
import sys

path = sys.argv[1]
try:
    with open(path, "rb") as source:
        values = plistlib.load(source)
except (FileNotFoundError, plistlib.InvalidFileException):
    values = {}
values["HAAccessToken"] = sys.stdin.read()
temporary = path + ".secret-tmp"
descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(descriptor, "wb") as destination:
    plistlib.dump(values, destination, fmt=plistlib.FMT_BINARY)
os.replace(temporary, path)
' "$plist_path"
}

unraid_ssh() {
    SSHPASS="${UNRAID_PASS:-}" sshpass -e ssh \
        -o StrictHostKeyChecking=no \
        -o PreferredAuthentications=password \
        "$UNRAID_USER@$UNRAID_HOST" "$@"
}

unraid_scp() {
    SSHPASS="${UNRAID_PASS:-}" sshpass -e scp \
        -o StrictHostKeyChecking=no \
        -o PreferredAuthentications=password \
        "$@"
}

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
            # The beta toolchain keeps Simulator inside its bundle and may not
            # register a global application name on this host.
            if [[ -d "$XCODE26/Contents/Developer/Applications/Simulator.app" ]]; then
                open "$XCODE26/Contents/Developer/Applications/Simulator.app" || true
            else
                open -a Simulator || true
            fi
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
            if [[ "$RESET_MODE" == true ]]; then
                defaults write "$PLIST" HAClearCredentials -bool true
            else
                defaults write "$PLIST" HAServerURL -string "$HA_SERVER"
                write_ha_token_to_plist "$PLIST"
            fi
            defaults write "$PLIST" HADashboard -string "$HA_DASHBOARD"
            [[ -n "$KIOSK_MODE" ]] && defaults write "$PLIST" HAKioskMode -bool "$([ "$KIOSK_MODE" = "YES" ] && echo true || echo false)"
            [[ -n "$DEMO_MODE" ]] && defaults write "$PLIST" HADemoMode -bool true
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

        if [[ -z "$IPHONE_DEVICECTL_ID" ]]; then
            echo "❌ IPHONE_DEVICECTL_ID is not configured"
            exit 1
        fi
        if ! xcrun devicectl device info details --device "$IPHONE_DEVICECTL_ID" >/dev/null 2>&1; then
            echo "❌ Configured iPhone is not currently resolvable by CoreDevice"
            exit 1
        fi

        echo "   Installing exact artifact..."
        xcrun devicectl device install app \
            --device "$IPHONE_DEVICECTL_ID" \
            "$APP" 2>&1 | tail -3
        echo "   ✅ Exact artifact install completed on iPhone"

        echo "   Launching with dashboard: ${HA_DASHBOARD:-default}..."
        set +e
        _IPHONE_LAUNCH_OUTPUT=$(xcrun devicectl device process launch \
            --device "$IPHONE_DEVICECTL_ID" \
            --terminate-existing \
            -- "$BUNDLE_ID" \
            "${LAUNCH_ARGS[@]}" 2>&1)
        _IPHONE_LAUNCH_STATUS=$?
        set -e
        printf '%s\n' "$_IPHONE_LAUNCH_OUTPUT" | tail -3

        if [[ "$_IPHONE_LAUNCH_STATUS" -eq 0 ]]; then
            echo "✅ Installed and running on iPhone"
        elif printf '%s\n' "$_IPHONE_LAUNCH_OUTPUT" | grep -Fq 'FBSOpenApplicationErrorDomain' &&
             printf '%s\n' "$_IPHONE_LAUNCH_OUTPUT" | grep -Fq 'Locked'; then
            echo "✅ Installed-only success on iPhone; unlock it and open HA Dashboard to complete runtime launch acceptance"
        else
            echo "❌ iPhone runtime launch failed after a successful install"
            exit "$_IPHONE_LAUNCH_STATUS"
        fi
        ;;

    ipadpro)
        echo "📱 Deploying to iPad Pro..."
        export DEVELOPER_DIR="$XCODE26/Contents/Developer"
        _IPAD_PRO_LAUNCHED=false

        IPAD_PRO_DEVICECTL_ID=$(resolve_ipad_pro_id || true)
        if [[ -z "$IPAD_PRO_DEVICECTL_ID" ]]; then
            echo "❌ A unique physical iPad Pro is not resolvable; set IPAD_PRO_DEVICECTL_ID"
            exit 1
        fi
        if ! xcrun devicectl device info details --device "$IPAD_PRO_DEVICECTL_ID" >/dev/null 2>&1; then
            echo "❌ Configured iPad Pro is not currently resolvable by CoreDevice"
            exit 1
        fi

        echo "   Installing exact artifact..."
        xcrun devicectl device install app \
            --device "$IPAD_PRO_DEVICECTL_ID" \
            "$APP" 2>&1 | tail -3
        echo "   ✅ Exact artifact install completed on iPad Pro"

        echo "   Launching with dashboard: ${HA_DASHBOARD:-default}..."
        set +e
        _IPAD_PRO_LAUNCH_OUTPUT=$(xcrun devicectl device process launch \
            --device "$IPAD_PRO_DEVICECTL_ID" \
            --terminate-existing \
            -- "$BUNDLE_ID" \
            "${LAUNCH_ARGS[@]}" 2>&1)
        _IPAD_PRO_LAUNCH_STATUS=$?
        set -e
        printf '%s\n' "$_IPAD_PRO_LAUNCH_OUTPUT" | tail -3

        if [[ "$_IPAD_PRO_LAUNCH_STATUS" -eq 0 ]]; then
            _IPAD_PRO_LAUNCHED=true
            echo "   ✅ Runtime launch accepted on iPad Pro"
        elif printf '%s\n' "$_IPAD_PRO_LAUNCH_OUTPUT" | grep -Fq 'FBSOpenApplicationErrorDomain' &&
             printf '%s\n' "$_IPAD_PRO_LAUNCH_OUTPUT" | grep -Fq 'Locked'; then
            echo "   ⚠️  Runtime launch not accepted because the iPad Pro is locked"
        else
            echo "❌ iPad Pro runtime launch failed after a successful install"
            exit "$_IPAD_PRO_LAUNCH_STATUS"
        fi

        if [[ "$_IPAD_PRO_LAUNCHED" == true ]]; then
            echo "✅ Installed and running on iPad Pro"
        else
            echo "✅ Installed-only success on iPad Pro; unlock it and open HA Dashboard to complete runtime launch acceptance"
        fi
        ;;

    mini5)
        echo "📱 Deploying to iPad Mini 5..."
        export DEVELOPER_DIR="$XCODE26/Contents/Developer"
        _MINI5_LAUNCHED=false

        if [[ -n "$IPAD_MINI5_DEVICECTL_ID" ]] && \
           xcrun devicectl device info details --device "$IPAD_MINI5_DEVICECTL_ID" >/dev/null 2>&1; then
            echo "   Installing via CoreDevice..."
            xcrun devicectl device install app \
                --device "$IPAD_MINI5_DEVICECTL_ID" \
                "$APP" 2>&1 | tail -3

            echo "   Launching with dashboard: ${HA_DASHBOARD:-default}..."
            xcrun devicectl device process launch \
                --device "$IPAD_MINI5_DEVICECTL_ID" \
                --terminate-existing \
                -- "$BUNDLE_ID" \
                "${LAUNCH_ARGS[@]}" 2>&1 | tail -3
            _MINI5_LAUNCHED=true
        elif [[ -n "$IPAD_MINI5_UDID" ]] && command -v ideviceinfo >/dev/null 2>&1 && \
             ideviceinfo -n -u "$IPAD_MINI5_UDID" -k DeviceName >/dev/null 2>&1; then
            echo "   CoreDevice record unavailable; using the validated MobileDevice WiFi pairing..."
            _MINI5_PACKAGE_DIR="$(mktemp -d /tmp/hadashboard-mini5.XXXXXX)"
            _CLEANUP_DIRS+=("$_MINI5_PACKAGE_DIR")
            if command -v ios-deploy >/dev/null 2>&1; then
                # iOS 26's installation-proxy upgrade can wait indefinitely
                # after copying. ios-deploy uses the same paired Wi-Fi channel
                # but gives observable install progress and a definitive
                # InstallComplete marker. A missing personalized DDI may still
                # prevent automatic launch after a successful installation.
                _MINI5_INSTALL_LOG="$_MINI5_PACKAGE_DIR/ios-deploy.log"
                set +e
                if command -v gtimeout >/dev/null 2>&1; then
                    gtimeout 120 ios-deploy -i "$IPAD_MINI5_UDID" -b "$APP" -L -I -t 20 \
                        2>&1 | tee "$_MINI5_INSTALL_LOG"
                else
                    ios-deploy -i "$IPAD_MINI5_UDID" -b "$APP" -L -I -t 20 \
                        2>&1 | tee "$_MINI5_INSTALL_LOG"
                fi
                _MINI5_IOS_DEPLOY_STATUS=${PIPESTATUS[0]}
                set -e
                if ! grep -Fq '[100%] Installed package' "$_MINI5_INSTALL_LOG"; then
                    echo "❌ iPad Mini 5 ios-deploy install failed"
                    [[ "${_MINI5_IOS_DEPLOY_STATUS:-1}" -ne 0 ]] || _MINI5_IOS_DEPLOY_STATUS=1
                    exit "$_MINI5_IOS_DEPLOY_STATUS"
                fi
                if [[ "$_MINI5_IOS_DEPLOY_STATUS" -eq 0 ]]; then
                    _MINI5_LAUNCHED=true
                else
                    echo "   Installed successfully; automatic launch needs the personalized Developer Disk Image or leaving Guided Access"
                fi
            elif command -v ideviceinstaller >/dev/null 2>&1; then
                mkdir "$_MINI5_PACKAGE_DIR/Payload"
                cp -R "$APP" "$_MINI5_PACKAGE_DIR/Payload/"
                _MINI5_IPA="$_MINI5_PACKAGE_DIR/HA-Dashboard.ipa"
                (cd "$_MINI5_PACKAGE_DIR" && zip -qry "$_MINI5_IPA" Payload)
                if command -v gtimeout >/dev/null 2>&1; then
                    gtimeout 120 ideviceinstaller -n -u "$IPAD_MINI5_UDID" upgrade "$_MINI5_IPA"
                else
                    ideviceinstaller -n -u "$IPAD_MINI5_UDID" upgrade "$_MINI5_IPA"
                fi
            else
                echo "❌ Neither ios-deploy nor ideviceinstaller is available for iPad Mini 5"
                exit 1
            fi
        else
            echo "❌ iPad Mini 5 is not reachable through CoreDevice or its saved MobileDevice WiFi pairing"
            exit 1
        fi

        if [[ "$_MINI5_LAUNCHED" == true ]]; then
            echo "✅ Running on iPad Mini 5"
        else
            echo "✅ Installed on iPad Mini 5; open HA Dashboard on the iPad to launch it"
        fi
        ;;

    mini4)
        if ! command -v ideviceinstaller &>/dev/null; then
            echo "❌ ideviceinstaller not found. Install libimobiledevice"
            exit 1
        fi

        if [[ -z "$IPAD_MINI4_UDID" ]]; then
            echo "❌ IPAD_MINI4_UDID is not configured"
            exit 1
        fi

        echo "📱 Deploying to iPad Mini 4 (WiFi via MobileInstallation)..."
        _MINI4_PACKAGE_DIR="$(mktemp -d /tmp/hadashboard-mini4.XXXXXX)"
        _CLEANUP_DIRS+=("$_MINI4_PACKAGE_DIR")
        mkdir "$_MINI4_PACKAGE_DIR/Payload"
        cp -R "$APP" "$_MINI4_PACKAGE_DIR/Payload/"
        _MINI4_IPA="$_MINI4_PACKAGE_DIR/HA-Dashboard.ipa"
        (cd "$_MINI4_PACKAGE_DIR" && zip -qry "$_MINI4_IPA" Payload)

        echo "   Upgrading without uninstalling (preserves the app container)..."
        if ! ideviceinstaller -n -u "$IPAD_MINI4_UDID" upgrade "$_MINI4_IPA"; then
            echo "❌ iPad Mini 4 install failed"
            exit 1
        fi

        _MINI4_LAUNCHED=false
        if command -v idevicedebug >/dev/null 2>&1 &&
           idevicedebug -n -u "$IPAD_MINI4_UDID" --detach run "$BUNDLE_ID" >/dev/null 2>&1; then
            _MINI4_LAUNCHED=true
        fi
        if [[ "$_MINI4_LAUNCHED" == true ]]; then
            echo "✅ Upgraded and launched iPad Mini 4"
        else
            echo "✅ Upgraded iPad Mini 4; open HA Dashboard on the device to launch it"
        fi
        ;;

    ipad2|ipad3|ipad4)
        # ── Shared jailbroken iPad deploy (SSH over WiFi) ─────────────
        case "$TARGET" in
            ipad2) _IPAD_LABEL="iPad 2"; _IPAD_IP="$IPAD2_IP"; _IPAD_PASS="$IPAD2_SSH_PASS" ;;
            ipad3) _IPAD_LABEL="iPad 3"; _IPAD_IP="$IPAD3_IP"; _IPAD_PASS="$IPAD3_SSH_PASS" ;;
            ipad4) _IPAD_LABEL="iPad 4"; _IPAD_IP="$IPAD4_IP"; _IPAD_PASS="$IPAD4_SSH_PASS" ;;
        esac
        _IPAD_CONTROL_PATH="/tmp/hadashboard-${TARGET}-ssh-$$.sock"
        _SSH_OPTIONS=(
            -o StrictHostKeyChecking=no
            -o UserKnownHostsFile=/dev/null
            -o HostkeyAlgorithms=ssh-rsa
            -o ControlMaster=auto
            -o ControlPersist=120
            -o ControlPath="$_IPAD_CONTROL_PATH"
            -o ConnectTimeout=12
            -o ConnectionAttempts=1
            -o NumberOfPasswordPrompts=1
            -o PreferredAuthentications=password
        )

        ipad_ssh() {
            SSHPASS="$_IPAD_PASS" sshpass -e ssh "${_SSH_OPTIONS[@]}" "root@$_IPAD_IP" "$@"
        }
        ipad_scp() {
            SSHPASS="$_IPAD_PASS" sshpass -e scp "${_SSH_OPTIONS[@]}" "$@"
        }

        echo "📱 Deploying to $_IPAD_LABEL via WiFi SSH ($_IPAD_IP)..."

        if [[ -z "$_IPAD_IP" ]]; then
            echo "❌ IP not set in .env for $TARGET"
            exit 1
        fi

        if ! ipad_ssh "echo ok" &>/dev/null; then
            echo "❌ Cannot SSH to $_IPAD_LABEL at $_IPAD_IP"
            echo "   Ensure the iPad is jailbroken, WiFi is connected, and a compatible SSH daemon is running"
            [[ "$TARGET" == "ipad4" ]] && echo "   h3lix/iOS 10.3.3 normally requires Dropbear; OpenSSH may accept port 22 but hang before its banner"
            exit 1
        fi

        # Keep a recoverable on-device copy before replacing the app or its
        # launch preferences. A failed backup is a hard stop.
        _BACKUP_ID="$(date +%Y%m%d-%H%M%S)"
        _BACKUP_DIR="/var/mobile/Library/HADashboard-backups/$BUNDLE_ID/$_BACKUP_ID"
        echo "   Backing up existing app and preferences..."
        if ! ipad_ssh "
            set -e
            mkdir -p '$_BACKUP_DIR'
            echo 'backup: directory ready'
            if [ -d '/Applications/HA Dashboard.app' ]; then
                tar czf '$_BACKUP_DIR/HA-Dashboard.app-before.tar.gz' -C /Applications 'HA Dashboard.app'
                echo 'backup: application archived'
            fi
            if [ -f '/var/mobile/Library/Preferences/$BUNDLE_ID.plist' ]; then
                cp '/var/mobile/Library/Preferences/$BUNDLE_ID.plist' '$_BACKUP_DIR/preferences-before.plist'
                echo 'backup: preferences copied'
                if command -v shasum >/dev/null 2>&1; then
                    shasum -a 256 '$_BACKUP_DIR/preferences-before.plist' > '$_BACKUP_DIR/preferences-before.sha256'
                elif command -v openssl >/dev/null 2>&1; then
                    openssl dgst -sha256 '$_BACKUP_DIR/preferences-before.plist' > '$_BACKUP_DIR/preferences-before.sha256'
                else
                    echo 'No SHA-256 utility is available for preference backup' >&2
                    exit 1
                fi
                echo 'backup: preferences checksummed'
            fi
        "; then
            echo "❌ Could not create a verified backup on $_IPAD_LABEL; no deployment was attempted"
            exit 1
        fi

        _DEPLOY_WORK_DIR=$(mktemp -d "$PROJECT_DIR/build/${TARGET}.deploy.XXXXXX")
        _CLEANUP_DIRS+=("$_DEPLOY_WORK_DIR")
        APP_TAR="$_DEPLOY_WORK_DIR/HADashboard.app.tar.gz"
        echo "   Packaging .app..."
        if [[ "$TARGET" == "ipad4" ]]; then
            # iOS 10+: strip Apple codesign (conflicts with ldid on-device)
            _STAGE="$_DEPLOY_WORK_DIR/stage-jb"
            mkdir -p "$_STAGE"
            cp -R "$APP" "$_STAGE/"
            _STAGED_APP="$_STAGE/$(basename "$APP")"
            _JB_ENTITLEMENTS="$_STAGED_APP/HA-Dashboard.jailbreak.entitlements"
            if ! codesign -d --entitlements :- "$_STAGED_APP/HA Dashboard" \
                > "$_JB_ENTITLEMENTS" 2>/dev/null ||
               ! plutil -lint "$_JB_ENTITLEMENTS" >/dev/null 2>&1; then
                echo "❌ Could not preserve the signed app entitlements for iPad 4 Keychain access"
                exit 1
            fi
            if ! plutil -extract application-identifier raw "$_JB_ENTITLEMENTS" >/dev/null 2>&1 &&
               ! plutil -extract com.apple.application-identifier raw "$_JB_ENTITLEMENTS" >/dev/null 2>&1; then
                echo "❌ The iPad 4 signing entitlements do not contain an application identifier"
                exit 1
            fi
            codesign --remove-signature "$_STAGED_APP/HA Dashboard" 2>/dev/null || true
            rm -f "$_STAGED_APP/embedded.mobileprovision"
            tar -czf "$APP_TAR" -C "$_STAGE" "$(basename "$APP")"
        else
            # iOS 9: ldid -S works fine over Apple-signed binaries
            tar -czf "$APP_TAR" -C "$(dirname "$APP")" "$(basename "$APP")"
        fi

        # Merge deploy preferences into existing plist on device
        _PLIST="$_DEPLOY_WORK_DIR/${TARGET}-prefs.plist"
        _SENSITIVE_PREFS_FILE="$_PLIST"
        PREFS_PATH="/var/mobile/Library/Preferences/$BUNDLE_ID.plist"
        rm -f "$_PLIST"
        ipad_scp "root@${_IPAD_IP}:$PREFS_PATH" "$_PLIST" 2>/dev/null || true
        _PLIST_BASE="${_PLIST%.plist}"
        if [ "$RESET_MODE" = "true" ]; then
            defaults write "$_PLIST_BASE" HAClearCredentials -bool true
        else
            defaults write "$_PLIST_BASE" HAServerURL -string "$HA_SERVER"
            write_ha_token_to_plist "$_PLIST"
        fi
        defaults write "$_PLIST_BASE" HADashboard -string "$HA_DASHBOARD"
        defaults write "$_PLIST_BASE" HAKioskMode -bool "$([ "$KIOSK_MODE" = "YES" ] && echo true || echo false)"
        [[ -n "$DEMO_MODE" ]] && defaults write "$_PLIST_BASE" HADemoMode -bool true
        plutil -convert binary1 "$_PLIST"

        echo "   Transferring to $_IPAD_LABEL ($_IPAD_IP)..."
        ipad_scp "$APP_TAR" "root@${_IPAD_IP}:/tmp/HADashboard.app.tar.gz"
        ipad_scp "$_PLIST" "root@${_IPAD_IP}:/tmp/ha-prefs.plist"

        echo "   Installing..."
        if ! ipad_ssh sh -s -- "$BUNDLE_ID" <<'REMOTE_INSTALL'
set -e
BUNDLE_ID="$1"
APP_DIR='/Applications/HA Dashboard.app'
APP_EXEC="$APP_DIR/HA Dashboard"

# The jailbroken iOS 9/10 userland has pgrep but no awk. Anchor the full
# executable path so only this app is signalled; a generic process-name kill is
# deliberately avoided.
if command -v pgrep >/dev/null 2>&1; then
    APP_PIDS=$(pgrep -f "^$APP_EXEC([[:space:]].*)?$" 2>/dev/null || true)
    for APP_PID in $APP_PIDS; do
        kill "$APP_PID" 2>/dev/null || true
    done
fi

cd /Applications
rm -rf 'HA Dashboard.app'
tar xzf /tmp/HADashboard.app.tar.gz
rm /tmp/HADashboard.app.tar.gz

if ! command -v ldid >/dev/null 2>&1; then
    echo 'ldid is required to install this jailbreak build' >&2
    exit 1
fi
if [ -f 'HA Dashboard.app/HA-Dashboard.jailbreak.entitlements' ]; then
    ldid -S'HA Dashboard.app/HA-Dashboard.jailbreak.entitlements' 'HA Dashboard.app/HA Dashboard'
    rm -f 'HA Dashboard.app/HA-Dashboard.jailbreak.entitlements'
else
    ldid -S 'HA Dashboard.app/HA Dashboard'
fi
uicache 2>/dev/null || true

# Clear only this app's caches. Other apps and their data remain untouched.
rm -rf "/var/mobile/Library/Caches/$BUNDLE_ID" 2>/dev/null || true
find /var/mobile/tmp -maxdepth 1 -name "$BUNDLE_ID*" -exec rm -rf {} \; 2>/dev/null || true

PREFS_DIR=/var/mobile/Library/Preferences
mkdir -p "$PREFS_DIR"
mv /tmp/ha-prefs.plist "$PREFS_DIR/$BUNDLE_ID.plist"
chmod 644 "$PREFS_DIR/$BUNDLE_ID.plist"
chown mobile:mobile "$PREFS_DIR/$BUNDLE_ID.plist"

rm -f /tmp/ha-log.txt
sleep 2
open "$BUNDLE_ID" 2>/dev/null || true
REMOTE_INSTALL
        then
            echo "❌ Remote installation failed on $_IPAD_LABEL"
            exit 1
        fi

        echo "   Waiting for startup log..."
        sleep 8
        echo ""
        echo "── $_IPAD_LABEL log ─────────────────────────────────────"
        ipad_ssh '
            LOG_PATH=$(find /var/mobile/Containers/Data/Application -path "*/Documents/ha-log.txt" -type f 2>/dev/null | head -1)
            if [ -n "$LOG_PATH" ]; then
                tail -160 "$LOG_PATH"
            else
                echo "(no app-container log file found)"
            fi
        '
        echo "────────────────────────────────────────────────────────"
        echo "   Backup retained at: $_BACKUP_DIR"
        ssh "${_SSH_OPTIONS[@]}" -O exit "root@$_IPAD_IP" >/dev/null 2>&1 || true
        echo ""
        echo "✅ Deployed to $_IPAD_LABEL (WiFi)"
        ;;

    mac)
        echo "🖥  Deploying to Mac (Catalyst)..."

        # Discover by this exact app executable path, verify every candidate,
        # and terminate only those PIDs. Do not use a generic process name.
        MAC_EXECUTABLE="$APP/Contents/MacOS/HA Dashboard"
        MAC_EXECUTABLE_PATTERN=$(printf '%s' "$MAC_EXECUTABLE" | sed 's/[][\\.^$*+?(){}|]/\\&/g')
        while IFS= read -r MAC_PID; do
            [[ -n "$MAC_PID" ]] || continue
            MAC_COMMAND=$(ps -p "$MAC_PID" -o command= 2>/dev/null || true)
            case "$MAC_COMMAND" in
                "$MAC_EXECUTABLE"|"$MAC_EXECUTABLE "*) kill "$MAC_PID" ;;
            esac
        done < <(pgrep -f "^${MAC_EXECUTABLE_PATTERN}([[:space:]]|$)" 2>/dev/null || true)
        sleep 0.5

        echo "   Launching with dashboard: ${HA_DASHBOARD:-default}..."
        # A sandboxed Catalyst app reads its own container preferences, so
        # global `defaults write` cannot seed this app. Pass only non-secret
        # settings; the existing Home Assistant token remains in the Keychain.
        open -n "$APP" --args "${LAUNCH_ARGS[@]}"

        MAC_LAUNCH_PID=""
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            while IFS= read -r MAC_PID; do
                [[ -n "$MAC_PID" ]] || continue
                MAC_COMMAND=$(ps -p "$MAC_PID" -o command= 2>/dev/null || true)
                case "$MAC_COMMAND" in
                    "$MAC_EXECUTABLE"|"$MAC_EXECUTABLE "*) MAC_LAUNCH_PID="$MAC_PID"; break ;;
                esac
            done < <(pgrep -f "^${MAC_EXECUTABLE_PATTERN}([[:space:]]|$)" 2>/dev/null || true)
            [[ -n "$MAC_LAUNCH_PID" ]] && break
            sleep 0.2
        done
        if [[ -z "$MAC_LAUNCH_PID" ]]; then
            echo "❌ Catalyst launch was not observed at the exact executable path"
            exit 1
        fi
        echo "   Launch verified: pid $MAC_LAUNCH_PID"

        echo "✅ Running on Mac"
        ;;

    ipad2-usb)
        echo "📱 Deploying to iPad 2 via Unraid USB ($UNRAID_HOST)..."

        if [[ -z "$UNRAID_HOST" ]]; then
            echo "❌ UNRAID_HOST not set in .env"
            exit 1
        fi
        if [[ -z "$IPAD2_UDID" ]]; then
            echo "❌ IPAD2_UDID is required for exact USB targeting"
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
        unraid_scp "$IPA" "$UNRAID_USER@$UNRAID_HOST:/tmp/HADashboard.ipa"

        # Transfer developer disk image if not already on server
        DDI_DIR="/Applications/Xcode-13.2.1.app/Contents/Developer/Platforms/iPhoneOS.platform/DeviceSupport/9.3"
        if ! unraid_ssh 'test -f /tmp/ios-ddi/DeveloperDiskImage.dmg' 2>/dev/null && \
            [[ -f "$DDI_DIR/DeveloperDiskImage.dmg" ]]; then
            echo "   Uploading developer disk image..."
            unraid_ssh 'mkdir -p /tmp/ios-ddi'
            unraid_scp \
                "$DDI_DIR/DeveloperDiskImage.dmg" "$DDI_DIR/DeveloperDiskImage.dmg.signature" \
                "$UNRAID_USER@$UNRAID_HOST:/tmp/ios-ddi/"
        fi

        # Install via Docker + libimobiledevice
        echo "   Installing on iPad 2..."
        unraid_ssh '
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
    EXPECTED_UDID='"$IPAD2_UDID"'
    if [ -z \"\$UDID\" ]; then
      echo \"❌ No iOS device found on USB\"
      exit 1
    fi
    if [ -n \"\$EXPECTED_UDID\" ] && [ \"\$UDID\" != \"\$EXPECTED_UDID\" ]; then
      echo \"❌ Connected USB device does not match configured iPad 2 UDID\"
      exit 1
    fi
    echo \"   Device: \$UDID\"

    # Ensure device is paired
    if ! idevicepair -u \"\$UDID\" validate 2>/dev/null; then
      echo \"   Pairing (tap Trust on iPad if prompted)...\"
      idevicepair -u \"\$UDID\" pair 2>&1 || true
      sleep 5
      idevicepair -u \"\$UDID\" validate 2>/dev/null || echo \"⚠️  Not paired — tap Trust on iPad, then retry\"
    fi

    # Install app
    ideviceinstaller -u \"\$UDID\" -i /tmp/HADashboard.ipa 2>&1 | grep -E \"(Install:|ERROR|DONE|Copying)\"

    # Mount developer disk image if available
    if [ -f /tmp/ddi/DeveloperDiskImage.dmg ]; then
      if ! ideviceimagemounter -u \"\$UDID\" -l 2>&1 | grep -q \"ImagePresent: true\"; then
        echo \"   Mounting developer disk image...\"
        ideviceimagemounter -u \"\$UDID\" /tmp/ddi/DeveloperDiskImage.dmg /tmp/ddi/DeveloperDiskImage.dmg.signature 2>&1
      fi
    else
      echo \"   ⚠️  No developer disk image at /tmp/ddi/\"
    fi

    # Launch without putting the Home Assistant token in process arguments.
    echo \"   Launching with non-secret arguments (token redacted)\"
    idevicedebug -u \"\$UDID\" run '"$BUNDLE_ID"' '"${USB_LAUNCH_ARGS[*]}"' 2>&1 &
    DBGPID=\\\$!
    sleep 5
    kill \\\$DBGPID 2>/dev/null || true
  "
'

        echo "✅ Deployed to iPad 2 (USB)"
        ;;

    ipad4-usb)
        echo "📱 Deploying to iPad 4 via Unraid USB ($UNRAID_HOST)..."

        if [[ -z "$UNRAID_HOST" ]]; then
            echo "❌ UNRAID_HOST not set in .env"
            exit 1
        fi
        if [[ -z "$IPAD4_UDID" ]]; then
            echo "❌ IPAD4_UDID is required for exact USB targeting"
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
        unraid_scp "$IPA" "$UNRAID_USER@$UNRAID_HOST:/tmp/HADashboard.ipa"

        # Transfer developer disk image for iOS 10.3 if needed
        DDI_DIR="/Applications/Xcode-13.2.1.app/Contents/Developer/Platforms/iPhoneOS.platform/DeviceSupport/10.3"
        if ! unraid_ssh 'test -f /tmp/ios-ddi-10/DeveloperDiskImage.dmg' 2>/dev/null && \
            [[ -d "$DDI_DIR" ]]; then
            echo "   Uploading developer disk image (iOS 10.3)..."
            unraid_ssh 'mkdir -p /tmp/ios-ddi-10'
            unraid_scp \
                "$DDI_DIR/DeveloperDiskImage.dmg" "$DDI_DIR/DeveloperDiskImage.dmg.signature" \
                "$UNRAID_USER@$UNRAID_HOST:/tmp/ios-ddi-10/"
        fi

        # Install via Docker + libimobiledevice
        echo "   Installing on iPad 4..."
        unraid_ssh '
mkdir -p /tmp/ios-lockdown
docker run --rm --privileged \
  -v /dev/bus/usb:/dev/bus/usb \
  -v /tmp/HADashboard.ipa:/tmp/HADashboard.ipa \
  -v /tmp/ios-lockdown:/var/lib/lockdown \
  -v /tmp/ios-ddi-10:/tmp/ddi \
  ubuntu:22.04 bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update > /dev/null 2>&1
    apt-get install -y usbmuxd libimobiledevice-utils ideviceinstaller > /dev/null 2>&1
    usbmuxd -f &
    sleep 3
    UDID=\$(idevice_id -l 2>/dev/null | head -1)
    EXPECTED_UDID='"$IPAD4_UDID"'
    if [ -z \"\$UDID\" ]; then
      echo \"❌ No iOS device found on USB\"
      exit 1
    fi
    if [ -n \"\$EXPECTED_UDID\" ] && [ \"\$UDID\" != \"\$EXPECTED_UDID\" ]; then
      echo \"❌ Connected USB device does not match configured iPad 4 UDID\"
      exit 1
    fi
    echo \"   Device: \$UDID\"

    # Ensure device is paired
    if ! idevicepair -u \"\$UDID\" validate 2>/dev/null; then
      echo \"   Pairing (tap Trust on iPad if prompted)...\"
      idevicepair -u \"\$UDID\" pair 2>&1 || true
      sleep 5
      idevicepair -u \"\$UDID\" validate 2>/dev/null || echo \"⚠️  Not paired — tap Trust on iPad, then retry\"
    fi

    # Install app
    ideviceinstaller -u \"\$UDID\" -i /tmp/HADashboard.ipa 2>&1 | grep -E \"(Install:|ERROR|DONE|Copying)\"

    # Mount developer disk image if available
    if [ -f /tmp/ddi/DeveloperDiskImage.dmg ]; then
      if ! ideviceimagemounter -u \"\$UDID\" -l 2>&1 | grep -q \"ImagePresent: true\"; then
        echo \"   Mounting developer disk image...\"
        ideviceimagemounter -u \"\$UDID\" /tmp/ddi/DeveloperDiskImage.dmg /tmp/ddi/DeveloperDiskImage.dmg.signature 2>&1
      fi
    else
      echo \"   ⚠️  No developer disk image at /tmp/ddi/\"
    fi

    # Launch without putting the Home Assistant token in process arguments.
    echo \"   Launching with non-secret arguments (token redacted)\"
    idevicedebug -u \"\$UDID\" run '"$BUNDLE_ID"' '"${USB_LAUNCH_ARGS[*]}"' 2>&1 &
    DBGPID=\\\$!
    sleep 5
    kill \\\$DBGPID 2>/dev/null || true
  "
'

        echo "✅ Deployed to iPad 4 (USB)"
        ;;
esac
