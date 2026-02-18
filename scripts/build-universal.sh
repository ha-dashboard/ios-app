#!/bin/bash
set -euo pipefail

# Build a universal armv7+arm64 IPA using a single Xcode toolchain.
#
# Both slices are compiled with Xcode 26's clang against the iOS 26 SDK.
# The armv7 slice bypasses xcodebuild's deprecated-architecture check by
# invoking clang directly, then links against Xcode 13's TBD stubs (which
# still have armv7 symbols) with -platform_version to stamp sdk=26.2.
#
# This produces a binary where BOTH slices report sdk=26.2 in their Mach-O
# headers, which is required for App Store Connect validation.
#
# Requirements:
#   - Xcode 26 (compiler, linker, SDK headers, arm64 build)
#   - Xcode 13.2.1 (armv7 TBD stubs for linking only)
#
# Usage:
#   scripts/build-universal.sh                    # Unsigned universal IPA
#   scripts/build-universal.sh --sign             # Development-signed
#   scripts/build-universal.sh --sign --ota URL   # + OTA install manifest

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODE13="/Applications/Xcode-13.2.1.app"
XCODE26="/Applications/Xcode.app"
BUILD_DIR="$PROJECT_DIR/build/universal"
SIGN=false
OTA_URL=""
EXEC="HA Dashboard"

# ── Parse args ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign) SIGN=true; shift ;;
        --ota)  OTA_URL="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: scripts/build-universal.sh [--sign] [--ota URL]"
            echo ""
            echo "  --sign     Sign with local Apple Development identity"
            echo "  --ota URL  Generate OTA manifest (itms-services://) for URL"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ── Load .env ─────────────────────────────────────────────────────────
if [[ -f "$PROJECT_DIR/.env" ]]; then
    set -a; source "$PROJECT_DIR/.env"; set +a
fi

BUNDLE_ID="${BUNDLE_ID:-com.ashhopkins.hadashboard}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"

# ── Validate ──────────────────────────────────────────────────────────
if [ ! -d "$XCODE26" ]; then
    echo "❌ Xcode 26 not found at $XCODE26"
    exit 1
fi

XCODE13_SDK="$XCODE13/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
if [ ! -d "$XCODE13_SDK" ]; then
    # Try versioned SDK path
    XCODE13_SDK=$(find "$XCODE13/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs" -maxdepth 1 -name "iPhoneOS*.sdk" 2>/dev/null | head -1)
fi
if [ ! -d "$XCODE13_SDK" ]; then
    echo "❌ Xcode 13.2.1 SDK not found (needed for armv7 TBD stubs)"
    echo "   Install: xcodes install 13.2.1"
    exit 1
fi

XCODE26_DEV="$XCODE26/Contents/Developer"
XCODE26_SDK="$XCODE26_DEV/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"
if [ ! -d "$XCODE26_SDK" ]; then
    XCODE26_SDK=$(find "$XCODE26_DEV/Platforms/iPhoneOS.platform/Developer/SDKs" -maxdepth 1 -name "iPhoneOS*.sdk" 2>/dev/null | head -1)
fi
CLANG="$XCODE26_DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
SDK_VER=$(plutil -extract Version raw "$XCODE26_SDK/SDKSettings.plist" 2>/dev/null || echo "26.x")

VERSION="$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo '1.0.0')"
BUILD_NUM="$(git -C "$PROJECT_DIR" rev-list --count HEAD)"

echo "Universal build v${VERSION} (${BUILD_NUM})"
echo "  armv7 → clang direct (Xcode 26 SDK $SDK_VER, iOS 9.0)"
echo "  arm64 → xcodebuild (Xcode 26, iOS 15.0)"
echo ""

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ── Step 1: Build armv7 slice with Xcode 26's clang ──────────────────
echo "━━ [1/5] Building armv7 (clang direct, sdk=$SDK_VER)..."

# Xcode 26's xcodebuild blocks armv7 as "deprecated", but its clang still
# has the ARM 32-bit backend. We compile all .m files directly with clang
# against Xcode 26's SDK headers (getting sdk=26.2 in Mach-O), then link
# against Xcode 13's TBD stubs (which include armv7 symbols) with
# -platform_version to override the SDK stamp in the linked binary.

ARMV7_OBJ="$BUILD_DIR/armv7-obj"
mkdir -p "$ARMV7_OBJ"

# Collect all include directories from project sources
INCLUDE_FLAGS=()
while IFS= read -r dir; do
    INCLUDE_FLAGS+=("-I$PROJECT_DIR/$dir")
