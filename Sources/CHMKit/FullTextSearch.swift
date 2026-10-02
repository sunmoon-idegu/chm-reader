import Foundation

/// In-memory full-text search over a book's pages. Built once per book, then queried as the user types.
public struct FullTextIndex: Sendable {
    public struct Page: Sendable {
        public let id: String
        public let title: String
        public let text: String

        public init(id: String, title: String, text: String) {
            self.id = id
            self.title = title
            self.text = text
        }
    }

    public struct Hit: Identifiable, Hashable, Sendable {
        public var id: String { "\(pageID)#\(occurrence)" }
        public let pageID: String
        /// 0-based index of this match among the matches on its page.
        public let occurrence: Int
        /// UTF-16 range of the match in the page text.
        public let range: NSRange
        public let before: String
        public let match: String
        public let after: String
    }

    public struct PageResult: Identifiable, Hashable, Sendable {
        public var id: String { pageID }
        public let pageID: String
        public let title: String
        public let hits: [Hit]
        public let totalHits: Int
    }

    public let pages: [Page]

    public init(pages: [Page]) {
        self.pages = pages
    }

    /// Matches are case-, width- and diacritic-insensitive. At most `hitsPerPage` hits per page carry snippets;
    /// `totalHits` counts them all. Stops collecting pages after `maxPages`.
    public func search(_ query: String, hitsPerPage: Int = 3, maxPages: Int = 200, context: Int = 18) -> [PageResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        var results: [PageResult] = []

        for page in pages {
            let text = page.text as NSString
            var hits: [Hit] = []
            var total = 0
            var searchRange = NSRange(location: 0, length: text.length)
            while true {
                let found = text.range(of: needle, options: options, range: searchRange)
                if found.location == NSNotFound { break }
                if hits.count < hitsPerPage {
                    let beforeStart = max(0, found.location - context)
                    let afterEnd = min(text.length, NSMaxRange(found) + context)
                    hits.append(Hit(
                        pageID: page.id, occurrence: total, range: found,
                        before: Self.oneLine(text.substring(with: NSRange(location: beforeStart, length: found.location - beforeStart))),
                        match: text.substring(with: found),
                        after: Self.oneLine(text.substring(with: NSRange(location: NSMaxRange(found), length: afterEnd - NSMaxRange(found))))))
                }
                total += 1
                let next = NSMaxRange(found)
                searchRange = NSRange(location: next, length: text.length - next)
            }
            if total > 0 {
                results.append(PageResult(pageID: page.id, title: page.title, hits: hits, totalHits: total))
                if results.count >= maxPages { break }
            }
        }
        return results
    }

    private static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

public enum HTMLText {
    /// Visible text of an HTML page, in document order: drops <head>, <script>, <style> and tags, decodes entities.
    /// Whitespace runs collapse to one space. The reader jumps to a hit by its occurrence number on the page,
    /// which stays aligned with the rendered text as long as the query itself has no whitespace.
    public static func plainText(_ html: String) -> String {
        var s = html
        for pattern in [#"(?is)<head\b.*?</head\s*>"#, #"(?is)<script\b.*?</script\s*>"#,
                        #"(?is)<style\b.*?</style\s*>"#, #"(?s)<!--.*?-->"#] {
            s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>|</(p|div|li|tr|h[1-6]|td|th|blockquote|pre)\s*>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        s = HTMLEntities.decode(s)
        return s.replacingOccurrences(of: "[ \\t\\r\\f\\u00A0]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s*\\n\\s*", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension CHMBook {
    /// Every HTML page in the archive with its visible text, in table-of-contents order, then the rest by path.
    public func searchablePages() -> [FullTextIndex.Page] {
        let htmlPaths = file.allPaths().filter { path in
            let lower = path.lowercased()
            return (lower.hasSuffix(".htm") || lower.hasSuffix(".html")) && !path.hasPrefix("/#") && !path.hasPrefix("/$")
        }
        var titles: [String: String] = [:]
        var order: [String] = []
        for row in toc.flatMap({ $0.flattened() }) {
            guard let local = row.entry.local else { continue }
            let key = CHMPath.stripFragment(local).lowercased()
            if titles[key] == nil {
                titles[key] = row.entry.name
                order.append(key)
            }
        }
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = htmlPaths.sorted { a, b in
            let ra = rank[a.lowercased()] ?? Int.max, rb = rank[b.lowercased()] ?? Int.max
            return ra != rb ? ra < rb : a < b
        }
        return sorted.compactMap { path in
            guard let data = file.data(at: path) else { return nil }
            let html = decodeText(data)
            let title = titles[path.lowercased()] ?? Self.htmlTitle(html) ?? (path as NSString).lastPathComponent
            return FullTextIndex.Page(id: path, title: title, text: HTMLText.plainText(html))
        }
    }

    static func htmlTitle(_ html: String) -> String? {
        guard let range = html.range(of: #"(?is)<title[^>]*>(.*?)</title>"#, options: .regularExpression) else { return nil }
        let title = HTMLText.plainText(String(html[range]))
        return title.isEmpty ? nil : title
    }
}
