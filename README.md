# News Reader

A **Seattle Times (NewsBank via KCLS)** reader for the **iPad 3 (iOS 9.3.5, armv7)**.
The app opens on a logon screen; pressing **Logon** signs in through KCLS's
OpenAthens redirector inside an embedded browser and opens the most recent issue
of the Seattle Times Collection (image format) for reading.

- Credentials are saved in the Keychain and pre-filled; returning users go
  straight into the sign-in flow.
- The reader is NewsBank's own image reader, shown in the embedded web view.
- If any step of the sign-in/click-through fails, the app shows an error and
  returns to the logon screen.
- An earlier offline mode (local files in `Documents/NewsFiles`) is still in the
  codebase but currently unreachable.

## Building and installing

The toolchain is documented in `AGENTS.md`. In short:

```
tools/build_legacy.sh                # build + install to the USB iPad
tools/build_legacy.sh --build-only   # build build/legacy/LibraryNewspaper.ipa
```

The first run provisions a legacy SDK (`tools/provision_sdk.sh`), then compiles the
Objective-C sources for `armv7-apple-ios9.3`, signs ad-hoc and installs with
`ideviceinstaller` (from `brew install ideviceinstaller`).

The sources also compile against the current Xcode for syntax checking:

```
xcodebuild -project LibraryNewspaper.xcodeproj -target LibraryNewspaper \
  -sdk iphonesimulator -configuration Debug \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO build
```

## Features

- **Logon**: username/password with a Logon button; Keychain-backed, pre-filled
  on launch; silent fill-and-submit on the OpenAthens login page.
- **Auto-navigation**: redirector → Seattle Times Collection → image format →
  newest issue, then the embedded web view hands control to the user.
- **Offline reader (unreachable)**: local `Documents/NewsFiles` issues with a
  replica page viewer, tappable articles, reflowed text, and full-text search.

## Content format

Content lives in `Documents/NewsFiles/<issue-id>/`:

```
issue.json        { id, title, subtitle, date, pages: [{ image, width, height }] }
pages/001.jpg     replica page images (jpg/png/heic/tiff); natural sort fallback
articles/*.json   { id, page, headline, bounds:{x,y,width,height}, text | textFile }
ocr/1.txt|1.json  page text for search ("text" or "lines" array)
```

`bounds` are in page pixel coordinates; `width`/`height` in `issue.json` let the viewer
scale rectangles onto the downsampled image. `issue.json` is optional if `pages/`
contains images.

### Example `issue.json`

```json
{
  "id": "sample-times-2026-10-17",
  "title": "The Sample Times",
  "subtitle": "Morning Edition",
  "date": "2026-10-17",
  "pages": [
    { "image": "pages/001.jpg", "width": 1600, "height": 2200 }
  ]
}
```

### Example article

```json
{
  "id": "1-1",
  "page": 1,
  "headline": "Council Backs Transit Plan",
  "bounds": { "x": 80, "y": 230, "width": 1440, "height": 400 },
  "text": "The city council approved a new budget..."
}
```

## Getting content onto the iPad

Use file sharing (iTunes/Finder, or a jailbreak file manager) to copy issue folders into
the app's `Documents/NewsFiles/`. The app reads the folder on launch and on pull-to-refresh.

`Sample/NewsFiles/` contains two generated sample issues:

```
swift tools/make_sample.swift
```

## Requirements

- iPad 3 (`iPad3,1`), iOS 9.3.5, armv7, jailbroken
- AppSync Unified (or equivalent) for ad-hoc signed installs

## License

MIT License — see `LICENSE`.
