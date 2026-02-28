#!/bin/bash
set -euo pipefail

# HA Dashboard Build Script
#
# Builds the app for simulator or device.
#
# Usage:
#   scripts/build.sh sim           # Simulator build (arm64, iOS 15+)
#   scripts/build.sh rosettasim    # Legacy simulator build (x86_64, iOS 9.0+, RosettaSim)
#   scripts/build.sh device        # Universal device build (armv7+arm64)
#
# The rosettasim target builds with Xcode 26 xcodebuild but sets
# MERGED_BINARY_TYPE=none to disable mergeable libraries — the default
# Debug stub+dylib pattern crashes on legacy runtimes' libdispatch.
#
# Output:
#   Prints the path to the built .app on success

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODE13="/Applications/Xcode-13.2.1.app"
XCODE26="/Applications/Xcode.app"

# ── Load .env ─────────────────────────────────────────────────────────
if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a; source "$PROJECT_DIR/.env"; set +a
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
    echo "Usage: scripts/build.sh <sim|device>"
    echo ""
    echo "Targets:"
    echo "  sim      Simulator build (arm64, Xcode 26)"
    echo "  device   Universal device build (armv7+arm64, matches CI)"
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
    echo "Building universal armv7+arm64 (Xcode 26 clang + Xcode 13 SDK)..." >&2

    if [ ! -d "$XCODE26" ]; then
        echo "Xcode 26 not found at $XCODE26" >&2
        exit 1
    fi
    if [ ! -d "$XCODE13" ]; then
        echo "Xcode 13.2.1 not found at $XCODE13 (needed for armv7 linking)" >&2
        exit 1
    fi

    export DEVELOPER_DIR="$XCODE26/Contents/Developer"
    local CLANG="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
    local DSYMUTIL="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/dsymutil"
    local XCODE26_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
    local XCODE13_SDK="$XCODE13/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
    local SDK_VER=$(plutil -extract Version raw "$XCODE26_SDK/SDKSettings.plist")
    local SRC_ICON="$PROJECT_DIR/HADashboard/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

    local BUILD_DIR="$PROJECT_DIR/build/universal"
    # Clean previous build to avoid stale artifacts
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    # ── Step 1: Compile armv7 with Xcode 26 clang ──────────────────────
    echo "   Compiling armv7 objects..." >&2

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

    # Compile all .m files
    mkdir -p "$BUILD_DIR/armv7-obj"
    local ERRORS=0
    local COMPILED=0
    for src in "${SOURCES[@]}"; do
        local OBJ_NAME=$(echo "$src" | sed 's|/|_|g; s|\.m$|.o|')
        if "$CLANG" \
            --target=armv7-apple-ios9.0 \
            -isysroot "$XCODE26_SDK" \
            -x objective-c -fobjc-arc -fmodules -Os -DNDEBUG -g -w \
            "${INCLUDE_FLAGS[@]}" \
            -c "$PROJECT_DIR/$src" -o "$BUILD_DIR/armv7-obj/$OBJ_NAME" 2>/dev/null; then
            COMPILED=$((COMPILED + 1))
        else
            ERRORS=$((ERRORS + 1))
            if [ $ERRORS -le 3 ]; then
                echo "   FAIL: $src" >&2
                "$CLANG" --target=armv7-apple-ios9.0 -isysroot "$XCODE26_SDK" \
                    -x objective-c -fobjc-arc -fmodules -Os -DNDEBUG \
                    "${INCLUDE_FLAGS[@]}" -c "$PROJECT_DIR/$src" -o /dev/null 2>&1 | grep 'error:' | head -3 >&2
            fi
        fi
    done

    if [ $ERRORS -gt 0 ]; then
        echo "armv7 compile failed: $COMPILED/$((COMPILED + ERRORS)) files" >&2
        exit 1
    fi
    echo "   Compiled $COMPILED files" >&2

    # Link against Xcode 13 SDK with platform_version override
    echo "   Linking armv7..." >&2
    "$CLANG" \
        --target=armv7-apple-ios9.0 \
        -isysroot "$XCODE13_SDK" \
        -framework Foundation -framework UIKit -framework CoreFoundation \
        -framework CoreGraphics -framework CoreText -framework QuartzCore \
        -framework Security -framework CFNetwork \
        -fobjc-arc -dead_strip \
        -Xlinker -platform_version -Xlinker ios -Xlinker 9.0 -Xlinker "$SDK_VER" \
        "$BUILD_DIR/armv7-obj"/*.o \
        -o "$BUILD_DIR/armv7-thin"

    # Generate armv7 dSYM
    "$DSYMUTIL" "$BUILD_DIR/armv7-thin" -o "$BUILD_DIR/armv7.dSYM"
    mv "$BUILD_DIR/armv7.dSYM/Contents/Resources/DWARF/armv7-thin" \
       "$BUILD_DIR/armv7.dSYM/Contents/Resources/DWARF/HA Dashboard" 2>/dev/null || true

    echo "   armv7 slice: $(du -h "$BUILD_DIR/armv7-thin" | cut -f1)" >&2

    # ── Step 2: Build arm64 with Xcode 26 xcodebuild ───────────────────
    echo "   Building arm64..." >&2
    local ARM64_BUILD="$BUILD_DIR/arm64"

    local SIGNING_FLAGS=(
        CODE_SIGN_IDENTITY="Apple Development"
        CODE_SIGN_STYLE=Manual
        "DEVELOPMENT_TEAM=$APPLE_TEAM_ID"
        PROVISIONING_PROFILE_SPECIFIER="HADashboard Development"
    )

    xcodebuild \
        -project "$PROJECT_DIR/HADashboard.xcodeproj" \
        -scheme HADashboard \
        -sdk iphoneos \
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
        build 2>&1 | grep -E '(error:|BUILD)' | tail -5 >&2

    local ARM64_APP="$ARM64_BUILD/Build/Products/Debug-iphoneos/HA Dashboard.app"
    if [ ! -d "$ARM64_APP" ]; then
        echo "arm64 build failed" >&2
        exit 1
    fi
    echo "   arm64 slice: $(du -h "$ARM64_APP/HA Dashboard" | cut -f1)" >&2

    # ── Step 3: Create universal app bundle ────────────────────────────
    echo "   Merging universal binary..." >&2
    local APP="$BUILD_DIR/HA Dashboard.app"
    rm -rf "$APP"
    cp -R "$ARM64_APP" "$APP"

    # Merge binaries
    lipo -create "$BUILD_DIR/armv7-thin" "$APP/HA Dashboard" \
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

    # Merge dSYMs
    local ARM64_DSYM="$ARM64_BUILD/Build/Products/Debug-iphoneos/HA Dashboard.app.dSYM"
    if [ -d "$ARM64_DSYM" ] && [ -d "$BUILD_DIR/armv7.dSYM" ]; then
        echo "   Merging dSYMs..." >&2
        local DSYM_OUT="$BUILD_DIR/HA Dashboard.app.dSYM"
        cp -R "$ARM64_DSYM" "$DSYM_OUT"
        local ARM64_DWARF="$DSYM_OUT/Contents/Resources/DWARF/HA Dashboard"
        local ARMV7_DWARF="$BUILD_DIR/armv7.dSYM/Contents/Resources/DWARF/HA Dashboard"
        if [ -f "$ARM64_DWARF" ] && [ -f "$ARMV7_DWARF" ]; then
            lipo -create "$ARMV7_DWARF" "$ARM64_DWARF" -output "${ARM64_DWARF}.universal"
            mv "${ARM64_DWARF}.universal" "$ARM64_DWARF"
        fi
    fi

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

    echo "   Universal binary: $(lipo -archs "$APP/HA Dashboard")" >&2
    echo "   MinOS: $(plutil -extract MinimumOSVersion raw "$PLIST")" >&2

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
    *)
        echo "Unknown target: $TARGET" >&2
        echo "Use 'sim', 'rosettasim', or 'device'" >&2
        exit 1
        ;;
esac
