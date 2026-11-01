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

The flow below was verified by walking the real pages in a desktop browser
(2026-10-31). Do not guess these selectors again — re-scrape if NewsBank changes.

The app opens on a logon screen (username + password + "Logon"). Credentials are
stored in the **Keychain** (`kSecClassGenericPassword`, service
`com.anand.librarynewspaper`) and pre-fill the fields on the next launch.

- Returning users with saved credentials go **straight into the web flow**
  (no Logon tap needed). If the flow fails, it pops back to the logon screen
  and does *not* auto-retry (`autoStartDone` guard prevents a push loop).
- Logon pushes `AuthWebViewController`, a `UIWebView` running a step machine.
  The real page sequence:
  1. fixed redirector
     `https://go.openathens.net/redirector/kcls.org?url=<percent-encoded infoweb.newsbank.com/apps/news/?p=NewsBank>`
  2. `evgcatalog.kcls.org` — KCLS catalog login form; fill username+password,
     submit (generic probe: password+text input in the same form)
  3. `login.openathens.net` — OpenAthens sign-in (may be a two-step SPA:
     username first, password appears in place) and then a hand-off page titled
     "OpenAthens" ("please wait while we transfer you to NewsBank"). That page
     is a **SAML2 POST form** (hidden `SAMLResponse` + `RelayState`, no submit
     button) whose auto-submit JS cannot run on iOS 9 — the app submits it
     itself (`SUBMITTED:saml` in the probe). The app polls every 1.5 s for
     forms; if a page shows no form for ~6 s it also follows any meta-refresh /
     continue link and can open embedded auth iframes directly.
  4. **NewsBank is reached through the OpenAthens proxy domain**:
     `infoweb-newsbank-com.us1.proxy.openathens.net` (also `www-newsbank-com.…`).
     Host matching uses `containsString:@"newsbank"`, NOT "newsbank.com".
     Landing page: "America's News | Easy Search" with a
     **"Seattle Times Collection"** link → `/apps/news/browse-multi?...`.
  5. Collection page = a **table** (Source | Dates | Location | Type | Format |
     Language). Two rows are both named "Seattle Times, The (WA)":
     Format **Text** = code `STIW` (1985–Current), Format **Image** = code
     **`STS2S-EEDT`** (2018–Current). The app reads the image-edition
     `browse-pub` URL from this page and **navigates to it directly** rather
     than clicking (fallback if the collection page is unavailable: the
     hardcoded image-edition URL `LNImageEditionURLString`).
  6. Publication page (server-rendered) has a **"View Recent Issues"** list;
     links point at `issue-browse?...mody:MMDD...&action=browse&format=image`.
     The app picks the largest `mody` among links whose text is a full date
     (ignoring the bare day-number calendar) and **navigates directly** to it.
  7. Viewer page = `issue-browse ... &format=image`: shows page 1 of the issue
     as an image ("News Article, Seattle Times, The (WA), <date>, p1") with a
     "Next Page" link. Automation stops here; the user reads in the web view.

Both the collection and publication pages are plain **server-rendered HTML**
(verified: `browse-pub` / `issue-browse` appear in the raw document, built with
no page-building XHR), so the app reaches NewsBank's pages by **direct
navigation of known URLs** rather than simulating clicks — UIWebView on iOS 9
cannot run the site's modern JavaScript. Each NewsBank step is polled every
1.5 s (late-rendering content still works; a page that never shows the expected
content fails with a diagnostic dump instead of hanging).
- Failure policy (user decision): any unrecognized page, load error, or 60 s
  step timeout → alert naming the step (plus URL / link dump for diagnosis),
  then **stay in the web view**. The alert offers "Retry" (re-arms the current
  step) or "Dismiss" (stay put). It does **not** pop back to the logon screen
  and does **not** auto-retry beyond the per-step polling cap.
- The NewsBank reader is viewed **inside the embedded web view only**. Never
  download/scrape issue content to disk.
- `Info.plist` sets `NSAppTransportSecurity` / `NSAllowsArbitraryLoads` (needed
  on iOS 9); the **Security** framework is linked (keychain).
- Known environmental risk: NewsBank sits behind **AWS WAF** (awswaf.com JS
  telemetry). If its challenge JS cannot run on iOS 9 the pages may be blocked
  — that would surface as a WAF/captcha page in the web view.

## Getting logs from the iPad

- **Live syslog**: `idevicesyslog --syslog-relay -m "LibraryNewspaper"`.
  The `--syslog-relay` flag is **required** on iOS 9 — default mode wants the
  newer `os_trace_relay`, which old iOS lacks, and exits with
  `Could not connect to com.apple.os_trace_relay service (-2)`.
- **Crash reports**: `idevicecrashreport <dir>` copies device crash logs
  (omit `-e`; that deletes them from the device).
- The web flow logs under the `[auth]` prefix (steps, page loads, JS probe
  results, failures); the logon screen logs keychain reads/writes under
  `[login]`. Credentials are never logged.
- **Keychain on an ad-hoc build**: iOS 9 refuses keychain access
  (`errSecMissingEntitlement`, error -34018) unless the signature carries
  entitlements. `build_legacy.sh` signs with
  `--entitlements tools/legacy-entitlements.plist`
  (`application-identifier` + `keychain-access-groups` = bundle id). If a
  rebuild loses keychain access, check that the entitlements file is still
  passed to `codesign`.
- **Full-screen on the iPad**: the hand-rolled `Info.plist` must carry
  `UIDeviceFamily` = `[1, 2]`. Xcode injects that key during normal builds, but
  `build_legacy.sh` copies the plist verbatim — without it iOS runs the app in
  scaled iPhone compatibility mode (small letterboxed window). If the app looks
  like a phone app on the iPad, check this key first.
- **No device screenshots**: `idevicescreenshot` needs the developer disk image
  mounted, which this Xcode cannot do for iOS 9. Verify UI issues via
  `idevicesyslog` and by eye.

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
