# Setup

Step-by-step instructions for building and running Mac Remote with a free
Apple ID (Personal Team) — no paid Apple Developer Program membership.

## 1. Prerequisites

- A Mac with Xcode 15 or later installed
- An iPhone with iOS 17 or later, connected to your Mac via cable or Wi-Fi
- [Homebrew](https://brew.sh) (to install XcodeGen)

## 2. Generate the Xcode project

The `.xcodeproj` is not checked into this repository — it's generated from
`project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so the
project structure stays a readable, diffable text file instead of an XML
blob. Run this from the repository root:

```bash
brew install xcodegen
xcodegen generate
```

This creates `MacRemote.xcodeproj` with three targets: `MacRemoteHost`
(the Mac app), `iPhoneRemote` (the iOS app), and `MacRemoteSharedTests`.
Re-run `xcodegen generate` any time `project.yml` changes or the
`.xcodeproj` gets deleted — it's fully reproducible.

## 3. Open the project

```bash
open MacRemote.xcodeproj
```

## 4. Set a unique bundle identifier

Apple requires bundle identifiers to be globally unique, even for apps you
never submit to the App Store. `project.yml` ships with placeholders
(`com.example.MacRemote.host`, `com.example.MacRemote.mobile`) that must be
replaced before physical-device installation.

Open `project.yml`, change the prefix to something under your own name:

```yaml
PRODUCT_BUNDLE_IDENTIFIER: com.yourname.macremote.host   # MacRemoteHost target
PRODUCT_BUNDLE_IDENTIFIER: com.yourname.macremote.mobile # iPhoneRemote target
```

then regenerate:

```bash
xcodegen generate
```

**Note:** the code also ships an optional iCloud rendezvous for cross-network
discovery, but free Personal Teams can't sign with the iCloud capability, so
it stays dormant — the Tailscale path in step 10 covers anywhere access
without it. (With a paid Apple Developer membership, add the iCloud
entitlements to both targets in `project.yml` and set
`ServiceConstants.cloudContainerIdentifier` to the same value on both apps
to enable it.)

## 5. Select your Personal Team

For **both** the `MacRemoteHost` and `iPhoneRemote` targets:

1. Select the target in Xcode's project navigator
2. Go to **Signing & Capabilities**
3. Under **Team**, choose your name (shown as "Personal Team")
4. Xcode will provision automatically — no manual profile management needed

If you don't see your name, sign in first: **Xcode → Settings → Accounts →
+ → Apple ID**.

## 6. Run the Mac host

Select the `MacRemoteHost` scheme, choose **My Mac** as the run destination,
and press Run. The app opens with an **Overview** screen showing your
Mac's name, network address, and permission status.

## 7. Run the iPhone app

Connect your iPhone, select the `iPhoneRemote` scheme, choose your iPhone as
the run destination, and press Run.

The first time you run an app from a Personal Team on a physical device,
iOS will refuse to launch it until you trust the developer certificate:
**Settings → General → VPN & Device Management → \[Your Apple ID\] → Trust**.

**Free-account limitation:** apps signed with a Personal Team stop running
after **7 days** and need to be reinstalled from Xcode to keep working.
This is an Apple restriction on free accounts, not something this project
can work around — a paid Apple Developer Program membership (not required
otherwise) removes it.

## 8. Grant Mac permissions

The Mac app needs **Screen Recording** (to stream its screen) and
**Accessibility** (to accept mouse/keyboard input) access. Its
**Permissions** tab shows live status for both and a button that opens the
exact System Settings pane — grant them there when the app asks.

The first time you use a Shortcut like Sleep, Restart, or Volume from the
iPhone, macOS will separately prompt for **Automation** access (System
Settings → Privacy & Security → Automation) — that one has no status row
in the Permissions tab since Apple doesn't provide a way to check it in
advance; see SECURITY.md.

## 9. Connect

With both apps running and both devices on the same Wi-Fi network, open Mac
Remote on your iPhone. Your Mac should appear under **My Macs** within a
couple of seconds. Tap it, then tap **Connect**.

If it doesn't appear, see the Troubleshooting section in `README.md` —
most commonly it's a Wi-Fi network that blocks Bonjour's multicast traffic
(common on corporate/guest networks). **Add by IP Address** on the Macs
list screen is the fallback; the Mac's address and port are on its
Overview screen.

## 10. Set up Tailscale on both devices (for anywhere access)

The recommended way to control your Mac from mobile data or another Wi-Fi
network is the free **Tailscale** app — it creates a private encrypted
network between your devices and needs no router configuration:

1. Install Tailscale from the App Store on the **iPhone** and from the Mac
   App Store on the **Mac**
2. Sign in to the **same account** on both (sharing your real email keeps
   the two devices in one network — don't use "Hide My Email")
3. Keep the Tailscale VPN toggle on on both devices

The first pairing still has to happen once on the same Wi-Fi. After that,
connect once more while Tailscale is on so the iPhone learns the Mac's
private address — your Mac then shows a **VIA INTERNET** badge on the
iPhone and is reachable from anywhere: tap the Mac, tap Connect. The app
tries nearby first, then the private network, then IPv6 and the router's
public address.

Without Tailscale, cross-network control still works if your router allows
it: enable UPnP (usually under LAN/Advanced settings) or add a manual
port-forward rule for TCP `53511` to the Mac. The Mac's Overview card
("Anywhere Access") tells you which case applies.

## 11. Screen-off behavior

The Mac stays connectable whenever the host app is open, display asleep or
not: close the lid or let the screen sleep and the iPhone can still connect
and control it (trackpad + keyboard work without video; the stream resumes
when the display wakes). Two hardware limits remain:

- A MacBook that closes its lid **on battery** will always sleep — keep it
  plugged in if you want lid-closed availability
- A shut-down Mac is unreachable; use **Wake Mac** (below) instead

## 12. Enable wake from sleep (optional)

On a MacBook, connect the charger and enable **System Settings → Battery →
Options → Wake for network access**. Open the updated Mac host and iPhone app
together at least once so the iPhone can remember the Mac's wake address.
When that remembered Mac is sleeping and shown as offline, open its detail
screen and tap **Wake Mac**.

Wake-on-LAN does not power on a fully shut-down MacBook, and it only works
while the iPhone can reach the Mac's local network.

## Regenerating after pulling changes

If someone (or a future phase) changes `project.yml`, `Info.plist` files,
or adds/removes source files, re-run:

```bash
xcodegen generate
```

Xcode will pick up the change automatically if the project is already open.
