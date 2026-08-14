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
- [ ] Phase 4 — Mouse/trackpad control
- [ ] Phase 5 — Keyboard input and shortcuts
- [ ] Phase 6 — Full product UX (settings, monitor picker, remote toolbar)
- [ ] Phase 7 — Clipboard sync, file transfer, media/system commands, reconnection
- [ ] Phase 8 — Performance tuning and test coverage

**Remote control (mouse/keyboard) doesn't work yet.** A paired iPhone can
now watch a live view of the Mac's primary display — tap "View Screen" on
a connected Mac's detail screen — but can't yet interact with it. See the
phase list above for what's next.

**A note on verification:** this codebase was written in an environment
without Xcode or the Swift/Apple toolchain available, so `xcodegen generate`
and an actual build have not happened yet — see SETUP.md, and treat the
first real build as the point where remaining compiler errors (if any) get
found and fixed, not as a formality.

## Project structure

```
MacRemote/
├── project.yml          XcodeGen project definition (see SETUP.md)
├── Shared/               Code compiled into both apps
│   ├── Models/           Connection state, discovered/paired device models
│   ├── Networking/       NWConnection wrapper, Bonjour constants
│   ├── Protocol/         Binary wire format and message types
│   ├── Security/         Keychain storage (identity keys land in Phase 2)
│   └── Utilities/        Logging, device identity
├── MacHost/              macOS app (the Mac being controlled)
│   ├── App/               App entry point, Info.plist
│   ├── Views/              SwiftUI screens
│   ├── ViewModels/         Presentation logic
│   ├── Networking/         Listener, Bonjour advertising, session handling
│   └── Permissions/        Screen Recording / Accessibility checks
└── iPhoneRemote/         iOS app (the remote control)
    ├── App/                App entry point, Info.plist
    ├── Views/              SwiftUI screens
    ├── ViewModels/         Presentation logic
    ├── Discovery/           Bonjour browsing
    └── Networking/          Client connection + handshake
```

Folders like `ScreenCapture/`, `VideoEncoding/`, `InputControl/`, `Pairing/`,
`Clipboard/`, and `FileTransfer/` already exist as scaffolding and are filled
in as each phase lands.

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

The Mac app needs **Screen Recording** to stream its screen (now required
— Phase 3) and **Accessibility** to be controlled (Phase 4/5, not required
yet). It has a dedicated Permissions screen that shows real status and
links straight to the right System Settings pane. If Screen Recording
isn't granted when an iPhone tries to view the screen, the Mac reports that
back explicitly (a `videoError` message) instead of the iPhone just seeing
a black screen with no explanation.

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
