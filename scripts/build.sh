#!/bin/bash
set -euo pipefail

# HA Dashboard Build Script
#
# Builds the app for simulator or device.
#
# Usage:
#   scripts/build.sh sim           # Simulator build (arm64, iOS 15+)
#   scripts/build.sh rosettasim    # Legacy simulator build (requires macOS 26 + Xcode 26)
#   scripts/build.sh device        # Universal device build (armv7+arm64)
#
# The rosettasim target builds with Xcode 26 xcodebuild and sets
# MERGED_BINARY_TYPE=none to disable mergeable libraries — the default
# Debug stub+dylib pattern crashes on legacy runtimes' libdispatch.
#
# Output:
#   Prints the path to the built .app on success

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CALLER_FORCE_SIGNING_STYLE="${HADASHBOARD_FORCE_SIGNING_STYLE:-}"
CALLER_FORCE_SIGNING_DEVICE_ID="${HADASHBOARD_FORCE_SIGNING_DEVICE_ID:-}"

# ── Load .env ─────────────────────────────────────────────────────────
ENV_FILE="$PROJECT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    # Linked worktrees share the main checkout's .git directory. Reuse that
    # checkout's ignored .env instead of copying secrets into every worktree.
    GIT_COMMON_DIR=$(git -C "$PROJECT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
    if [[ -n "$GIT_COMMON_DIR" && "$(basename "$GIT_COMMON_DIR")" == ".git" ]]; then
        COMMON_CHECKOUT_ENV="$(dirname "$GIT_COMMON_DIR")/.env"
        if [[ -f "$COMMON_CHECKOUT_ENV" ]]; then
            ENV_FILE="$COMMON_CHECKOUT_ENV"
        fi
    fi
fi
if [[ -f "$ENV_FILE" ]]; then
    # Keep secrets as shell variables. Commands receive only the individual
    # non-secret values passed explicitly below.
    source "$ENV_FILE"
fi
# The build never needs a Home Assistant token.
unset HA_TOKEN HADASHBOARD_TOKEN_OVERRIDE 2>/dev/null || true
# Fleet-only force values supplied by deploy.sh outrank persisted .env defaults.
[[ -n "$CALLER_FORCE_SIGNING_STYLE" ]] && HADASHBOARD_FORCE_SIGNING_STYLE="$CALLER_FORCE_SIGNING_STYLE"
[[ -n "$CALLER_FORCE_SIGNING_DEVICE_ID" ]] && HADASHBOARD_FORCE_SIGNING_DEVICE_ID="$CALLER_FORCE_SIGNING_DEVICE_ID"

XCODE13="${XCODE13_PATH:-/Applications/Xcode-13.2.1.app}"
XCODE26="${XCODE_PATH:-/Applications/Xcode.app}"
# Keep the documented stable path first, but permit a deliberately selected
# Xcode 27 beta when it is the only installed modern toolchain on this host.
if [[ ! -d "$XCODE26" && -d "/Applications/Xcode-beta.app" ]]; then
    XCODE26="/Applications/Xcode-beta.app"
fi

BUNDLE_ID="${BUNDLE_ID:-com.hadashboard.app}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"

# ── Derive version from git tags ─────────────────────────────────────
TAG=$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo "")
if [[ -n "$TAG" ]]; then
    APP_VERSION="${TAG#v}"
else
    APP_VERSION="0.0.0-dev"
fi
BUILD_NUMBER=$(git -C "$PROJECT_DIR" rev-list --count HEAD)
echo "Version: $APP_VERSION ($BUILD_NUMBER)" >&2

# ── Parse args ────────────────────────────────────────────────────────
TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
    echo "Usage: scripts/build.sh <sim|device|mac>"
    echo ""
    echo "Targets:"
    echo "  sim      Simulator build (arm64, Xcode 26/27)"
    echo "  device   Universal device build (armv7+arm64, matches CI)"
    echo "  mac      Mac Catalyst build (arm64, macOS)"
    exit 1
fi

