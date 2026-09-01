# HA Dashboard

Native Home Assistant dashboard app. The scripted universal product carries armv7 and arm64 slices with an iOS 9.0 minimum, covering iOS 9.3.3 legacy devices through iOS 27, plus a Mac Catalyst developer build. Local Camera Stream is separately gated to iOS 10.3.3+.

## Published Links

- **App Store**: https://apps.apple.com/gb/app/ha-dash/id6759347912
- **Landing Page**: https://ha-dashboard.github.io/ios-app/
- **Support Page**: https://ha-dashboard.github.io/ios-app/support.html
- **Privacy Policy**: https://ha-dashboard.github.io/ios-app/privacy.html
- **GitHub**: https://github.com/ha-dashboard/ios-app

## Project Goals

- Render the user's HA Lovelace dashboard natively — not a web view
- Visual parity across all devices: same cards, same layout, same data
- Kiosk mode for wall-mounted iPads (hide nav bar, prevent sleep, triple-tap escape)
- Fast startup and smooth scrolling, especially on the iPad 2's A5 chip (512MB RAM)

## Build Setup

The modern toolchain plus legacy iPhoneOS link stubs are required for the full universal product:

| Xcode | Path | Purpose |
|-------|------|---------|
| **13.2.1 SDK** | Full Xcode app or `XCODE13_SDK_PATH` | Link stubs for both iOS 9 armv7 and arm64 device slices. |
| **26 or 27** | `/Applications/Xcode.app`, beta fallback, or `XCODE_PATH` | Modern compiler, current simulator, signed bundle template, physical-device tooling, and Catalyst. |

### Build Targets

| Target | Command | Arch | iOS Min | SDK | Notes |
|--------|---------|------|---------|-----|-------|
| Simulator | `scripts/build.sh sim` | arm64 | 15.0 | Xcode 26 | Native arm64 sim for iOS 16+ |
| RosettaSim | `scripts/build.sh rosettasim` | x86_64 | 9.0 | macOS 26 + Xcode 26 only | Legacy sim for iOS 9–14. Xcode/macOS 27 fail closed because they cannot build/boot the x86-only runtimes. |
| Device | `scripts/build.sh device` | armv7+arm64 | 9.0 in both slices | Xcode 26/27 clang + Xcode 13 link stubs | Both executables compile/link directly; armv7 is forced to ARM mode to avoid Xcode 27 Thumb-relocation loss, while xcodebuild supplies only the signed bundle/resources before replacement and re-signing. |
| Mac Catalyst | `scripts/build.sh mac` | arm64 | iOS 15 Catalyst mapping | Xcode 26/27 | Sandboxed developer build with camera, microphone, client, server, and app-private Keychain access-group entitlements. |

- **XcodeGen** generates `HADashboard.xcodeproj` from `project.yml` — run `scripts/regen.sh` after changing project.yml
- `regen.sh` sources `.env` to inject your Team ID and Bundle ID into the project before generation
- **Signing**: Automatic provisioning via App Store Connect API key (credentials in `.env`)

## Environment Configuration

All secrets and device-specific configuration live in `.env` at project root (git-ignored). Copy `.env.example` to get started:

```bash
cp .env.example .env
# Then fill in your values
```

Key variables:
- `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` — Apple signing
- `BUNDLE_ID` — your app bundle identifier (used by build + deploy scripts)
- `HA_SERVER`, `HA_TOKEN`, `HA_DASHBOARD` — Home Assistant connection
- Device UDIDs for physical deploy targets (see `.env.example` for full list)
- Simulator UDIDs are auto-detected by device name if not set

**Never commit `.env`, `private_keys/`, or any tokens/passwords to source control.**

## Deployment Targets

