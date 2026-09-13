# Bluetooth Proxy

HA Dashboard can act as an encrypted, ESPHome-compatible Bluetooth LE proxy
while the iOS app is open. It uses public Core Bluetooth APIs. This feature
extends the range of compatible Home Assistant BLE integrations; it does not
forward Bluetooth audio or expose an unrestricted radio adapter.

## Setup

1. Open Settings → Bluetooth Proxy and enable it. Allow Bluetooth access.
2. Keep the dashboard open. Kiosk mode can prevent automatic display sleep.
3. While connected to Home Assistant as an administrator, tap **Add to Home
   Assistant**. The app uses the existing ESPHome integration.
4. Alternatively, add ESPHome manually using the displayed local address,
   port 6053, and the copied encryption key.

Home Assistant must reach the device's private IPv4 address. A DHCP reservation
is useful. Proxy traffic is encrypted with Noise NNpsk0; setup sends the key via
the configured HA HTTP/HTTPS connection, so use HTTPS or a trusted local network.
There is no developer relay. Leaving the iOS app or locking it pauses the proxy.

## Device identity

Apple supplies local peripheral UUIDs instead of Bluetooth MAC addresses. The
proxy therefore distinguishes:

- Addresses embedded in supported SwitchBot manufacturer advertisements.
- Hardware addresses explicitly associated by the user.
- Local aliases for devices whose address is unknown.

Tap a nearby device to import known Bluetooth devices from HA. The matching view
compares registry information and advertisements received by other scanners.
It can also read standard GATT serial, system ID, manufacturer and model fields
when a device provides them. Matching names, readings and service UUIDs are
suggestions, not proof of identity; confirm the physical device before linking.

An alias is not a hardware MAC. It may create a separate HA identity, will not
automatically match other iPads or ESP32 proxies, and cannot substitute for the
address used by encrypted BTHome payloads. Each iPad needs its own association
between Apple's local identifier and the known device. Some devices provide no
unique readable identifier and require manual association.

## Supported behaviour and limits

- BLE advertisements visible to Core Bluetooth, preserving callback order.
- Up to three active GATT connections, with reads, writes and notifications.
- ESPHome V3 connection semantics. Core Bluetooth objects are resolved before
  reporting a connection ready, and translated handles persist across reconnects.
- Notification descriptor writes are translated into Core Bluetooth's public
  notification API. Explicit pairing/unpairing, raw radio controls and remote
  cache clearing are not advertised as capabilities.
- Four network clients at most, bounded frames and output queues, handshake and
  idle timeouts, and authenticated traffic only.
- The iPad 2 lacks BLE hardware. Older BLE-capable iPads require real-device
  validation; a compiled binary or a powered-on scanner is insufficient.
- Apple filters some Bluetooth traffic, including iBeacon packets in Core
  Bluetooth. Background operation cannot provide ESP32-like continuous service.

The wire implementation currently uses the ESPHome API's decoded-advertisement
fallback. Current HA clients accept it; it is a compatibility dependency to
check when upgrading HA/aioesphomeapi. Firmware/version fields identify the
compatibility target and the HA Dashboard project, not an ESP32 firmware image.

## Credentials and reset

The randomly generated key is stored in the device-only Keychain. Anyone with
the key and network reachability can use the proxy. It is not included in local
diagnostic snapshots. HA keeps its own copy, including in backups.

Turning the feature off closes its connections. Log Out & Reset also removes
the local key, address associations, handle tables and diagnostic snapshot.
Remove unwanted ESPHome entries separately in HA.

## Development and validation

`scripts/deploy.sh` accepts `--ble-proxy`, `--no-ble-proxy`, and
`--register-ble-proxy`. For an explicitly selected CoreDevice target, use
`device --device-id ID`. Normal installations remain opt-in.

For a Mini 5 that is reachable through MobileDevice Wi-Fi but missing from
CoreDevice, the validated launch path is a personalized developer image followed
by a lockdown tunnel:

```sh
ideviceimagemounter -n -u DEVICE_UDID mount /Library/Developer/DeveloperDiskImages/iOS_DDI
sudo pymobiledevice3 lockdown start-tunnel --udid DEVICE_UDID
# Keep the tunnel running; use its reported RSD address and port:
scripts/deploy.sh mini5 --no-build --register-ble-proxy --rsd RSD_ADDRESS RSD_PORT
```

The GATT test driver can obtain only the selected proxy's key through HA's
administrator API (`esphome/get_encryption_key`), keeping it in memory:

```sh
# HA_SERVER and HA_TOKEN must already be supplied to the environment.
build/ble-proxy-venv/bin/python scripts/ble-proxy-gatt-probe.py \
  --host PROXY_IP --address FIXTURE_ADDRESS --ha-entry PROXY_ENTRY_ID \
  --fixture FIXTURE_RECEIPT.json --output RESULT.json --stress-reconnect 3
```

Use it only with the controlled peripheral from `scripts/ble-test-peripheral.m`.
The driver checks its service UUID and marker before sending a test write.

Native transport checks:

```sh
uv venv --python 3.13 build/ble-proxy-venv
uv pip install --python build/ble-proxy-venv/bin/python aioesphomeapi pyobjc-framework-Cocoa noiseprotocol
bash scripts/test-ble-proxy.sh
```

Keep native transport tests, on-device radio observations, HA advertisement
delivery, and real GATT operations as separate acceptance results. The local
`Documents/ble-proxy-diagnostics.json` snapshot includes radio state, counts and
device observations. Validate its timestamp when collecting it; a stale file
does not prove a running app.

The initial validation established real HA advertisement delivery and a
successful HA clock-sync operation through a physical iPad Mini 4. HA's
connection allocation identified that iPad as the route, and the app recorded
the writes and reply notification. Controlled physical tests on the Mini 4 and
Mini 5 then verified reads, writes, notifications, readback and cached-handle
reconnects. The Mini 4 also passed three immediate reconnects after dropping the
network transport with a BLE connection allocated. Native transport checks
passed 10 tests; an isolated signed Catalyst regression run passed 45 existing
auth, registration and streaming tests. Broader device and failure-path
acceptance remains in progress; no App Store release is implied by these results.

Reference implementations and API documentation:

- [ESPHome native API](https://developers.esphome.io/architecture/api/protocol_details/)
- [ESPHome protocol schema](https://github.com/esphome/esphome/blob/dev/esphome/components/api/api.proto)
- [Home Assistant Bluetooth API](https://developers.home-assistant.io/docs/core/bluetooth/api/)
- [Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
- [BTHome encryption](https://bthome.io/encryption/)
