# Wire Protocol

Custom binary framing over TCP (`Network.framework`), not JSON. High-
frequency messages — mouse moves, video frames — would pay JSON's parsing
and size overhead on every single packet; a fixed binary layout avoids that
entirely, and using it consistently (rather than JSON for "small" messages
and binary for "hot" ones) keeps the codebase to one encode/decode path
instead of two. The cost is that adding a field means writing an encoder
and decoder by hand instead of getting `Codable` for free — an acceptable
trade for a protocol with a small, deliberately-curated message set.

## Frame layout

```
┌──────────────┬───────────┬────────┬─────────────────┐
│ frameLength  │ category  │  type  │     payload     │
│   UInt32 BE  │   UInt8   │ UInt8  │  frameLength - 2 │
└──────────────┴───────────┴────────┴─────────────────┘
```

- `frameLength` counts everything **after** itself (category + type +
  payload), so a reader knows exactly how many more bytes to wait for.
- All multi-byte integers are big-endian.
- Strings are length-prefixed UTF-8 (`UInt16` length, so max 64KB — every
  current use is names/paths/reasons, far under that).
- Opaque blobs (encrypted payloads, file chunks, video frames) are
  length-prefixed with `UInt32`.
- Frames larger than `FrameParser.maxFrameLength` (16MB) are rejected; that
  bounds how much a misbehaving peer can make a receiver buffer.

`FrameParser` (`Shared/Protocol/FrameParser.swift`) reassembles frames from
arbitrarily-chunked TCP reads: feed it whatever `NWConnection.receive`
hands you, get back zero or more complete, decoded messages.

## Categories

| Category | Byte | Carries |
|---|---|---|
| `authentication` | 1 | Pairing handshake, session auth (implemented) |
| `session` | 2 | Hello / HelloAck (implemented) |
| `video` | 3 | Encoded frame data (implemented) |
| `input` | 4 | Mouse/touch/trackpad events (implemented) |
| `keyboard` | 5 | Key events, modifiers, text input (implemented) |
| `clipboard` | 6 | Clipboard sync (implemented) |
| `file` | 7 | File transfer chunks/metadata (implemented, iPhone → Mac only) |
| `system` | 8 | Mac shortcuts: lock, sleep, media keys (implemented) |
| `heartbeat` | 9 | Ping/pong (implemented; not yet driven by a timer) |
| `quality` | 10 | Streaming quality (manual selection implemented; automatic adjustment is Phase 8) |

A category existing in this table does not mean it has message types yet —
`ProtocolMessage` only defines cases for what's actually implemented.
Decoding an unimplemented category throws `unknownType` rather than
crashing, so a newer peer sending a message an older peer doesn't
understand fails that one message, not the connection.

## Messages implemented so far

### `session` / Hello (type 1)

Sent by whichever side is dialing out, immediately once the connection is
`.ready`. No secrets in this message — it's identification, not
authentication.

```
UInt16   protocolVersion
UUID     deviceID          (as string, see ByteWriter.writeUUID)
String   deviceName
String   deviceModel
UInt8    deviceKind        (1 = mac, 2 = iPhone)
UInt8    channelPurpose    (1 = control, 2 = video)
```

`channelPurpose` is what makes the two-connection design (control + video,
see ARCHITECTURE.md) work without a separate binding protocol: a device
opens a second connection, declares `channelPurpose: .video` in its Hello,
and runs through the *exact same* authentication as the control connection
— reusing `sessionAuth` since by the time a video connection is opened the
device is already paired. `HostSessionManager` branches on this field only
after authentication succeeds, to decide whether to start `VideoStreamer`
or hand the connection to the ordinary authenticated-traffic pump.

### `session` / HelloAck (type 2)

Sent in response to Hello.

```
UInt16   protocolVersion
UUID     deviceID
String   deviceName
String   deviceModel
Bool     accepted
String   reason          (empty string decodes as nil)
```

`accepted` here is just "the handshake itself was well-formed" — it's
always `true` for a valid Hello from an iPhone speaking the right protocol
version. The real accept/reject decision happens later, in `authResult`,
once authentication actually runs.

### `heartbeat` / Ping, Pong (types 1, 2)

```
UInt64   timestamp   (milliseconds since epoch, sender's clock)
```

Driven from the iPhone side of the **video** connection, every 3 seconds,
but only while streaming quality is `.auto` (`VideoSessionViewModel.
startHeartbeat`) — its purpose is round-trip-time measurement for Phase
8's automatic quality adjustment (`AdaptiveQualityController`), not
connection-loss detection. Detecting a *dropped* connection (Phase 7) is
handled separately, by the pump loop's `nextMessage()` simply returning
`nil` when a connection closes — no heartbeat needed for that, since
`NWConnection` already surfaces closure/failure as a state change.

## Authentication sequence

