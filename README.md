# HA Dashboard

[![Download on the App Store](https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83&releaseDate=1740009600)](https://apps.apple.com/gb/app/ha-dash/id6759347912)

A native iOS app that renders your [Home Assistant](https://www.home-assistant.io/) dashboards natively, achieving usable framerates on the oldest iOS devices.

Built to run on everything from an iPad 2 (iOS 9.3.5, armv7) wall-mounted as a kiosk, to the latest iPhones on iOS 26.

## Features

- **Native rendering** of Home Assistant dashboards — sections, masonry, panel, and sidebar layouts (entities, lights, climate, sensors, cameras, graphs, gauges, badges, and more)
- **Real-time updates** via WebSocket — entity states update live
- **Broad Home Assistant dashboard support** — covers controls, inputs, composite cards, and entity detail views
- **Themes** — Auto, Dark, Light, and Gradient modes with 5 gradient presets plus custom hex colors
- **Kiosk mode** — hides navigation, prevents sleep, triple-tap to escape
- **Dashboard switcher** — switch between multiple HA dashboards
- **mDNS discovery** — finds Home Assistant servers on your local network
- **Triple auth** — trusted network support, long-lived access token, or full OAuth login flow with token refresh
- **Universal binary** — armv7 + arm64 in a single build for legacy device support
- **Demo mode** — Built-in dashboards with simulated entities and history

## Screenshots

See the [landing page](https://ha-dashboard.github.io/ios-app/) for screenshots.

## Requirements

- **Xcode 26** (for modern devices and simulators)
- **Xcode 13.2.1** (optional — only needed if targeting iPad 2 / armv7)
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
scripts/deploy.sh all --kiosk      # All targets in kiosk mode
```

See `.env.example` for the device UDIDs and credentials needed for each target.

## Architecture

- Pure **Objective-C**
- Programmatic Auto Layout (`NSLayoutConstraint` anchors, iOS 9+)
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

HA Dashboard does not collect, store, or transmit any personal data. All communication is directly between your device and your Home Assistant server. See [PRIVACY.md](PRIVACY.md) for the full privacy policy.

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
