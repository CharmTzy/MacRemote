# Mac Remote

Control your Mac from your iPhone over your local network. No cloud, no
accounts, no App Store — a Mac host app and an iPhone client app that find
each other over Bonjour and talk directly, peer to peer, on your LAN.

This is a personal-use project, built from scratch on Apple's native
frameworks (SwiftUI, Network.framework, ScreenCaptureKit, VideoToolbox,
CryptoKit) rather than on top of WebRTC or a hosted signaling service.

## Status

This repository is being built in phases (see `ARCHITECTURE.md` for the full
list). What exists right now:

- [x] Phase 1 — Project foundation, Bonjour discovery, and a Hello/HelloAck
      handshake over a real TCP connection.
- [x] Phase 2 — Pairing (numeric code), Ed25519 device identity, signature-based
      session authentication for returning devices, AES-GCM encrypted
      post-auth channel, Keychain-backed trusted-device store with revoke.
      **Written but not yet run on real hardware** — see the note below.
- [x] Phase 3 — Live screen streaming: ScreenCaptureKit capture → VideoToolbox
      H.264 encode → encrypted video connection → `AVSampleBufferDisplayLayer`
      on the iPhone. **Written but not yet run on real hardware** — see the
      note below, and ARCHITECTURE.md's "Video pipeline" section for which
      two files carry the most risk.
- [x] Phase 4 — Direct-touch mouse control on the video view: tap (click),
      double tap, long-press (right click), drag, two-finger scroll, all
      mapped through normalized coordinates and posted as `CGEvent`s.
- [x] Phase 5 — Keyboard: the system keyboard types real text on the Mac
      (Unicode injection, so autocorrect/emoji/any script works), a
      keyboard-accessory bar carries ⌘⌥⌃⇧ + esc/tab/arrows, and shortcuts
      like ⌘C work by arming a modifier then tapping a letter.
