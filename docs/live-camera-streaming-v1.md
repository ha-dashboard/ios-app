# Local Camera and Audio Streaming

## Compatibility boundary

The HA Dashboard app targets iOS 9.0 and is intended to run on iOS 9.3.3 and
later. Local Camera Stream is a separate optional feature that requires iOS
10.3.3 or later. Its persisted enable flag is discarded on an unsupported OS,
and every arm attempt checks the platform again before requesting permission.

Simultaneous front/rear capture uses `AVCaptureMultiCamSession`, so Both appears
only on compatible iOS 13-or-later hardware. A normal single-camera stream does
not require MultiCam support. Mac Catalyst is a developer-build target rather
than part of the iPhone/iPad App Store compatibility claim.

## Media and lifecycle boundary

HA Dashboard hosts its streams in-process. It uses no relay, cloud media
service, recording service, remote publisher, or third-party media server.
Turning on **Local Camera Stream** arms RTSP/RTP-over-TCP listeners while the
dashboard remains visible. No in-app or hidden preview is rendered.

Arming a listener does not turn on the camera or microphone. Capture begins
only when an RTSP client successfully authenticates and sends a media request
(`DESCRIBE`), which may occur before that client sends `PLAY`. Merely opening a
TCP connection, sending `OPTIONS`, or failing authentication does not activate
capture. Capture stops after the final authenticated media client leaves; the
armed listener remains ready for the next client. Turning the feature off,
leaving the foreground, logging out/resetting, losing permission, or a
listener/capture failure stops listeners and capture.

The enable switch, selected camera mode, and capability-based quality persist.
Returning to the foreground re-arms a previously enabled feature. Home
Assistant cannot remotely enable capture or change these app settings.

## Addresses, cameras, and consumers

- The listener binds the exact selected private IPv4 address on the primary
  `en0` interface (normally Wi-Fi). It does not bind cellular, VPN, CoreDevice,
  USB, or other host adapters and does not listen on every interface.
- A single selected camera uses `rtsp://<device>:8554/live`.
- In Both mode, front uses port 8554 and rear uses port 8555. Each stream carries
  the same live AAC microphone source and uses the same device credential.
- RTSP uses interleaved TCP only; UDP `SETUP` is intentionally unsupported.
- The implementation targets two simultaneous consumers per endpoint. Earlier
  pre-candidate builds physically demonstrated that count, but exact-candidate
  acceptance remains pending. The server does not publish a larger contractual
  client limit. A transiently blocked TCP receiver is protected by an ordered,
  bounded output queue rather than being disconnected on its first nonblocking
  `EAGAIN`; a receiver is disconnected if its pending queue reaches 1 MiB or
  makes no write progress for two seconds.
- Stream URLs use the device's current local address. Home Assistant must be
  able to route to it. Use a DHCP reservation; after an address change, re-arm
  and rerun registration so saved Generic Camera URLs are updated.

## Security boundary

Each device uses the fixed username `hadashboard` and one 32-character,
unpadded base64url password generated from 24 bytes of secure random data. The
password is stored as a device-only Keychain item that is available only while
the device is unlocked; it is not synchronised to another device. Turning the
stream off retains the credential so clients continue to work after re-arming.
**Log Out & Reset** deletes it.

The server requires RTSP Digest authentication (MD5 without `qop`, for legacy
VLC/live555/FFmpeg compatibility) before a connection can run `DESCRIBE`,
`SETUP`, `PLAY`, or `TEARDOWN`; `OPTIONS` remains public. One valid Digest
request authenticates that TCP connection while RTSP session/state checks still
apply to later requests. Every new connection receives a fresh nonce; a client
that reconnects with a previously verified nonce receives `stale=true` and must
recompute its Digest response. This access control prevents a client without
the password from activating capture, but it is not transport encryption: RTSP
control and interleaved RTP camera/microphone media remain
**plaintext and unencrypted on the LAN**. A host that obtains the password and
can reach the listener can receive live media. Use Local Camera Stream only on
a trusted local network, never forward ports 8554/8555, avoid exposing them
through a VPN, and turn the feature off when it is not needed.

Settings displays and sensor attributes use bare addresses without
credentials. Tapping an address copies that bare value. The explicit
**Protected access > Copy URL with Password** action copies a sensitive value
such as `rtsp://hadashboard:<password>@<device>:8554/live`. If the clipboard
value has not changed, it expires after 60 seconds. The item is local-only so
Universal Clipboard does not propagate it to another device; HA Dashboard also
clears an unchanged expired value while active or when it next becomes active.
This leaves enough time to switch to VLC and paste it. Other apps with clipboard
access may be able to read the credential before it expires. Treat copied URLs
as passwords. VLC or another receiving client may retain a protected URL in its
own history or logs; HA Dashboard cannot clear another app's storage.

