# Bluetooth Proxy

HA Dashboard can act as an encrypted, ESPHome-compatible Bluetooth LE proxy
while the iOS app is open. It uses public Core Bluetooth APIs. This feature
extends the range of compatible Home Assistant BLE integrations; it does not
forward Bluetooth audio or expose an unrestricted radio adapter.

## Setup

1. **Register with Home Assistant** automatically activates the proxy unless you
   have explicitly switched Bluetooth Proxy off. You can also enable it in
   Settings → Bluetooth Proxy. Allow Bluetooth access when prompted.
2. Keep the dashboard open. Kiosk mode can prevent automatic display sleep.
3. With device registration enabled and an administrator account connected,
   setup happens automatically through the existing ESPHome integration. The
   **Add to Home Assistant** button remains available for manual setup.
4. Alternatively, add ESPHome manually using the displayed local address,
   port 6053, and the copied encryption key.

Home Assistant must reach the device's private IPv4 address. A DHCP reservation
is useful. Proxy traffic is encrypted with Noise NNpsk0; setup sends the key via
the configured HA HTTP/HTTPS connection, so use HTTPS or a trusted local network.
There is no developer relay. Leaving the iOS app or locking it pauses the proxy.

Automatic setup refuses non-local HTTP endpoints. The next App Store submission
must review export-compliance classification for the bundled cryptography; the
previous blanket exemption flag is omitted so App Store Connect presents its
[encryption questionnaire](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption).

## Device identity

Apple supplies local peripheral UUIDs instead of Bluetooth MAC addresses. The
proxy therefore distinguishes:

- Addresses embedded in supported SwitchBot manufacturer advertisements.
- Hardware addresses explicitly associated by the user.
- Local aliases for devices whose address is unknown.

The proxy imports known HA identities and independent scanner observations
automatically. It can bind Blue Connect device identifiers to independently
observed addresses, including registry entries without Bluetooth connections.
An unambiguous GATT serial can also match an address registered in HA. Generic
names, services and matching measurements never authorize an automatic link.
Conflicting records or addresses require confirmation. All HA Dashboard proxy
sources are excluded from address evidence; native and ESP32 scanners remain
eligible. Automatic associations are scoped to the HA account session and
refresh every five minutes. Supported Blue Connect advertisements are briefly
buffered during the initial import to avoid premature alias discoveries.

Tap a nearby device to inspect matching evidence and known Bluetooth devices. The matching view
compares registry information and advertisements received by other scanners.
It can also read standard GATT serial, system ID, manufacturer and model fields
when a device provides them. Matching names, readings and service UUIDs are
suggestions, not proof of identity; confirm the physical device before linking.

An alias is not a hardware MAC. It may create a separate HA identity, will not
automatically match other iPads or ESP32 proxies, and cannot substitute for the
address used by encrypted BTHome payloads. Each iPad needs its own association
between Apple's local identifier and the known device. Some devices provide no
unique readable identifier and require manual association.

## Discovery modes

Automatic mode starts with broad Core Bluetooth discovery. If it receives no
discoveries for ten seconds, it can import service UUIDs observed by Home
Assistant and scan for those services. While using filters, it periodically
tries broad discovery again. HA service imports refresh every five minutes.

The Discovery section also provides explicit **Broad discovery** and **Known
services** modes, a manual HA import, and additional service UUIDs. Manual UUIDs
are combined with HA's imported services. A total of 128 filters is supported.
HA's advertisement subscription requires administrator access; manual service
UUIDs can be used when no other HA scanner has observed the device.

These are advertised service UUIDs, not characteristic IDs or MAC addresses.
Devices without a matching advertised service may be missed in filtered mode.
Choosing filters does not establish a device's identity or automatically link
its hardware address.

A controlled test on a jailbroken iPad 4 running iOS 10.3.3 received zero
callbacks with three broad-scan variants and 504 callbacks with an explicit
service filter, while the nearby iPhone reference was verified advertising
throughout. The reference included a name and a 128-bit service UUID; Apple's
[overflow advertising](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/startadvertising(_:))
can require an explicit service filter. This result is specific to that control,
not proof that all broad scanning fails on those iOS versions. Build 170 then
passed physical GATT checks on both the iPad 3 and iPad 4. The iPad 3 discovered
the reference using services imported from HA, without a manual seed.

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
the local key, address associations, service filters, handle tables and diagnostic snapshot.
Remove unwanted ESPHome entries separately in HA.

