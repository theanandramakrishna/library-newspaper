# AGENTS.md

## Target device

- **iPad 3 (`iPad3,1`)**, iOS **9.3.5**, **armv7 (32-bit)**.
- Jailbroken (Phoenix). Treat the device as offline-first; the app must not require network access.

## Sideloading

Use the legacy installer explicitly:

```
/tmp/legacy-ios-kit/bin/macos/ideviceinstaller -i <path-to.ipa|.app>
```

- The kit was **not present** on 2026-10-31 (`/tmp`, `/private/tmp`, `/var/tmp`, `/opt`,
  `/usr/local` and the home folder were searched). Provision it before relying on this path.
- `ideviceinstaller` can also be installed with `brew install ideviceinstaller`;
  the kit path above is the preferred, self-contained location.
- `/tmp` is cleared on reboot, so the kit may need re-provisioning.

## Toolchain constraint (important)

The installed Xcode is **26.3 / iOS 26.2 SDK**, which **cannot** produce a binary for this iPad:

- SDK `MinimumDeploymentTarget` is **12.0** (project needs 9.3).
- `UIKit.tbd` only contains `arm64-ios` / `arm64e-ios` (no armv7).
- Swift has **no armv7 iOS standard library** (`unable to load standard library for target 'armv7-apple-ios9.3'`).
- Xcode 26 ships no developer services for iOS 9.x (`ddiServicesAvailable: false`).

To build for the device, use a machine that can run either:

- **macOS 11 Big Sur + Xcode 12.5.1**, or
- **macOS 12 Monterey + Xcode 13.2.1**.

Build settings for the device build:

```
IPHONEOS_DEPLOYMENT_TARGET=9.3
ARCHS=armv7
VALID_ARCHS=armv7
```

The Xcode project in this repo already targets 9.3 and uses only iOS 9-era UIKit APIs.

## Verifying the code on this machine

The code can still be compiled against a supported SDK to catch errors:

```
xcodebuild -project LibraryNewspaper.xcodeproj -target LibraryNewspaper \
  -sdk iphonesimulator -configuration Debug \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO build
```

Do not run the simulator unless asked.

## Project layout

```
LibraryNewspaper.xcodeproj/        Xcode project (programmatic UIKit, no main storyboard)
LibraryNewspaper/
  AppDelegate.swift                @UIApplicationMain, navigation controller
  Models.swift                     IssueInfo / PageInfo / ArticleInfo, JSON parsing
  LibraryStore.swift               Scans Documents/NewsFiles, articles, OCR, search, image cache
  LibraryViewController.swift      Issue list + empty state
  IssueViewController.swift        Paged replica reader, toolbar, article list
  ZoomablePageView.swift           Pinch/double-tap zoom, tappable article rectangles
  ArticleViewController.swift      Full-text reader
  ArticleListViewController.swift  Article picker popover
  SearchViewController.swift       Full-text search
  Info.plist                       UIFileSharingEnabled, iOS 9 orientations
  LaunchScreen.storyboard
Sample/NewsFiles/                  Two generated sample issues
tools/make_sample.swift            Regenerates the sample issues: `swift tools/make_sample.swift`
```

## Content format

Content lives in `Documents/NewsFiles/<issue-id>/`:

```
issue.json        { id, title, subtitle, date, pages: [{ image, width, height }] }
pages/001.jpg     replica page images (jpg/png/heic/tiff), natural sort fallback
articles/*.json   { id, page, headline, bounds:{x,y,width,height}, text | textFile }
ocr/1.txt|1.json  page text for search / read-aloud ("text" or "lines" array)
```

Article `bounds` are in page pixel coordinates. Page `width`/`height` in `issue.json`
let the viewer scale rectangles onto the downsampled image.

## Rules

- The user fetches replica files themselves. Do **not** add network fetching,
  NewsBank/OpenAthens integration, authentication or scraping code.
- Keep the app source-compatible with iOS 9.3 / Swift 5 and avoid APIs newer than iOS 9.
- Keep everything on-device; no analytics, no third-party SDKs.
