# Security

## Current state: Phase 1 has no security yet

This matters enough to say plainly, at the top, in case anyone reads only
this section: **the control connection implemented so far is unauthenticated
and unencrypted.** Any device on the LAN can open a TCP connection to the
advertised port, send a well-formed `Hello`, and the Mac will accept it and
reply. There is no pairing, no identity verification, and no encryption at
this stage — Phase 1's only job was proving the transport and handshake
work end to end.

**Do not use this build on a network you don't trust**, and treat the "Mac
appears connected" state in Phase 1 as a plumbing test, not a security
boundary. Phase 2 (in progress) is what makes this document's threat model
below actually true.

## Threat model (target state, once Phase 2 lands)

**In scope:** other devices on the same LAN. Someone on your home Wi-Fi, or
a guest network you're also on, should not be able to see your Mac's screen
or control it without you explicitly approving their device during pairing.

**Out of scope:** a fully active, real-time attacker who is *also* on your
LAN at the exact moment you pair a new device, watching every packet, and
who can guess your 6-digit pairing code within its validity window. This is
a personal LAN tool, not a hardened multi-tenant product — see "Known
limitation: pairing is not a full PAKE" below for exactly what that costs
you and why it's an acceptable trade here.

Also explicitly out of scope, because the product itself is: anything
beyond the local network. There is no cloud relay, so there's no
cloud-side attack surface to reason about.

## Identity

Each installed copy of each app generates a long-term Ed25519 signing
key pair (`Curve25519.Signing` via CryptoKit) on first launch, stored in
the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — usable
only after the device has been unlocked once since boot, never synced to
iCloud Keychain or backed up). This key pair is the device's identity for
every future session; it is generated once and never leaves the device.

`Shared/Security/KeychainStore.swift` is the storage primitive this rests
on. It's already in place in Phase 1, holding just a device UUID; Phase 2
adds the actual key material alongside it.

## Pairing

Pairing happens once per new device, the first time it connects:

1. The Mac generates a random 6-digit code and displays it (plus,
   optionally, a QR code encoding the same setup information for a faster
   flow).
2. Both sides run an ephemeral X25519 key exchange (`Curve25519.KeyAgreement`)
   to derive a shared secret.
3. That secret is combined with the pairing code (via HKDF) to derive a
   session key. Each side sends an HMAC confirmation proving it derived the
   same key — which is only possible if it also knew the correct code.
   If the confirmation doesn't match, pairing aborts.
4. Once confirmed, each side sends its long-term Ed25519 public key,
   authenticated (encrypted + MACed) under the just-derived session key.
   Each device stores the other's public key as a trusted record — this is
   the trust anchor for every future session.
5. The pairing code is single-use and expires after a short window (a
   couple of minutes); the Mac locks out further attempts after a small
   number of failed confirmations, so brute-forcing the 6-digit code
   (1,000,000 possibilities) within the window is impractical.

### Known limitation: pairing is not a full PAKE

This confirmation-code design raises the bar for an eavesdropper (who
learns nothing without the code) and for a passive attacker, but it is not
a formally-proven Password-Authenticated Key Exchange like SPAKE2 or
OPAQUE. A sufficiently active attacker on the same LAN, in real time,
during the pairing window, attempting to man-in-the-middle the exchange
would need to also guess the 6-digit code correctly before the window
expires and before hitting the lockout — which is the actual protection
here, not cryptographic infeasibility of MITM in the abstract. Swapping in
a real PAKE construction is a reasonable future hardening step (tracked as
a Phase 2 stretch goal) and is called out here rather than glossed over.

## Sessions (after pairing)

Every new session (i.e. every time the iPhone reconnects to an
already-paired Mac) performs a fresh ephemeral X25519 exchange for forward
secrecy, then each side signs its ephemeral public key with its long-term
Ed25519 identity key. The receiving side verifies that signature against
the public key recorded during pairing. If it doesn't match, the session is
rejected — this is what makes `HelloAckPayload.accepted = false` meaningful
in Phase 2 instead of decorative.

The session key derived from that exchange (via HKDF-SHA256) encrypts all
control-channel traffic with AES-GCM: authenticated encryption, so tampered
or replayed packets are rejected rather than silently accepted. Each
message carries a monotonically increasing sequence number as replay
protection within a session.

## What's never done

- Encryption keys, pairing codes, and passwords are never hardcoded,
  logged, or committed to source control.
- Pairing codes and key material are never written to `UserDefaults` —
  only the Keychain, with `ThisDeviceOnly` accessibility so a Keychain/iCloud
  backup restore to another Mac doesn't carry them along.
- `Logging.swift`'s categories log state transitions and failures, never
  message payload contents — see the doc comment there.

## Revocation

Every paired device is listed in Settings → Security → Paired Devices, and
can be individually forgotten (removes its trusted public key, so it must
re-pair from scratch) or all paired devices can be forgotten at once. This
is the honest fallback for "I don't trust that this device is still under
my control" — there is no remote-wipe or revocation-list mechanism because
there is no server to host one.
