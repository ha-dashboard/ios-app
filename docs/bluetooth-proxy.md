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

## Single-proxy operation

An installation with one iPad does not require another scanner to forward BLE
advertisements. Each peripheral already has a stable local transport alias derived
from the persisted installation identity and its Core Bluetooth identifier.
Unknown devices can forward once the initial import establishes that no candidate
is pending. A potentially known device gets at most sixty seconds of learning
before forwarding under that alias, even if import fails or matching remains
unresolved. Identification and read-only probing continue after this deadline.

The alias is not a recovered hardware MAC. It survives ordinary app restarts and
upgrades while the installation and Core Bluetooth identifiers remain the same.
Reinstallation, explicit reset or an OS identifier change can require additional
fingerprint evidence to reconnect the previous identity. Joining a second proxy
must compare evidence rather than equating its unrelated Apple UUID with the
first proxy's UUID. The standalone timeout does not create verified bindings or
merge ambiguous candidates.

A sole proxy can also create a fingerprint-derived logical identity after two
separate stable reads of an eligible identifier. Eligible fields include the
standard Device Information Serial Number and System ID characteristics, plus
context-filtered MAC/UUID fields in structured characteristic values. Model
strings, generic profiles, changing values and placeholder identifiers do not
qualify. Serial-based identities additionally require stable manufacturer and
model values from the same Device Information service. Those values scope the
serial, so two manufacturers or models reusing a serial do not collapse into one
identity. A joining proxy must supply matching context when using serial as a
secondary identifier. No second proxy or registered HA device is required. Unresolved
connectable devices enter the bounded automatic probe queue even without an
integration matcher or external reference; discovery waits, connection-slot
limits, per-device retry limits and read-only operation restrictions still apply.
The probe queue first completes pending repeat reads, then prioritizes devices
whose name or profile has an eligible fingerprint reference in the shared
catalog or fresh peer inventory, then uses signal strength. This is only a
scheduling hint: it cannot select an identity or bypass connection and retry
budgets. Unknown standalone devices remain eligible when references are absent
or cooling down.
Referenced devices can be attempted if seen within sixty seconds, accommodating
sparse reception; unknown devices retain the fifteen-second freshness limit.
Connection timeouts and probe budgets still bound unsuccessful attempts.
Connectable provisional matches remain eligible for these probes; verified and
manually associated devices do not. Diagnostics include the last automatic probe
time and this process's attempt count, including unsuccessful attempts, so an
untried device can be distinguished from one that has been attempted.
Successful characteristic reads are retained if a later operation fails. Such
sessions remain explicitly incomplete and retain their error; a failed session
with no read data cannot add evidence or erase earlier fingerprints. The normal
independent-session and contradiction checks still apply to partial reads.
The latest automatic probe also reports whether it is pending, complete, partial
or failed, with timestamps and the reported error when available.

If HA has already configured a device under this receiver's generated local
alias, a later GATT proof preserves that address and HA device identity. The
proof is shared automatically, so a joining proxy with a matching fresh witness
can reuse it. Provisional similarity cannot replace that configured local address
or be published as a verified bridge. Multiple HA devices claiming the same local
address remain ambiguous.

Compatible independently created synthetic and registered GATT identities are reconciled into
a deterministic canonical view. A common eligible identifier connects the proofs;
conflicting stable identifiers or manufacturer/model context reject the complete
connected group. One configured HA address takes precedence; multiple configured
addresses remain ambiguous. Original catalog proofs are retained, and cached
unions cannot override later contradictory evidence. This reconciliation currently
covers GATT roots and configured local aliases, not native/provisional identity migration.

The shared proof retains all collected identifier fields. A later proxy can match
an available secondary field without changing the canonical address originally
chosen from another field. Matching remains subject to conflicts and competing
devices; the resulting address is a logical identity, not an assertion that the
read value was the peripheral's Bluetooth MAC.

## Device identity

