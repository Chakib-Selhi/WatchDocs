# Product Requirements: WatchDocs (iPhone to Apple Watch)

Written October 23, 2026 by Chakib Selhi. Amended October 26, 2026 (marked ⚑): no limit on pages per document or number of documents.

## 1. Summary and goals

WatchDocs sends PDFs, images, photos, Word, Excel and TXT files from the iPhone to the Apple Watch, so they can be read on the watch without the iPhone nearby. The core of the product is a conversion done on the iPhone, because watchOS has no PDFKit, QuickLook or WebKit.

**Problem.** The Apple Watch cannot open documents. People who want to check a ticket, a list, notes or a map on their wrist have to take out their phone.

**V1 goals**
- Send a file to the watch in fewer than 3 actions, from the app or from the iOS share sheet.
- Read every received document fully offline (iPhone off or away).
- Queue transfers when the watch is unreachable and deliver them automatically.
- Comfortable reading on a small screen: Digital Crown zoom, resizable text, scrollable tables.
- ⚑ No limit on the number of pages per document or on the number of documents.

**V1 non-goals**: editing or annotating; Android, Wear OS or Mac versions; cloud sync (V2); DRM-protected documents; perfect layout fidelity for legacy `.doc` and `.xls`.

## 2. Users and use cases

| Use case | Typical format | Key need |
|---|---|---|
| Plane, train or concert ticket | PDF, screenshot | Fast display, scannable QR code |
| Presentation notes, cheat sheet | TXT, Word | Resizable text, Crown scrolling |
| Grocery list, checklist | TXT, Excel | Offline reading |
| Map, plan or diagram | Image, PDF | Zoom and pan |
| Schedule or data table | Excel, CSV | Scrollable table, sheet choice |
| Run or hike without the phone | All | 100% offline |

## 3. Formats and conversion

All conversion happens on the iPhone. The watch only receives page images, plain text and JSON tables. Each document offers one or two reading modes.

| Source | Extensions | Pages mode | Text / Table mode | iOS tools |
|---|---|---|---|---|
| PDF | .pdf | Pages rasterized to HEIC | Extracted text | PDFKit |
| Images | .jpg .png .heic .gif .webp .tiff | Resized image | | ImageIO |
| Photos | Photo library | Same as images | | PhotosPicker |
| Word | .docx .doc .rtf | WebKit to PDF, then HEIC | Text from the .docx XML | WebKit, ZIPFoundation, XMLParser |
| Excel | .xlsx .xls .csv | WebKit to PDF, then HEIC | JSON table per sheet | CoreXLSX, CSV parser |
| Text | .txt .md .json .log | | Plain text with encoding detection | |

Rules: page width 500 / 800 / 1200 px (Economy / Standard / High); HEIC at 0.7 with JPEG fallback; password-protected PDFs unlocked on the iPhone; ⚑ ~~200-page limit~~ no limit, pages converted in batches of five; `.doc` and `.xls` handled on a best-effort basis through WebKit, with a clear message on failure; animated GIF: first frame only.

## 4. Offline and online

| Situation | Expected behavior | Mechanism |
|---|---|---|
| iPhone and watch nearby | Immediate transfer, progress shown | `WCSession.transferFile` |
| Watch unreachable | *Waiting*, automatic delivery later | System queue + local state |
| Watch app closed | Background reception | `session(_:didReceive:)` |
| iPhone away | Every received document readable | watchOS app container |
| V2: iPhone away, watch on Wi-Fi or cellular | Download from iCloud | CloudKit |

Metadata: the iPhone keeps the reference list; deletions propagate with `transferUserInfo`; global state (space used, document count) goes through `updateApplicationContext`. Transport is isolated behind a `DocumentTransport` protocol.

## 5. Functional requirements

P0 = required in V1, P1 = wanted in V1, P2 = later.

### 5.1 iPhone app