**Rotate Stream Password** generates a new device password, disconnects current
viewers, and restarts the protected listeners. The rotation operation completes
when the local listener re-arms; it does not wait for Home Assistant. While
**Register with Home Assistant** is enabled, the app then starts asynchronous
reconciliation of the replacement credential with app-owned camera entries.
Retryable failures continue while the same stream, registration setting,
account, and Home Assistant origin remain active. Old URLs stop authenticating,
and clients or entries added manually must be updated manually. The settings UI
asks for confirmation before invalidating existing clients.

While capture is active, an always-on-top red **Camera + mic live** indicator
shows the authenticated media-client count above the dashboard, including in
kiosk mode. Tapping the indicator immediately stops and disables Local Camera
Stream. Reported sensor diagnostics separately distinguish raw connections,
authenticated media clients, and clients that sent `PLAY`.

The listener also limits each endpoint to eight concurrent sockets, caps a
request at 16 KiB, gives an unauthenticated socket five seconds to authenticate,
closes an idle authenticated connection after 10 seconds, and closes a
connection after three invalid-credential attempts. An initial missing
Authorization header and a verified stale nonce do not consume that failure
budget. Pending output is capped at 1 MiB per client and must make progress
within two seconds. These bounds reduce casual resource abuse but do not make
an exposed listener safe for the public Internet.

The **Mute Camera Audio** setting controls playback of Home Assistant camera
cards. It does not remove AAC audio from Local Camera Stream; disabling Local
Camera Stream is the way to stop publishing its microphone audio.

## Capability-based quality and orientation

The slider is built from formats reported by the selected camera. Its label
shows the selected resolution, frame rate, and estimated H.264 bitrate.
MultiCam mode uses formats supported by both cameras and caps frame rate for a
sustainable simultaneous-capture range.

Quality and orientation changes preserve connected RTSP sessions. HA Dashboard
restarts only capture/encoders, keeps RTP timestamps monotonic, and sends new
H.264 SPS/PPS plus an IDR so VLC/FFmpeg can reconfigure without reopening the
listener. Video follows the current interface orientation.

On iOS 10, AVFoundation deactivates `AVCaptureAudioDataOutput` when an app
selects a photo-equivalent camera `activeFormat`. The legacy single-camera path
therefore uses capability-checked 640x480/720p/1080p video session presets;
iOS 11+ and MultiCam keep direct capability formats. Old-device video and
microphone callbacks use separate serial queues. The live AAC input callback
also distinguishes temporary exhaustion from permanent end-of-stream so one
PCM chunk cannot finalize the reusable encoder after its first packet.

VLC 3.x commonly applies about 1000 ms of client-side network cache. For
latency testing, start VLC with `--network-caching=100 --rtsp-tcp`. Opening a
network URL starts playback automatically; pressing VLC's play/pause control
afterward pauses the stream.

## Home Assistant registration

**Register with Home Assistant** is first the opt-in mobile-app registration
used for device sensors and commands. Once it succeeds, an already armed Local
Camera Stream immediately starts its camera-entry flow. The app uses the
logged-in token with Home Assistant's Generic Camera config flow; Home
Assistant requires an administrator to create or change config entries.

Only config-entry IDs previously saved by this app are reused or updated. The
app never claims an existing Generic Camera by guessing from its title or host.
If no saved ID exists, it creates a new entry after Home Assistant validates
the source. In Both mode it creates named front and rear entries. Leaving Both
mode does not delete or disable the rear entry on the Home Assistant server;
remove it there if it is no longer wanted.

The app supplies the bare RTSP source URL, username, password, Digest
authentication mode, TCP transport, and selected 15/30 fps capture-profile rate
as separate Generic Camera settings. It tracks a non-secret credential revision
and the submitted frame rate so, while registration is enabled, rotating a
password or changing the profile starts asynchronous reconciliation of saved
entries even when the stream address has not changed. A changed credential,
profile, camera, address, or device name supersedes an older scheduled retry
immediately. An app-owned legacy entry missing either marker is forced through
Home Assistant's options flow rather than accepted unchanged.
Home Assistant therefore stores the stream credential in its config entry, and
Home Assistant backups may contain it; protect those backups as you would other
credentials.

Credential registration uses the configured Home Assistant server URL. HTTPS
protects the password submission in transit. Automatic registration over HTTP
proceeds without another per-server prompt only when the configured address is
loopback, `.local`, IPv4 link-local/RFC1918, or IPv6 link-local/unique-local.
**HTTP provides no transport encryption: another host able to monitor that LAN
may recover the camera username and password.** Use it only on a trusted local
network. Non-local HTTP is never accepted for automatic camera credential
registration. Same-origin redirect enforcement remains active for both HTTP
and HTTPS so credentials cannot follow a redirect to another origin.

