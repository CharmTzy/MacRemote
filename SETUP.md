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

## 10. Enable wake from sleep (optional)

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