| Device | Arch | iOS | Deploy Method |
|--------|------|-----|---------------|
| iPad 2 | armv7 | 9.3.5 | WiFi SSH (jailbroken) or Unraid USB |
| iPad 3 | armv7 | 9.3.5 | WiFi SSH (jailbroken) |
| iPad 4 | armv7 | 10.3.x | Wi-Fi SSH (jailbroken) or validated Unraid USB |
| iPad Mini 4 | arm64 | 15.x | MobileDevice Wi-Fi via `ideviceinstaller` |
| iPad Mini 5 | arm64 | 26.x | CoreDevice, with validated MobileDevice Wi-Fi fallback |
| iPhone 16 | arm64 | 26.x | CoreDevice/devicectl |
| iPad Simulator | arm64 | 16.4+ | `xcrun simctl install/launch` |
| iPhone Simulator | arm64 | 16.4+ | `xcrun simctl install/launch` |
| Legacy Simulator | x86_64 | 9.3–14.x | `rosettasim-ctl` on macOS 26 + Xcode 26 only |

## Versioning & Release

Version is derived from **git tags** — no files to edit for a version bump.

- `scripts/build.sh` reads the latest `v*` tag → `MARKETING_VERSION`, commit count → `CURRENT_PROJECT_VERSION`
- `Info.plist` uses `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` build setting variables
- `project.yml` has `0.0.0` / `0` fallback defaults (only used if building directly from Xcode without the build script)
- **Never hardcode version numbers** in Info.plist, project.yml, or pbxproj

### Release Workflow

Release only from a clean, current `main` after the exact candidate has passed
the acceptance checklist. Curated notes are required because the historical
`v1.2.5` tag predates source already shipped as App Store build 158.

```bash
cp docs/releases/v1.2.6.md docs/releases/vX.Y.Z.md
# Edit and verify the notes, merge to main, then:
scripts/release.sh X.Y.Z
```

`release.sh` refuses detached HEAD, a dirty tree, a non-main branch, an
out-of-date `origin/main`, a missing notes file, or an existing tag. It creates
and pushes an annotated tag. Never move a published release tag.

### CI Pipeline (`.github/workflows/build.yml`)

Triggered on pushes to `main` and `v*` tags:

| Job | Trigger | What it does |
|-----|---------|-------------|
| `build-and-test` | All pushes | Builds simulator target, verifies compilation |
| `verify-ios9-slices` | Every CI run | Downloads/checks the immutable Xcode 13 SDK stubs, then compiles and verifies unsigned armv7+arm64 iOS 9 slices. |
| `archive-release` | Tag push only | Direct armv7+arm64 iOS 9 compile/link → signed bundle template → universal replacement/dSYM → export App Store/TestFlight + Ad Hoc IPA → GitHub Release. |

The `archive-release` job handles **everything** for App Store submission:
- Builds a universal armv7+arm64 binary whose two Mach-O slices both target iOS 9.0
- Signs with dev certificate + provisioning profile (from GitHub secrets)
- Exports App Store IPA via `xcodebuild -exportArchive` with ASC API key auth
- **Automatically uploads to TestFlight** (the App Store export triggers upload)
- Exports Ad Hoc IPA and attaches to GitHub Release

