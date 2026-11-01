# AGENTS.md

## Quick start (resume here)

Everything needed to rebuild and sideload is already in the repo:

```
tools/provision_sdk.sh          # once per reboot; fetches iPhoneOS11.4.sdk into /tmp/legacy-sdks
tools/build_legacy.sh           # compile armv7, ad-hoc sign, build IPA, install to the USB iPad
tools/build_legacy.sh --build-only   # just build build/legacy/LibraryNewspaper.ipa
```

Verified on 2026-10-31: the build produces `Mach-O executable arm_v7` with
`LC_VERSION_MIN_IPHONEOS 9.3`. Do not assume the old Swift setup works — see the
toolchain section below for why the app is Objective-C.

If the install fails, read "Troubleshooting the install" at the bottom before
changing code or build flags.

## Target device

- **iPad 3 (`iPad3,1`)**, iOS **9.3.5**, **armv7 (32-bit)**.
- Jailbroken (Phoenix). Treat the device as offline-first; the app must not require network access.

## Sideloading

Installing needs `ideviceinstaller` on `PATH` (`brew install ideviceinstaller`);
`tools/build_legacy.sh` uses it for the install step. Manual install:

```
ideviceinstaller install build/legacy/LibraryNewspaper.ipa
```

- `ideviceinstaller` 1.2.x uses subcommands (`install`, `uninstall`, `list`,
  `upgrade`); the old one-letter flags (`-i`, `-U`, `-l`) were removed in 1.2.0.
- No symlinks or wrapper paths: the Homebrew binary is used directly.
- `/tmp` is cleared on reboot, so the SDK (`/tmp/legacy-sdks`) may need
  re-provisioning; `ideviceinstaller` itself survives reboots.
- `tools/build_legacy.sh` falls back to a plain `PATH` lookup, and honours
  `INSTALLER=/path/to/ideviceinstaller` if you ever need to override it.

## Logon flow (KCLS / OpenAthens)

The app opens on a logon screen (username + password + "Logon"). Credentials are
stored in the **Keychain** (`kSecClassGenericPassword`, service
`com.anand.librarynewspaper`) and pre-fill the fields on the next launch.

- Returning users with saved credentials go **straight into the web flow**
  (no Logon tap needed). If the flow fails, it pops back to the logon screen
  and does *not* auto-retry (`autoStartDone` guard prevents a push loop).
- Logon pushes `AuthWebViewController`, a `UIWebView` running a step machine:
  1. load the fixed redirector
     `https://go.openathens.net/redirector/kcls.org?url=<percent-encoded infoweb.newsbank.com/apps/news/?p=NewsBank>`
  2. any page with a login form (OpenAthens- or library-hosted): silently fill
     username/password and submit (`LNLoginFillScript`); a second login page
     after a submission means rejected credentials → fail
  3. NewsBank landing → click the link matching "seattle times"
  4. collection page → click the link matching "image"
  5. edition page → click the newest issue (date-text link preferred; see
     `LNPickIssueScript`), then stop automating — the user reads in the web view
- Failure policy (user decision): any unrecognized page, load error, or 60 s
  step timeout → alert naming the step (plus URL / link dump for diagnosis),
  then pop back to the logon screen. **No manual fallback, no retries.**
- The NewsBank reader is viewed **inside the embedded web view only**. Never
  download/scrape issue content to disk.
- Selector JS is heuristic; when NewsBank/OpenAthens change their layout the
  flow fails by design — refine the JS constants in `AuthWebViewController.m`.