Generic Camera validation uses a camera-specific 75-second request and
120-second resource timeout without slowing normal dashboard API calls. Home
Assistant 2026.8.3's Generic Camera flow starts a temporary HLS stream and waits
up to its 30-second source timeout for the first HLS part. A roughly 30-second
attempt therefore means Home Assistant did not obtain usable preview media; a
healthy iPad 4 validation in this run completed in about 2.9 seconds. After
each retryable failed attempt, the app waits 2, 4, 8, 16, and 32 seconds, then
60 seconds between attempts while the same stream, integration, account, and
Home Assistant origin remain active. These waits begin after the preceding
attempt ends; they are not an end-to-end completion deadline. The app requests
deletion of a known failed flow before scheduling its retry and logs cleanup
failures.
Disabling registration or the stream, stopping the listener, changing
account/origin, or full reset cancels in-flight and scheduled work.

If the user is not an administrator, direct RTSP continues to work and a Home
Assistant administrator can add Generic Camera manually. Use the bare URL,
username `hadashboard`, the password from between `hadashboard:` and `@` in the
explicitly copied protected URL, Digest authentication, and TCP transport.
Camera config-entry IDs, bare URLs, and non-secret credential revisions are
stored in the app container. The password remains in the device Keychain and,
after successful registration, the Home Assistant config entry. Camera and
microphone media never uses the mobile-app webhook, cloudhook, or remote UI
route.

The existing mobile-app integration reports `sensor.camera_stream` state, bare
active URLs, selected camera mode, authenticated-media/playing/raw connection
counts, MultiCam capability, and resolved quality. It never reports the stream
password. Other opt-in diagnostics may use a Home Assistant Cloud or remote UI
webhook returned by the user's Home Assistant instance; see the privacy policy
for the complete data list.

## Release acceptance record

Do not describe the following as release proof until it is completed against
one exact candidate.

- Candidate commit: _pending_
- Marketing/build version: _pending_
- Test date: _pending_
- Artifact hashes: _pending_
- iOS 9.3.3/9.3.5 armv7 launch, login, dashboard, Settings, reset: _pending_
- iOS 9–14 arm64 physical launch: _pending_
- Both armv7 and arm64 Mach-O minimum versions are 9.0: _pending_
- Privacy manifest present in iOS and Catalyst bundle locations: _pending_
- Catalyst H.264/AAC, permissions, login, Settings: _pending_
- Mini 4 single-camera decode and orientation: _pending_
- Mini 5 single-camera decode and orientation: _pending_
- iPhone front/rear/Both concurrent decode: _pending_
- Two consumers, disconnect capture stop, reconnect restart: _pending_
- Missing/wrong/correct Digest authentication and no pre-auth capture: _pending_
- Connection/request/idle/authentication-failure limits: _pending_
- Keychain persistence, rotation, reset deletion, and clipboard expiry: _pending_
- Kiosk-visible live indicator and tap-to-stop behavior: _pending_
- Live quality and rotation without client reconnect: _pending_
- Home Assistant admin/non-admin credential registration, password-rotation
  update, and proxy image: _pending_
- Foreground/background listener shutdown and persisted re-arm: _pending_

### Pre-candidate engineering evidence

On 31 August 2026, dirty development build 1.2.5 (159) produced H.264/AAC
playback on Catalyst, iPad Mini 4, iPad Mini 5, and iPhone. Two simultaneous
clients decoded the Mini 5 endpoint; iPhone front and rear MultiCam endpoints
decoded concurrently; and Home Assistant loaded Catalyst, Mini 4, and iPhone
Generic Camera entries. A later local rebuild compiled all sources separately
for armv7 and arm64, produced minimum-iOS-9.0 load commands in both slices, and
generated a matching two-architecture dSYM. This evidence predates the
protected-stream implementation, guided media work only, and is **not**
authentication or acceptance proof for the eventual 1.2.6 commit or IPA.

On 1 September 2026, the later dirty protected-stream source produced a signed
universal 1.2.5 (159) development app whose executable SHA-256 was
`a40044432c521cde6ff135d9638a83649662e0cf683f865b3fdc459dfaf96fe7`.
Both armv7 and arm64 slices and the bundle reported minimum iOS 9.0; the
signature, privacy manifest, and two-architecture dSYM UUIDs verified. A signed
Catalyst run passed 19 focused tests, including device-only Keychain behavior,
Digest gates, strict CSeq/request limits, the fixed unauthenticated deadline,
and cross-origin redirect/path rejection. Direct protected playback returned
401 before authentication, then 200 for DESCRIBE, both SETUP tracks, and PLAY;
the client received H.264 and AAC (148 video and 10 audio packets, first packets
at 7 ms and 15 ms), the red live indicator appeared during capture, and capture
stopped after disconnect. An earlier protected build also delivered both tracks
to two simultaneous authenticated clients.

