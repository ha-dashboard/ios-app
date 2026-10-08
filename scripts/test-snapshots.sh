#!/bin/bash
set -uo pipefail

# Snapshot Regression Tests
#
# Usage:
#   scripts/test-snapshots.sh                    # Run all HADashboardTests
#   scripts/test-snapshots.sh record              # Record new reference images
#   scripts/test-snapshots.sh -only-testing:HADashboardTests/HAActionTests
#   scripts/test-snapshots.sh record -only-testing:HADashboardTests/HAClimateSnapshotTests/testThermostatShowCurrentAsPrimary
#
# Any arguments after an optional leading "record" are passed through to
# `xcodebuild test` verbatim, so `-only-testing:<id>` (repeatable) and other
# xcodebuild test flags work as usual.
#
# Simulator selection (first match wins):
#   SNAPSHOT_SIM_UDID    - exact simulator UDID to use
#   SNAPSHOT_SIM_NAME    + SNAPSHOT_SIM_OS - device name + OS version
#   otherwise: falls back to a booted/available "iPad (10th generation)"
#   simulator, preferring the iOS 18.0 runtime that reference images are
#   pinned to (see CLAUDE.md Testing section), then any available iPad.
#
# Reference images default to the iOS 18.0-pinned set (ReferenceImages_ios18_64).
#   HA_SNAPSHOT_RUNTIME_SUFFIX=_ios18   (default) - pinned iOS 18.0 set
#   HA_SNAPSHOT_RUNTIME_SUFFIX=""       - legacy iOS 17.4 set (ReferenceImages_64)
#   HA_SNAPSHOT_RUNTIME_SUFFIX=_foo     - any other OS-tagged set

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

SCHEME="HADashboard"
TEST_TARGET="HADashboardTests"
PINNED_OS="18.0"
PINNED_DEVICE="iPad (10th generation)"

# ── Parse args ──────────────────────────────────────────────────────
RECORD_MODE="NO"
EXTRA_ARGS=()
if [[ "${1:-}" == "record" ]]; then
    RECORD_MODE="YES"
    shift
fi
EXTRA_ARGS=("$@")

if [[ "$RECORD_MODE" == "YES" ]]; then
    echo "📸 Recording reference images..."
else
    echo "🔍 Running snapshot regression tests..."
fi

# ── Pick a destination simulator ───────────────────────────────────
pick_destination() {
    if [[ -n "${SNAPSHOT_SIM_UDID:-}" ]]; then
        echo "platform=iOS Simulator,id=${SNAPSHOT_SIM_UDID}"
        return
    fi
    if [[ -n "${SNAPSHOT_SIM_NAME:-}" ]]; then
        echo "platform=iOS Simulator,name=${SNAPSHOT_SIM_NAME},OS=${SNAPSHOT_SIM_OS:-$PINNED_OS}"
        return
    fi

    # Resolve a concrete UDID for the pinned device/OS so we never depend
    # on an "OS=" destination match silently picking the wrong runtime.
    # Parsed with plain shell/grep/sed (no extra interpreter dependency):
    # `simctl list devices available` groups devices under "-- iOS X.Y --"
    # headers, one device per line as "    <name> (<UDID>) (<state>)".
    local udid=""
    local cur_os=""
    while IFS= read -r line; do
        case "$line" in
            "-- iOS "*" --")
                cur_os="${line#-- iOS }"
                cur_os="${cur_os% --}"
                ;;
            *"$PINNED_DEVICE ("*)
                if [[ "$cur_os" == "$PINNED_OS" ]]; then
                    udid=$(echo "$line" | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')
                    break
                fi
                ;;
        esac
    done < <(xcrun simctl list devices available 2>/dev/null)

    if [[ -n "$udid" ]]; then
        echo "platform=iOS Simulator,id=${udid}"
        return
    fi

    echo "⚠️  Could not find '$PINNED_DEVICE' on iOS $PINNED_OS; falling back to any available iPad simulator." >&2
    echo "platform=iOS Simulator,name=${PINNED_DEVICE}"
}

DESTINATION="$(pick_destination)"
echo "   Destination: $DESTINATION"