The resolver is generic. It has no sensor-brand names, company-ID tables, model
patterns or vendor service UUIDs in its production matching rules. It imports
HA's device registry and existing discovery metadata as data, so those rules do
not need to be copied or maintained in this app.

Synchronization starts automatically with the HA connection, listens for
registry and shared-state changes, and periodically refreshes. A manual refresh
is optional. Known identities, standard identification fields and relevant live
peer observations are imported without user-managed synchronization.

The initial import reads HA registry IDs, Bluetooth addresses, registered unit
identifiers, friendly names, model and serial metadata, plus the installed
integrations' discovery manifests. A registry update triggers another import;
reconnection and a five-minute fallback refresh cover missed updates. The native
advertisement subscription renews every thirty seconds to obtain a current HA
snapshot even when unchanged payloads produce sparse update events. Original
observation times are retained; replayed snapshots do not add samples, and
retired callbacks or older observations cannot replace newer evidence. Once a
minute, an authenticated Bluetooth diagnostics request also imports individual
scanners' raw observations. This preserves independent native evidence when the
general feed selects a proxy reporting the same canonical address. Only bounded
BLE fields are retained; app-proxy sources are excluded, and scanner monotonic
timestamps preserve observation age. Diagnostic byte literals are decoded with
a restricted parser, never evaluated. Shared
associations and peer evidence have their own live subscriptions. A friendly
name is used for display after identification, not substituted for an identity.

The resolver considers:

- Standard GATT serial/system identifiers and registered HA unit identifiers.
- Address bytes in observed payloads, corroborated by an independent radio.
- Timestamp-aligned changes in manufacturer and service-data payloads.
- Stable identifier-shaped values from bounded read-only GATT probes, compared
  across proxies. Matching serial-like MAC/UUID fields can establish a shared
  synthetic identity without a registered HA device or native scanner.
- Names, service inventories and packet shapes as candidate filters, not unique
  identities on their own.

A separate provisional tier can reuse an independent native radio address when
an identifier-shaped name (letters and digits), canonical service list and
complete payload fields agree. Local reception must span thirty seconds with
at least three distinct observation times and no gap over twenty seconds during
initial qualification. Once qualified, the unchanged signature can survive a
reception gap of up to two minutes; a changed signature or longer gap starts
learning again. A fresh local packet and native reference no older than two
minutes are still required, and conflicting devices still veto the match.
If Apple supplies an extended
payload, every byte of the complete shorter native field must agree; arbitrary
common prefixes, missing channels and contradictory fields do not qualify.

When no native identity is available, a separate peer-only provisional path
compares the complete name, service list and payload against fresh original
observations from another registered app proxy. It requires sustained local
reception and rejects twins or conflicting identifier fields across the matching
observations. Its deterministic synthetic address lets non-connectable devices
converge without a GATT probe. Existing verified or native references are not
replaced by this path. These associations are not persisted as verified proof. An unchanged signature on the same local peripheral retains its address
through temporary peer loss and app restart. A minimal local record stores only
the signature and historical sources, bound to the HA account and receiver scope.
Fresh matching data is required after reload; no saved address override is trusted. Conflicts, stronger identities, changed signatures,
removed observations and changed HA/source scope invalidate that continuity.
Payload-change handling and merging independently created roots still require
lifecycle validation before claiming complete identity continuity.

Provisional associations are explicitly described as such in their evidence.
They are re-evaluated during scanning and are never persisted or published as
verified proof. Competing local devices or native addresses with the same
signature reject the association, including twins with differing extensions of
the same native payload. This tier is observational evidence, not a guarantee
of a unique hardware identity.

Packet correlation requires twelve distinct changes, distributed over time,
with strong agreement and clock alignment. It retains a bounded fifteen-minute
window to accommodate slow sensors. Static readings and repeated snapshots do
not qualify as packet-sequence evidence. HA's accumulated manufacturer dictionaries are never
treated as individual packets; independent raw advertisements or authenticated
peer observations supply the timing evidence.