# ── Simulator build (arm64 only) ──────────────────────────────────────
build_simulator() {
    echo "Building for simulator (arm64)..." >&2

    if [ ! -d "$XCODE26" ]; then
        echo "Xcode not found at $XCODE26" >&2
        exit 1
    fi
    export DEVELOPER_DIR="$XCODE26/Contents/Developer"

    local BUILD_DIR="$PROJECT_DIR/build/sim"

    xcodebuild \
        -project "$PROJECT_DIR/HADashboard.xcodeproj" \
        -scheme HADashboard \
        -sdk iphonesimulator \
        -configuration Debug \
        -derivedDataPath "$BUILD_DIR" \
        ARCHS=arm64 \
        VALID_ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=NO \
        IPHONEOS_DEPLOYMENT_TARGET=15.0 \
        "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" \
        "MARKETING_VERSION=$APP_VERSION" \
        "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGN_IDENTITY="" \
        build 2>&1 | grep -E '(error:|BUILD)' | tail -5 >&2

    local APP="$BUILD_DIR/Build/Products/Debug-iphonesimulator/HA Dashboard.app"
    if [ ! -d "$APP" ]; then
        echo "Build failed" >&2
        exit 1
    fi

    echo "$APP"
}

# ── RosettaSim build (x86_64 simulator for legacy iOS 9–14 runtimes) ──
# Uses standard xcodebuild with MERGED_BINARY_TYPE=none to avoid the
# debug dylib pattern that crashes on legacy runtimes' libdispatch.
build_rosettasim() {
    echo "Building for RosettaSim (x86_64, no mergeable libraries)..." >&2

    if [ ! -d "$XCODE26" ]; then
        echo "Xcode 26 not found at $XCODE26" >&2
        exit 1
    fi
    export DEVELOPER_DIR="$XCODE26/Contents/Developer"

    local XCODE_MAJOR
    XCODE_MAJOR=$("$DEVELOPER_DIR/usr/bin/xcodebuild" -version | awk '/^Xcode / { split($2, v, "."); print v[1] }')
    if [[ -n "$XCODE_MAJOR" && "$XCODE_MAJOR" -ge 27 ]]; then
        echo "RosettaSim iOS 9-14 builds require macOS 26 with Xcode 26." >&2
        echo "Xcode $XCODE_MAJOR rejects simulator deployment targets below iOS 15, and macOS 27 cannot boot the x86-only legacy runtimes." >&2
        echo "Use scripts/build.sh device for the iOS 9-compatible physical armv7/arm64 product on this host." >&2
        exit 1
    fi

    local BUILD_DIR="$PROJECT_DIR/build/rosettasim"

    xcodebuild \
        -project "$PROJECT_DIR/HADashboard.xcodeproj" \
        -scheme HADashboard \
        -sdk iphonesimulator \
        -configuration Debug \
        -derivedDataPath "$BUILD_DIR" \
        ARCHS=x86_64 \
        VALID_ARCHS=x86_64 \
        ONLY_ACTIVE_ARCH=NO \
        IPHONEOS_DEPLOYMENT_TARGET=9.0 \
        "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" \
        "MARKETING_VERSION=$APP_VERSION" \
        "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
        MERGED_BINARY_TYPE=none \
        ENABLE_DEBUG_DYLIB=NO \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGN_IDENTITY="" \
        build 2>&1 | grep -E '(error:|BUILD)' | tail -5 >&2

    local APP="$BUILD_DIR/Build/Products/Debug-iphonesimulator/HA Dashboard.app"
    if [ ! -d "$APP" ]; then
        echo "Build failed" >&2
        exit 1
    fi

    echo "$APP"
}

