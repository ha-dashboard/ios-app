# RosettaSim Legacy Simulator Deployment

Deploying HA Dashboard to legacy iOS simulators (iOS 9.3–14.x) running under RosettaSim (x86_64).

## Prerequisites

- **RosettaSim** installed with `rosettasim-ctl` built at `~/Projects/rosetta/src/build/rosettasim-ctl`
- **Xcode 26** at `/Applications/Xcode.app`
- Legacy iOS simulator runtimes installed (iOS 9.3, 10.3, etc.)
- `sim_app_installer.dylib` injected into each legacy runtime's SpringBoard (handled by the RosettaSim setup)
- `coreutils` installed (`brew install coreutils`) for the `gtimeout` binary

## Building

```bash
scripts/build.sh rosettasim
```

This produces an x86_64 simulator binary at:
```
build/rosettasim/Build/Products/Debug-iphonesimulator/HA Dashboard.app
```

The build uses standard Xcode 26 xcodebuild with `MERGED_BINARY_TYPE=none`. This is critical — the default Debug configuration uses mergeable libraries (stub binary + debug dylib), which crashes on legacy runtimes due to libdispatch incompatibility.

## Installing on a Legacy Simulator

Legacy simulators (iOS 9.3–14.x) cannot use `xcrun simctl install` — it hangs. Instead, the app is installed via a dylib injected into SpringBoard that calls `MobileInstallationInstallForLaunchServices` on boot.

### Step 1: Ensure no other legacy sims are booted

The installer dylib runs in whichever legacy SpringBoard boots first. If multiple legacy devices of the same runtime version are booted, the install may target the wrong one.

```bash
xcrun simctl shutdown all
```

### Step 2: Erase the target device (clean install)

Required to avoid stale container references from previous installs.

```bash
xcrun simctl erase <UDID>
```

### Step 3: Write the pending install JSON

```bash
cat > /tmp/rosettasim_pending_installs.json << 'EOF'
[{
    "path": "/Users/<you>/Projects/hass-dashboard/build/rosettasim/Build/Products/Debug-iphonesimulator/HA Dashboard.app",
    "bundle_id": "com.hadashboard.app"
}]
EOF
```

The `path` must point to the **source** `.app` bundle, not a container copy.

### Step 4: Boot the target device

```bash
xcrun simctl boot <UDID>
```

Wait ~25 seconds for SpringBoard to start and the installer dylib to run.

### Step 5: Check the install result

```bash
cat /tmp/rosettasim_install_result.txt
```

The dylib may report "FAIL" even on success (false negative). Verify via syslog:

```bash
grep "Install Successful" ~/Library/Logs/CoreSimulator/<UDID>/system.log
```

### Step 6: Reboot to update LaunchServices

The install completes after the LaunchServices map is built on first boot. A reboot regenerates the map with the newly registered app:

```bash
rm -f /tmp/rosettasim_pending_installs.json   # prevent re-install
xcrun simctl shutdown <UDID>
sleep 3
xcrun simctl boot <UDID>
```

After reboot, the app icon appears on the home screen (usually page 2).

### Step 7: Launch the app

Programmatic launch (`simctl launch`) does not work on legacy runtimes. Tap the icon on the home screen in the Simulator window.

## Quick Reference: Device UDIDs

| Device | iOS | UDID |
|--------|-----|------|
| iPad Pro | 9.3 | `D9DCA298-C3D2-4B68-9501-E5279A1B96B6` |
| iPad (5th gen) | 10.3 | `261D4B19-BE81-42F2-A646-3EF6F668DD84` |

## Other rosettasim-ctl Commands

```bash
RSCTL=~/Projects/rosetta/src/build/rosettasim-ctl

$RSCTL list                          # List all devices with status
$RSCTL status <UDID>                 # Detailed device info
$RSCTL boot <UDID>                   # Boot device
$RSCTL shutdown <UDID>               # Shutdown device
$RSCTL screenshot <UDID> output.png  # Take screenshot (legacy framebuffer)
```

## Native Simulators (iOS 15+)

iOS 16.4, 26.2, and other native arm64 runtimes use standard `xcrun simctl install/launch`:

```bash
scripts/build.sh sim                                    # arm64 build
xcrun simctl install <UDID> "build/sim/.../HA Dashboard.app"
xcrun simctl launch <UDID> com.hadashboard.app
```

## Troubleshooting

### "BUG in libdispatch" crash on launch
The app was built without `MERGED_BINARY_TYPE=none`. Rebuild with `scripts/build.sh rosettasim`.

### Install result file shows "FAIL" but syslog shows "Install Successful"
This is a known false negative in the installer dylib. Trust the syslog.

### App icon doesn't appear after install
Reboot the device (step 6). The LaunchServices map is only rebuilt on boot.

### `rosettasim-ctl` commands fail with "timeout not found"
Install coreutils: `brew install coreutils`. The tool uses `gtimeout` from `/opt/homebrew/bin/`.

### Install targets wrong device
Shut down all other legacy sims before booting the target. Legacy runtimes share SpringBoard, and the installer runs in whichever boots first.
