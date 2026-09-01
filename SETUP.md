# Developer Setup Guide

Get HA Dashboard building and running from scratch on a new Mac.

## Prerequisites

### macOS

Apple Silicon Mac required (arm64). Intel Macs won't run the arm64 simulators.

### Xcode

| Xcode | Install Path | Required? | Purpose |
|-------|-------------|-----------|---------|
| **26 or 27** | `/Applications/Xcode.app` or `XCODE_PATH` | Yes | Modern compiler plus simulator, bundle-template, and Mac Catalyst builds |
| **13.2.1 iPhoneOS SDK** | Full Xcode app or `XCODE13_SDK_PATH` | Universal device builds | Link stubs used for both iOS 9 armv7 and arm64 slices |

After installing the modern Xcode, open it once and install a current iOS simulator runtime when prompted.

If you only build `sim` or `mac`, you can omit the Xcode 13 SDK. `device` always needs the full Xcode 13.2.1 iPhoneOS SDK or the repository's extracted SDK stubs, because both shipped slices retain an iOS 9 minimum.

Legacy x86_64 RosettaSim builds are a separate exception: they require macOS 26 and Xcode 26. Xcode 27 rejects simulator deployment targets below iOS 15, and macOS 27 cannot boot the x86-only iOS 9–14 runtimes. Physical iOS 9 device builds continue to work with Xcode 27 through the direct-clang path.

### Homebrew Dependencies

```bash
brew install xcodegen
```

That's the only required Homebrew dependency. XcodeGen generates the `.xcodeproj` from `project.yml`.

### Optional Tools (for physical device deploy)

These are only needed if deploying to physical devices, not for simulator development:

| Tool | Install | Used By |
|------|---------|---------|
| `libimobiledevice` + `ideviceinstaller` | `brew install libimobiledevice ideviceinstaller` | Mini 4/Mini 5 MobileDevice Wi-Fi fallback |
| `sshpass` | `brew install hudochenkov/sshpass/sshpass` | Jailbroken iPad 2/3/4 Wi-Fi SSH deploy |

## Quick Start (Simulator)

```bash
# 1. Clone the repo
git clone https://github.com/ha-dashboard/ios-app.git
cd ios-app

# 2. Create your .env file
cp .env.example .env
```

Edit `.env` with at minimum:
```bash
BUNDLE_ID=com.yourname.hadashboard    # Your bundle identifier
# Apple Team ID is optional only for simulator builds; device and Catalyst
# builds need it for signing and the app-private Keychain access group.
```

If you have a Home Assistant server, also set:
```bash
HA_SERVER=http://192.168.1.100:8123   # Your HA server
HA_TOKEN=eyJ...                        # Long-lived access token from HA
HA_DASHBOARD=living-room               # Dashboard path
```

If you don't have a HA server, you can use demo mode (see below).

```bash
# 3. Generate the Xcode project
scripts/regen.sh

# 4. Build and run in the iPad simulator
scripts/deploy.sh sim
```

This builds the app and launches it in an iPad simulator. The first build takes a couple of minutes; subsequent builds are incremental.

For an iPhone simulator instead:
```bash
scripts/deploy.sh sim iphone
```

### Demo Mode (No Server Needed)

If you don't have a Home Assistant server available:

```bash
scripts/deploy.sh sim --demo
```

This launches with 3 built-in dashboards (Home, Monitoring, Media) using simulated entities and history data. No network connection required.

## What the Scripts Do

| Script | Purpose |
|--------|---------|
| `scripts/regen.sh` | Runs XcodeGen to generate `.xcodeproj` from `project.yml`. Run after changing project.yml or adding/removing source files. |
| `scripts/build.sh sim` | Builds arm64 simulator binary |
| `scripts/build.sh device` | Builds universal armv7+arm64 with iOS 9 minimum in both slices (requires Xcode 13 SDK stubs); the legacy slice uses ARM mode to avoid Xcode 27 Thumb-entry/IMP relocation loss |
| `scripts/build.sh rosettasim` | Builds x86_64 for legacy simulators (macOS 26 + Xcode 26 only) |
| `scripts/build.sh mac` | Builds and automatically provisions the signed Mac Catalyst binary, including its app-private Keychain access group |
| `scripts/deploy.sh <target>` | Builds + installs + launches on a target |
| `scripts/test-snapshots.sh` | Runs snapshot regression tests |
| `scripts/clean.sh` | Cleans build artifacts |

