# RosettaSim Legacy Simulator Deployment

Deploying HA Dashboard to legacy iOS simulators (iOS 9.3–14.x) running under RosettaSim (x86_64).

## Prerequisites

- **RosettaSim** installed with `rosettasim-ctl` built at `~/Projects/rosetta/src/build/rosettasim-ctl`
- **Xcode 26** at `/Applications/Xcode.app`
- Legacy iOS simulator runtimes installed (iOS 9.3, 10.3, etc.)
- `coreutils` installed (`brew install coreutils`) for the `gtimeout` binary

## Building

```bash
scripts/build.sh rosettasim
```

This produces an x86_64 simulator binary at:
```
build/rosettasim/Build/Products/Debug-iphonesimulator/HA Dashboard.app
```

Uses standard Xcode 26 xcodebuild with `MERGED_BINARY_TYPE=none`. This is critical — the default Debug configuration uses mergeable libraries (stub binary + debug dylib) which crashes on legacy runtimes due to libdispatch incompatibility.

## Installing and Launching

Use `rosettasim-ctl` for all legacy simulator operations. Do **not** use `xcrun simctl install/launch/terminate` — they hang on legacy runtimes.

```bash
RSCTL=~/Projects/rosetta/src/build/rosettasim-ctl
APP="build/rosettasim/Build/Products/Debug-iphonesimulator/HA Dashboard.app"
UDID="D9DCA298-C3D2-4B68-9501-E5279A1B96B6"  # iOS 9.3 iPad Pro

$RSCTL boot $UDID
$RSCTL install $UDID "$APP"
$RSCTL launch $UDID com.hadashboard.app
```

## rosettasim-ctl Commands

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

## Device UDIDs

| Device | iOS | UDID |
|--------|-----|------|
| iPad Pro | 9.3 | `D9DCA298-C3D2-4B68-9501-E5279A1B96B6` |
| iPad (5th gen) | 10.3 | `261D4B19-BE81-42F2-A646-3EF6F668DD84` |
| iPad (10th gen) | 16.4 | `87E82E85-7B26-480C-B5A2-6D68403CF920` |
| iPad (A16) | 26.2 | `6937E3CC-604A-4E46-A356-17E82351093A` |

## Native Simulators (iOS 16+)

```bash
scripts/build.sh sim
xcrun simctl install <UDID> "build/sim/.../HA Dashboard.app"
xcrun simctl launch <UDID> com.hadashboard.app
```

Or use `scripts/deploy.sh sim` which handles build + install + launch.

## Troubleshooting

### "BUG in libdispatch" crash on launch
The app was built without `MERGED_BINARY_TYPE=none`. Rebuild with `scripts/build.sh rosettasim`.

### `rosettasim-ctl` commands fail with "timeout not found"
Install coreutils: `brew install coreutils`. The tool resolves `gtimeout` from `/opt/homebrew/bin/`.

### `xcrun simctl install` hangs on legacy sim
Use `rosettasim-ctl install` instead. Standard simctl hangs on iOS 7–14 runtimes.
