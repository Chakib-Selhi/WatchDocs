# Install and run

Step-by-step guide to build WatchDocs and run it on a real iPhone and Apple Watch.

## 1. Tools

| Tool | Why | How |
|---|---|---|
| Xcode | Build the iOS and watchOS apps | Mac App Store |
| iOS and watchOS platforms | SDKs and simulators | Xcode > Settings > Components |
| XcodeGen | Generates `WatchDocs.xcodeproj` from `project.yml` | `brew install xcodegen` |

After installing Xcode:

```sh
sudo xcode-select -s /Applications/Xcode.app
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
```

## 2. Signing values

Your personal values are kept out of git in `Configs/Local.xcconfig`:

```sh
cp Configs/Local.example.xcconfig Configs/Local.xcconfig
```

Edit it:

```
BUNDLE_PREFIX = com.yourname
DEVELOPMENT_TEAM = XXXXXXXXXX
```

- `BUNDLE_PREFIX` must be unique to you. It builds every bundle ID (`com.yourname.watchdocs`, `.share`, `.watchkitapp`) and the App Group.
- `DEVELOPMENT_TEAM` is your team ID. With a free Apple ID, Xcode does not display it directly. The easiest way to get it: generate the project, pick your *Personal Team* in the **Signing & Capabilities** tab of the WatchDocs target, then run:
  ```sh
  grep "DEVELOPMENT_TEAM = " WatchDocs.xcodeproj/project.pbxproj | sort -u
  ```
  The 10-character value is your team ID.

## 3. Generate and open the project

```sh
xcodegen generate
open WatchDocs.xcodeproj
```

Xcode downloads ZIPFoundation and CoreXLSX on first open. Run `xcodegen generate` again whenever `project.yml` or `Configs/` change.

## 4. Prepare the devices

- **iPhone**: Settings > Privacy & Security > Developer Mode > On (restart required).
- Connect the iPhone with a cable and trust the Mac.
- **Apple Watch**: keep it on your wrist, unlocked and close to the iPhone. The Mac, the iPhone and the watch must be on the **same home Wi-Fi network**, with no VPN. Public, school and guest networks isolate devices and Xcode will not reach the watch.
- The first time Xcode connects to the watch, accept *Trust this computer* on the watch. Then enable **Developer Mode** on the watch: Settings > Privacy & Security > Developer Mode (at the bottom).

## 5. Run

1. Scheme **WatchDocs**, destination your iPhone, `Cmd+R`.
2. If iOS refuses to open the app ("Untrusted Developer"): Settings > General > VPN & Device Management > your Apple ID > Trust.
3. Scheme **WatchDocsWatch**, destination your Apple Watch, `Cmd+R`. This registers the watch in your provisioning profile and installs the watch app. The first install can take several minutes.

With a free Apple ID, apps expire after **7 days**: run them again from Xcode to renew. A paid Apple Developer membership extends this to one year and enables TestFlight.

## 6. Use

- In the iPhone app: **+** > Files or Photos, then **Send**.
- From another app: Share > **Send to Watch**, then open WatchDocs (or tap the notification). The extension cannot talk to the watch directly; the app converts and sends.
- On the watch: tap a document. Digital Crown zooms (Pages) or scrolls (Text), swipe changes page, double tap resets the zoom, the QR button enables ticket mode.

## Troubleshooting

| Symptom | Fix |
|---|---|
| "No Apple Watch is paired" | Check pairing in the Watch app on the iPhone. |
| "WatchDocs is not installed on the watch" | Run the WatchDocsWatch scheme on the watch from Xcode. |
| Watch shows *Currently Unavailable* in Xcode | Same Wi-Fi for Mac and watch, no VPN, watch unlocked. As a last resort: `xcrun devicectl manage unpair --device <watch id>` then reconnect and trust the Mac again. |
| "The app could not be installed because its integrity could not be verified" (watch) | The watch is not in the provisioning profile yet: run the WatchDocsWatch scheme with the watch as destination, then run the iPhone app again. |
| A document stays *Waiting* | The watch is far, locked or charging. Opening WatchDocs on the watch speeds up delivery. |
| Blank pages on the watch | iPhone app Settings > Image format > JPEG, then send again. |
| Share extension says "App Group not configured" | Check the App Groups capability of the WatchDocs and WatchDocsShare targets. |
