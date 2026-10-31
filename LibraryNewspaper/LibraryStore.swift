import Foundation
import UIKit
import ImageIO

/// Scans the app's Documents/NewsFiles folder and exposes issues, article
/// rectangles, OCR text and search.
final class LibraryStore {

    static let shared = LibraryStore()

    let rootURL: URL

    private var issueCache: [IssueInfo]?
    private var articleCache: [String: [ArticleInfo]] = [:]
    private var ocrCache: [String: String] = [:]

    init() {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        rootURL = URL(fileURLWithPath: documents).appendingPathComponent("NewsFiles", isDirectory: true)
        if !FileManager.default.fileExists(atPath: rootURL.path) {
            try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
        }
    }

    // MARK: - Issues

    func issues() -> [IssueInfo] {
        if let cached = issueCache { return cached }
        let loaded = loadIssues()
        issueCache = loaded
        return loaded
    }

    func reload() {
        issueCache = nil
        articleCache.removeAll()
        ocrCache.removeAll()
    }

    private func loadIssues() -> [IssueInfo] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: rootURL.path) else { return [] }

        var result: [IssueInfo] = []
        for name in names where !name.hasPrefix(".") {
            let directory = rootURL.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            if let issue = loadIssue(directory: directory, fallbackID: name) {
                result.append(issue)
            }
        }

        result.sort { lhs, rhs in
            let left = lhs.date ?? Date.distantPast
            let right = rhs.date ?? Date.distantPast
            if left != right { return left > right }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return result
    }

    private func loadIssue(directory: URL, fallbackID: String) -> IssueInfo? {
        let manifest = JSON.object(at: directory.appendingPathComponent("issue.json"))
            ?? JSON.object(at: directory.appendingPathComponent("metadata.json"))
            ?? [:]

        var pages: [PageInfo] = []

        // Preferred: explicit page list in the manifest.
        for (index, entry) in JSON.array(manifest["pages"]).enumerated() {
            var relativePath: String?
            var width = 0
            var height = 0

            if let path = entry as? String {
                relativePath = path
            } else {
                let page = JSON.dictionary(entry)
                relativePath = JSON.string(page["image"])
                    ?? JSON.string(page["file"])
                    ?? JSON.string(page["path"])
                width = JSON.int(page["width"]) ?? 0
                height = JSON.int(page["height"]) ?? 0
            }

            guard let path = relativePath else { continue }
            let url = directory.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            pages.append(PageInfo(number: pages.count + 1, imageURL: url, width: width, height: height))
        }

        // Fallback: every image inside the pages folder, sorted naturally.
        if pages.isEmpty {
            let files = Models.imageFiles(in: directory.appendingPathComponent("pages", isDirectory: true))
            if files.isEmpty { return nil }
            pages = files.enumerated().map {
                PageInfo(number: $0.offset + 1, imageURL: $0.element, width: 0, height: 0)
            }
        }

        let title = JSON.string(manifest["title"])
            ?? JSON.string(manifest["publication"])
            ?? fallbackID
        let subtitle = JSON.string(manifest["subtitle"])
            ?? JSON.string(manifest["edition"])
            ?? ""
        let dateText = JSON.string(manifest["date"])
            ?? JSON.string(manifest["dateText"])
            ?? ""
        let id = JSON.string(manifest["id"]) ?? fallbackID

        return IssueInfo(id: id,
                         directory: directory,
                         title: title,
                         subtitle: subtitle,
                         dateText: dateText,
                         date: Models.parseDate(dateText) ?? Models.parseDate(fallbackID),
                         pages: pages)
    }

    // MARK: - Articles

    func articles(for issue: IssueInfo) -> [ArticleInfo] {
        if let cached = articleCache[issue.id] { return cached }

        var result: [ArticleInfo] = []
        let articlesDirectory = issue.directory.appendingPathComponent("articles", isDirectory: true)

        if let names = try? FileManager.default.contentsOfDirectory(atPath: articlesDirectory.path) {
            for name in names.sorted() where name.lowercased().hasSuffix(".json") {
                let url = articlesDirectory.appendingPathComponent(name)
                if let object = JSON.object(at: url),
                   let article = LibraryStore.article(from: object, issue: issue) {
                    result.append(article)
                }
            }
        }

        if let combined = JSON.object(at: issue.directory.appendingPathComponent("articles.json")) {
            for entry in JSON.array(combined["articles"]) {
                if let article = LibraryStore.article(from: JSON.dictionary(entry), issue: issue) {
                    result.append(article)
                }
            }
        }

        result.sort { lhs, rhs in
            if lhs.pageNumber != rhs.pageNumber { return lhs.pageNumber < rhs.pageNumber }
            if lhs.bounds.minY != rhs.bounds.minY { return lhs.bounds.minY < rhs.bounds.minY }
            return lhs.bounds.minX < rhs.bounds.minX
        }

        articleCache[issue.id] = result
        return result
    }

    private static func article(from object: [String: Any], issue: IssueInfo) -> ArticleInfo? {
        guard !object.isEmpty else { return nil }

        let page = JSON.int(object["page"])
            ?? JSON.int(object["pageNumber"])
            ?? 1
        guard page >= 1, page <= issue.pages.count else { return nil }
        guard let bounds = JSON.rect(object["bounds"] ?? object["rect"]) else { return nil }

        let headline = JSON.string(object["headline"])
            ?? JSON.string(object["title"])
            ?? "Untitled"

        var text = JSON.string(object["text"]) ?? ""
        if text.isEmpty, let file = JSON.string(object["textFile"]), !file.isEmpty {
            let url = issue.directory.appendingPathComponent("ocr").appendingPathComponent(file)
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }

        return ArticleInfo(id: JSON.string(object["id"]) ?? headline,
                           pageNumber: page,
                           headline: headline,
                           bounds: bounds,
                           text: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - OCR

    func ocrText(for issue: IssueInfo, page: PageInfo) -> String {
        let key = "\(issue.id)|\(page.number)"
        if let cached = ocrCache[key] { return cached }
        let text = loadOCRText(issue: issue, page: page)
        ocrCache[key] = text
        return text
    }

    private func loadOCRText(issue: IssueInfo, page: PageInfo) -> String {
        let directory = issue.directory.appendingPathComponent("ocr", isDirectory: true)
        let baseName = page.imageURL.deletingPathExtension().lastPathComponent

        let candidates = [
            directory.appendingPathComponent("\(page.number).json"),
            directory.appendingPathComponent(String(format: "%03d.json", page.number)),
            directory.appendingPathComponent("\(baseName).json"),
            directory.appendingPathComponent("\(page.number).txt"),
            directory.appendingPathComponent("\(baseName).txt")
        ]

        for url in candidates {
            if url.pathExtension.lowercased() == "txt" {
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            } else if let object = JSON.object(at: url) {
                if let text = JSON.string(object["text"]), !text.isEmpty {
                    return text
                }
                let lines = JSON.array(object["lines"])
                let joined = lines
                    .compactMap { JSON.string(JSON.dictionary($0)["text"]) }
                    .joined(separator: " ")
                if !joined.isEmpty { return joined }
            }
        }
        return ""
    }

    // MARK: - Search

    func search(_ query: String, limit: Int = 200) -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var hits: [SearchHit] = []
        let allArticles = issues().map { ($0, articles(for: $0)) }

        for (issue, articles) in allArticles {
            for page in issue.pages {
                let text = ocrText(for: issue, page: page)
                guard !text.isEmpty,
                      let range = text.range(of: trimmed, options: .caseInsensitive) else { continue }

                let headline = articles.first(where: {
                    $0.pageNumber == page.number &&
                    $0.text.range(of: trimmed, options: .caseInsensitive) != nil
                })?.headline ?? "Page \(page.number)"

                hits.append(SearchHit(issue: issue,
                                      pageNumber: page.number,
                                      headline: headline,
                                      snippet: LibraryStore.snippet(in: text, around: range, radius: 90)))

                if hits.count >= limit { return hits }
            }
        }
        return hits
    }

    static func snippet(in text: String, around range: Range<String.Index>, radius: Int) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex

        var snippet = String(text[lower..<upper])
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if lower != text.startIndex { snippet = "…" + snippet }
        if upper != text.endIndex { snippet += "…" }
        return snippet
    }
}

/// Decodes and caches page images at a bounded size so large scanned pages do
/// not blow up memory.
final class ImageLoader {

    static let shared = ImageLoader()

    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "news.image-loader", qos: .userInitiated, attributes: .concurrent)

    private init() {
        cache.countLimit = 3
    }

    func cachedImage(for url: URL) -> UIImage? {
        return cache.object(forKey: url.path as NSString)
    }

    func loadImage(for url: URL, maxPixelSize: CGFloat = 3200, completion: @escaping (UIImage?) -> Void) {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }

        queue.async {
            let image = ImageLoader.downsample(url: url, maxPixelSize: maxPixelSize)
            if let image = image {
                self.cache.setObject(image, forKey: key)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    private static func downsample(url: URL, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