# ── Regenerate project only if needed, and never dirty tracked files ──
# xcodegen generate (run directly) would bake whatever DEVELOPMENT_TEAM is
# in the environment into the committed pbxproj. scripts/regen.sh already
# does the safe temp-substitute-then-restore dance, so delegate to it
# instead of calling xcodegen ourselves, and only when the project is
# actually missing or stale relative to project.yml.
if [[ ! -d "$PROJECT_DIR/HADashboard.xcodeproj" ]] || [[ "$PROJECT_DIR/project.yml" -nt "$PROJECT_DIR/HADashboard.xcodeproj/project.pbxproj" ]]; then
    if [[ -x "$SCRIPT_DIR/regen.sh" ]]; then
        echo "   Project is missing or stale — regenerating via scripts/regen.sh..."
        "$SCRIPT_DIR/regen.sh"
    fi
fi

# The test process runs inside the simulator and does NOT inherit this
# shell's exported environment, so both record mode and the runtime-suffix
# pin are passed as compile-time GCC_PREPROCESSOR_DEFINITIONS (one build
# setting — specifying it twice would make the second occurrence win
# instead of merging) rather than runtime environment variables.
# Default to the pinned iOS 18.0 reference set. Set HA_SNAPSHOT_RUNTIME_SUFFIX=""
# (empty, explicitly) to fall back to the legacy iOS 17.4 "ReferenceImages_64" set.
RUNTIME_SUFFIX="${HA_SNAPSHOT_RUNTIME_SUFFIX-_ios18}"

PREPROCESSOR_DEFS='$(inherited)'
if [[ "$RECORD_MODE" == "YES" ]]; then
    PREPROCESSOR_DEFS="$PREPROCESSOR_DEFS RECORD_SNAPSHOTS=1"
fi
if [[ -n "$RUNTIME_SUFFIX" ]]; then
    PREPROCESSOR_DEFS="$PREPROCESSOR_DEFS HA_SNAPSHOT_RUNTIME_SUFFIX='\"${RUNTIME_SUFFIX}\"'"
fi
RECORD_DEFINE=()
if [[ "$PREPROCESSOR_DEFS" != '$(inherited)' ]]; then
    RECORD_DEFINE=("GCC_PREPROCESSOR_DEFINITIONS=${PREPROCESSOR_DEFS}")
fi

# ── Build and run tests ────────────────────────────────────────────
echo "   Building and testing..."

LOG_FILE="$(mktemp -t hadashboard-test-snapshots)"
trap 'rm -f "$LOG_FILE"' EXIT

xcodebuild test \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -only-testing:"$TEST_TARGET" \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 \
    CODE_SIGNING_ALLOWED=NO \
    ${RECORD_DEFINE[@]+"${RECORD_DEFINE[@]}"} \
    ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"} \
    > "$LOG_FILE" 2>&1
RESULT=$?

PASS_COUNT=0
FAIL_COUNT=0
FAILED_TESTS=()

while IFS= read -r line; do
    if echo "$line" | grep -q "Test Case.*started"; then
        TEST_NAME=$(echo "$line" | sed -E 's/.*-\[([^]]*)\].*/\1/')
        echo "   ▶ $TEST_NAME"
    elif echo "$line" | grep -q "Test Case.*passed"; then
        TEST_NAME=$(echo "$line" | sed -E 's/.*-\[([^]]*)\].*/\1/')
        echo "   ✅ $TEST_NAME"
        PASS_COUNT=$((PASS_COUNT + 1))
    elif echo "$line" | grep -q "Test Case.*failed"; then
        TEST_NAME=$(echo "$line" | sed -E 's/.*-\[([^]]*)\].*/\1/')
        echo "   ❌ $TEST_NAME"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_TESTS+=("$TEST_NAME")
    fi
done < "$LOG_FILE"

echo ""
if [[ $RESULT -eq 0 ]]; then
    echo "✅ TEST SUCCEEDED — $PASS_COUNT passed, $FAIL_COUNT failed"
else
    echo "❌ TEST FAILED — $PASS_COUNT passed, $FAIL_COUNT failed"
    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo ""
        echo "Failed tests:"
        for t in "${FAILED_TESTS[@]}"; do
            echo "   - $t"
        done
    fi
    echo ""
    echo "Full xcodebuild log: $LOG_FILE"
    trap - EXIT
fi

# List failure diffs if any exist
DIFF_DIR="$PROJECT_DIR/HADashboardTests/FailureDiffs"
if [[ -d "$DIFF_DIR" ]] && [[ $(find "$DIFF_DIR" -name "*.png" 2>/dev/null | wc -l) -gt 0 ]]; then
    echo ""
    echo "📋 Failure diff images:"
    find "$DIFF_DIR" -name "*.png" | while read -r f; do
        echo "   $(basename "$f")"
    done
fi

exit "$RESULT"