Correlation compares opaque payload bytes in channels grouped by AD type and
payload length, preserving separate histories when one device alternates packet
layouts. Qualification requires at least 90% agreement, changes in six or more
five-second buckets spanning at least thirty seconds, median observation skew
no greater than three seconds, and evidence seen within the last two minutes.
Contradictory comparable channels or competing local/remote candidates reject
the match. These thresholds are conservative evidence checks, not a guarantee
that arbitrary indistinguishable transmitters can be identified.

For equal-length payloads, the engine can learn a small recurring leading-byte
alphabet and compare those packet groups separately. No prefix value has a
predefined device or protocol meaning. Each group still needs the full changing
payload evidence; contradictory comparable groups still reject the match.
Rejected decisions expose timing, agreement, freshness, or ambiguity reasons
instead of showing only a count that has already exceeded the threshold.

Generic associations are stored in HA's shared system store. Local Apple UUID
bindings remain scoped to the configured HA account. An automatically synchronized, bounded inventory also shares unresolved
observations, original local aliases and hashed GATT fingerprints independently
of the verified catalog. Publication rotates through payload-limited batches;
receivers merge batches and expire stale observations. Newer devices replace
older observations when a local inventory reaches capacity. Origin lineage prevents a derived proxy from validating its ancestor.
Previously verified bindings survive restarts, and the earlier stored-association
format is migrated as data rather than through device-specific parsing rules.

Because HA's shared store does not provide an atomic compare-and-swap, each peer
reconciles missing catalog additions against its still-valid local proofs. This
repairs additions lost to concurrent writes without overwriting an existing
association at the same address. Registered-device proofs must still match HA's current registry and local
account scope. Observed native and peer-only identities have separate validated
provenance and do not require registry membership.

Each receiving Apple device must establish its own local peripheral-to-HA
binding. Importing a shared catalog entry alone does not equate an unfamiliar
Apple UUID with that physical unit. A receiver can compare its observations
with a verified peer's history automatically; the peer preserves original
observation times instead of making old packets appear new when republished.

Unambiguous standard identity or corroborated evidence can establish a binding.
Indistinguishable candidates remain pending. Public Bluetooth APIs cannot prove
that two identical observable signals belong to different units; confirmation
may be necessary in those cases. Confirmed associations then synchronize
automatically. Generic names or equal sensor readings never justify merging
all matching devices into one address.

Read-only identification probes are bounded and use standard Device Information
characteristics. The app does not send vendor control commands for matching.
Unknown aliases are explicitly labelled and are not hardware MAC addresses.

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

For a shared-identity acceptance check, launching with
`-HABLEIdentitySharedOnly YES` skips live scanner comparison in the identity
resolver. It still requires an existing verified HA association; the flag does
not supply or override any address. Normal launches compare live observations.

Use the GATT test driver only with the controlled peripheral from
`scripts/ble-test-peripheral.m`.
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

Generic resolver completion validation (builds 187–189):

- 86 signed focused regression tests pass, including ambiguity, timing shifts,
  static readings, contradictory packet groups, account changes, automatic
  subscriptions, peer lineage and concurrent-catalog reconciliation.
- HT1 and HT.w both resolve to their existing HA registry addresses. HT.w's
  shared proof records fourteen changing payloads against the independent
  scanner. Catalyst subsequently qualified thirteen changes using verified peer
  observations, with median timing skew approximately 0.01 seconds.
- Build 189 Catalyst and iPad Pro restored both bindings immediately after an
  update/restart, before accumulating a new qualifying sequence. Encrypted
  captures then received HT1/HT.w counts of 16/11 and 25/26 respectively, with
  every captured advertisement using the configured address.
- iPhone 16 also passed both-sensor encrypted captures on build 187. Its initial
  build 189 capture was unavailable while the app was paused; this failed receipt
  is retained rather than represented as a forwarding pass. After resuming, its
  build 189 capture received 21 HT1 and 31 HT.w advertisements, all with the
  configured addresses. The capture logged an EOF; these counts prove forwarding
  and identity, not uninterrupted connection uptime.