At that stage this was still pre-candidate evidence: the tree was uncommitted
and behind `origin/main`; the then-current build still required a separate
local-HTTP credential exception that had not been approved, so protected HA
registration/rotation remained pending. The exact app was running on Catalyst,
upgraded successfully on iPad Mini 4, and installed on the connected iPad Pro;
the locked Pro could not be launched. Mini 5 accepted the IPA and reported
build 159, but its MobileDevice installer never returned a completion signal,
so that upgrade remains unverified. The iPhone remained locked. The iPad 4
was subsequently upgraded through Dropbear and remained running on iOS 10.3.3
with normal Home Assistant startup logs and no new crash report. Its Local
Camera Stream preference was not enabled, so protected capture/playback on that
device remains a user-driven permission test. This is not release or complete
physical-device acceptance.

Later on 1 September, an earlier signed dirty Catalyst build passed 35 focused
streaming/registration tests, including the then-bounded registration retry.
The final current source passed 37 signed streaming/credential tests and 60
isolated device-integration/remote-control tests, all with no failures or skips.
The current suites cover VLC's same-connection
Digest reuse, stale-nonce reconnect, partial write plus `EAGAIN`, ordered
H.264/AAC queue drain, slow-client eviction at the output cap, protected
app-owned Home Assistant entry updates at the selected profile's actual frame
rate, private-LAN HTTP policy, continuous context-bound retries, immediate
supersession by a rotated credential, iOS 10 audio-compatible presets, and
repeated AAC output after temporary live input exhaustion. They also cover the
audio stop/re-arm queue barrier, WebSocket-only registration migration, the raw
mobile-push event shape, standard 0–255 brightness payloads, wake/sleep,
navigation, appearance, kiosk and reload commands. A second Mac on a
different local subnet deliberately stopped reading for 500 ms, then received
11,812 H.264 and 727 AAC RTP packets through 15 seconds; both tracks were still
arriving at the end. Home Assistant updated the existing Catalyst entry in
place to Digest/TCP and 30 fps, validated the protected stream, and left the
entity loaded and idle. The rebuilt armv7 and arm64 slices and bundle still
reported minimum iOS 9.0. This remains development evidence, not an exact clean
release-candidate result.

The latest dirty fleet artifact is recorded under deploy evidence run
`20260901T141019Z-23305`, built from rebased commit `044af4c` as build 162.
Its universal executable SHA-256 is
`fe58c424626473c0a9b15a2c52f173acf9ca47fbeb1e587022be59e3f87dc3f4`;
the Catalyst executable is
`3d7259f8dd2bd9bbda9cd59b837ed1d7009c71bbcfd10af535505b0bc1b5d042`.
Both universal slices and the bundle report minimum iOS 9.0, and the automatic
profile covers the five active physical targets. That exact universal bundle
was installed on iPhone, Mini 5, Mini 4, iPad 4, and iPad Pro. Mini 4 and iPad 4
launched; Mini 5 reported `InstallComplete`; the locked iPhone and iPad Pro are
recorded as installed-only successes. Catalyst launched from a single 4.5 MiB
non-mergeable main executable, so its recorded hash identifies the application
code rather than Xcode's former 56 KiB debug launcher.

On physical iOS 10.3.3, the final iPad 4 process used the iOS 10-safe 1280x720
preset and 44.1 kHz mono audio. Home Assistant consumed HLS for 12.613 seconds:
the master request returned 200, 2/2 playlists and 13/13 media resources
returned HTTP 200, 7,089,608 media bytes arrived, and there were no fetch
errors. The
fresh device session recorded the Digest challenge followed by authenticated
DESCRIBE 200, both SETUP responses, PLAY 200, first and sustained PCM, first
H.264 RTP, first AAC RTP, and a graceful TEARDOWN/disconnect. Home Assistant
still has exactly one loaded `iPad Office Camera` entry and one corresponding
entity, so registration/relaunch created no duplicate.

The same final iPad 4 build refreshed its old registration to WebSocket-only
local push and Home Assistant explicitly accepted the channel. A live
`notify.mobile_app_ipad_office` call delivered `command_screen_on`; the standard
`command_screen_brightness_level` payload then restored the measured 79%
brightness. A second brightness command delivered more than 10 seconds later,
proving confirmations kept the local channel alive. Wake on Touch's one-minute
state transition is separately covered by deterministic controller/handler
tests because that option was not enabled on this iPad. This remains a dirty
development deployment, not the merged/tagged release candidate.
