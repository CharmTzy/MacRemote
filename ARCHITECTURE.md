# Architecture

## Goals and non-goals

Mac Remote is two native apps that talk directly to each other over a LAN.
There is no server, no relay, no account system — the Mac and the iPhone
are peers. That constraint shapes most of the design: every feature has to
work with only the two devices in the room, which is what makes "no cloud
infrastructure" true rather than aspirational.

## High-level shape

```
                    Bonjour (_macremote._tcp)
   ┌──────────┐  ───────────────────────────▶  ┌──────────┐
   │  iPhone  │                                 │   Mac    │
   │  Remote  │  ◀── control connection (TCP) ─▶ │   Host   │
   └──────────┘                                 └──────────┘
                  ◀── video connection (TCP) ──
                  ◀── file transfer (on demand) ─▶
```

Three logical channels, each its own `NWConnection`, opened after the
control handshake succeeds:

1. **Control** — auth, pairing, session, heartbeat, quality, input,
   keyboard, clipboard. Small, frequent, latency-sensitive messages.
2. **Video** — H.264 frame data, one direction (Mac → iPhone).
3. **File transfer** — opened only while a transfer is in progress, so a
   large file never sits in a queue ahead of a mouse click on the control
   channel (see PROTOCOL.md's "why three connections" section).

Phase 1 implements only the control channel, carrying just the Hello/
HelloAck handshake. Video and file-transfer channels are added in Phase 3
and Phase 7 respectively, once there's something real to send over them.

## Module layout

```
Shared/          Compiled into both app targets. Platform-agnostic except
                 where marked with #if os(...). No SwiftUI, no AppKit/UIKit.
  Models/        Plain value types shared by both apps' view layers.
  Protocol/      The wire format: ByteWriter/ByteReader, ProtocolMessage,
                 FrameParser. See PROTOCOL.md.
  Networking/    MessageTransport (the NWConnection wrapper), Bonjour
                 service constants, NWParameters factory.
  Security/      KeychainStore now; identity/pairing crypto from Phase 2.
  Utilities/     Logging categories, device identity.

MacHost/         macOS app only. AppKit/CoreGraphics/ScreenCaptureKit live
                 here, never in Shared.
iPhoneRemote/    iOS app only. UIKit/AVFoundation live here, never in Shared.
```

Both app targets follow MVVM: `Views/` are SwiftUI and hold no business
logic beyond simple presentation (`if`/`ForEach` over already-computed
state). `ViewModels/` are `@MainActor` `ObservableObject`s that own
`@Published` state and talk to the networking/capture/input layers below
them. Networking, capture, encoding, and input control are their own
non-UI types, independently testable without a view in the picture.

## Concurrency model

- **`MessageTransport`** is an `actor` that owns one `NWConnection`. All
  Network.framework callbacks land on a dedicated serial `DispatchQueue`;
  the actor is what makes it safe to call `send(_:)` or read state from
  SwiftUI's main-actor code without manual locking. It exposes an
  `AsyncStream<TransportEvent>` rather than a delegate protocol, so
  consumers use `for await event in transport.events` instead of managing
  callback lifetimes by hand.
- **`HostSessionManager`** (Mac) and **`DiscoveryViewModel` /
  `DeviceSessionViewModel`** (iPhone) are `@MainActor` `ObservableObject`s.
  They spawn `Task { }` to consume a transport's or browser's event stream;
  because `Task { }` inherits the isolation of the context that creates it,
  code inside those tasks runs back on the main actor by default, and
  `@Published` properties can be written directly without an extra hop.
- **`BonjourBrowser`** (iPhone) mirrors `MessageTransport`'s shape: an actor
  wrapping `NWBrowser`, publishing results as an `AsyncStream`.

This keeps exactly one place (`MessageTransport`) responsible for bridging
Network.framework's completion-handler API into Swift concurrency, instead
of every call site doing its own `withCheckedContinuation`.

Video capture/encode (Phase 3) will use its own dedicated queues rather than
the control channel's queue — screen capture callbacks are much
higher-frequency than control messages and shouldn't contend with them.

## Wire protocol, briefly

Custom binary framing, not JSON — see `PROTOCOL.md` for the full format and
rationale. The short version: `[UInt32 length][UInt8 category][UInt8
type][payload]`, decoded incrementally by `FrameParser` as TCP data arrives
in arbitrary-sized chunks.

## Discovery, connection, and authentication flow

```
Mac launches
  → HostSessionManager.start()
  → NWListener created on ServiceConstants.defaultPort, TCP_NODELAY on
  → NWListener.service set (Bonjour advertise _macremote._tcp with a TXT
    record carrying device name / model / protocol version)
  → listener.start(queue:)

iPhone launches, opens Macs list
  → DiscoveryViewModel.start()
  → BonjourBrowser browses _macremote._tcp
  → results become [DiscoveredMac], shown under "Nearby"

User taps a Mac
  → DeviceSessionViewModel.connect(to:)
  → RemoteConnection dials the Mac's NWEndpoint.service directly
    (Network.framework resolves the Bonjour endpoint internally — no
    separate NWEndpoint.hostPort resolution step needed)
  → on .ready, sends HelloPayload; Mac replies HelloAck (still just an
    identification exchange — see below for what actually gates access)
  → RemoteConnection runs the authentication phase against
    HostSessionManager's HostAuthenticator:
      - known device (in TrustedDeviceStore)  → signature challenge/response
      - unknown device                        → RemoteConnection.connect(to:)
        returns .pairingCodeNeeded; DeviceSessionViewModel surfaces
        PairingCodeView; submitPairingCode(_:) resumes the same connection
  → on success, both sides hold a SecureSession (AES-GCM key) and the peer's
    verified identity — this is what "Connected" actually means
```

Full message-by-message sequence, including exactly which side sends what
and why, is in PROTOCOL.md's "Authentication sequence" section; the
cryptographic reasoning behind each step is in SECURITY.md.

One deliberate consequence of pairing needing user input (the code) mid-
handshake: `RemoteConnection` can't be one straight-line `async` function
the way `MessageTransport` is. It holds an `AsyncStream` iterator as actor
state between `connect(to:)` returning `.pairingCodeNeeded` and
`submitPairingCode(_:)` being called later, once the person typing the code
gets around to it — see the doc comment on `RemoteConnection` for why that
iterator has to be threaded through by hand rather than re-derived from
`transport.events` each time (`AsyncStream` doesn't support more than one
live consumer).

## Why not WebRTC

WebRTC gives you NAT traversal, adaptive bitrate, and a battle-tested
congestion controller for free — real advantages if this needed to work
across arbitrary networks or through NATs. It doesn't need to: both devices
are always on the same LAN by construction (that's the product's whole
premise), so NAT traversal and STUN/TURN are dead weight. Building directly
on `Network.framework` + `VideoToolbox` keeps the dependency surface to
Apple's own frameworks (matching the "avoid unnecessary third-party
dependencies" requirement), gives full control over the low-latency
priority the product needs, and means every layer of the stack — transport,
framing, encoding — is something this codebase owns and can debug. The
tradeoff is that adaptive bitrate/quality (Phase 8) and reconnection
(Phase 7) are hand-rolled instead of inherited from a mature library; the
architecture notes above are written with that cost in mind.

## Phase plan

See the checklist in `README.md` for current status. The phase boundaries
mirror the product spec this project was built from: each phase is a
vertical slice that ends in something observably working, not a layer that
only makes sense once every other layer exists.