- No manual identity import or manufacturer-specific production rule was used.
  The earlier Mini 5 shared-only learning and restart checks below independently
  establish automatic peer import without native-scanner comparison.
- Two existing SensorPush discovery prompts remain, including the older Mini 4
  aliases. These are not deleted by identity learning, and an older proxy that
  remains active needs updating separately. This validates the resolver; it does
  not claim every unavailable fleet member is running the latest build.

The equal-length packet-group regression reproduces a generic dilution problem.
It is not proof that this was the sole cause of the earlier HT.w delay: the
captured live rejection identified timing alignment, and later peer evidence
qualified without lowering the thresholds.

Earlier generic identity validation (builds 181–183):

- 82 signed focused regression tests pass on build 183, including changing
  payloads, alternating advertisement layouts, ambiguous devices, stale evidence,
  peer lineage, original observation timestamps, and startup advertisement bursts.
- Catalyst learned the configured SensorPush HT1 address from twelve distinct
  independently observed payload changes over approximately ten minutes. No
  SensorPush-specific parser, identifier table or manual import was used.
- A build 182 Catalyst restart with live scanner comparison disabled restored
  that binding from the local Apple UUID and automatically imported HA catalog.
  This proves restart restoration; it does not alone prove a new peer can learn it.
- Build 183 corrected a main-thread overload found on the Mini 5: advertisement
  callbacks no longer repeatedly classify every buffered packet against the
  registry. Fresh Mini 5 diagnostics now advance while scanning and synchronizing.
- Build 183 Mini 5 independently learned the same SensorPush address with native
  scanner comparison disabled. HA carried its learning requests and the verified
  peers' timestamped observation history automatically. Twelve changes qualified
  the binding without a manual import or address assignment.
- A subsequent encrypted wire capture received eight matching SensorPush
  advertisements from Mini 5, three from iPhone 16, and six from iPad Pro; every
  captured address equalled the existing HA address. Catalyst received four
  more after returning to the foreground. Mini 5 restored its binding immediately
  after restarting in normal comparison mode. Two pre-existing SensorPush
  discovery prompts remained, including the unreachable Mini 4's old alias.
- Fleet validation is partial: Mini 4 was unavailable, iPad 4 refused SSH, the
  second iPad Pro installed but was locked, and iPhone 11 launched and connected
  to HA but retained stale BLE diagnostics. Older results below describe their
  specific builds and are not acceptance of the generic replacement.

Earlier identity and activation validation (build 178, before the generic resolver):

- 74 signed regression tests passed, including delayed HA startup, partial
  advertisements, conflicting identifiers, persisted associations and opt-out.
- Six proxy receipts agreed on the existing Blue Connect address. HA retained
  its one configured sensor, and the restart monitor reported zero duplicate
  discovery prompts in seven checks over one minute, followed by a clear final
  check after the remaining deployments.
- A build 178 restart with live identity comparison disabled forwarded both
  observed pool advertisements under the address stored in HA. This verifies
  the shared-identity path independently of fresh scanner address evidence.
- The iPhone 11 buffered its initial pool advertisement until identity import
  completed, then matched it with no dropped packets. Known unresolved devices
  now remain pending instead of escaping through a startup timeout as aliases.
- All nine available iOS devices received build 178. Eight have runtime
  receipts; the second iPad Pro was locked after installation. The iPad 2
  reports unsupported BLE hardware. Catalyst was restored to normal mode.

A read-only pool connection through the matched Mac proxy discovered its vendor
GATT services. The pool does not expose the standard Device Information service,
so its automatic identity uses the Blue Connect identifier and vendor evidence.
A separate Mini 5 pool connection attempt timed out at a weak signal; matching
an identity does not establish reliable radio range. Earlier complete GATT
acceptance is recorded separately below.

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