done < <(find HADashboard Vendor -type d \
    -not -path '*/iOSSnapshotTestCase/*' \
    -not -path '*/MDI/*' \
    -not -path '*/.git/*' \
    -not -path '*/Assets.xcassets/*')

# Collect all .m source files
SOURCES=()
while IFS= read -r src; do
    SOURCES+=("$src")
done < <(find HADashboard Vendor -name '*.m' \
    -not -path '*/iOSSnapshotTestCase/*' \
    -not -path '*/MDI/*')

ERRORS=0
COMPILED=0
for src in "${SOURCES[@]}"; do
    OBJ_NAME=$(echo "$src" | sed 's|/|_|g; s|\.m$|.o|')
    if "$CLANG" \
        --target=armv7-apple-ios9.0 \
        -isysroot "$XCODE26_SDK" \
        -x objective-c \
        -fobjc-arc \
        -fmodules \
        -Os \
        -DNDEBUG \
        -g \
        -w \
        "${INCLUDE_FLAGS[@]}" \
        -c "$PROJECT_DIR/$src" \
        -o "$ARMV7_OBJ/$OBJ_NAME" 2>/dev/null; then
        COMPILED=$((COMPILED + 1))
    else
        ERRORS=$((ERRORS + 1))
        # Re-run with errors visible for the first failure
        if [ $ERRORS -eq 1 ]; then
            echo "  First error:"
            "$CLANG" \
                --target=armv7-apple-ios9.0 \
                -isysroot "$XCODE26_SDK" \
                -x objective-c -fobjc-arc -fmodules -Os -DNDEBUG \
                "${INCLUDE_FLAGS[@]}" \
                -c "$PROJECT_DIR/$src" -o /dev/null 2>&1 | grep 'error:' | head -3
        fi
    fi
done

if [ $ERRORS -gt 0 ]; then
    echo "❌ armv7 compile failed: $COMPILED/$((COMPILED + ERRORS)) files"
    exit 1
fi
echo "  Compiled $COMPILED files"

