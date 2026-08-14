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
| `video` | 3 | Encoded frame data (Phase 3) |
| `input` | 4 | Mouse/touch/trackpad events (Phase 4) |
| `keyboard` | 5 | Key events, modifiers, text input (Phase 5) |
| `clipboard` | 6 | Clipboard sync (Phase 7) |
| `file` | 7 | File transfer chunks/metadata (Phase 7) |
| `system` | 8 | Mac shortcuts: lock, sleep, media keys (Phase 7) |
| `heartbeat` | 9 | Ping/pong (implemented; not yet driven by a timer) |
| `quality` | 10 | Adaptive streaming stats/profile changes (Phase 8) |

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
UUID     deviceID        (as string, see ByteWriter.writeUUID)
String   deviceName
String   deviceModel
UInt8    deviceKind      (1 = mac, 2 = iPhone)
```

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

Implemented and round-trip tested, not yet driven by a periodic timer —
that lands with Phase 7's connection-loss detection and reconnect logic.

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
`ProtocolMessage.encodedInner()` / `decodeInner(_:)`). No feature sends
anything through this yet; it exists so Phase 3+ has an encrypted channel
ready to use rather than needing to invent one under time pressure.

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
