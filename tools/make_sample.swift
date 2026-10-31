#!/usr/bin/env swift

// Generates two sample issues (replica page JPEGs + manifests + article JSON + OCR text)
// so the app can be exercised without real content.
//
// Usage:  swift tools/make_sample.swift
// Output: Sample/NewsFiles/<issue-id>/...

import Foundation
import AppKit
import CoreText

let pageWidth: CGFloat = 1600
let pageHeight: CGFloat = 2200

// MARK: - Text

let sentences: [String] = [
    "The city council approved a new budget on Tuesday, setting aside funds for transit, parks and a long-delayed repair program.",
    "Officials said the plan would take effect next spring, though several members warned that the timeline could slip again.",
    "Residents packed the meeting room, many carrying signs and asking for more detail about how the money would be spent.",
    "A spokesperson for the department declined to comment on the specifics, saying only that a full report would be released soon.",
    "The announcement follows months of quiet negotiations between the agency and neighborhood groups.",
    "Analysts described the decision as a compromise that leaves almost everyone partly satisfied and partly frustrated.",
    "Work is expected to begin along the waterfront corridor before the end of the year, weather permitting.",
    "For now, the practical effect is modest: a handful of new signs, a revised schedule and a promise to revisit the issue in the fall.",
    "Teachers and parents have raised concerns about class sizes, and the district says it is reviewing staffing levels.",
    "The forecast calls for rain through the weekend, with a chance of clearing by Monday morning.",
    "Ticket sales have been strong, and organizers say they expect a larger crowd than last year.",
    "The library will extend its hours on weeknights beginning next month, funded by a private grant.",
    "Construction crews closed two lanes of the bridge for most of the afternoon, causing delays across the city.",
    "A small group of volunteers spent the morning clearing debris from the trail after the storm.",
    "The report recommends three changes: shorter meetings, clearer agendas and more time for public comment.",
    "Officials emphasized that no final decision has been made and that additional hearings will be scheduled."
]

let headlines: [[String]] = [
    ["Council Backs Transit Plan After Long Debate",
     "Waterfront Repairs Set to Begin This Year",
     "Schools Review Class Sizes as Enrollment Grows"],
    ["Storm Cleanup Continues Across the Region",
     "Library Extends Weeknight Hours",
     "Bridge Work Snarls Evening Commute"],
    ["Budget Vote Draws a Crowd",
     "Transit Agency Promises a Full Report",
     "Neighborhood Groups Press for Details"],
    ["Rain Expected Through the Weekend",
     "Tickets Strong for Weekend Festival",
     "Volunteers Clear the Riverside Trail"]
]

func paragraph(seed: Int, count: Int) -> String {
    var result: [String] = []
    for index in 0..<count {
        result.append(sentences[(seed * 3 + index * 5) % sentences.count])
    }
    return result.joined(separator: " ")
}

// MARK: - Drawing helpers

func ctFont(_ name: String, _ size: CGFloat) -> CTFont {
    return CTFontCreateWithName(name as CFString, size, nil)
}

func attributed(_ text: String,
                font: CTFont,
                color: CGColor,
                lineSpacing: CGFloat = 0,
                alignment: CTTextAlignment = .left) -> NSAttributedString {
    var spacing = lineSpacing
    var align = alignment
    return withUnsafeBytes(of: &spacing) { spacingBuffer in
        withUnsafeBytes(of: &align) { alignBuffer in
            let settings: [CTParagraphStyleSetting] = [
                CTParagraphStyleSetting(spec: .lineSpacingAdjustment,
                                        valueSize: MemoryLayout<CGFloat>.size,
                                        value: spacingBuffer.baseAddress!),
                CTParagraphStyleSetting(spec: .alignment,
                                        valueSize: MemoryLayout<CTTextAlignment>.size,
                                        value: alignBuffer.baseAddress!)
            ]
            let paragraphStyle = CTParagraphStyleCreate(settings, settings.count)

            return NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
            ])
        }
    }
}

