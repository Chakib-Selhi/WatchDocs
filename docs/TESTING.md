# Testing

## Automated tests

| Level | Command | Coverage |
|---|---|---|
| Shared package (unit + integration) | `cd Packages/WatchDocsKit && swift test` | SHA-256, manifest encoding, page naming, CSV parsing, text encodings, Word XML extraction, full transfer protocol with an in-memory link: random order, duplicates, corrupted file, missing file, two-way deletion, recovery of stalled documents, 1,500-page document. |
| Converters (iOS simulator) | `xcodebuild test -scheme WatchDocs -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WatchDocsTests` | 20-page PDF in under 10 s, password-protected PDF, image, UTF-8 and ISO-8859-1 text, Word, Excel (two sheets), CSV. |
| UI (iOS simulator) | `xcodebuild test -scheme WatchDocs -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:WatchDocsUITests` | Launch, add menu, file picker. |

Fixtures live in `Tests/Fixtures` (`sample-protected.pdf` uses the password `watch`).

GitHub Actions runs the package tests and builds both apps on every push ([workflow](../.github/workflows/ci.yml)).

## Manual checklist on real devices

WatchConnectivity transfers between paired simulators are unreliable, so transfer behavior is validated on a real iPhone and Apple Watch. Requirement IDs refer to [PRD.md](PRD.md).

| # | Requirement | Steps | Expected |
|---|---|---|---|
| 1 | IOS-05, WCH-01 | Send `sample.pdf` with the watch app open. | *Sending* then *Delivered*; readable on the watch. |
| 2 | WCH-01 | Close the watch app, send an image, open the watch app a minute later. | The document is already there. |
| 3 | Queueing | Put the watch on its charger away from the iPhone, send three files. | *Waiting*, then automatic delivery when back in range. |
| 4 | WCH-07 | iPhone in Airplane Mode, open every document on the watch. | Everything opens. |
| 5 | WCH-03, WCH-04 | Open a multi-page PDF. | "3 / 12" indicator, swipe, Crown zoom 1x to 4x, pan, double tap resets. |
| 6 | WCH-05 | Open `sample.txt`, change text size. | Four sizes, Crown scrolling. |
| 7 | WCH-06 | Open `sample.xlsx`. | Frozen header, two-way scrolling, switch between sheets. |
| 8 | WCH-08, IOS-06 | Delete a document on the watch, another on the iPhone. | Removed on the other device. |
| 9 | WCH-09, WCH-10 | Switch Pages/Text on a PDF, leave, reopen. | Mode and page are restored. |
| 10 | No limits | Send a 500+ page PDF, then 30 documents at once. | Everything is delivered; the watch stays smooth. |
| 11 | SHR-01, SHR-02 | Share from Files, Mail, Safari (PDF), Photos. | "Ready to send" notification; sent when the app opens. |
| 12 | Storage cap | Set a 250 MB cap and send more. | Clear refusal message. |
| 13 | Recovery | Kill the iPhone app during a conversion, relaunch. | Conversion resumes. |
| 14 | WCH-11 | Ticket mode on a QR code screenshot. | White background, code scannable. |
