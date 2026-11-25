# NovaBeam

Android Beam, rebuilt with Flutter: **tap two phones together over NFC to bootstrap a
Nearby Connections session, then push the actual file over Wi-Fi Direct / BLE at
Wi-Fi speed — fully offline.**

Android Beam itself was deprecated in Android 10 and replaced by Nearby Share
(now Quick Share), which uses exactly this two-radio pattern. NovaBeam is a
minimal, open reimplementation of that idea in Flutter.

## How it works

```
 Phone A (has file)                         Phone B (receiver)
 ─────────────────                          ─────────────────
 "Start beaming"                            "Start beaming"
   ├─ NFC: arm NDEF push (handshake)         ├─ NFC: arm NDEF push (handshake)
   └─ Nearby: advertise + discover           └─ Nearby: advertise + discover
                    │ tap backs together │
   NFC push ───────────────────────────────▶  NDEF read (handshake A)
                                              └─ requestConnection(endpoint A)
   ◀───────────────────────────── connection initiated → acceptConnection
   ◀──── control: {auth, token from NFC} ──── (receiver echoes NFC token)
   token matches ──▶ control: manifest ─────▶ (name, size, mime, sha256)
   STREAM payload (file bytes) ─────────────▶ saved to files dir, sha256 verified
   ◀──── control: {ack} ────────────────────
```

- **NFC** (~424 kbps) carries only a small bootstrap record
  (`application/x-novabeam` NDEF MIME payload, JSON):
  `{v, endpoint, token, name, hasFile}` — see `lib/src/handshake.dart`.
  NFC is plaintext and unauthenticated, so nothing sensitive goes here and
  every field is strictly validated on parse.
- **Nearby Connections** (`ConnectionsClient`, `P2P_POINT_TO_POINT`) carries
  everything else, encrypted by default: an auth echo of the NFC token, a JSON
  manifest, then the file as a STREAM payload.
- Roles are decided deterministically from the tapped handshake: the phone
  without a file is the receiver (it initiates the connection); if both have
  files, the smaller endpoint id receives. The sender only starts sending after
  the receiver echoes the NFC token over the Nearby link and it matches.

## Repo layout

```
lib/
  main.dart                     app entry
  src/handshake.dart            NFC NDEF handshake model + strict codec (pure Dart)
  src/transfer_messages.dart    manifest + control message codecs (pure Dart)
  src/nfc_beam_channel.dart     MethodChannel/EventChannel wrapper for NFC
  src/nearby_channel.dart       MethodChannel/EventChannel wrapper for Nearby
  src/beam_controller.dart      session state machine (ChangeNotifier)
  src/home_page.dart            UI
test/                           unit tests for the pure-Dart codecs
android/app/src/main/kotlin/com/tinkerershaven/novabeam/
  MainActivity.kt               registers plugins, forwards NFC dispatch intents
  NfcBeamPlugin.kt              foreground NDEF dispatch + NDEF push callback
  NearbyBeamPlugin.kt           ConnectionsClient wrapper (advertise/discover/
                                connect/payloads, sha256 verify on receive)
  BeamTransferService.kt        dataSync foreground service (Android 14+)
```

## Build & run

Requirements: Flutter SDK (Dart >= 3.5), Android SDK with compileSdk 35, two
Android phones with NFC and Google Play services.

```bash
flutter pub get
# If android/gradle/wrapper/gradle-wrapper.jar is missing (this repo only ships
# the properties file), generate it once with any local Gradle 8.10 install:
#   cd android && gradle wrapper
flutter run        # on device A
flutter run        # on device B (or install the same APK on both)
```

On both phones: pick a file on the sender (optional on the receiver), press
**Start beaming**, then tap the backs of the phones together. Grant the
Bluetooth/nearby-Wi-Fi/notification permissions when asked. Received files
land in `Android/data/com.tinkerershaven.novabeam/files/` with the sha256 from
the manifest verified.

## Permissions

Declared in `android/app/src/main/AndroidManifest.xml` and requested at
runtime before beaming: `NFC`; `BLUETOOTH_SCAN/ADVERTISE/CONNECT` (API 31+,
`neverForLocation`) or `ACCESS_FINE_LOCATION` (<= 30); `NEARBY_WIFI_DEVICES`
(API 33+); `ACCESS_WIFI_STATE`/`CHANGE_WIFI_STATE` for Wi-Fi Direct;
`FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_DATA_SYNC` + `POST_NOTIFICATIONS`
to keep transfers alive on Android 14+.

## Security notes / limitations (MVP)

- The NFC handshake is authenticated by echoing the random per-session token
  over the encrypted Nearby link before any file is sent. Connections are
  auto-accepted — production should surface
  `ConnectionInfo.authenticationDigits` on both screens for user verification.
- The file is read into memory in Dart for hashing (`file_picker` bytes);
  large files should switch to `Payload.fromFile`/content-URI streaming.
- Android-only (NFC push + Nearby Connections are Android/Play-services
  features); iOS would need Core NFC read-only + MultipeerConnectivity.
- Requires Google Play services; Google has announced upcoming changes to the
  Nearby Connections API — pin `play-services-nearby` deliberately.

## Tests

```bash
flutter test    # codec round-trips + rejection of malformed NFC input
```
