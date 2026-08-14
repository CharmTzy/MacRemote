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
| `authentication` | 1 | Pairing handshake, session auth (Phase 2) |
| `session` | 2 | Hello / HelloAck (Phase 1, implemented) |
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

`accepted` is always `true` in Phase 1 — every well-formed Hello from an
iPhone is accepted. Phase 2 makes this meaningful: a device that isn't
paired, or whose signature doesn't check out, gets `accepted = false` with
a human-readable `reason`.

### `heartbeat` / Ping, Pong (types 1, 2)

```
UInt64   timestamp   (milliseconds since epoch, sender's clock)
```

Implemented and round-trip tested, not yet driven by a periodic timer —
that lands with Phase 7's connection-loss detection and reconnect logic.

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
