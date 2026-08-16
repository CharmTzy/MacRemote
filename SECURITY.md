# Security

## Reporting a vulnerability

Please do not open a public issue for a suspected security vulnerability.
Use GitHub's **Security → Report a vulnerability** flow so pairing, screen,
input, or cryptographic problems can be discussed privately before details
are disclosed.

The implementation has been built and exercised on physical Mac and iPhone
hardware, with automated coverage for protocol framing, authentication
payloads, encryption counters, coordinate mapping, and compatibility. This
is not a claim of a formal third-party security audit.

Phase 1's Hello/HelloAck handshake is still the very first thing that
happens on a new connection, and it remains unauthenticated by design — it
only exchanges names and a protocol version. Nothing is trusted, and no
capability is granted, until the authentication phase described below
completes.

## Threat model

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
on; `IdentityKeyManager` (Shared/Security) owns generating and persisting
the key itself.

## Pairing

Only Method A (numeric code) is implemented. QR pairing (Method B) is
deferred — nothing about the protocol precludes adding it later as an
alternative way to get the same code and setup info onto the iPhone faster,
it just isn't built yet.

Pairing happens once per new device, the first time it connects
(`MacHost/Networking/HostAuthenticator.swift` on the Mac,
`iPhoneRemote/Networking/RemoteConnection.swift` on the iPhone; full
message sequence in PROTOCOL.md):

1. The Mac generates a random 6-digit code and displays it
   (`MacHost/Pairing/PairNewDeviceView.swift`) only while "Pair New Device"
   is open — pairing cannot be attempted at any other time.
2. Both sides run an ephemeral X25519 key exchange (`Curve25519.KeyAgreement`)
   to derive a shared secret.
3. That secret and the pairing code both feed into an HKDF derivation (the
   code goes into HKDF's `sharedInfo`, not the input key material — see
   `PairingCrypto.pairingConfirmKey`). Each side sends an HMAC confirmation
   proving it derived the same key, which is only possible if it also knew
   the correct code. If the confirmation doesn't match, pairing aborts.
4. Once confirmed, each side sends its long-term Ed25519 public key, sealed
   with AES-GCM under a second, independently-derived key (`PairingCrypto.
   pairingTrafficKey` — deliberately not the same key used for the
   confirmation MAC). Each device stores the other's public key as a
   `PairedDeviceRecord` in the Keychain (`TrustedDeviceStore`) — this is the
   trust anchor for every future session.
5. The pairing code is single-use and expires after a short window (a
   couple of minutes); the Mac locks out further attempts after a small
   number of failed confirmations (`PairingCoordinator`), so brute-forcing
   the 6-digit code (1,000,000 possibilities) within the window is
   impractical.

### Known limitation: pairing is not a full PAKE

This confirmation-code design raises the bar for an eavesdropper (who
learns nothing without the code) and for a passive attacker, but it is not
a formally-proven Password-Authenticated Key Exchange like SPAKE2 or
OPAQUE. A sufficiently active attacker on the same LAN, in real time,
during the pairing window, attempting to man-in-the-middle the exchange
would need to also guess the 6-digit code correctly before the window
expires and before hitting the lockout — which is the actual protection
here, not cryptographic infeasibility of MITM in the abstract. Swapping in
a real PAKE construction is a reasonable future hardening step and is
called out here rather than glossed over.

## Sessions (after pairing)

Every new session (i.e. every time the iPhone reconnects to an
already-paired Mac) performs a fresh ephemeral X25519 exchange for forward
secrecy, then each side signs the key-agreement transcript (both ephemeral
public keys plus a fresh nonce) with its long-term Ed25519 identity key.
The receiving side verifies that signature against the public key recorded
during pairing — the Mac checks the iPhone's signature against what it
stored when that iPhone paired, and the iPhone checks the Mac's signature
against what it stored, so impersonation from either direction is caught
before anything else happens. If a signature doesn't match, the session
ends with `AuthResultPayload.accepted = false`.

The session key derived from that exchange (via HKDF-SHA256,
`PairingCrypto.sessionKey`) is used by `SecureSession` to seal every
message sent after authentication completes with AES-GCM: authenticated
encryption, so tampered packets fail to decrypt rather than being silently
accepted. Each direction tracks its own strictly-increasing counter,
carried as AES-GCM associated data, so a captured-and-replayed message is
rejected even though nonces themselves are fresh per message.