/// Core Text frames flow from the top of their path downward, so convert a
/// top-left origin into Core Graphics coordinates.
func pageRect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
    return CGRect(x: x, y: pageHeight - top - height, width: width, height: height)
}

func drawText(_ string: NSAttributedString, in rect: CGRect, context: CGContext) {
    let path = CGPath(rect: rect, transform: nil)
    let framesetter = CTFramesetterCreateWithAttributedString(string)
    let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
    CTFrameDraw(frame, context)
}

func drawRule(y: CGFloat, context: CGContext, weight: CGFloat = 2) {
    context.setStrokeColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
    context.setLineWidth(weight)
    let lineY = pageHeight - y
    context.move(to: CGPoint(x: 80, y: lineY))
    context.addLine(to: CGPoint(x: pageWidth - 80, y: lineY))
    context.strokePath()
}

// MARK: - Page rendering

struct SampleArticle {
    let headline: String
    let body: String
    let x: CGFloat
    let top: CGFloat
    let width: CGFloat
    let height: CGFloat
}

func makeArticles(pageSeed: Int) -> [SampleArticle] {
    let pageHeadlines = headlines[pageSeed % headlines.count]

    let top = SampleArticle(headline: pageHeadlines[0],
                            body: paragraph(seed: pageSeed, count: 5),
                            x: 80, top: 230, width: pageWidth - 160, height: 400)

    let left = SampleArticle(headline: pageHeadlines[1],
                             body: paragraph(seed: pageSeed + 1, count: 8),
                             x: 80, top: 760, width: 690, height: 880)

    let right = SampleArticle(headline: pageHeadlines[2],
                              body: paragraph(seed: pageSeed + 2, count: 8),
                              x: 830, top: 760, width: 690, height: 880)

    let bottom = SampleArticle(headline: "In Brief",
                               body: paragraph(seed: pageSeed + 3, count: 4),
                               x: 80, top: 1700, width: pageWidth - 160, height: 380)

    return [top, left, right, bottom]
}

func renderPage(seed: Int, pageNumber: Int, totalPages: Int, dateText: String) -> Data {
    let width = Int(pageWidth)
    let height = Int(pageHeight)

    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: width,
                                     pixelsHigh: height,
                                     bitsPerSample: 8,
                                     samplesPerPixel: 4,
                                     hasAlpha: true,
                                     isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0,
                                     bitsPerPixel: 0) else {
        fatalError("Could not create bitmap")
    }
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    guard let nsContext = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Could not create graphics context")
    }
    NSGraphicsContext.current = nsContext
    let context = nsContext.cgContext

    // Paper
    context.setFillColor(CGColor(red: 0.99, green: 0.985, blue: 0.97, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

    let ink = CGColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
    let gray = CGColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1)

    // Masthead
    drawText(attributed("THE SAMPLE TIMES",
                        font: ctFont("Times New Roman", 92),
                        color: ink,
                        alignment: .center),
             in: pageRect(x: 80, top: 45, width: pageWidth - 160, height: 110),
             context: context)

    drawText(attributed("\(dateText)  ·  Morning Edition  ·  Page \(pageNumber) of \(totalPages)",
                        font: ctFont("Helvetica", 22),
                        color: gray,
                        alignment: .center),
             in: pageRect(x: 80, top: 155, width: pageWidth - 160, height: 32),
             context: context)

    drawRule(y: 200, context: context, weight: 4)

    let articles = makeArticles(pageSeed: seed)
    for (index, article) in articles.enumerated() {
        let headlineSize: CGFloat = index == 3 ? 40 : 56
        drawText(attributed(article.headline,
                            font: ctFont("Times New Roman Bold", headlineSize),
                            color: ink),
                 in: pageRect(x: article.x,
                              top: article.top,
                              width: article.width,
                              height: headlineSize * 2.2),
                 context: context)

        drawText(attributed(article.body,
                            font: ctFont("Times New Roman", 26),
                            color: ink,
                            lineSpacing: 6),
                 in: pageRect(x: article.x,
                              top: article.top + headlineSize * 2.4,
                              width: article.width,
                              height: article.height - headlineSize * 2.4),
                 context: context)
    }

    drawRule(y: 700, context: context)
    drawRule(y: 1680, context: context)
    drawRule(y: 2120, context: context)

    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
        fatalError("Could not encode JPEG")
    }
    return data
}