- [x] Phase 6 — Product UX: Trackpad mode (relative movement, alongside
      Direct Touch), a compact translucent remote toolbar, a live
      multi-display picker (switching doesn't reconnect), and real Settings
      on both apps (Quality actually changes the encoder's bitrate/frame
      rate; paired-device management; trackpad sensitivity/natural
      scrolling). No onboarding carousel — the pairing and permissions
      flows already guide a first run, and the spec's own guidance is to
      keep onboarding short.
- [x] Phase 7 — Clipboard sync (Mac→iPhone automatic; iPhone→Mac is a
      one-tap "Send Clipboard to Mac" — see SECURITY.md for why they're not
      symmetric), file transfer (iPhone→Mac, its own dedicated connection
      per transfer, progress shown on both apps), 15 system/media commands
      (Mission Control, Spotlight, sleep, volume, play/pause, ...,
      restart/shutdown behind a confirmation), and automatic reconnection
      with exponential backoff when the control connection drops
      unexpectedly.
- [x] Phase 8 — Automatic quality adjustment (`AdaptiveQualityController`,
      driven by round-trip time measured over the video connection's own
      heartbeat, unit tested), continuous-input throttling (mouse
      move/drag capped to ~60/sec so a fast drag doesn't flood the
      network), a code-review performance pass (see ARCHITECTURE.md's
      "Performance notes" — real profiling needs a device this
      environment doesn't have), and unit test coverage across every wire
      message, the crypto primitives, coordinate mapping, and the
      reconnect backoff schedule.

**Every feature in the spec's success criteria is implemented**: discovery,
pairing, permissions, live screen mirroring, direct-touch and trackpad
control, keyboard input and shortcuts, multi-display switching, clipboard
sync, file transfer, system commands, automatic reconnection, and adaptive
quality. All 8 phases are code-complete.

**A note on verification — read this before trusting any of the above:**
this codebase was written in an environment without Xcode or the
Swift/Apple toolchain available, so `xcodegen generate` and an actual
build have never happened. "Implemented" above means the code exists,
handles the cases described, and reads correctly against Apple's
documented APIs on manual review — not that it compiles cleanly or works
on a device yet. Treat the first real build as the actual finish line:
see SETUP.md, and expect to spend real time on it, starting with
`ARCHITECTURE.md`'s "Video pipeline" section (`H264Encoder.swift` and
`VideoDecoder.swift` are flagged as the highest-risk files in the whole
project) if video doesn't show up on first run.

## Project structure

```
MacRemote/
├── project.yml          XcodeGen project definition (see SETUP.md)
├── Shared/               Code compiled into both apps
│   ├── Models/           Connection state, device/display/quality/transfer models
│   ├── Networking/       NWConnection wrapper, Bonjour constants
│   ├── Protocol/         Binary wire format and every message type
│   ├── Security/         Keychain, identity keys, pairing crypto, SecureSession
│   └── Utilities/        Logging, device identity, geometry/backoff/quality math
├── MacHost/              macOS app (the Mac being controlled)
│   ├── App/               App entry point, Info.plist
│   ├── Views/              SwiftUI screens (Overview/Devices/Display/Permissions/Settings)
│   ├── ViewModels/         Presentation logic
│   ├── Networking/         Listener, session handling, video streaming
│   ├── ScreenCapture/      ScreenCaptureKit capture session
│   ├── VideoEncoding/      VTCompressionSession H.264 encoder
│   ├── InputControl/       CGEvent posting (mouse/keyboard/system commands)
│   ├── Pairing/            Pairing-code coordinator and UI
│   ├── Clipboard/          NSPasteboard polling
│   ├── FileTransfer/       Incoming file receiver
│   ├── Permissions/        Screen Recording / Accessibility checks
│   └── Settings/           UserDefaults-backed preference keys
└── iPhoneRemote/         iOS app (the remote control)
    ├── App/                App entry point, Info.plist
    ├── Views/              SwiftUI screens (Macs list, detail, remote viewer, ...)
    ├── ViewModels/         Presentation logic
    ├── Video/              VTDecompressionSession-free H.264 decode + display
    ├── Gestures/           UIKit gesture bridges (direct touch, trackpad)
    ├── Keyboard/           System-keyboard-to-wire-message translation
    ├── Networking/         Client connection + handshake
    ├── Discovery/          Bonjour browsing
    ├── Pairing/             Pairing-code entry UI
    ├── FileTransfer/        Outgoing file sender
    └── Settings/            Settings screen + shared preference keys
```

## System requirements

- A Mac running macOS 14 (Sonoma) or later, with Xcode 15 or later
- An iPhone running iOS 17 or later
- Both devices on the same Wi-Fi network (or a Mac personal hotspot)
- A free Apple ID is enough — no paid Apple Developer Program membership
  is required for any of this. See `SETUP.md`.

## Running it

Full walkthrough (including Xcode Personal Team signing) is in
[`SETUP.md`](SETUP.md). Short version:

```bash
brew install xcodegen
xcodegen generate
open MacRemote.xcodeproj
```

Then in Xcode: select your Personal Team for both targets, run
`MacRemoteHost` on your Mac, run `iPhoneRemote` on your iPhone, open Mac
Remote on the iPhone, and your Mac should appear under **Nearby**.

## Permissions

The Mac app needs **Screen Recording** to stream its screen and
**Accessibility** to accept mouse/keyboard control — both required for the
app to be useful, neither silently skipped. It has a dedicated Permissions
screen that shows real status and links straight to the right System
Settings pane. If Screen Recording isn't granted when an iPhone tries to
view the screen, the Mac reports that back explicitly (a `videoError`
message) instead of the iPhone just seeing a black screen with no
explanation; if Accessibility isn't granted, input events silently don't
land (that's how `CGEvent.post` itself behaves) — the Permissions tab is
where that becomes visible.

Sleep/Restart/Shut Down/Mute/Volume (the system-command Shortcuts) need a
third, separate permission — **Automation** — the first time one of them
is used; see SECURITY.md for why that one doesn't have a dedicated status
row the way the other two do.

## Pairing and security

The first time an iPhone connects to a Mac, the Mac needs "Pair New Device"
open (Devices tab) showing a 6-digit code, which you enter on the iPhone.
After that, reconnecting doesn't need the code again — each device proved
its identity once during pairing and gets recognized automatically from
then on. See `SECURITY.md` for exactly what's protected and what the threat
model does and doesn't cover — this is a LAN tool for personal devices, not
a hardened multi-tenant product, and the docs say so plainly rather than
overclaim.

## Troubleshooting

**My iPhone doesn't see my Mac.** Confirm both devices are on the same
Wi-Fi network (not one on Wi-Fi and one on cellular/VPN). Corporate or
guest Wi-Fi networks often block the multicast traffic Bonjour needs (client
isolation) — a home network or personal hotspot is the reliable path during
development. You can always fall back to **Add by IP Address** using the
address shown on the Mac's Overview screen.

**Xcode says my bundle identifier is already in use.** Free Personal Team
accounts need a globally unique bundle ID. Change `com.macremote.host` /
`com.macremote.mobile` in `project.yml` to something under your own name
(e.g. `com.yourname.macremote.host`), then re-run `xcodegen generate`.

**The app on my iPhone stops working after a week.** Free Personal Team
provisioning profiles expire after 7 days. Re-run the app from Xcode with
your iPhone connected to renew it — this is an Apple limitation of free
accounts, not a bug here.

## Documentation

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — system design, concurrency model, phase plan
- [`PROTOCOL.md`](PROTOCOL.md) — wire format and message catalog
- [`SECURITY.md`](SECURITY.md) — threat model, pairing design, what's protected
- [`SETUP.md`](SETUP.md) — step-by-step Xcode/Personal Team setup