| ID | P | Requirement | Acceptance criteria |
|---|---|---|---|
| IOS-01 | P0 | Import from Files | `fileImporter`, multiple selection |
| IOS-02 | P0 | Import photos | Multiple `PhotosPicker`, ⚑ no limit (was 50) |
| IOS-03 | P0 | Convert according to section 3 | 20 pages in under 10 s |
| IOS-04 | P0 | Preview before sending | Editable title, page count, size, mode |
| IOS-05 | P0 | Send and track status | Converting, Waiting, Sending, Delivered, Failed (with reason) |
| IOS-06 | P0 | List sent documents | Search, sort by date, deletion propagated |
| IOS-07 | P0 | Watch status | Paired, app installed, reachable, space used |
| IOS-08 | P1 | Settings | Quality, storage cap, default mode |
| IOS-09 | P1 | Resend a failed document | Without reconverting if the package still exists |
| IOS-10 | P2 | Folders or tags | V2 |

### 5.2 Share extension

| ID | P | Requirement | Acceptance criteria |
|---|---|---|---|
| SHR-01 | P0 | "Send to Watch" in the share sheet | Files, Photos, Mail, Safari (PDF), Messages |
| SHR-02 | P0 | Shared inbox | File copied to the App Group; the app converts and sends |
| SHR-03 | P1 | Processing without opening the app | `BGProcessingTask` + "Ready to send" notification |

### 5.3 Apple Watch app

| ID | P | Requirement | Acceptance criteria |
|---|---|---|---|
| WCH-01 | P0 | Background reception | File moved before `session(_:didReceive:)` returns |
| WCH-02 | P0 | Document list | Icon, title, date; "Receiving…" when incomplete |
| WCH-03 | P0 | Pages reader | One page, horizontal swipe, "3 / 12" |
| WCH-04 | P0 | Zoom and pan | Crown 1x to 4x, drag, double tap |
| WCH-05 | P0 | Text reader | Crown scrolling, four sizes |
| WCH-06 | P0 | Table reader | Two-way scroll, frozen header, sheet choice |
| WCH-07 | P0 | Offline reading | iPhone in Airplane Mode |
| WCH-08 | P0 | Deletion | Propagated to the iPhone |
| WCH-09 | P1 | Switch Pages / Text | When both modes exist |
| WCH-10 | P1 | Resume reading | Page and position remembered |
| WCH-11 | P1 | Ticket mode | White background |
| WCH-12 | P2 | Complication | V2 |

## 6. Non-functional requirements

| Area | Requirement |
|---|---|
| iPhone performance | Background conversion, UI never blocked, batches of five pages |
| Watch performance | Opens in under 1 s, at most 3 pages in memory |
| Watch storage | ⚑ No default quota (real free space), optional cap, clear refusal |
| Battery | No heavy processing and no network requests on the watch |
| Reliability | Resumes after a restart; a partial document is never shown as complete |
| Privacy | No third-party server, no analytics, `completeUntilFirstUserAuthentication` |
| Accessibility | VoiceOver labels, Dynamic Type in the Text reader |
| Languages | English and French (String Catalog) |
| App Store | `PrivacyInfo.xcprivacy`, `PhotosPicker` without full library access |

## 7. Milestones

M0 project foundation · M1 minimal transport · M2 manifest and library · M3 images and photos · M4 PDF · M5 text · M6 Word and Excel · M7 share extension · M8 polish.

V2: CloudKit sync, folders and tags, complication, animated GIFs.

## 8. Risks

| Risk | Mitigation |
|---|---|
| WatchConnectivity unavailable in the share extension | App Group inbox processed by the app |
| Imprecise WebKit rendering (`.doc`, `.xls`) | Text or Table mode always offered; message suggesting a PDF export |
| Slow transfers for large documents | Economy preset, size estimate in the preview |
| Memory pressure on the watch | Downsampled images, three pages in memory |
| Signing and installation | Free account: apps expire after 7 days; paid account for TestFlight and the App Store |
