# Privacy Policy — HA Dashboard

**Last updated:** September 2026

HA Dashboard is a native app that connects to Home Assistant infrastructure
chosen by the user. This policy distinguishes communication with that
infrastructure from collection by the app developer.

## Developer Data Collection

HA Dashboard does **not** send personal data to the developer and contains no
developer analytics, tracking, advertising, telemetry, or crash-reporting SDK.
The developer cannot access your Home Assistant credentials, dashboard data,
device diagnostics, or camera/microphone media through the app.

## Home Assistant Communication

- The app exchanges authentication, dashboard configuration, entity state, and
  service-call data with the Home Assistant server URL you configure.
- If you explicitly enable **Register with Home Assistant**, the app registers
  a mobile-app device and sends its generated device ID, device name, model,
  operating-system/app versions, battery, brightness, app state, active
  dashboard, network state, Wi-Fi SSID/BSSID when available, and Local Camera
  Stream status, bare URLs, camera mode/capability, quality, transport and
  authentication mode, and authenticated/playing/raw connection counts to your
  Home Assistant instance. It does not send the stream password as a sensor
  value.
- Home Assistant may return a Home Assistant Cloud cloudhook or remote UI URL.
  When present, optional device diagnostic webhooks may use that user-controlled
  route. Camera and microphone media never uses a cloudhook or remote UI route.
- Remote commands and in-app notification banners use Home Assistant's local
  WebSocket push channel while the app is open and connected. The app does not
  register a developer cloud-push URL/token or fall back to a developer push
  service when that channel is unavailable.
- Available-storage diagnostics are sent only when the selected webhook route
  is a local-network address and only after device registration is enabled.

## Local Camera and Microphone Stream

- Local Camera Stream is off by default and requires iOS 10.3.3 or later. It
  requests Camera and Microphone access only after you enable the feature.
- While the app is foregrounded, enabling the feature arms an in-process
  H.264/AAC RTSP-over-TCP listener on the selected private primary (`en0`)
  address. Camera and microphone capture starts only after an RTSP client
  successfully authenticates and requests media, not merely because the toggle
  is on or an unauthenticated client reaches the port.
- A single selected camera uses port 8554. On supported MultiCam devices, Both
  mode uses front on 8554 and rear on 8555.
- Each device uses the fixed RTSP username `hadashboard` and its own
  cryptographically generated 32-character password. The password is stored in
  the platform Keychain as available only while the device is unlocked and is
  not synchronised to other devices.
- The listener requires RTSP Digest authentication, but RTSP/RTP media remains
  plaintext and is **not encrypted on the local network**. A host with the
  password and network access can receive live camera and microphone media.
  Use this feature only on a trusted local network, do not forward these ports
  or expose them through a VPN, and turn it off when it is not needed.
- A visible **Camera + mic live** indicator appears above the dashboard,
  including in kiosk mode, whenever authenticated viewers have activated
  capture. Tapping it stops and disables Local Camera Stream.
- The **Mute Camera Audio** setting affects playback of Home Assistant camera
  cards only. Local Camera Stream includes microphone AAC whenever it is being
  viewed; turn Local Camera Stream off to stop publishing that audio.
- Capture stops after the final authenticated media client disconnects. The
  listener and capture both stop when you turn the feature off, leave the
  foreground, log out, lose permission, or encounter a listener/capture
  failure. The app does not record media, show a hidden preview, run
  camera/microphone capture in the background, or accept a Home Assistant
  command that remotely enables capture.

## Credentials and Local Storage

- Home Assistant access and refresh tokens are stored in the platform Keychain.
  Developer deployment arguments may bootstrap a token once; the app moves
  valid credentials to Keychain and removes persisted bootstrap values.
- The Local Camera Stream password remains in the device-only Keychain when the
  stream is turned off so existing clients continue to work the next time it is
  enabled. Rotating it disconnects current viewers and invalidates manually
  saved URLs. **Log Out & Reset** deletes it; a new password is generated if the
  feature is used again.
- The stream address shown in Settings and reported as a sensor attribute does
  not contain credentials. The explicit **Copy URL with Password** action puts
  a sensitive connection URL on the system clipboard as a local-only item, so
  it is not propagated through Universal Clipboard. The app gives the system a
  60-second expiration date and also clears an unchanged expired value itself
  while active or when it next becomes active. Other apps with clipboard access
  may be able to read the credential before it expires. A receiving RTSP client
  may retain a protected URL in its own history or logs; remove it there when no
  longer needed.
- App preferences, cached Home Assistant state, stream mode/quality, and saved
  Home Assistant config-entry IDs and non-secret credential revisions are
  stored in the app container.
- If camera registration is enabled, Home Assistant stores Generic Camera
  entries with the bare RTSP URLs, username, and password on your Home Assistant
  server. Password rotation completes locally after the protected listener
  re-arms and does not wait for Home Assistant. While **Register with Home
  Assistant** remains enabled, the app then starts asynchronous reconciliation
  of the replacement credential through Home Assistant's camera config flow. It
  updates only entries whose IDs it saved, or creates a new entry when it has no
  saved ID; retryable failures continue while the same stream, registration
  setting, account, and Home Assistant origin remain active. Manually configured
  or unowned entries must be updated manually. Home Assistant backups may
  therefore contain the stream password; protect those backups as you would
  other Home Assistant credentials.
- Camera registration sends the username and password to the configured Home
  Assistant URL using that server connection. HTTPS protects that submission in
  transit. For a loopback, `.local`, link-local, RFC1918, or IPv6 unique-local
  Home Assistant address, automatic registration may instead use HTTP without
  another per-server prompt. **HTTP provides no transport encryption: another
  host able to monitor that LAN may recover the camera username and password.**
  Use this only on a trusted local network. Non-local HTTP is never accepted for
  automatic camera credential registration.
- Live camera and microphone media is not written to the app container, Photos,
  iCloud, or a developer service.

## Local Network Access

The app uses Bonjour/mDNS to discover Home Assistant and may host the optional
RTSP listener described above. iOS and iPadOS 14 or later request Local Network
permission for this access; earlier supported releases do not show that system
permission. Discovery results remain on the device.

## User Controls and Retention

Turning off Register with Home Assistant stops device reporting and removes its
local webhook credentials. **Log Out & Reset** clears local Home Assistant and
stream credentials, registration identity, preferences, cached Home Assistant
state/history, local logs, and stream configuration. Home Assistant devices and
Generic Camera entries, including their saved stream credentials, are not
deleted automatically; remove them in Home Assistant if no longer wanted.

## Cookies, Tracking, and Third-Party SDKs

The app does not use cookies, advertising identifiers, tracking, or web-based
analytics. It includes no third-party analytics or advertising SDK. Home
Assistant and optional Home Assistant Cloud routes are services configured by
the user, not developer data-collection services.

## Children's Privacy

The developer does not knowingly collect data from anyone, including children.

## Changes to This Policy

If this policy changes, the updated version will be published at the same URL.

## Contact

For privacy questions, open an issue on the GitHub repository. A separate
non-GitHub support address has not yet been published.