## What's never done

- Encryption keys, pairing codes, and passwords are never hardcoded,
  logged, or committed to source control.
- Pairing codes and key material are never written to `UserDefaults` —
  only the Keychain, with `ThisDeviceOnly` accessibility so a Keychain/iCloud
  backup restore to another Mac doesn't carry them along.
- `Logging.swift`'s categories log state transitions and failures, never
  message payload contents — see the doc comment there.

## Revocation

On the Mac, every paired device is listed under Devices → Paired Devices
(`MacHost/Views/DevicesView.swift`), and can be individually forgotten
(swipe to delete) or all forgotten at once (toolbar menu → Forget All
Paired Devices) — both remove the stored trusted public key, so the device
must re-pair from scratch, with a new code, before it can connect again.
On the iPhone, the Mac's detail screen has a matching "Forget This Mac"
action, and both apps' Settings screens (Phase 6) offer "Forget All" too.

This is the honest fallback for "I don't trust that this device is still
under my control" — there is no remote-wipe or revocation-list mechanism
because there is no server to host one.

## Remote wake and application launcher

Wake-on-LAN is intentionally not an authenticated control channel. It is a
standard local broadcast containing the Mac network interface's hardware
address; another device on the same LAN may also be able to wake the Mac.
Waking only brings macOS to its normal lock/login screen—it does not grant a
remote session. Screen, input, and application activation still require the
paired, encrypted control channel.

The Fit-mode launcher only enumerates regular applications that are already
running. Activation requests identify an app by bundle identifier, and the
Mac host rejects anything that is not currently present in
`NSWorkspace.runningApplications`. It does not accept executable paths,
launch new programs, or run arbitrary commands.

## Clipboard sync's asymmetric design

Phase 7 syncs the clipboard both directions, but not the same way in each
direction, because of an iOS platform constraint worth calling out
explicitly: **writing** to `UIPasteboard` from your own app carries no
special restriction, but **reading** it — especially automatically, not in
direct response to a user action — can trigger iOS's "Allow Paste from
\[app\]" permission prompt (iOS 16+), and doing so repeatedly on a timer
would trigger it repeatedly. So:

- **Mac → iPhone** is automatic: the Mac polls `NSPasteboard.changeCount`
  (there's no push API for the system pasteboard either — this is the
  standard technique every Mac clipboard tool uses) and pushes changes;
  the iPhone writes them straight to `UIPasteboard` on receipt.
- **iPhone → Mac** requires a tap: "Send Clipboard to Mac" in the remote
  viewer's menu reads `UIPasteboard` at that exact moment, which iOS
  treats as an ordinary user-initiated read rather than background
  polling. There is deliberately no continuous iPhone-side clipboard
  monitor.

## System commands and the Automation permission

Sleep, Restart, Shut Down, Mute, and Volume (Phase 7) run through
AppleScript talking to System Events (`NSAppleScript`, `MacHost/InputControl/
SystemCommandController.swift`) — there's no `CGEvent`-level public API for
them. macOS gates this behind the Automation permission (System Settings →
Privacy & Security → Automation), prompted on first use, separate from
Screen Recording and Accessibility. If a user denies it, those specific
commands silently no-op (logged, not surfaced back to the iPhone) — a real
gap, accepted for now since Apple provides no preflight-check API for
Automation the way it does for the other two permissions.

## Not yet covered

- **Denial of service**: nothing currently rate-limits connection attempts
  at the TCP/listener level (only pairing *attempts* are rate-limited, via
  `PairingCoordinator`'s failed-attempt lockout). A device flooding the
  listener with connections isn't handled specially yet.
- **The Mac's TCC prompts remain the last line of defense** for actual
  screen/input access — Screen Recording and Accessibility permission
  gate what a fully-authenticated session can do with the video and input
  categories (see README.md's Permissions section). Authentication answers
  "is this a device I trust," not "what should a trusted device be allowed
  to do," which those OS permissions continue to answer.
- **File transfer has no size limit or malware scanning.** A paired device
  is a trusted device by this app's threat model, same as it would be for
  AirDrop between your own devices — but worth stating plainly rather than
  leaving implicit.
