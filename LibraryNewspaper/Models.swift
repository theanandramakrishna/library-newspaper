import Foundation
import CoreGraphics

/// One imported issue (a single publication on a single day).
struct IssueInfo {
    let id: String
    let directory: URL
    let title: String
    let subtitle: String
    let dateText: String
    let date: Date?
    let pages: [PageInfo]

    var pageCount: Int { return pages.count }

    var displayDate: String {
        if !dateText.isEmpty { return dateText }
        guard let date = date else { return "" }
        return IssueInfo.displayFormatter.string(from: date)
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

/// One replica page image.
struct PageInfo {
    let number: Int          // 1-based
    let imageURL: URL
    let width: Int           // pixels, 0 if unknown
    let height: Int          // pixels, 0 if unknown
}

/// A clickable region on a page plus its reading text.
struct ArticleInfo {
    let id: String
    let pageNumber: Int      // 1-based
    let headline: String
    let bounds: CGRect       // page pixel coordinates
    let text: String
}

/// One search result.
struct SearchHit {
    let issue: IssueInfo
    let pageNumber: Int
    let headline: String
    let snippet: String
}

/// Tiny, forgiving JSON helpers. Hand-written parsing keeps the app compatible
/// with iOS 9 and with loosely-authored manifest files.
enum JSON {

    static func object(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return object(from: data)
    }

    static func object(from data: Data) -> [String: Any]? {
        guard let value = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        return value as? [String: Any]
    }

    static func dictionary(_ value: Any?) -> [String: Any] {
        return value as? [String: Any] ?? [:]
    }

    static func array(_ value: Any?) -> [Any] {
        return value as? [Any] ?? []
    }

    static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    static func double(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(number.doubleValue) }
        if let string = value as? String, let number = Double(string) { return CGFloat(number) }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return (string as NSString).boolValue }
        return nil
    }

    /// Accepts {x,y,width,height}, {x,y,w,h}, {left,top,width,height} or [x,y,w,h].
    static func rect(_ value: Any?) -> CGRect? {
        if let array = value as? [Any], array.count == 4,
           let x = double(array[0]), let y = double(array[1]),
           let width = double(array[2]), let height = double(array[3]) {
            return CGRect(x: x, y: y, width: width, height: height)
        }

        let dictionary = self.dictionary(value)
        guard !dictionary.isEmpty else { return nil }

        let x = double(dictionary["x"]) ?? double(dictionary["left"]) ?? 0
        let y = double(dictionary["y"]) ?? double(dictionary["top"]) ?? 0
        guard let width = double(dictionary["width"]) ?? double(dictionary["w"]),
              let height = double(dictionary["height"]) ?? double(dictionary["h"]) else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Shared file-system helpers.
enum Models {

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff"]

    static func imageFiles(in directory: URL) -> [URL] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names
            .filter { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { directory.appendingPathComponent($0) }
    }

    /// Parses yyyy-MM-dd, MM/dd/yyyy, ISO timestamps, or a date embedded in a
    /// folder name such as "seattle-times-2026-10-17".
    static func parseDate(_ text: String) -> Date? {
        if text.isEmpty { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy", "yyyyMMdd", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }

        let regex = try? NSRegularExpression(pattern: "(\\d{4})-(\\d{2})-(\\d{2})", options: [])
        let nsText = text as NSString
        if let match = regex?.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) {
            let year = nsText.substring(with: match.range(at: 1))
            let month = nsText.substring(with: match.range(at: 2))
            let day = nsText.substring(with: match.range(at: 3))
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: "\(year)-\(month)-\(day)")
        }
        return nil
    }
}
