# AGENTS.md

## Target device

- **iPad 3 (`iPad3,1`)**, iOS **9.3.5**, **armv7 (32-bit)**.
- Jailbroken (Phoenix). Treat the device as offline-first; the app must not require network access.

## Sideloading

Use the legacy installer explicitly:

```
/tmp/legacy-ios-kit/bin/macos/ideviceinstaller -i <path-to.ipa|.app>
```

- The kit path is the preferred location. Provision it by symlinking the Homebrew
  binary: `brew install ideviceinstaller`, then
  `mkdir -p /tmp/legacy-ios-kit/bin/macos && ln -s "$(command -v ideviceinstaller)" /tmp/legacy-ios-kit/bin/macos/ideviceinstaller`.
- `/tmp` is cleared on reboot, so the kit may need re-provisioning.
- `tools/build_legacy.sh` prefers the kit path and falls back to `ideviceinstaller` on `PATH`.

## Toolchain constraint (important)

The installed Xcode is **26.3 / iOS 26.2 SDK**, which **cannot** produce a binary for this iPad:

- SDK `MinimumDeploymentTarget` is **12.0** (project needs 9.3).
- `UIKit.tbd` only contains `arm64-ios` / `arm64e-ios` (no armv7).
- Xcode 26 ships no developer services for iOS 9.x (`ddiServicesAvailable: false`).

For **Objective-C** this is only an SDK problem: current clang still emits armv7 object
code, so the app is built against the community `theos/sdks` **iPhoneOS11.4.sdk**
(headers + armv7 `.tbd` stubs) with `-target armv7-apple-ios9.3`.

For **Swift** the problem is worse and cannot be worked around without an old Xcode:

- Swift 5.5.3 toolchains from swift.org still ship an armv7 iOS standard library, but
  the Foundation/UIKit/Dispatch **Swift overlays live in the Xcode SDK**, not the
  toolchain. The `theos/sdks` mirrors strip them, so `import Foundation`/`import UIKit`
  fails (`IndexPath`/`Data`/`URL` missing, `BOOL` imported as `Int8`, `NSDateFormatter`
  renamed to a type that does not exist).
- Producing the overlays requires the iOS 14.5/15.2 SDK that ships with Xcode 12.5 or
  13.2, which Apple only distributes behind a developer-account login.

This is why the app is written in **Objective-C**: it keeps iOS 9.3 / armv7 compatibility
and can be built on this machine today. Do not reintroduce Swift unless the build moves
to Xcode 12.5/13.2 (or an SDK with matching Swift overlays).

## Building

```
tools/build_legacy.sh                # build + install to the connected iPad
tools/build_legacy.sh --build-only   # build build/legacy/LibraryNewspaper.ipa
```

What the script does:

1. Provisions `iPhoneOS11.4.sdk` with `tools/provision_sdk.sh` if it is missing
   (sparse clone of `github.com/theos/sdks` into `/tmp/legacy-sdks`).
2. Compiles every `LibraryNewspaper/*.m` with
   `clang -target armv7-apple-ios9.3 -isysroot <SDK> -fobjc-arc -fmodules`.
3. Links `UIKit`, `Foundation`, `CoreGraphics`, `ImageIO`.
4. Assembles the bundle (`Info.plist`, `PkgInfo`, `LaunchScreen.storyboardc` compiled
   with `ibtool --minimum-deployment-target 9.3`).
5. Signs ad-hoc with `codesign -f -s -` and zips the IPA.

Build settings that matter:

```
IPHONEOS_DEPLOYMENT_TARGET=9.3
ARCHS=armv7
-target armv7-apple-ios9.3
```

## Verifying the code on this machine

The Objective-C sources also compile with the current Xcode, which catches syntax and
API mistakes (do not launch the simulator unless asked):

```
xcodebuild -project LibraryNewspaper.xcodeproj -target LibraryNewspaper \
  -sdk iphonesimulator -configuration Debug \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO build
```

## Project layout

```
LibraryNewspaper.xcodeproj/        Xcode project (programmatic UIKit, no main storyboard)
LibraryNewspaper/
  main.m                           UIApplicationMain
  AppDelegate.h/.m                 Window + navigation controller, dark navigation bar
  Models.h/.m                      LNIssue / LNPage / LNArticle / LNSearchHit, JSON parsing
  LibraryStore.h/.m                Scans Documents/NewsFiles, articles, OCR, search, image cache
  LibraryViewController.h/.m       Issue list + empty state
  IssueViewController.h/.m         Paged replica reader, toolbar, article list
  ZoomablePageView.h/.m            Pinch/double-tap zoom, tappable article rectangles
  ArticleViewController.h/.m       Full-text reader
  ArticleListViewController.h/.m   Article picker popover
  SearchViewController.h/.m        Full-text search
  Info.plist                       UIFileSharingEnabled, iOS 9 orientations
  LaunchScreen.storyboard
Sample/NewsFiles/                  Two generated sample issues
tools/build_legacy.sh              armv7 build, bundle, sign, IPA, install
tools/provision_sdk.sh             Fetches the legacy iPhoneOS SDK (theos/sdks)
tools/make_sample.swift            Regenerates the samples: `swift tools/make_sample.swift`
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
- Keep the app source-compatible with iOS 9.3 and avoid APIs newer than iOS 9.
- Keep everything on-device; no analytics, no third-party SDKs.
- Signing is ad-hoc; the iPad needs AppSync Unified (or an equivalent jailbreak patch)
  to install unsigned/ad-hoc apps. If installation is rejected, check AppSync first.