- `Info.plist` sets `NSAppTransportSecurity` / `NSAllowsArbitraryLoads` (needed
  on iOS 9); the **Security** framework is linked (keychain).

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
  LoginViewController.h/.m         Logon screen, Keychain credential storage
  AuthWebViewController.h/.m       UIWebView flow: OpenAthens login -> Seattle Times issue
  Models.h/.m                      LNIssue / LNPage / LNArticle / LNSearchHit, JSON parsing (offline reader)
  LibraryStore.h/.m                Scans Documents/NewsFiles, articles, OCR, search, image cache (offline reader)
  LibraryViewController.h/.m       Issue list + empty state (offline reader, currently unreachable)
  IssueViewController.h/.m         Paged replica reader, toolbar, article list (offline reader)
  ZoomablePageView.h/.m            Pinch/double-tap zoom, tappable article rectangles (offline reader)
  ArticleViewController.h/.m       Full-text reader (offline reader)
  ArticleListViewController.h/.m   Article picker popover (offline reader)
  SearchViewController.h/.m        Full-text search (offline reader)
  Info.plist                       UIFileSharingEnabled, NSAllowsArbitraryLoads, iOS 9 orientations
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

- The only network destination is the KCLS OpenAthens redirector and the
  NewsBank pages it leads to. No other endpoints, no analytics, no third-party
  SDKs, nothing on-device beyond the Keychain credential entry.
- Credentials live only in the iOS Keychain. Never log them, send them
  anywhere else, or store them in `NSUserDefaults`.
- No scraping/downloading of issue content: the NewsBank reader runs in the
  embedded web view. The old offline `Documents/NewsFiles` reader
  (`LibraryViewController` and friends) stays compiled but unreachable.
- Keep the app source-compatible with iOS 9.3 and avoid APIs newer than iOS 9.
- Signing is ad-hoc; the iPad needs AppSync Unified (or an equivalent jailbreak patch)
  to install unsigned/ad-hoc apps. If installation is rejected, check AppSync first.

## Troubleshooting the install

Work through these in order; most failures are environmental, not code problems.

1. **`ideviceinstaller: command not found`** — install it with
   `brew install ideviceinstaller` and make sure `/usr/local/bin` is on `PATH`. The
   Homebrew build pulls `libimobiledevice`, which compiles from source here and takes
   several minutes; do not assume it hung.
2. **`Could not connect to lockdownd` / `No device found`** — the device is not
   paired or usbmuxd cannot see it. Check with
   `xcrun devicectl list devices`, then pair explicitly:
   ```
   idevicepair pair       # tap "Trust" on the iPad
   idevicepair validate
   ```
   Reconnecting the cable or rebooting the iPad usually requires pairing again.
3. **`ERROR: Install failed. Got error "ApplicationVerificationFailed"`** — the iPad
   rejected the ad-hoc signature. That means AppSync Unified is missing or disabled.
   Check what is installed with `ideviceinstaller list`; if the list is empty or the
   call fails, install/enable AppSync Unified in Cydia and retry. There is no
   fallback: this Mac has no codesigning identity (`security find-identity -v -p
   codesigning` reports zero) and no provisioning profiles, so re-signing properly
   is not an option.
4. **`APIInternalError` / `MismatchedApplicationIdentifierEntitlement`** — a build with
   the same bundle identifier is already installed. Uninstall first:
   `ideviceinstaller uninstall com.anand.librarynewspaper`, then install again.
5. **App installs but crashes on launch on iOS 9.3** — confirm the binary is really
   armv7: `lipo -info build/legacy/LibraryNewspaper.app/LibraryNewspaper` must say
   `armv7`, and `otool -l ... | grep -A3 LC_VERSION_MIN_IPHONEOS` must show `9.3`.
   If it says `arm64` something built with plain Xcode settings instead of
   `tools/build_legacy.sh`.
6. **`/tmp/legacy-sdks` disappeared** — `/tmp` is cleared on reboot. Re-run
   `tools/provision_sdk.sh` (or just `tools/build_legacy.sh`, which provisions the SDK
   automatically). `ideviceinstaller` lives in Homebrew and is unaffected.
7. **Sideloading a debug build** — you can also install the `.app` directory directly
   (`ideviceinstaller install build/legacy/LibraryNewspaper.app`); the IPA is just a
   zip of `Payload/` around it.
