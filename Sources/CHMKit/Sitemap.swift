import Foundation

public struct SitemapEntry: Identifiable, Hashable, Sendable {
    public let id: Int
    public var name: String
    /// Absolute archive path, possibly with a `#fragment`. Nil for pure folder nodes.
    public var local: String?
    public var children: [SitemapEntry]

    public var childrenOrNil: [SitemapEntry]? { children.isEmpty ? nil : children }

    /// Depth-first flattening with depth, for list-style display.
    public func flattened(depth: Int = 0) -> [(entry: SitemapEntry, depth: Int)] {
        [(self, depth)] + children.flatMap { $0.flattened(depth: depth + 1) }
    }
}

/// Parses `.hhc` (table of contents) and `.hhk` (keyword index) sitemap files.
/// They are loose HTML: nested `<UL>` lists of `<OBJECT type="text/sitemap">` with `<param>` children.
public enum SitemapParser {
    public static func parse(_ html: String, basePath: String = "/") -> [SitemapEntry] {
        final class Node {
            var name = ""
            var local: String?
            var children: [Node] = []
        }

        let root = Node()
        // One container per open <UL>; a <UL> nests under the last entry of the enclosing list.
        var stack: [Node] = []
        var current: Node?

        let tagPattern = #"<\s*(/?)\s*(ul|object|param)\b([^>]*)>"#
        let regex = try! NSRegularExpression(pattern: tagPattern, options: .caseInsensitive)
        let ns = html as NSString

        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let closing = ns.substring(with: match.range(at: 1)) == "/"
            let tag = ns.substring(with: match.range(at: 2)).lowercased()
            let attrs = attributes(ns.substring(with: match.range(at: 3)))

            switch (tag, closing) {
            case ("ul", false):
                if let top = stack.last {
                    stack.append(top.children.last ?? top)
                } else {
                    stack.append(root)
                }
            case ("ul", true):
                _ = stack.popLast()
            case ("object", false):
                current = (attrs["type"]?.lowercased().contains("sitemap") ?? false) ? Node() : nil
            case ("object", true):
                if let node = current, !node.name.isEmpty || node.local != nil {
                    (stack.last ?? root).children.append(node)
                }
                current = nil
            case ("param", false):
                guard let node = current, let key = attrs["name"]?.lowercased(), let value = attrs["value"] else { break }
                if key == "name", node.name.isEmpty {
                    node.name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if key == "local", node.local == nil {
                    node.local = CHMPath.resolve(value, relativeTo: basePath)
                }
            default:
                break
            }
        }

        var nextID = 0
        func freeze(_ node: Node) -> SitemapEntry {
            nextID += 1
            let id = nextID
            return SitemapEntry(id: id, name: node.name, local: node.local, children: node.children.map(freeze))
        }
        return root.children.map(freeze)
    }

    static func attributes(_ text: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][\w:.-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        var result: [String: String] = [:]
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: m.range(at: 1)).lowercased()
            var value = ""
            for group in 2...4 where m.range(at: group).location != NSNotFound {
                value = ns.substring(with: m.range(at: group))
                break
            }
            result[key] = HTMLEntities.decode(value)
        }
        return result
    }
}

enum HTMLEntities {
    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let regex = try! NSRegularExpression(pattern: #"&(#x[0-9A-Fa-f]+|#[0-9]+|[A-Za-z]+);"#)
        let ns = s as NSString
        var out = ""
        var last = 0
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let body = ns.substring(with: m.range(at: 1))
            var replacement: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                replacement = UInt32(body.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
            } else if body.hasPrefix("#") {
                replacement = UInt32(body.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
            } else {
                replacement = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"][body.lowercased()]
            }
            out += replacement ?? ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}

public enum CHMPath {
    /// Turns a sitemap/link value into an absolute archive path (keeping any `#fragment`).
    /// Handles `ms-its:book.chm::/page.htm` and `mk:@MSITStore:book.chm::/page.htm` forms.
    public static func resolve(_ raw: String, relativeTo base: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\", with: "/")
        if let range = value.range(of: "::") {
            value = String(value[range.upperBound...])
        } else if value.range(of: "^[A-Za-z][A-Za-z0-9+.-]+:", options: .regularExpression) != nil {
            return value
        }
        if value.hasPrefix("/") { return normalize(value) }
        let dir = base.hasSuffix("/") ? base : (base as NSString).deletingLastPathComponent + "/"
        return normalize((dir.hasPrefix("/") ? dir : "/" + dir) + value)
    }

    /// Collapses `.` and `..` segments; keeps the fragment untouched.
    public static func normalize(_ path: String) -> String {
        let parts = path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        var stack: [Substring] = []
        for seg in parts[0].split(separator: "/") {
            if seg == "." { continue }
            if seg == ".." { _ = stack.popLast(); continue }
            stack.append(seg)
        }
        var result = "/" + stack.joined(separator: "/")
        if parts.count > 1 { result += "#" + parts[1] }
        return result
    }

    public static func stripFragment(_ path: String) -> String {
        path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
    }

    public static func fragment(_ path: String) -> String? {
        let parts = path.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
    }
}