Runs immediately after Hello/HelloAck, before either side does anything
else. Full design rationale (why code-confirmed pairing, why signatures for
returning devices, what the threat model does and doesn't cover) is in
SECURITY.md — this section is just the message-level mechanics.

```
iPhone                                          Mac
  │──────────────── hello ────────────────────▶ │
  │◀─────────────── helloAck ────────────────── │
  │                                              │  (looks up hello.deviceID
  │                                              │   in TrustedDeviceStore)
  │──────────────── authBegin ─────────────────▶ │  (iPhone's ephemeral X25519 key)
  │◀─────────────── authChallenge ────────────── │  (Mac's ephemeral key + nonce;
  │                                              │   mode = pairingRequired or
  │                                              │   sessionAuth; signature only
  │                                              │   present for sessionAuth)
  │
  ├─ if sessionAuth (returning device) ─────────────────────────────────────┤
  │──────────── sessionAuthResponse ───────────▶ │  (iPhone's signature over
  │                                              │   the transcript)
  │◀─────────────── authResult ────────────────  │
  │
  ├─ if pairingRequired (first-time device) ─────────────────────────────────┤
  │  (UI pauses here for the user to type the code shown on the Mac)
  │──────────────── pairingConfirm ────────────▶ │  (HMAC tag proving iPhone
  │                                              │   knows the code)
  │◀─────────────── pairingConfirm ────────────  │  (Mac's tag, proving the same
  │                                              │   back)
  │──────────────── identityExchange ──────────▶ │  (iPhone's long-term public
  │                                              │   key, sealed)
  │◀─────────────── identityExchange ──────────  │  (Mac's long-term public key,
  │                                              │   sealed)
  │◀─────────────── authResult ────────────────  │
  └───────────────────────────────────────────────────────────────────────────┘

  From here on, every message either side sends is wrapped in
  secureEnvelope, sealed with the session key this exchange produced.
```

### `authentication` / AuthBegin (type 1)

```
Data   ephemeralPublicKey   (32 bytes, X25519)
```

### `authentication` / AuthChallenge (type 2)

```
UInt8  mode                 (1 = pairingRequired, 2 = sessionAuth)
Data   ephemeralPublicKey   (32 bytes, X25519, Mac's)
Data   nonce                (16 bytes; HKDF salt for every key this session derives)
Data   signature            (empty for pairingRequired; Ed25519 signature for sessionAuth)
```

### `authentication` / SessionAuthResponse (type 3)

`sessionAuth` path only.

```
Data   signature   (iPhone's Ed25519 signature over the transcript)
```

### `authentication` / PairingConfirm (type 4)

`pairingRequired` path only. Sent by the iPhone first, then by the Mac.

```
Data   confirmTag   (HMAC-SHA256, see PairingCrypto.confirmTag)
```

### `authentication` / IdentityExchange (type 5)

`pairingRequired` path only, sent by both sides once pairingConfirm
matches in both directions.

```
UInt64   counter    (SecureSession send counter, starts at 1)
Data     combined   (AES-GCM sealed box: nonce + ciphertext + tag, containing
                      a PairingIdentityPlaintext — long-term public key +
                      device name + model)
```

### `authentication` / AuthResult (type 6)

Sent by the Mac only — it holds the trust records, so it makes the final
call. Terminates both paths.

```
Bool     accepted
String   reason   (empty string decodes as nil)
```

### `authentication` / SecureEnvelope (type 7)

Every message sent after `authResult(accepted: true)`. Same shape as
`IdentityExchange` (`counter` + `combined`), but the sealed plaintext is a
*full inner message* — its own category + type + payload, unframed (see
`ProtocolMessage.encodedInner()` / `decodeInner(_:)`). The video connection
is what actually exercises this now: every `videoConfig`/`videoFrame`/
`videoError` the Mac sends travels wrapped in one of these.

### `video` / VideoConfig (type 1)

Sent once a video connection is streaming (and again if the source display
or its resolution changes), before any `VideoFrame`. Always wrapped in
`secureEnvelope`.

```
UInt32   width
UInt32   height
Data     sps   (H.264 Sequence Parameter Set, AVCC framing)
Data     pps   (H.264 Picture Parameter Set, AVCC framing)
```

### `video` / VideoFrame (type 2)

One encoded frame. Always wrapped in `secureEnvelope`.

```
Bool     isKeyFrame
Data     sampleData   (AVCC-framed H.264 sample, exactly as VTCompressionSession
                        produced it — no Annex-B conversion in either direction)
```

### `video` / VideoError (type 3)

Sent instead of frames when the Mac can't stream — most commonly a missing
Screen Recording permission. Lets the iPhone show a real explanation
instead of a black screen with no context.

```
String   reason
```

### `input` / MouseMove, MouseButton, MouseClick, MouseDragged, Scroll (types 1-5)

All wrapped in `secureEnvelope`, sent over the **control** connection (never
video). `NormalizedPoint` (`Shared/Models/NormalizedPoint.swift`) is two
`Float32`s in `[0, 1]` — a fraction of the Mac's display, not a pixel
position, so it's meaningful regardless of either device's resolution.

```
MouseMove     NormalizedPoint position
MouseButton   NormalizedPoint position, UInt8 button, Bool isDown
MouseClick    NormalizedPoint position, UInt8 button, UInt8 clickCount
MouseDragged  NormalizedPoint position, UInt8 button
Scroll        Float deltaX, Float deltaY
```

`button`: 1 = left, 2 = right. `MouseClick` is the common case (a plain tap
or a long-press-as-right-click) sent as one atomic message; `MouseButton`
+ `MouseDragged` + `MouseButton` bracket an actual drag, matching the
down/dragged/up shape `CGEvent` itself expects on the Mac side.

### `keyboard` / TextInput (type 1)

Literal text, injected as Unicode on the Mac (see `KeyboardController.
typeText`) — not usable for shortcuts, since Unicode injection types
characters rather than invoking key-event-driven menu commands.

```
String   text
```

### `keyboard` / SpecialKey (type 2)

Everything that needs a real key-code-level event: navigation/editing
keys, function keys, and — combined with modifiers — shortcuts.

```
UInt8   key         (SpecialKey raw value — see Shared/Protocol/SpecialKey.swift)
UInt8   modifiers    (KeyModifiers bitmask: 1=⌘ 2=⌥ 4=⌃ 8=⇧)
Bool    isDown
```

`SpecialKey` is deliberately not macOS's own virtual key codes — it's a
small platform-neutral set (navigation, F1-F12, a-z, 0-9) that
`MacHost/InputControl/VirtualKeyCode.swift` maps to the real `CGKeyCode`
values. Modifiers are "armed" by tapping ⌘/⌥/⌃/⇧ on the iPhone's keyboard
accessory bar and consumed by the next key press, then cleared — there's
no physical key being held down the way there is on a real keyboard, so
sticky-key-style one-tap-then-act is the natural equivalent.

### `video` / DisplayList (type 4), SelectDisplay (type 5)

`DisplayList` is sent once a video connection starts streaming (and again
if the display set changes); `SelectDisplay` is sent back by the iPhone to
switch which display it's watching, without a reconnect. Both wrapped in
`secureEnvelope`.

```
DisplayList     UInt8 count, then count × {
                  UInt32 id, UInt32 width, UInt32 height, Bool isMain, String name
                }
SelectDisplay   UInt32 displayID
```

### `quality` / QualityPreference (type 1)

Sent by the iPhone once when a video connection starts (from its saved
Settings preference) and again whenever the user changes Quality in
Settings. The Mac restarts capture/encoding at the new bitrate and frame
rate target — display resolution is always native, only encode quality
changes.

```
UInt8   profile   (1=auto 2=low 3=balanced 4=high — see Shared/Models/QualityProfile.swift)
```

`.auto` currently just uses `.balanced`'s numbers. Genuinely automatic,
network-condition-aware adjustment is Phase 8 scope, built as a second
layer that calls the same `VideoStreamer.applyQuality(_:)` mechanism
automatically instead of only in response to a user's Settings choice.

### `clipboard` / ClipboardUpdate (type 1)

Bidirectional over the control connection.

```
String   text
```

The Mac polls `NSPasteboard.general.changeCount` (there's no push API for
it) and broadcasts on change; the iPhone applies incoming updates directly
since writing to `UIPasteboard` isn't subject to iOS's read-permission
prompt. The iPhone → Mac direction is user-triggered (a "Send Clipboard to
Mac" action), not continuous background polling — see SECURITY.md for why.

### `file` / FileOffer, FileChunk, FileComplete (types 1-3)

Each transfer gets its own `.file`-purpose connection, opened only for the
transfer's duration. No accept/decline round trip — both ends are already
an authenticated, paired device by the time a `.file` connection exists.

```
FileOffer      UUID transferID, String filename, UInt64 fileSize
FileChunk      UUID transferID, UInt64 offset, Data chunk   (256KB chunks)
FileComplete   UUID transferID
```

iPhone → Mac only in this implementation — see ARCHITECTURE.md's
connection model for why a Mac-initiated push isn't wired up.

### `system` / SystemCommand (type 1)

```
UInt8   command   (SystemCommand raw value — see Shared/Protocol/SystemCommand.swift)
```

One of 15 fixed actions (Mission Control, Launchpad, Spotlight, App
Switcher, Show Desktop, Lock, Sleep, Mute, Volume Up/Down, Play/Pause,
Previous/Next Track, Restart, Shut Down). `restart` and `shutdown` require
the iPhone to confirm before sending — see `SystemCommand.requiresConfirmation`.

## Design rules for future messages

- **Route by category, not by inspecting payloads.** The transport layer
  (Phase 8's quality/priority work) needs to make scheduling decisions
  without decoding a message.
- **Input and video never share a connection with file transfer.** File
  chunks are large and bursty; queuing them behind a mouse click would add
  visible input lag. See `ARCHITECTURE.md`'s three-connection design.
- **Every message needs a `Sendable` payload type with `encode(into:)` /
  `static decode(from:)`.** No `Codable`/JSON on this path — see the intro
  above for why.
- **Add fields at the end.** `ByteReader` reads positionally; a decoder for
  an older protocol version simply won't read trailing fields it doesn't
  know about, which is why every field needed by a Phase-N feature should
  be present in that phase's payload rather than assumed from context.
