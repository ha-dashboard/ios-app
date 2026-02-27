# HA Dashboard

Native iOS Home Assistant dashboard app. Renders HA Lovelace dashboards natively across iOS 9.3.5 (iPad 2, armv7) through iOS 18+ (iPhone 16 Pro Max, arm64), providing a kiosk-friendly wall-mounted display experience on old iPads while also working as a mobile dashboard on modern devices.

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

Two Xcode versions are required:

| Xcode | Path | Purpose |
|-------|------|---------|
| **13.2.1** | `/Applications/Xcode-13.2.1.app` | Builds armv7+arm64 universal binary for iOS 9.0. Required for iPad 2. |
| **26** | `/Applications/Xcode.app` | Builds arm64 for iOS 15+. Used for simulator, iPhone, and newer iPads. |

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
| iPad Mini 4 | arm64 | 15.x | WiFi via ios-deploy + pymobiledevice3 |
| iPad Mini 5 | arm64 | 26.x | WiFi via devicectl |
| iPhone 16 Pro Max | arm64 | 18.x | WiFi via devicectl |
| iPad Simulator | arm64 | 16.4+ | `xcrun simctl install/launch` |
| iPhone Simulator | arm64 | 16.4+ | `xcrun simctl install/launch` |
| Legacy Simulator | x86_64 | 9.3–14.x | `rosettasim-ctl install/launch` (via RosettaSim) |

## Versioning

Version is derived from **git tags** — no files to edit for a version bump.

```bash
git tag v1.0.2
git push --tags
```

- `scripts/build.sh` reads the latest `v*` tag and passes `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` to xcodebuild
- CI workflow does the same (tag → version, commit count → build number)
- `Info.plist` uses `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)` build setting variables
- `project.yml` has `0.0.0` / `0` fallback defaults (only used if building directly from Xcode without the build script)
- **Never hardcode version numbers** in Info.plist, project.yml, or pbxproj

## Build & Deploy

```bash
scripts/deploy.sh sim              # iPad simulator (arm64, iOS 16+)
scripts/deploy.sh sim iphone       # iPhone simulator (arm64, iOS 16+)
scripts/deploy.sh iphone           # Physical iPhone via devicectl
scripts/deploy.sh mini5            # iPad Mini 5 via devicectl (WiFi)
scripts/deploy.sh mini4            # iPad Mini 4 via ios-deploy (WiFi)
scripts/deploy.sh ipad2            # iPad 2 via WiFi SSH (jailbroken)
scripts/deploy.sh all              # Deploy to all targets
scripts/deploy.sh all --kiosk      # Deploy to all targets in kiosk mode
```

Options: `--no-build`, `--dashboard X`, `--default`, `--server URL`, `--kiosk`, `--no-kiosk`

### RosettaSim (Legacy Simulators — iOS 9.3–14.x)

Legacy iOS simulators run x86_64 under RosettaSim. Standard `xcrun simctl install/launch` **hangs** on these runtimes — use `rosettasim-ctl` instead.

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

**All rosettasim-ctl commands:**

| Command | Description |
|---------|-------------|
| `list` | List all devices with status (marks legacy runtimes) |
| `boot <UDID>` | Boot device |
| `shutdown <UDID\|all>` | Shutdown device(s) |
| `install <UDID> <path.app>` | Install app (MobileInstallation for legacy) |
| `launch <UDID> <bundle-id>` | Launch app (SpringBoard injection for legacy) |
| `terminate <UDID> <bundle-id>` | Kill running app |
| `screenshot <UDID> <output>` | Screenshot from daemon framebuffer |
| `listapps <UDID>` | List installed apps |
| `appinfo <UDID> <bundle-id>` | JSON app info |
| `status <UDID>` | Full device status with daemon/IO info |
| `privacy <UDID> grant <service> <bundle-id>` | Grant TCC permissions |

For native runtimes (iOS 16+), `rosettasim-ctl` transparently passes through to `xcrun simctl`.

**Known legacy simulator UDIDs:**

| Device | iOS | UDID |
|--------|-----|------|
| iPad Pro | 9.3 | `D9DCA298-C3D2-4B68-9501-E5279A1B96B6` |
| iPad (5th gen) | 10.3 | `261D4B19-BE81-42F2-A646-3EF6F668DD84` |
| iPad (10th gen) | 16.4 | `87E82E85-7B26-480C-B5A2-6D68403CF920` |
| iPad (A16) | 26.2 | `6937E3CC-604A-4E46-A356-17E82351093A` |

## Architecture

### Language & Frameworks
- Pure **Objective-C**, no Swift, no storyboards, no XIBs
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

### Snapshot Regression Tests (96 tests)

Pixel-perfect visual regression tests covering all 32 cell types in multiple states across gradient + light themes.

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
├── Models/         # HADashboardConfig, HAEntity, HALovelaceParser
├── Networking/     # HAAPIClient, HAConnectionManager, HAWebSocketClient, HADiscoveryService
├── Theme/          # HATheme, HAIconMapper, HAHaptics
├── Views/
│   ├── Cells/      # 25+ entity cells (HABaseEntityCell subclasses) + composite cards
│   ├── HAColumnarLayout, HAEntityCellFactory, HAEntityDisplayHelper
│   ├── HAEntityRowView, HAGraphView, HASectionHeaderView
│   └── HAThermostatGaugeView
├── Info.plist
└── main.m
Vendor/             # SocketRocket (SRWebSocket), MDI icon font, iOSSnapshotTestCase
HADashboardTests/   # 96 snapshot regression tests + reference images
scripts/            # Build, deploy, test, screenshot capture
screenshots/        # HA web + app screenshot captures (git-ignored)
project.yml         # XcodeGen project definition (placeholders — .env fills real values)
.env.example        # Template for required environment variables
PRIVACY.md          # Privacy policy
```

## Known Issues

- Constraint warning on iPad 2 settings screen (UISegmentedControl vertical position) — cosmetic only
- Developer disk image must be remounted after iPad 2 reboot (deploy script handles this automatically)
- iPad Mini 4 deploy requires ios-deploy + pymobiledevice3 installed via Homebrew/pip