## Development and validation

`scripts/deploy.sh` accepts `--ble-proxy`, `--no-ble-proxy`, and
`--register-ble-proxy`. Add service filters with `--ble-services FCD2,FD3D`.
For an explicitly selected CoreDevice target, use
`device --device-id ID`. Normal installations remain opt-in.

For a developer-authorized credential replacement, transfer a private JSON file
containing `server` and `token` to the app's
`Documents/.ha-bootstrap-auth.json`, then launch with
`-HAImportBootstrapAuth`. The app consumes and deletes the file before saving
credentials to Keychain. Keep the transfer file out of receipts and logs, remove
the local temporary copy, and verify that the device copy was consumed. Do not
put the token in process arguments. This import requires the explicit launch flag.

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
  --host PROXY_IP --discover-fixture --ha-entry PROXY_ENTRY_ID \
  --fixture FIXTURE_RECEIPT.json --output RESULT.json --stress-reconnect 3 \
  --check-client-isolation
```

Use it only with the controlled peripheral from `scripts/ble-test-peripheral.m`.
The driver checks its service UUID and marker before sending a test write.
Live discovery avoids selecting an old alias after a reference device rotates
its Bluetooth address. A known fixed address can alternatively be supplied with
`--address FIXTURE_ADDRESS`.
The optional client-isolation check verifies prompt rejection of a second
client and confirms that the original connection remains readable.

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

Physical validation on 13 September 2026 established encrypted HA advertisement
forwarding and active GATT operation using public APIs. Build 173 was installed
and launched on all nine available iOS devices, plus Catalyst. Fresh diagnostics
showed seven iOS proxies and Catalyst forwarding, and HA reported all eight
corresponding ESPHome entries loaded.

| Device | Build 173 runtime receipt | Last complete physical GATT check |
| --- | --- | --- |
| iPhone 11 | Forwarding to HA | Build 173 |
| iPhone 16 Pro Max | Forwarding to HA | Build 172 |
| iPad Pro M2 | Forwarding to HA | Build 167 |
| iPad Mini 4 | Forwarding to HA | Build 167 |
| iPad Mini 5 | Forwarding to HA | Build 173 |
| iPad 3, iOS 9.3.5 | Forwarding with service filters | Build 170 |
| iPad 4, iOS 10.3.3 | Forwarding with service filters | Build 170 |
| Second iPad Pro | Bluetooth permission denied | Not performed |
| iPad 2, iOS 9.3.5 | Core Bluetooth reports unsupported | Not applicable |

The GATT checks verify the reference service and marker, an acknowledged write,
matching notification and readback, cached-handle reconnect,
three reconnects after dropping the network transport, and rejection of a second
client while preserving the original connection. The last GATT build and final
installation are reported separately; installing build 173 is not a claim that
every device repeated the complete GATT test on that build.

Earlier real-device validation also routed a Home Assistant clock-sync operation
through the Mini 4 to a SwitchBot CO2 meter. HA identified the proxy allocation,
and the app recorded the writes and reply notification.

Native transport checks passed 10 tests. The signed Catalyst regression selection
passed 59 tests covering BLE, authentication, OAuth, device registration and
streaming. This includes bounded retries when HA rejects refreshed credentials.
The iPhone 11's administrator credential bootstrap was subsequently validated on
the physical device: HA registration succeeded, the one-time file disappeared,
and preferences contained no access token.

Temporary phone and iPad test apps are separate from HA Dashboard. No private
Bluetooth framework is needed for these results. Foreground operation and
Core Bluetooth's identity/discovery limits still apply; these checks do not
establish unattended background service or universal device compatibility.
No App Store release is implied by this development validation.

Reference implementations and API documentation:

- [ESPHome native API](https://developers.esphome.io/architecture/api/protocol_details/)
- [ESPHome protocol schema](https://github.com/esphome/esphome/blob/dev/esphome/components/api/api.proto)
- [Home Assistant Bluetooth API](https://developers.home-assistant.io/docs/core/bluetooth/api/)
- [Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
- [BTHome encryption](https://bthome.io/encryption/)