// MARK: - Writing an issue

func writeIssue(id: String,
                title: String,
                subtitle: String,
                dateText: String,
                pageDates: [String],
                root: URL) throws {

    let manager = FileManager.default
    let issueDirectory = root.appendingPathComponent(id, isDirectory: true)
    let pagesDirectory = issueDirectory.appendingPathComponent("pages", isDirectory: true)
    let articlesDirectory = issueDirectory.appendingPathComponent("articles", isDirectory: true)
    let ocrDirectory = issueDirectory.appendingPathComponent("ocr", isDirectory: true)

    for directory in [issueDirectory, pagesDirectory, articlesDirectory, ocrDirectory] {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
    }

    var pageManifest: [[String: Any]] = []
    let totalPages = pageDates.count

    for (offset, date) in pageDates.enumerated() {
        let pageNumber = offset + 1
        let fileName = String(format: "%03d.jpg", pageNumber)
        let fileURL = pagesDirectory.appendingPathComponent(fileName)

        let jpeg = renderPage(seed: offset + pageNumber, pageNumber: pageNumber, totalPages: totalPages, dateText: date)
        try jpeg.write(to: fileURL)

        pageManifest.append(["image": "pages/\(fileName)",
                             "width": Int(pageWidth),
                             "height": Int(pageHeight)])

        // Article JSON + OCR text
        let articles = makeArticles(pageSeed: offset + pageNumber)
        var pageText: [String] = ["THE SAMPLE TIMES", date, "Page \(pageNumber) of \(totalPages)"]

        for (articleIndex, article) in articles.enumerated() {
            let articleID = String(format: "%d-%d", pageNumber, articleIndex + 1)
            let payload: [String: Any] = [
                "id": articleID,
                "page": pageNumber,
                "headline": article.headline,
                "bounds": ["x": article.x,
                           "y": article.top,
                           "width": article.width,
                           "height": article.height],
                "text": article.headline + "\n\n" + article.body
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
            try data.write(to: articlesDirectory.appendingPathComponent("\(articleID).json"))

            pageText.append(article.headline)
            pageText.append(article.body)
        }

        let ocrText = pageText.joined(separator: "\n\n")
        try ocrText.write(to: ocrDirectory.appendingPathComponent("\(pageNumber).txt"),
                          atomically: true,
                          encoding: .utf8)
    }

    let manifest: [String: Any] = [
        "id": id,
        "title": title,
        "subtitle": subtitle,
        "date": dateText,
        "pages": pageManifest
    ]
    let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])
    try manifestData.write(to: issueDirectory.appendingPathComponent("issue.json"))
}

// MARK: - Main

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let outputRoot = scriptURL.deletingLastPathComponent().appendingPathComponent("Sample/NewsFiles", isDirectory: true)

let manager = FileManager.default
if manager.fileExists(atPath: outputRoot.path) {
    try manager.removeItem(at: outputRoot)
}
try manager.createDirectory(at: outputRoot, withIntermediateDirectories: true, attributes: nil)

try writeIssue(id: "sample-times-2026-10-17",
               title: "The Sample Times",
               subtitle: "Morning Edition",
               dateText: "2026-10-17",
               pageDates: ["Saturday, October 17, 2026",
                           "Saturday, October 17, 2026",
                           "Saturday, October 17, 2026",
                           "Saturday, October 17, 2026"],
               root: outputRoot)

try writeIssue(id: "sample-times-2026-10-18",
               title: "The Sample Times",
               subtitle: "Weekend Edition",
               dateText: "2026-10-18",
               pageDates: ["Sunday, October 18, 2026",
                           "Sunday, October 18, 2026",
                           "Sunday, October 18, 2026"],
               root: outputRoot)

print("Wrote sample issues to \(outputRoot.path)")
