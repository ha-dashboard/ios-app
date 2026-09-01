# HA Dashboard

[![Download on the App Store](https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83)](https://apps.apple.com/gb/app/ha-dash/id6759347912)

A native iOS app that renders your [Home Assistant](https://www.home-assistant.io/) dashboards natively, achieving usable framerates on the oldest iOS devices.

Built to run from armv7 and arm64 devices on iOS 9.3.3 through current iOS 27 devices, with a Mac Catalyst developer build. The optional Local Camera Stream requires iOS 10.3.3 or later.

## Features

- **Native rendering** of Home Assistant dashboards — sections, masonry, panel, and sidebar layouts (entities, lights, climate, sensors, cameras, graphs, gauges, badges, and more)
- **Real-time updates** via WebSocket — entity states update live
- **Broad Home Assistant dashboard support** — covers controls, inputs, composite cards, and entity detail views
- **Themes** — Auto, Dark, Light, and Gradient modes with 5 gradient presets plus custom hex colors
- **Kiosk mode** — hides navigation, prevents sleep, triple-tap to escape
- **Dashboard switcher** — switch between multiple HA dashboards
- **Local remote controls** — use Home Assistant's WebSocket notification
  channel to wake/dim an open kiosk, set brightness, navigate, change
  appearance/kiosk state, reload, or show an in-app banner
- **mDNS discovery** — finds Home Assistant servers on your local network
- **Triple auth** — trusted network support, long-lived access token, or full OAuth login flow with token refresh
- **Universal binary** — armv7 + arm64 in one build, with an iOS 9.0 minimum encoded in both slices
- **Demo mode** — Built-in dashboards with simulated entities and history
- **Optional local camera streams** — Foreground-only, per-device password-protected H.264/AAC RTSP with front/rear selection, simultaneous MultiCam where supported, concurrent consumers, live capability-based quality/orientation, and Home Assistant Generic Camera registration (iOS 10.3.3+)

Local Camera Stream requires RTSP Digest authentication with the fixed username
`hadashboard` and a strong password generated separately on each device. Capture
starts only for an authenticated viewer. RTSP media is still plaintext and is
not encrypted on the LAN, so use it only on a trusted local network and do not
forward ports 8554 or 8555. See the
[streaming contract](docs/live-camera-streaming-v1.md).

Remote commands work only while HA Dashboard is open and connected; they cannot
unlock the device, launch a backgrounded app, or remotely enable camera capture.
See the [support guide](https://ha-dashboard.github.io/ios-app/support.html) for
the supported commands and payloads.

## Screenshots

See the [landing page](https://ha-dashboard.github.io/ios-app/) for screenshots.

## Requirements

- **Xcode 26 or 27** (modern compiler, devices, simulators, and Catalyst)
- **Xcode 13.2.1 iPhoneOS SDK stubs** (full app or extracted SDK via `XCODE13_SDK_PATH`) for universal iOS 9 device linking
- **XcodeGen** (`brew install xcodegen`)
- A Home Assistant server with pre-configured dashboards

## Getting Started

### Easy path

Install from the [App Store](https://apps.apple.com/gb/app/ha-dash/id6759347912)

### For contributors or developers

1. **Clone the repo**
   ```bash
   git clone https://github.com/ha-dashboard/ios-app.git
   cd ios-app
   ```

2. **Set up environment**
   ```bash
   cp .env.example .env
   # Edit .env with your Apple Team ID, Bundle ID, and HA credentials
   ```

3. **Generate the Xcode project**
   ```bash
   scripts/regen.sh
   ```

4. **Build and run in the simulator**
   ```bash
   scripts/deploy.sh sim
   ```

## Deploy to Devices

You should customise this to your needs.

```bash
scripts/deploy.sh sim              # iPad simulator
scripts/deploy.sh iphone           # Paired iPhone
scripts/deploy.sh mini5            # iPad Mini 5 (CoreDevice or MobileDevice Wi-Fi)
scripts/deploy.sh mini4            # iPad Mini 4 (MobileDevice Wi-Fi)
scripts/deploy.sh ipad4            # Jailbroken iPad 4 over SSH
scripts/deploy.sh mac              # Local Mac Catalyst build
scripts/deploy.sh all --kiosk      # All targets in kiosk mode
```

See `.env.example` for the device UDIDs and credentials needed for each target.

## Architecture

- Pure **Objective-C**
- Programmatic application UI and Auto Layout (`NSLayoutConstraint` anchors, iOS 9+); `LaunchScreen.storyboard` is the sole storyboard
- **SocketRocket** for WebSocket, **NSURLSession** for REST
- Custom 12-column `UICollectionViewLayout` for iPad multi-column dashboards
- Performance optimizations for older devices: deferred loading, coalesced reloads, cell rasterization, lightweight graph mode

## Testing

```bash
# Run snapshot regression tests
scripts/test-snapshots.sh

# Visual parity screenshots (uses demo.ha-dash.app)
cd scripts && npm install   # One-time: install deps
npm run capture             # Capture HA web screenshots for comparison
```

## FAQs

- I've switched to Kiosk mode, how do I get back to the settings? Triple tap the top of the screen, the menu bar will reappear for a few seconds.

## Links

- [App Store](https://apps.apple.com/gb/app/ha-dash/id6759347912)
- [Landing Page](https://ha-dashboard.github.io/ios-app/)
- [Support](https://ha-dashboard.github.io/ios-app/support.html)
- [Privacy Policy](https://ha-dashboard.github.io/ios-app/privacy.html)

## Privacy

HA Dashboard sends no personal data to the developer. Optional device diagnostics go only to the Home Assistant infrastructure you configure; camera/microphone media goes directly to authenticated RTSP clients while the app is foregrounded and never through a developer relay. See [PRIVACY.md](PRIVACY.md), the [live-streaming contract](docs/live-camera-streaming-v1.md), and the [1.2.6 release dossier](docs/releases/v1.2.6.md).

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