`deploy.sh` calls `build.sh` automatically — you don't normally need to call `build.sh` directly.

## Opening in Xcode

If you prefer building from Xcode's UI rather than the command line:

1. Run `scripts/regen.sh` to generate the project
2. Open `HADashboard.xcodeproj`
3. Select the **HADashboard** scheme
4. Choose a simulator destination
5. Build and run (Cmd+R)

Note: the build scripts inject the version number from git tags. Building directly from Xcode uses the `0.0.0` fallback and produces only the normal modern-Xcode architecture/deployment settings; use `scripts/build.sh device` for the distributable iOS 9 universal product.

## Running Tests

```bash
scripts/test-snapshots.sh
```

This runs pixel-perfect snapshot regression tests against reference images in `HADashboardTests/ReferenceImages_64/`. The tests use an iPad 10th gen simulator on iOS 17.4.

To re-record reference images after intentional visual changes:
```bash
scripts/test-snapshots.sh record
```

## Versioning

Version numbers come from git tags — never hardcode them:

Create curated notes at `docs/releases/vX.Y.Z.md`, merge and verify a clean current `main`, then run `scripts/release.sh X.Y.Z`. The script refuses detached, dirty, or out-of-date trees and creates an annotated tag.

The build scripts read the latest `v*` tag for `MARKETING_VERSION` and use the commit count for `CURRENT_PROJECT_VERSION`.

## Project Overview

- **Language**: Pure Objective-C — no Swift or application UI storyboards/XIBs; `LaunchScreen.storyboard` is the sole storyboard
- **UI**: Application UI is programmatic and uses `NSLayoutConstraint` anchors; `LaunchScreen.storyboard` is the sole storyboard
- **Networking**: SocketRocket (WebSocket), NSURLSession (REST)
- **Project config**: XcodeGen (`project.yml`) — the `.xcodeproj` is generated and committed, but should be regenerated via `scripts/regen.sh` after changing `project.yml`

### Key Directories

```
HADashboard/         App source code
├── Auth/            Authentication (OAuth, tokens, keychain)
├── Controllers/     View controllers (dashboard, settings)
├── Integration/     Home Assistant device sensors and remote commands
├── Models/          Data models, Lovelace JSON parser
├── Networking/      WebSocket, REST, mDNS discovery
├── Streaming/       Protected RTSP server, per-device Keychain credential, capture, and encoders
├── Theme/           Themes, icon mapping, haptics
└── Views/           All UI — cells, layouts, helpers
Vendor/              Third-party: SocketRocket, MDI icons, snapshot test framework
HADashboardTests/    Snapshot regression tests + reference images
scripts/             Build, deploy, test automation
```

## Troubleshooting

**`xcodegen: command not found`** — Run `brew install xcodegen`

**Simulator not found** — Open Xcode, go to Settings > Platforms, and install the iOS simulator runtime. The deploy script looks for "iPad Pro 11 M4" by default; set `SIM_IPAD_NAME` in `.env` to match an available simulator.

**Build fails with signing errors** — For simulator builds, signing is disabled automatically. Device and Mac Catalyst builds need `APPLE_TEAM_ID` in `.env`. Catalyst also needs either the App Store Connect API-key variables in `.env` or a suitable Apple account signed in to Xcode so automatic provisioning can authorize its Keychain access group.

**iPad 4 accepts port 22 but SSH hangs before the banner** — The 32-bit iOS 10.3.3 h3lix jailbreak is not compatible with the normal OpenSSH daemon even though the package can install and open the port. Use a trusted armv7 Dropbear package/service for h3lix, then retry `scripts/deploy.sh ipad4`. The deploy preserves and reapplies the app's application-identifier entitlement so Keychain credentials survive upgrades.

**`scripts/build.sh rosettasim` rejects Xcode 27** — This is intentional. Run legacy simulator builds on macOS 26 with Xcode 26, or validate the iOS 9 physical-device product with `scripts/build.sh device`.

**Snapshot tests fail immediately** — Make sure you have the iPad (10th generation) + iOS 17.4 simulator runtime installed. Snapshot tests are pixel-exact and depend on a specific device/OS combination.
