# News Reader

An offline replica-newspaper reader for the **iPad 3 (iOS 9.3.5, armv7)**. It shows
scanned newspaper pages with tappable article regions, a reflowed text reader, and
full-text search over per-page text.

You supply the page images and article/OCR data; the app never fetches anything from
the network.

## Building and installing

The toolchain is documented in `AGENTS.md`. In short:

```
tools/build_legacy.sh                # build + install to the USB iPad
tools/build_legacy.sh --build-only   # build build/legacy/LibraryNewspaper.ipa
```

The first run provisions a legacy SDK (`tools/provision_sdk.sh`), then compiles the
Objective-C sources for `armv7-apple-ios9.3`, signs ad-hoc and installs with
`/tmp/legacy-ios-kit/bin/macos/ideviceinstaller`.

The sources also compile against the current Xcode for syntax checking:

```
xcodebuild -project LibraryNewspaper.xcodeproj -target LibraryNewspaper \
  -sdk iphonesimulator -configuration Debug \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 CODE_SIGNING_ALLOWED=NO build
```

## Features

- **Library**: every folder in `Documents/NewsFiles` becomes an issue, newest first,
  with a first-page thumbnail.
- **Replica reader**: pinch/double-tap zoom, page slider, swipe or arrow paging,
  tappable article rectangles, tap the page to hide/show the chrome.
- **Articles**: article list popover, full-text reader with headline and page marker.
- **Search**: case-insensitive search across every issue's page text, with snippets
  and highlighted headlines.
- **Image handling**: pages are downsampled through ImageIO and cached, so large
  scans do not exhaust memory.

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