# Link against Xcode 13's TBD stubs (which have armv7 entries) but override
# the SDK version stamp to match the modern SDK.
ARMV7_THIN="$BUILD_DIR/armv7-thin"
"$CLANG" \
    --target=armv7-apple-ios9.0 \
    -isysroot "$XCODE13_SDK" \
    -framework Foundation \
    -framework UIKit \
    -framework CoreFoundation \
    -framework CoreGraphics \
    -framework CoreText \
    -framework QuartzCore \
    -framework Security \
    -framework CFNetwork \
    -fobjc-arc \
    -dead_strip \
    -Xlinker -platform_version -Xlinker ios -Xlinker 9.0 -Xlinker "$SDK_VER" \
    "$ARMV7_OBJ"/*.o \
    -o "$ARMV7_THIN" 2>&1

if [ ! -f "$ARMV7_THIN" ]; then
    echo "❌ armv7 link failed"
    exit 1
fi

# Verify
if ! file "$ARMV7_THIN" | grep -q "arm_v7"; then
    echo "❌ Expected armv7 slice, got:"
    file "$ARMV7_THIN"
    exit 1
fi
# Generate dSYM for armv7 slice (rename DWARF to match the final executable name)
DSYMUTIL="$XCODE26_DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/dsymutil"
"$DSYMUTIL" "$ARMV7_THIN" -o "$BUILD_DIR/armv7.dSYM" 2>/dev/null
# dsymutil names the DWARF file after the input ("armv7-thin"); rename to match the app
ARMV7_DWARF_DIR="$BUILD_DIR/armv7.dSYM/Contents/Resources/DWARF"
if [ -f "$ARMV7_DWARF_DIR/armv7-thin" ]; then
    mv "$ARMV7_DWARF_DIR/armv7-thin" "$ARMV7_DWARF_DIR/$EXEC"
fi

echo "  ✓ armv7 slice: $(du -h "$ARMV7_THIN" | cut -f1) (sdk=$SDK_VER)"

# ── Step 2: Build arm64 slice with Xcode 26 ──────────────────────────
echo "━━ [2/5] Building arm64 (Xcode 26)..."

# When --sign is requested, build WITH signing so Xcode embeds the provisioning
# profile and we can extract entitlements for the final re-sign after lipo merge.
ARM64_SIGNING_FLAGS=(CODE_SIGNING_ALLOWED=NO "CODE_SIGN_IDENTITY=")
if [[ "$SIGN" == true ]]; then
    ASC_KEY_EXPANDED="${ASC_KEY_PATH/#\~/$HOME}"
    ARM64_AUTH_FLAGS=()
    if [[ -n "${ASC_KEY_PATH:-}" && -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" ]]; then
        ARM64_AUTH_FLAGS=(
            -authenticationKeyPath "$ASC_KEY_EXPANDED"
            -authenticationKeyID "$ASC_KEY_ID"
            -authenticationKeyIssuerID "$ASC_ISSUER_ID"
            -allowProvisioningUpdates
        )
    fi
    ARM64_SIGNING_FLAGS=(
        CODE_SIGN_IDENTITY="Apple Development"
        CODE_SIGN_STYLE=Manual
        "DEVELOPMENT_TEAM=${APPLE_TEAM_ID}"
        PROVISIONING_PROFILE_SPECIFIER="HADashboard Development"
        "${ARM64_AUTH_FLAGS[@]}"
    )
fi

DEVELOPER_DIR="$XCODE26/Contents/Developer" xcodebuild \
    -project "$PROJECT_DIR/HADashboard.xcodeproj" \
    -scheme HADashboard \
    -sdk iphoneos \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/dd-arm64" \
    IPHONEOS_DEPLOYMENT_TARGET=15.0 \
    ARCHS=arm64 \
    VALID_ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUM" \
    "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" \
    "${ARM64_SIGNING_FLAGS[@]}" \
    build 2>&1 | grep -E '(error:|BUILD)' | tail -10

ARM64_APP="$BUILD_DIR/dd-arm64/Build/Products/Release-iphoneos/$EXEC.app"
if [ ! -f "$ARM64_APP/$EXEC" ]; then
    echo "❌ arm64 build failed — binary not found at:"
    echo "   $ARM64_APP/$EXEC"
    find "$BUILD_DIR/dd-arm64" -name "$EXEC" -type f 2>/dev/null | head -5
    exit 1
fi
echo "  ✓ arm64 slice: $(du -h "$ARM64_APP/$EXEC" | cut -f1)"

# ── Step 3: Merge with lipo ──────────────────────────────────────────
echo "━━ [3/5] Merging with lipo..."

MERGED_APP="$BUILD_DIR/app/$EXEC.app"
mkdir -p "$BUILD_DIR/app"

# Use arm64 .app as base — it has modern compiled resources, asset catalog,
# and the correct fonts/plists from Xcode 26
cp -R "$ARM64_APP" "$MERGED_APP"

# Replace the main executable with the universal binary
lipo -create \
    "$ARMV7_THIN" \
    "$ARM64_APP/$EXEC" \
    -output "$MERGED_APP/$EXEC"

ARCHS=$(lipo -archs "$MERGED_APP/$EXEC" 2>/dev/null)
if [[ "$ARCHS" != *"armv7"* ]] || [[ "$ARCHS" != *"arm64"* ]]; then
    echo "❌ Merge failed — expected armv7+arm64, got: $ARCHS"
    exit 1
fi
echo "  ✓ Universal binary: $ARCHS ($(du -h "$MERGED_APP/$EXEC" | cut -f1))"

# Merge dSYMs: combine armv7 and arm64 DWARF files into a universal dSYM
DSYM_DIR="$BUILD_DIR/dSYMs"
DSYM="$DSYM_DIR/$EXEC.app.dSYM"
mkdir -p "$DSYM/Contents/Resources/DWARF"
cp "$BUILD_DIR/armv7.dSYM/Contents/Info.plist" "$DSYM/Contents/Info.plist" 2>/dev/null || true

ARM64_DSYM=$(find "$BUILD_DIR/dd-arm64" -name "$EXEC.app.dSYM" -type d 2>/dev/null | head -1)
if [[ -n "$ARM64_DSYM" && -f "$BUILD_DIR/armv7.dSYM/Contents/Resources/DWARF/$EXEC" ]]; then
    lipo -create \
        "$BUILD_DIR/armv7.dSYM/Contents/Resources/DWARF/$EXEC" \
        "$ARM64_DSYM/Contents/Resources/DWARF/$EXEC" \
        -output "$DSYM/Contents/Resources/DWARF/$EXEC" 2>/dev/null
    echo "  ✓ dSYMs merged ($(dwarfdump --uuid "$DSYM/Contents/Resources/DWARF/$EXEC" 2>/dev/null | wc -l | tr -d ' ') UUIDs)"
elif [[ -f "$BUILD_DIR/armv7.dSYM/Contents/Resources/DWARF/$EXEC" ]]; then
    cp "$BUILD_DIR/armv7.dSYM/Contents/Resources/DWARF/$EXEC" "$DSYM/Contents/Resources/DWARF/$EXEC"
    echo "  ⚠ armv7 dSYM only (arm64 dSYM not found)"
else
    echo "  ⚠ No dSYMs generated"
fi

# Recompile LaunchScreen.storyboard targeting iOS 9.0.
# Xcode 26's xcodebuild compiles the storyboard for its deployment target (iOS 15),
# producing a NIBArchive format that iOS 9's UIKit cannot load (causes watchdog hang).
# Recompiling with --minimum-deployment-target 9.0 produces a backward-compatible NIB.
IBTOOL="$XCODE26_DEV/usr/bin/ibtool"
if [ -f "$PROJECT_DIR/HADashboard/LaunchScreen.storyboard" ] && [ -x "$IBTOOL" ]; then
    DEVELOPER_DIR="$XCODE26_DEV" "$IBTOOL" --compile "$MERGED_APP/LaunchScreen.storyboardc" \
        "$PROJECT_DIR/HADashboard/LaunchScreen.storyboard" \
        --minimum-deployment-target 9.0 \
        --target-device ipad --target-device iphone 2>/dev/null
    echo "  ✓ LaunchScreen.storyboardc recompiled for iOS 9.0"
fi

# ── Step 4: Reconcile Info.plist ──────────────────────────────────────
echo "━━ [4/5] Reconciling Info.plist..."

PLIST="$MERGED_APP/Info.plist"

# MinimumOSVersion = 9.0 so armv7 devices (iPad 2, iOS 9.3.5) accept the binary.
# Each Mach-O slice has its own LC_VERSION_MIN / LC_BUILD_VERSION — the runtime
# picks the correct slice per device, so arm64 code still targets iOS 15 internally.
plutil -replace MinimumOSVersion -string "9.0" "$PLIST"

# Remove the arm64 device capability requirement. [armv7] is satisfied by ALL
# iOS devices (arm64 is a superset of armv7 capability), so this doesn't
# restrict modern devices.
plutil -remove UIRequiredDeviceCapabilities "$PLIST" 2>/dev/null || true
plutil -insert UIRequiredDeviceCapabilities -json '["armv7"]' "$PLIST"

# Inject version (Info.plist has hardcoded 1.0/1 instead of $(MARKETING_VERSION))
plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$BUILD_NUM" "$PLIST"

echo "  ✓ MinimumOSVersion → 9.0"
echo "  ✓ UIRequiredDeviceCapabilities → [armv7]"
echo "  ✓ Version → $VERSION ($BUILD_NUM)"

# Show per-slice Mach-O metadata
echo ""
echo "  Per-slice Mach-O headers:"
for arch in armv7 arm64; do
    THIN_TMP=$(mktemp)
    lipo -thin "$arch" "$MERGED_APP/$EXEC" -output "$THIN_TMP" 2>/dev/null

    # LC_VERSION_MIN_IPHONEOS (armv7) or LC_BUILD_VERSION (arm64)
    MIN_VER=$(otool -l "$THIN_TMP" 2>/dev/null | \
        grep -A4 'LC_VERSION_MIN_IPHONEOS\|LC_BUILD_VERSION' | \
        grep -E '^\s+(minos|version)' | head -1 | awk '{print $2}')
    SDK_VER=$(otool -l "$THIN_TMP" 2>/dev/null | \
        grep -A4 'LC_VERSION_MIN_IPHONEOS\|LC_BUILD_VERSION' | \
        grep 'sdk' | head -1 | awk '{print $2}')

    printf "    %-6s  min=%-8s  sdk=%s\n" "$arch" "${MIN_VER:-?}" "${SDK_VER:-?}"
    rm -f "$THIN_TMP"
done
echo ""

# ── Step 5: Sign + Package ───────────────────────────────────────────
echo "━━ [5/5] Packaging..."

if [[ "$SIGN" == true ]]; then
    # The arm64 build was signed by Xcode, so the base .app already has
    # embedded.mobileprovision. We need to re-sign after swapping the binary.

    # Find signing identity
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | \
        grep "Apple Development" | head -1 | sed 's/.*"\(.*\)"/\1/')
    if [[ -z "$IDENTITY" ]]; then
        echo "❌ No 'Apple Development' signing identity found"
        security find-identity -v -p codesigning 2>/dev/null | head -5
        exit 1
    fi

    # Extract team ID from provisioning profile for entitlements
    TEAM_ID=""
    if [[ -f "$MERGED_APP/embedded.mobileprovision" ]]; then
        TEAM_ID=$(security cms -D -i "$MERGED_APP/embedded.mobileprovision" 2>/dev/null | \
            plutil -extract Entitlements.com\\.apple\\.developer\\.team-identifier raw - 2>/dev/null || true)
    fi
    TEAM_ID="${TEAM_ID:-$APPLE_TEAM_ID}"

    if [[ -z "$TEAM_ID" ]]; then
        echo "❌ Could not determine Team ID for entitlements"
        exit 1
    fi

    # Build entitlements plist
    ENT_FILE="$BUILD_DIR/entitlements.plist"
    cat > "$ENT_FILE" <<ENTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>application-identifier</key>
    <string>${TEAM_ID}.${BUNDLE_ID}</string>
    <key>com.apple.developer.team-identifier</key>
    <string>${TEAM_ID}</string>
    <key>get-task-allow</key>
    <true/>
    <key>keychain-access-groups</key>
    <array>
        <string>${TEAM_ID}.${BUNDLE_ID}</string>
        <string>com.apple.token</string>
    </array>
</dict>
</plist>
ENTEOF

    echo "  Signing: $IDENTITY"
    codesign --force --sign "$IDENTITY" \
        --entitlements "$ENT_FILE" \
        --timestamp=none \
        "$MERGED_APP" 2>&1

    # Verify (codesign -vv writes to stderr)
    VERIFY_OUT=$(codesign -vv "$MERGED_APP" 2>&1)
    if echo "$VERIFY_OUT" | grep -q "valid on disk"; then
        echo "  ✓ Signature valid"
        [[ -f "$MERGED_APP/embedded.mobileprovision" ]] && echo "  ✓ Provisioning profile embedded"
    else
        echo "  ⚠ Signature verification:"
        echo "$VERIFY_OUT" | head -3
    fi
else
    echo "  (unsigned — use --sign for code-signed IPA)"
fi

# Package IPA
PAYLOAD="$BUILD_DIR/ipa-staging/Payload"
mkdir -p "$PAYLOAD"
cp -R "$MERGED_APP" "$PAYLOAD/"
IPA_NAME="HADashboard-${VERSION}-universal-armv7-arm64.ipa"
(cd "$BUILD_DIR/ipa-staging" && zip -qr "../$IPA_NAME" Payload/)

IPA="$BUILD_DIR/$IPA_NAME"

# ── Cleanup intermediates (keep .app + .ipa) ─────────────────────────
rm -rf "$BUILD_DIR/armv7-obj" "$BUILD_DIR/armv7.dSYM" "$BUILD_DIR/dd-arm64" "$BUILD_DIR/ipa-staging" "$ARMV7_THIN"

# ── Results ───────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  IPA:    $IPA"
echo "  App:    $MERGED_APP"
echo "  dSYMs:  $DSYM_DIR"
echo "  Size:   $(du -h "$IPA" | cut -f1)"
echo "  Archs:  $ARCHS"
echo "  Signed: $SIGN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Deploy to iPad 2 (SSH):   scp -r \"$MERGED_APP\" root@\$IPAD2_IP:/var/mobile/Applications/"
echo "Deploy to modern device:  scripts/deploy.sh --no-build <target>"

# ── OTA manifest (optional) ──────────────────────────────────────────
if [[ -n "$OTA_URL" ]]; then
    MANIFEST="$BUILD_DIR/manifest.plist"
    cat > "$MANIFEST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>items</key>
    <array>
        <dict>
            <key>assets</key>
            <array>
                <dict>
                    <key>kind</key>
                    <string>software-package</string>
                    <key>url</key>
                    <string>${OTA_URL}/${IPA_NAME}</string>
                </dict>
            </array>
            <key>metadata</key>
            <dict>
                <key>bundle-identifier</key>
                <string>${BUNDLE_ID}</string>
                <key>bundle-version</key>
                <string>${VERSION}</string>
                <key>kind</key>
                <string>software</string>
                <key>title</key>
                <string>HA Dashboard</string>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST
    echo ""
    echo "OTA manifest: $MANIFEST"
    echo "Install URL:  itms-services://?action=download-manifest&url=${OTA_URL}/manifest.plist"
    echo ""
    echo "Host both $IPA_NAME and manifest.plist at $OTA_URL (must be HTTPS)."
    echo "Users visit the install URL on any iOS device to install."
fi
