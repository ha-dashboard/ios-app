# RosettaSim Legacy Simulator Deployment

RosettaSim runs x86_64 iOS 9–14 simulator runtimes on a compatible host. It is
useful for legacy UI testing, but it is not the build path for the universal
physical-device product.

## Host support

| Host | Status |
|------|--------|
| macOS 26 + Xcode 26 | Supported legacy build/install/boot path |
| Xcode 27 | Unsupported: xcodebuild rejects simulator targets below iOS 15 |
| macOS 27 | Unsupported: CoreSimulator cannot construct an x86 launch host for the legacy runtime |

`scripts/build.sh rosettasim` detects Xcode 27 and fails with this explanation
instead of producing a misleading partial artifact. The physical-device path
remains available on Xcode 27: `scripts/build.sh device` compiles armv7 and
arm64 directly with an iOS 9 minimum.

## Prerequisites on a supported host

- macOS 26
- Xcode 26 selected through `/Applications/Xcode.app` or `XCODE_PATH`
- RosettaSim with `rosettasim-ctl` built at
  `~/Projects/rosetta/src/build/rosettasim-ctl`
- The required legacy simulator runtime installed with RosettaSim's installer
- `coreutils` (`brew install coreutils`) for `gtimeout`

## Build

```bash
scripts/build.sh rosettasim
```

The output is an x86_64 app at:

```text
build/rosettasim/Build/Products/Debug-iphonesimulator/HA Dashboard.app
```

The build uses `MERGED_BINARY_TYPE=none` and `ENABLE_DEBUG_DYLIB=NO`. Without
those settings, modern Xcode's stub executable/debug-dylib layout crashes in
legacy libdispatch before the app launches.

## Discover, install, and launch

Do not copy a saved simulator UDID from documentation; recreating a device
changes it. Discover the current IDs first:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
RSCTL=~/Projects/rosetta/src/build/rosettasim-ctl
APP="build/rosettasim/Build/Products/Debug-iphonesimulator/HA Dashboard.app"

$RSCTL list
$RSCTL boot <legacy-udid>
$RSCTL install <legacy-udid> "$APP"
$RSCTL launch <legacy-udid> com.hadashboard.app
```

Standard `xcrun simctl install`, `launch`, and `terminate` may hang against
legacy runtimes. Use `rosettasim-ctl` for those operations.

Useful commands include:

| Command | Description |
|---------|-------------|
| `list` | Show current runtimes and devices |
| `status <UDID>` | Show the selected device/runtime state |
| `boot <UDID>` | Boot a supported legacy device |
| `shutdown <UDID\|all>` | Shut down devices |
| `install <UDID> <app>` | Install through legacy MobileInstallation |
| `launch <UDID> <bundle-id>` | Launch through the legacy SpringBoard path |
| `terminate <UDID> <bundle-id>` | Stop the app |
| `screenshot <UDID> <output>` | Capture the legacy framebuffer |
| `privacy <UDID> grant <service> <bundle-id>` | Set a simulator TCC grant |

## iOS 9.3.3 acceptance

A successful RosettaSim run is useful evidence but does not replace physical
armv7/arm64 validation. For a release candidate, also inspect both Mach-O
slices for minimum iOS 9.0 and launch the exact universal artifact on reachable
legacy hardware. Local Camera Stream must remain disabled below iOS 10.3.3 and
must not request Camera or Microphone permission there.

## Troubleshooting

### Deployment target must be iOS 15 or later

Xcode 27 is selected. Move the test to a macOS 26/Xcode 26 host; do not patch
the app's plist and call that an iOS 9 simulator build, because the executable
load command would still require iOS 15.

### Runtime unavailable or liblaunch_sim could not be opened

First confirm the host is macOS 26. On macOS 27 this is an architectural host
block, not a missing app setting. On a supported host, reinstall the legacy
runtime with RosettaSim's installer and re-run `rosettasim-ctl list`.

### BUG in libdispatch at launch

Rebuild through `scripts/build.sh rosettasim`; the app was likely built with a
mergeable debug dylib.

### timeout not found

Install coreutils: `brew install coreutils`.