# ── Universal device build (armv7+arm64) ──────────────────────────────
build_device() {
    echo "Building universal armv7+arm64 (modern Xcode clang + Xcode 13 SDK stubs)..." >&2

    if [ ! -d "$XCODE26" ]; then
        echo "Modern Xcode not found at $XCODE26" >&2
        exit 1
    fi
    export DEVELOPER_DIR="$XCODE26/Contents/Developer"
    local CLANG="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    local DSYMUTIL="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/dsymutil"
    local XCODE26_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
    local XCODE13_SDK="${XCODE13_SDK_PATH:-$XCODE13/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk}"
    if [ ! -d "$XCODE13_SDK" ]; then
        echo "Xcode 13.2.1 SDK not found at $XCODE13_SDK" >&2
        echo "Set XCODE13_SDK_PATH to an extracted iPhoneOS.sdk if using cached SDK stubs." >&2
        exit 1
    fi
    echo "   iOS 9 link SDK: $XCODE13_SDK" >&2
    local SDK_VER=$(plutil -extract Version raw "$XCODE26_SDK/SDKSettings.plist")
    local SRC_ICON="$PROJECT_DIR/HADashboard/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

    local BUILD_DIR="$PROJECT_DIR/build/universal"
    # Clean previous build to avoid stale artifacts
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # Collect include directories
    local INCLUDE_FLAGS=()
    while IFS= read -r dir; do
        INCLUDE_FLAGS+=("-I$PROJECT_DIR/$dir")
    done < <(find HADashboard Vendor -type d \
        -not -path '*/iOSSnapshotTestCase/*' \
        -not -path '*/MDI/*' \
        -not -path '*/.git/*' \
        -not -path '*/Assets.xcassets/*' 2>/dev/null)

    # Collect source files
    local SOURCES=()
    while IFS= read -r src; do
        SOURCES+=("$src")
    done < <(find HADashboard Vendor -name '*.m' \
        -not -path '*/iOSSnapshotTestCase/*' \
        -not -path '*/MDI/*' 2>/dev/null)

    # Xcode 27 no longer lets xcodebuild target pre-iOS 15, so compile both
    # device slices directly with the modern compiler and link against the
    # Xcode 13 SDK stubs. The Xcode build below is retained only as the signed
    # bundle/resource template.
    compile_ios9_slice() {
        local arch="$1"
        local target="$arch-apple-ios9.0"
        local object_dir="$BUILD_DIR/$arch-obj"
        local architecture_flags=()
        local errors=0
        local compiled=0
        if [[ "$arch" == "armv7" ]]; then
            # Xcode 27 ld can drop Thumb mode bits from LC_MAIN and Objective-C
            # method IMP relocations. Compile the legacy slice in ARM mode so
            # every even entry point is unambiguous on A5/A6-era devices.
            architecture_flags=(-marm)
        fi
        mkdir -p "$object_dir"
        echo "   Compiling $arch objects for iOS 9..." >&2

        for src in "${SOURCES[@]}"; do
            local object_name
            local compile_output
            object_name=$(echo "$src" | sed 's|/|_|g; s|\.m$|.o|')
            if compile_output=$("$CLANG" \
                --target="$target" \
                -isysroot "$XCODE26_SDK" \
                -x objective-c -fobjc-arc -fmodules -Os -DNDEBUG -g \
                -Werror=unguarded-availability \
                ${architecture_flags[@]+"${architecture_flags[@]}"} \
                "${INCLUDE_FLAGS[@]}" \
                -c "$PROJECT_DIR/$src" -o "$object_dir/$object_name" 2>&1); then
                compiled=$((compiled + 1))
            else
                errors=$((errors + 1))
                if [ "$errors" -le 3 ]; then
                    echo "   FAIL ($arch): $src" >&2
                    if [[ -n "$compile_output" ]]; then
                        printf '%s\n' "$compile_output" | sed -n '1,12p' >&2
                    else
                        echo "   Compiler exited without a diagnostic." >&2
                    fi
                fi
            fi
        done

        if [ "$errors" -gt 0 ]; then
            echo "$arch compile failed: $compiled/$((compiled + errors)) files" >&2
            exit 1
        fi

        echo "   Linking $arch for iOS 9..." >&2
        "$CLANG" \
            --target="$target" \
            -isysroot "$XCODE13_SDK" \
            -framework Foundation -framework UIKit -framework CoreFoundation \
            -framework CoreGraphics -framework CoreText -framework QuartzCore \
            -framework Security -framework CFNetwork -framework AVFoundation \
            -framework AudioToolbox -framework CoreMedia -framework CoreVideo \
            -framework VideoToolbox \
            -fobjc-arc -dead_strip \
            ${architecture_flags[@]+"${architecture_flags[@]}"} \
            -Xlinker -platform_version -Xlinker ios -Xlinker 9.0 -Xlinker "$SDK_VER" \
            "$object_dir"/*.o \
            -o "$BUILD_DIR/$arch-thin"
        echo "   $arch slice: $(du -h "$BUILD_DIR/$arch-thin" | cut -f1)" >&2
    }

    # ── Step 1: Build true iOS 9 armv7 and arm64 executables ───────────
    compile_ios9_slice armv7
    compile_ios9_slice arm64

    assert_ios9_slice() {
        local binary="$1"
        local arch="$2"
        local actual_arch
        local minimum
        actual_arch=$(lipo -archs "$binary")
        if [[ "$actual_arch" != "$arch" ]]; then
            echo "Unexpected architecture for $binary: $actual_arch (expected $arch)" >&2
            exit 1
        fi
        minimum=$(otool -l -arch "$arch" "$binary" | awk '
            $1 == "cmd" && $2 == "LC_VERSION_MIN_IPHONEOS" { wanted = 1; next }
            wanted && $1 == "version" { print $2; wanted = 0 }
        ')
        if [[ "$minimum" != "9.0" ]]; then
            echo "$arch slice minimum is '${minimum:-missing}', expected 9.0" >&2
            exit 1
        fi
        if [[ "$arch" == "armv7" ]]; then
            local entryoff
            entryoff=$(otool -l -arch armv7 "$binary" | awk '
                $1 == "cmd" && $2 == "LC_MAIN" { wanted = 1; next }
                wanted && $1 == "entryoff" { print $2; exit }
            ')
            if [[ -z "$entryoff" || $((entryoff % 2)) -ne 0 ]]; then
                echo "armv7 ARM-mode LC_MAIN entryoff is unexpectedly odd: ${entryoff:-missing}" >&2
                exit 1
            fi
            if nm -arch armv7 -m "$binary" | grep ' _main$' | grep -q '\[Thumb\]'; then
                echo "armv7 main is unexpectedly marked as Thumb" >&2
                exit 1
            fi
        fi
    }
    assert_ios9_slice "$BUILD_DIR/armv7-thin" armv7
    assert_ios9_slice "$BUILD_DIR/arm64-thin" arm64

    if [[ "${HADASHBOARD_SLICES_ONLY:-NO}" == "YES" ]]; then
        lipo -create "$BUILD_DIR/armv7-thin" "$BUILD_DIR/arm64-thin" \
            -output "$BUILD_DIR/universal-thin"
        echo "   Verified iOS 9 armv7+arm64 release slices" >&2
        echo "$BUILD_DIR"
        return
    fi

    # ── Step 2: Build a signed arm64 bundle/resource template ──────────
    echo "   Building signed bundle template..." >&2
    local ARM64_BUILD="$BUILD_DIR/arm64"

    local SIGNING_FLAGS=(
        CODE_SIGN_IDENTITY="Apple Development"
        "DEVELOPMENT_TEAM=$APPLE_TEAM_ID"
    )
    local PROVISIONING_UPDATE_FLAGS=()
    local DEVICE_DESTINATION_FLAGS=()
    local APP_STORE_CONNECT_FLAGS=()
    local SIGNING_STYLE="${HADASHBOARD_FORCE_SIGNING_STYLE:-${HADASHBOARD_SIGNING_STYLE:-manual}}"
    local SIGNING_DEVICE_ID="${HADASHBOARD_FORCE_SIGNING_DEVICE_ID:-${HADASHBOARD_SIGNING_DEVICE_ID:-}}"
    if [[ "$SIGNING_STYLE" == "automatic" ]]; then
        # Use when a newly connected device is absent from the named local
        # profile. This permits Xcode to fetch/create a matching development
        # profile for the user-selected team during an authorized deployment.
        SIGNING_FLAGS+=(CODE_SIGN_STYLE=Automatic)
        PROVISIONING_UPDATE_FLAGS=(-allowProvisioningUpdates -allowProvisioningDeviceRegistration)
        if [[ -n "$SIGNING_DEVICE_ID" ]]; then
            # Xcode destinations require the physical hardware UDID (for
            # example 000081xx-...), not devicectl's CoreDevice UUID.
            DEVICE_DESTINATION_FLAGS=(-destination "id=${SIGNING_DEVICE_ID}")
        fi
        if [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
            APP_STORE_CONNECT_FLAGS=(
                -authenticationKeyPath "$ASC_KEY_PATH"
                -authenticationKeyID "$ASC_KEY_ID"
                -authenticationKeyIssuerID "$ASC_ISSUER_ID"
            )
        fi
    else
        SIGNING_FLAGS+=(CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER="HADashboard Development")
    fi

    xcodebuild \
        -project "$PROJECT_DIR/HADashboard.xcodeproj" \
        -scheme HADashboard \
        ${APP_STORE_CONNECT_FLAGS[@]+"${APP_STORE_CONNECT_FLAGS[@]}"} \
        -sdk iphoneos \
        ${DEVICE_DESTINATION_FLAGS[@]+"${DEVICE_DESTINATION_FLAGS[@]}"} \
        -configuration Debug \
        -derivedDataPath "$ARM64_BUILD" \
        ARCHS=arm64 \
        VALID_ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=NO \
        IPHONEOS_DEPLOYMENT_TARGET=15.0 \
        "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" \
        "MARKETING_VERSION=$APP_VERSION" \
        "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
        "${SIGNING_FLAGS[@]}" \
        ${PROVISIONING_UPDATE_FLAGS[@]+"${PROVISIONING_UPDATE_FLAGS[@]}"} \
        build 2>&1 | grep -E '(error:|BUILD)' | tail -5 >&2

    local ARM64_APP="$ARM64_BUILD/Build/Products/Debug-iphoneos/HA Dashboard.app"
    if [ ! -d "$ARM64_APP" ]; then
        echo "arm64 build failed" >&2
        exit 1
    fi
    echo "   Bundle template: $(du -sh "$ARM64_APP" | cut -f1)" >&2

    # ── Step 3: Create universal app bundle ────────────────────────────
    echo "   Merging universal binary..." >&2
    local APP="$BUILD_DIR/HA Dashboard.app"
    rm -rf "$APP"
    cp -R "$ARM64_APP" "$APP"

    # Merge binaries
    lipo -create "$BUILD_DIR/armv7-thin" "$BUILD_DIR/arm64-thin" \
        -output "$APP/HA Dashboard.tmp"
    mv "$APP/HA Dashboard.tmp" "$APP/HA Dashboard"

    # Recompile LaunchScreen for iOS 9 compatibility
    echo "   Recompiling LaunchScreen for iOS 9..." >&2
    xcrun ibtool --compile "$APP/LaunchScreen.storyboardc" \
        "$PROJECT_DIR/HADashboard/LaunchScreen.storyboard" \
        --minimum-deployment-target 9.0 \
        --target-device ipad --target-device iphone 2>/dev/null

    # Patch Info.plist
    echo "   Patching Info.plist..." >&2
    local PLIST="$APP/Info.plist"
    plutil -replace MinimumOSVersion -string "9.0" "$PLIST"
    plutil -remove UIRequiredDeviceCapabilities "$PLIST" 2>/dev/null || true
    plutil -insert UIRequiredDeviceCapabilities -json '["armv7"]' "$PLIST"
    plutil -remove UILaunchScreen "$PLIST" 2>/dev/null || true
    plutil -replace UILaunchStoryboardName -string "LaunchScreen" "$PLIST" 2>/dev/null || \
        plutil -insert UILaunchStoryboardName -string "LaunchScreen" "$PLIST"

    # Add iPad icon references
    plutil -remove 'CFBundleIcons~ipad.CFBundlePrimaryIcon.CFBundleIconFiles' "$PLIST" 2>/dev/null || true
    plutil -insert 'CFBundleIcons~ipad.CFBundlePrimaryIcon.CFBundleIconFiles' \
        -json '["AppIcon60x60","AppIcon76x76","AppIcon83.5x83.5"]' "$PLIST" 2>/dev/null || true

    # Add standalone icon PNGs
    if [ -f "$SRC_ICON" ]; then
        echo "   Generating icon PNGs..." >&2
        sips -z 76 76 "$SRC_ICON" --out "$APP/AppIcon76x76~ipad.png" >/dev/null 2>&1
        sips -z 152 152 "$SRC_ICON" --out "$APP/AppIcon76x76@2x~ipad.png" >/dev/null 2>&1
        sips -z 167 167 "$SRC_ICON" --out "$APP/AppIcon83.5x83.5@2x~ipad.png" >/dev/null 2>&1
        sips -z 120 120 "$SRC_ICON" --out "$APP/AppIcon60x60@2x.png" >/dev/null 2>&1
        sips -z 180 180 "$SRC_ICON" --out "$APP/AppIcon60x60@3x.png" >/dev/null 2>&1
    fi

    # Generate one dSYM from the final replacement executable so both UUIDs
    # match the shipped armv7/arm64 slices. The Xcode template dSYM belongs to
    # the discarded iOS 15 executable and must not be reused.
    echo "   Generating universal dSYM..." >&2
    "$DSYMUTIL" "$APP/HA Dashboard" -o "$BUILD_DIR/HA Dashboard.app.dSYM"

    # Re-sign with entitlements from arm64 build
    echo "   Re-signing..." >&2
    local IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')
    if [ -n "$IDENTITY" ]; then
        # Extract entitlements from arm64 binary
        local ENTITLEMENTS="$BUILD_DIR/entitlements.plist"
        codesign -d --entitlements :- "$ARM64_APP" > "$ENTITLEMENTS" 2>/dev/null

        # Copy embedded provisioning profile from arm64 build
        if [ -f "$ARM64_APP/embedded.mobileprovision" ]; then
            cp "$ARM64_APP/embedded.mobileprovision" "$APP/"
        fi

        # Re-sign with entitlements
        codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" --timestamp=none "$APP" >&2
    else
        echo "   Warning: No signing identity found, app may need manual signing" >&2
    fi

    local FINAL_ARCHS
    FINAL_ARCHS=$(lipo -archs "$APP/HA Dashboard")
    if [[ "$FINAL_ARCHS" != "armv7 arm64" ]]; then
        echo "Unexpected universal architecture set: $FINAL_ARCHS" >&2
        exit 1
    fi
    assert_ios9_slice "$BUILD_DIR/armv7-thin" armv7
    assert_ios9_slice "$BUILD_DIR/arm64-thin" arm64
    if [[ "$(plutil -extract MinimumOSVersion raw "$PLIST")" != "9.0" ]]; then
        echo "Bundle MinimumOSVersion is not 9.0" >&2
        exit 1
    fi
    if [[ ! -f "$APP/PrivacyInfo.xcprivacy" ]]; then
        echo "PrivacyInfo.xcprivacy is missing from the iOS app root" >&2
        exit 1
    fi
    plutil -lint "$APP/PrivacyInfo.xcprivacy" >/dev/null

    local BINARY_UUIDS
    local DSYM_UUIDS
    BINARY_UUIDS=$(dwarfdump --uuid "$APP/HA Dashboard" | awk '{print $2, $3}' | sort)
    DSYM_UUIDS=$(dwarfdump --uuid "$BUILD_DIR/HA Dashboard.app.dSYM" | awk '{print $2, $3}' | sort)
    if [[ "$BINARY_UUIDS" != "$DSYM_UUIDS" ]]; then
        echo "Universal dSYM UUIDs do not match the final executable" >&2
        exit 1
    fi
    if [[ -n "$IDENTITY" ]]; then
        codesign --verify --deep --strict "$APP"
    fi

    echo "   Universal binary: $FINAL_ARCHS" >&2
    echo "   MinOS: 9.0 (armv7, arm64, and bundle)" >&2

    echo "$APP"
}

# ── Mac Catalyst build (arm64, macOS) ──────────────────────────────────
build_mac() {
    echo "Building for Mac Catalyst (arm64)..." >&2

    if [ ! -d "$XCODE26" ]; then
        echo "Xcode not found at $XCODE26" >&2
        exit 1
    fi
    export DEVELOPER_DIR="$XCODE26/Contents/Developer"

    local BUILD_DIR="$PROJECT_DIR/build/mac"
    # Catalyst derives macOS 10.15 from the app's iOS 9 target. Xcode 27 no
    # longer supports that macOS SDK target, so lift *only Catalyst* to iOS 15
    # (macOS 12 equivalent); the standalone iOS product stays at iOS 9.
    local CATALYST_IOS_MIN="${CATALYST_IPHONEOS_DEPLOYMENT_TARGET:-15.0}"

    local SIGNING_FLAGS=(
        CODE_SIGN_IDENTITY="Apple Development"
        CODE_SIGN_STYLE=Automatic
        "DEVELOPMENT_TEAM=$APPLE_TEAM_ID"
    )
    local APP_STORE_CONNECT_FLAGS=()
    if [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
        APP_STORE_CONNECT_FLAGS=(
            -authenticationKeyPath "$ASC_KEY_PATH"
            -authenticationKeyID "$ASC_KEY_ID"
            -authenticationKeyIssuerID "$ASC_ISSUER_ID"
        )
    fi

    xcodebuild \
        -project "$PROJECT_DIR/HADashboard.xcodeproj" \
        -scheme HADashboard \
        ${APP_STORE_CONNECT_FLAGS[@]+"${APP_STORE_CONNECT_FLAGS[@]}"} \
        -allowProvisioningUpdates \
        -destination 'platform=macOS,variant=Mac Catalyst' \
        -configuration Debug \
        -derivedDataPath "$BUILD_DIR" \
        ARCHS=arm64 \
        ONLY_ACTIVE_ARCH=YES \
        ENABLE_DEBUG_DYLIB=NO \
        MERGED_BINARY_TYPE=none \
        "IPHONEOS_DEPLOYMENT_TARGET=$CATALYST_IOS_MIN" \
        "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" \
        "MARKETING_VERSION=$APP_VERSION" \
        "CURRENT_PROJECT_VERSION=$BUILD_NUMBER" \
        "${SIGNING_FLAGS[@]}" \
        clean build 2>&1 | grep -E '(error:|BUILD)' | tail -5 >&2

    local APP="$BUILD_DIR/Build/Products/Debug-maccatalyst/HA Dashboard.app"
    if [ ! -d "$APP" ]; then
        echo "Build failed" >&2
        exit 1
    fi
    local EXECUTABLE="$APP/Contents/MacOS/HA Dashboard"
    if [[ ! -f "$EXECUTABLE" || -f "$APP/Contents/MacOS/HA Dashboard.debug.dylib" ]]; then
        echo "Catalyst build must contain one non-mergeable main executable" >&2
        exit 1
    fi
    if [[ $(stat -f %z "$EXECUTABLE") -lt 1000000 ]]; then
        echo "Catalyst main executable is unexpectedly small" >&2
        exit 1
    fi
    if [[ ! -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy" ]]; then
        echo "PrivacyInfo.xcprivacy is missing from Catalyst resources" >&2
        exit 1
    fi
    plutil -lint "$APP/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null
    codesign --verify --deep --strict "$APP"

    echo "$APP"
}

# ── Main ──────────────────────────────────────────────────────────────
case "$TARGET" in
    sim|simulator)
        build_simulator
        ;;
    rosettasim)
        build_rosettasim
        ;;
    device|universal)
        build_device
        ;;
    mac|catalyst)
        build_mac
        ;;
    *)
        echo "Unknown target: $TARGET" >&2
        echo "Use 'sim', 'rosettasim', 'device', or 'mac'" >&2
        exit 1
        ;;
esac