The tag workflow creates the GitHub release automatically using the matching
`docs/releases/vX.Y.Z.md` file. After CI completes, go to [App Store Connect](https://appstoreconnect.apple.com) → TestFlight to:
1. Add release notes for the TestFlight build
2. Submit for external testing or App Review

### Signing & App Store Connect Credentials

All credentials are in `.env` (local) and GitHub secrets (CI):

| Credential | `.env` key | GitHub Secret | Purpose |
|-----------|-----------|---------------|---------|
| Team ID | `APPLE_TEAM_ID` | `vars.TEAM_ID` | Apple Developer team |
| ASC API Key ID | `ASC_KEY_ID` | `secrets.ASC_KEY_ID` | App Store Connect API auth |
| ASC Issuer ID | `ASC_ISSUER_ID` | `secrets.ASC_ISSUER_ID` | App Store Connect API auth |
| ASC API Key (.p8) | `ASC_KEY_PATH` (file path) | `secrets.ASC_KEY_BASE64` (base64) | API key for signing + TestFlight upload |
| Dev Certificate | — | `secrets.DEV_CERT_BASE64` | Code signing certificate (.p12) |
| Certificate Password | — | `secrets.DEV_CERT_PASSWORD` | Password for .p12 |
| Provisioning Profile | — | `secrets.PROVISIONING_PROFILE_BASE64` | App provisioning |

Local builds use `ASC_KEY_PATH` to point to the `.p8` file on disk. CI decodes `ASC_KEY_BASE64` at runtime.

## Build & Deploy

```bash
scripts/deploy.sh sim              # iPad simulator (arm64, iOS 16+)
scripts/deploy.sh sim iphone       # iPhone simulator (arm64, iOS 16+)
scripts/deploy.sh iphone           # Physical iPhone via devicectl
scripts/deploy.sh mini5            # iPad Mini 5 via CoreDevice/MobileDevice Wi-Fi
scripts/deploy.sh mini4            # iPad Mini 4 via ideviceinstaller (Wi-Fi)
scripts/deploy.sh ipad2            # iPad 2 via WiFi SSH (jailbroken)
scripts/deploy.sh ipad3            # iPad 3 via WiFi SSH (jailbroken)
scripts/deploy.sh ipad4            # iPad 4 via WiFi SSH (jailbroken)
scripts/deploy.sh ipad4-usb        # iPad 4 via validated Unraid USB
scripts/deploy.sh mac              # Mac Catalyst
scripts/deploy.sh all              # Deploy to all targets
scripts/deploy.sh all --kiosk      # Deploy to all targets in kiosk mode
```

Options: `--no-build`, `--dashboard X`, `--default`, `--server URL`, `--token`, `--kiosk`, `--no-kiosk`, `--reset`, `--demo`

### RosettaSim (Legacy Simulators — iOS 9.3–14.x)

Legacy iOS simulators run x86_64 under RosettaSim on **macOS 26 with Xcode 26**. Standard `xcrun simctl install/launch` hangs on these runtimes, so use `rosettasim-ctl`. Xcode 27 rejects the legacy deployment target and macOS 27 cannot construct an x86 launch host; `build.sh rosettasim` therefore fails closed there. This does not affect the physical iOS 9 universal device build.

**Binary**: `/Users/ashhopkins/Projects/rosetta/src/build/rosettasim-ctl`

**Build:**
```bash
scripts/build.sh rosettasim        # x86_64 sim build with MERGED_BINARY_TYPE=none
```

The `MERGED_BINARY_TYPE=none` flag is critical — without it, Xcode 26's default Debug configuration produces a stub binary + debug dylib (mergeable libraries) that crashes on legacy runtimes' libdispatch.

**Deploy:**
```bash
RSCTL=/Users/ashhopkins/Projects/rosetta/src/build/rosettasim-ctl

$RSCTL install <UDID> "build/rosettasim/Build/Products/Debug-iphonesimulator/HA Dashboard.app"
$RSCTL launch <UDID> com.hadashboard.app
$RSCTL terminate <UDID> com.hadashboard.app
$RSCTL screenshot <UDID> output.png
```

**rosettasim-ctl commands** (full simctl parity for legacy runtimes):

| Command | Description |
|---------|-------------|
| `list` | List all devices with status (marks legacy runtimes) |
| `boot <UDID>` | Boot device |
| `shutdown <UDID\|all>` | Shutdown device(s) |
| `install <UDID> <path.app>` | Install app (darwin notify + MobileInstallation) |
| `launch <UDID> <bundle-id>` | Launch app (SpringBoard injection) |
| `terminate <UDID> <bundle-id>` | Kill app process |
| `screenshot <UDID> <output.png>` | Screenshot from daemon framebuffer |
| `listapps <UDID>` | List installed apps |
| `appinfo <UDID> <bundle-id>` | JSON app info |
| `status <UDID>` | Full device status with daemon/IO info |
| `privacy <UDID> grant <service> <bundle-id>` | TCC permissions |
| `touch <UDID> <x> <y>` | Simulated touch input |
| `location <UDID> set <lat>,<lon>` | GPS simulation |
| `push <UDID> <bundle-id> <payload.json>` | Push notification |
| `ui <UDID> content_size <size>` | Accessibility text size |
| `keychain <UDID> reset` | Reset keychain |
| `addmedia <UDID> <file>` | Add photos/videos |
| `getenv <UDID> <var>` | Read environment variable |
| `pbcopy <UDID>` | Copy to pasteboard (pipe stdin) |
| `pbpaste <UDID>` | Paste from pasteboard |

For native runtimes (iOS 16+), all commands transparently pass through to `xcrun simctl`.

**Rebuild rosettasim-ctl**: `cd ~/Projects/rosetta/src && make ctl`

**Example saved simulator UDIDs (verify locally; simulator recreation changes them):**

| Device | iOS | UDID |
|--------|-----|------|
| iPad Pro | 9.3 | `D9DCA298-C3D2-4B68-9501-E5279A1B96B6` |
| iPad (5th gen) | 10.3 | `261D4B19-BE81-42F2-A646-3EF6F668DD84` |
| iPad (10th gen) | 16.4 | `87E82E85-7B26-480C-B5A2-6D68403CF920` |
| iPad (A16) | 26.2 | `6937E3CC-604A-4E46-A356-17E82351093A` |

## Architecture

### Language & Frameworks
- Pure **Objective-C**, no Swift and no application UI storyboards/XIBs; `LaunchScreen.storyboard` is the sole storyboard
- All UI built programmatically with `NSLayoutConstraint` anchors (iOS 9+)
- **SocketRocket** (`Vendor/SRWebSocket`) for WebSocket
- **NSURLSession** for REST API calls
- **NSNetServiceBrowser** for mDNS server discovery

### Key Classes

| Class | Role |
|-------|------|
| `HAAuthManager` | Singleton. Keychain credential storage. Dual mode: long-lived token or OAuth. |
| `HAOAuthClient` | 3-step HA OAuth flow with token refresh. |
| `HAConnectionManager` | WebSocket lifecycle, entity state cache, dashboard config. |
| `HAWebSocketClient` | SocketRocket wrapper. Auth, state subscriptions, service calls, Lovelace fetch. |
| `HAAPIClient` | REST client with Bearer auth. Auto-retries 401 with refresh in OAuth mode. |
| `HADiscoveryService` | Bonjour/mDNS browser for `_home-assistant._tcp`. |
| `HAStreamingManager` | Opt-in foreground RTSP listeners plus authenticated-media-client-gated H.264/AAC capture and encoding. |
| `HARTSPCredentialManager` | Generates and rotates the per-device RTSP password stored in the device-only Keychain; username is fixed as `hadashboard`. |
| `HARTSPServer` | Digest-authenticated RTSP/RTP-over-TCP server bound to one selected local address; media remains plaintext. |
| `HACameraRegistrationManager` | Asynchronous, admin-authenticated Generic Camera reconciliation for app-owned entry IDs, with RTSP Digest credentials, 75/120-second camera-only timeouts, and context-bound retry delays capped at 60 seconds. |
| `HALovelaceParser` | Converts HA Lovelace JSON into `HADashboardConfig` (sections + items). |
| `HAEntityDisplayHelper` | Centralized entity display: name, state, icon glyph, icon color, toggle detection. |
| `HAEntityCellFactory` | Maps entity domains + card types to cell reuse identifiers. |
| `HAColumnarLayout` | Custom `UICollectionViewLayout`. 12-column sub-grid packing for iPad. |
| `HADashboardViewController` | Main dashboard. Collection view with visibility-based cell loading. |
| `HASettingsViewController` | Server URL, auth mode, mDNS discovery, dashboard picker, kiosk toggle. |

### Layout System
- **iPad** (columnar layout): Multi-column sections, 12-column sub-grid packing. Cards specify `columnSpan` (1-12). Grid cards with `columns` property subdivide: child spans = 12/columns.
- **iPhone** (flow layout): Single column, full-width cards. Also uses 12-column sub-grid for grid cards with `columns > 1`.
- **Grid headings**: In HA sections layout, heading cards appear inside nested grid wrappers. The grid's `grid_options.columns` determines the heading's column span. Headings are rendered via the **embedded headingIcon mechanism**: the parser sets `headingIcon` + `displayName` on the first content item in each grid. The cell renders the heading ABOVE its card content within the same cell bounds. This preserves side-by-side packing. **Never convert headingIcon items to standalone heading items** — this breaks side-by-side layout.

### Authentication
- **Token mode** (HAAuthModeToken): User pastes a long-lived access token. No refresh needed.
- **OAuth mode** (HAAuthModeOAuth): Username/password login. 3-step HA auth flow, Keychain storage, proactive refresh 5 min before expiry.
- Launch args (`-HAServerURL`, `-HAAccessToken`, `-HADashboard`) override stored credentials.

### Performance Optimizations (iPad 2)
- **Deferred loading**: Graph/camera fetches start in `willDisplayCell:`, cancelled in `didEndDisplayingCell:`.
- **Coalesced reloads**: WebSocket updates batch over 0.5s. Only visible cells reload.
- **Cell rasterization**: `shouldRasterize = YES` for smooth scrolling.
- **Lightweight graph mode**: Device model detection skips gradient layers on iPad 2.
- **Graph downsampling**: History capped at 100 points (LTTB-style sampling).
- **Opaque backgrounds**: No alpha compositing on cell backgrounds.

### HA API Integration
- **WebSocket** (`ws://host:8123/api/websocket`): Auth, state subscriptions, service calls, Lovelace config, area/entity/device registries.
- **REST** (`http://host:8123/api/`): Config, states, services, history (for graph cards).
- **History**: `GET /api/history/period/{ISO8601}?filter_entity_id={id}&minimal_response&no_attributes` — 24h window.
- **Camera**: Proxy path from entity attributes, fetched with Bearer auth, refreshed every 10s.

## Testing

### Snapshot Regression Tests

Pixel-perfect visual regression coverage across card types and multiple states in gradient and light themes. Avoid hard-coded suite counts here; query the current test bundle and reference directory when reporting coverage.

```bash
scripts/test-snapshots.sh
```

- `HADashboardTests/HABaseSnapshotTestCase` — shared base with `verifyView:identifier:` (dual-theme) and cell helpers
- `HADashboardTests/HASnapshotTestHelpers` — 89 factory methods for all entity domains
- `HADashboardTests/ReferenceImages_64/` — 190 reference images (committed, source of truth)
- To re-record: set `self.recordMode = YES` in `HABaseSnapshotTestCase.m`, run tests, set back to `NO`

### Visual Parity Screenshots

Uses the demo server at https://demo.ha-dash.app for side-by-side comparison.

```bash
cd scripts && npm install   # One-time: install deps
npm run capture             # Capture HA web screenshots
npm run compare             # Generate comparison report
```

Screenshots are saved to `screenshots/` (git-ignored) and can be regenerated with the above commands.
Demo server infra lives in the private repo `ha-dashboard/demo-server`.

### Physical iPad Screenshots (Jailbroken Devices)

The app has a built-in file-trigger screenshot mechanism for jailbroken iPads (iPad 2, 3, 4):

```bash
# 1. Touch the trigger file via SSH (app watches for it after layout settles)
source .env
sshpass -p "$IPAD3_SSH_PASS" ssh -o StrictHostKeyChecking=no -o HostkeyAlgorithms=ssh-rsa \
  root@$IPAD3_IP touch /tmp/take_screenshot

# 2. Wait ~4 seconds for app to capture (3s internal delay + margin)
sleep 4

# 3. Pull the screenshot back
sshpass -p "$IPAD3_SSH_PASS" scp -o StrictHostKeyChecking=no -o HostkeyAlgorithms=ssh-rsa \
  root@$IPAD3_IP:/tmp/screenshot.png ./screenshots/ipad3-screenshot.png
```

Replace `IPAD3` with `IPAD2` or `IPAD4` for other devices. Credentials are in `.env` (see `.env.example`).

**How it works:** `HADashboardViewController` checks for `/tmp/take_screenshot` after dashboard rebuild. If found, it deletes the trigger, waits 3s for layout to settle, then renders the key window to `/tmp/screenshot.png`. The `screenshotScheduled` flag prevents duplicate captures per app lifecycle — relaunch the app to take another screenshot.

### Launch Arguments (for testing)
- `-HAServerURL http://...` — HA server URL
- `-HAAccessToken eyJ...` — Bearer token
- `-HADashboard test-harness` — Dashboard path
- `-HAViewIndex N` — Initial view index (0-7)
- `-HAThemeMode N` — Theme override (0=auto, 1=gradient, 2=dark, 3=light)
- `-HAKioskMode YES/NO` — Kiosk mode

## File Structure

```
HADashboard/
├── Auth/           # HAAuthManager, HAKeychainHelper, HAOAuthClient
├── Controllers/    # HADashboardViewController, HASettingsViewController
├── Integration/    # Home Assistant sensors and remote commands
├── Models/         # HADashboardConfig, HAEntity, HALovelaceParser
├── Networking/     # HAAPIClient, HAConnectionManager, HAWebSocketClient, HADiscoveryService
├── Streaming/      # Digest-protected RTSP, device credential, capture, and H.264/AAC encoders
├── Theme/          # HATheme, HAIconMapper, HAHaptics
├── Views/
│   ├── Cells/      # 25+ entity cells (HABaseEntityCell subclasses) + composite cards
│   ├── HAColumnarLayout, HAEntityCellFactory, HAEntityDisplayHelper
│   ├── HAEntityRowView, HAGraphView, HASectionHeaderView
│   └── HAThermostatGaugeView
├── Info.plist
├── PrivacyInfo.xcprivacy
└── main.m
Vendor/             # SocketRocket (SRWebSocket), MDI icon font, iOSSnapshotTestCase
HADashboardTests/   # 96 snapshot regression tests + reference images
scripts/            # Build, deploy, test, screenshot capture
screenshots/        # HA web + app screenshot captures (git-ignored)
project.yml         # XcodeGen project definition (placeholders — .env fills real values)
.env.example        # Template for required environment variables
PRIVACY.md          # Privacy policy
docs/releases/      # Curated GitHub, App Store, TestFlight, and release-gate notes
```

## Known Issues

- Constraint warning on iPad 2 settings screen (UISegmentedControl vertical position) — cosmetic only
- Developer disk image must be remounted after iPad 2 reboot (deploy script handles this automatically)
- Mini 4/Mini 5 MobileDevice fallback requires `libimobiledevice` and `ideviceinstaller`; automatic launch additionally needs a matching Developer Disk Image
- The 32-bit iOS 10.3.3 h3lix jailbreak needs a compatible Dropbear service; OpenSSH can accept port 22 but hang before sending its banner
- RosettaSim iOS 9–14 validation requires macOS 26 + Xcode 26 and is unavailable on macOS/Xcode 27
- Local Camera Stream requires per-device RTSP Digest credentials, but media remains plaintext and unencrypted; use only on a trusted LAN, never forward 8554/8555, and prefer a DHCP reservation
- Leaving Both camera mode does not delete the saved rear Generic Camera entry from Home Assistant

## Privacy and Release Metadata

- `HADashboard/PrivacyInfo.xcprivacy` declares app-only defaults, elapsed-time logging, and local user-approved storage display required-reason APIs.
- Keep `HADashboard/Info.plist` and `project.yml` camera, microphone, and local-network purpose strings identical.
- Public privacy wording lives in `PRIVACY.md` and `docs/privacy.html`; camera support guidance is in `docs/support.html` and `docs/live-camera-streaming-v1.md`.
- `docs/releases/vX.Y.Z.md` is the internal App Store/TestFlight/acceptance dossier; `vX.Y.Z-github.md` is the bounded public GitHub release body.
