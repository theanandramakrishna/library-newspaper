# News Reader App

A newspaper reading application for iPad that supports replica image viewing like PressReader.

## Building the App

1. Open the Xcode project:
   - Navigate to `News Reader.xcodeproj`
   - Double-click to open

2. Ensure you're targeting iOS 9.3.5
   - Open Project Settings (Cmd + ,)
   - Go to `Deployment Target`
   - Set to iOS 9.3.5

3. Build and Run:
   - Press Cmd + B to build
   - Press Cmd + R to run on simulator or connected device

## Features

### Main Interface
- **Import News**: Import news files from your device
- **Browse News**: Browse available news issues

### Browsing
- View a list of all imported news issues
- Each issue shows title, subtitle, and date
- Tap an issue to view its pages

### Page Viewing
- View individual pages with zoom support (pinch to zoom)
- Articles are highlighted on pages (red semi-transparent overlays)
- Tap highlighted article areas to view full text

### Article Details
- Full-screen article text view
- Scrollable content
- Close button to return to page view

### Search
- Search across all articles
- Filter by page number
- Click results to navigate directly

## File Structure

### Data Organization
News files should be organized in this structure:

```
NewsFiles/
├── issue_001/
│   ├── metadata.json
│   ├── pages/
│   │   ├── page_1.jpg
│   │   ├── page_2.jpg
│   │   └── ...
│   ├── articles/
│   │   ├── article_1.json
│   │   ├── article_2.json
│   │   └── ...
│   └── ocr/
│       ├── page_1.txt
│       ├── page_2.txt
│       └── ...
└── issue_002/
    ├── ... (similar structure)
```

### Metadata JSON Format
Each issue needs a `metadata.json` file:

```json
{
    "id": "issue_001",
    "title": "Seattle Times",
    "subtitle": "August 17, 2026",
    "date": "08/17/2026",
    "year": "2026",
    "pages": 50,
    "articles": 25
}
```

### Article JSON Format
Each article needs an `.json` file:

```json
{
    "id": 1,
    "headline": "Breaking News Headline",
    "bounds": {
        "x": 100.0,
        "y": 200.0,
        "width": 300.0,
        "height": 80.0
    },
    "textFile": "article_1.txt"
}
```

### OCR Text Files
Each OCR text file should be a `.txt` file containing the full article text.

## Importing News Files

1. Run the app on simulator or device
2. Tap **Import News** button
3. Select a zip file containing your news files
4. The app will extract and organize the files in the Documents/NewsFiles directory

## How It Works

1. **Import**: Files are extracted to `Documents/NewsFiles/{issueId}/`
2. **Metadata**: Issue metadata is read from `metadata.json` files
3. **Pages**: Images are loaded directly from the files
4. **Articles**: Article locations are read from JSON files
5. **OCR**: Full article text is loaded when needed for viewing

## Performance Notes

- Uses on-device storage only (offline-first)
- Optimized for iOS 9.3.5 compatibility
- Supports basic gesture handling (tap, pinch zoom)
- Memory efficient with lazy loading of article text

## Requirements

- iOS 9.3.5 or later
- iPad (recommended)
- Minimum 512MB RAM
- Sufficient storage space for news files

## License

MIT License - See LICENSE file for details
