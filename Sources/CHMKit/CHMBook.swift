import CryptoKit
import Foundation

/// A CHM archive plus its parsed metadata, table of contents and keyword index.
public final class CHMBook: @unchecked Sendable {
    public let file: CHMFile
    public let title: String
    public let lcid: UInt32
    public let encodings: [String.Encoding]
    public let defaultTopic: String
    public let toc: [SitemapEntry]
    public let index: [SitemapEntry]
    /// Stable identity for annotations: survives moving or renaming the file.
    public let key: String

    public var url: URL { file.url }

    public init(url: URL) throws {
        let file = try CHMFile(url: url)
        self.file = file
        self.key = try FileFingerprint.key(for: url)

        let system = SystemInfo(data: file.data(at: "/#SYSTEM") ?? Data())
        lcid = system.lcid ?? 0x0404
        encodings = TextDecoding.encodings(forLCID: lcid)
        let encodings = self.encodings
        func text(_ bytes: Data?) -> String? {
            guard let bytes, !bytes.isEmpty else { return nil }
            let s = TextDecoding.decode(bytes, fallbacks: encodings).trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }

        let paths = file.allPaths()
        func firstPath(withExtension ext: String) -> String? {
            paths.first { $0.lowercased().hasSuffix(ext) && !$0.hasPrefix("/#") && !$0.hasPrefix("/$") }
        }

        let hhcPath = text(system.contentsFile).map { CHMPath.resolve($0, relativeTo: "/") }
            .flatMap { file.data(at: $0) != nil ? $0 : nil } ?? firstPath(withExtension: ".hhc")
        let hhkPath = text(system.indexFile).map { CHMPath.resolve($0, relativeTo: "/") }
            .flatMap { file.data(at: $0) != nil ? $0 : nil } ?? firstPath(withExtension: ".hhk")

        let sitemapTOC = hhcPath.flatMap { p in file.data(at: p).map { SitemapParser.parse(TextDecoding.decode($0, fallbacks: encodings), basePath: p) } } ?? []
        toc = sitemapTOC.isEmpty ? TopicsTable.entries(in: file, decode: { TextDecoding.decode($0, fallbacks: encodings) }) : sitemapTOC
        index = hhkPath.flatMap { p in file.data(at: p).map { SitemapParser.parse(TextDecoding.decode($0, fallbacks: encodings), basePath: p) } } ?? []

        title = text(system.title) ?? url.deletingPathExtension().lastPathComponent

        let firstTOCPage = toc.lazy.flatMap { $0.flattened() }.compactMap { $0.entry.local }.first
        let candidates: [String?] = [
            text(system.defaultTopic).map { CHMPath.resolve($0, relativeTo: "/") },
            "/index.htm", "/index.html", "/default.htm", "/default.html",
            firstTOCPage,
            firstPath(withExtension: ".htm") ?? firstPath(withExtension: ".html"),
        ]
        defaultTopic = candidates.compactMap { $0 }.first { file.data(at: CHMPath.stripFragment($0)) != nil } ?? "/"
    }

    public var preferredEncoding: String.Encoding { encodings.first ?? TextDecoding.cp950 }

    public func decodeText(_ data: Data) -> String {
        TextDecoding.decode(data, fallbacks: encodings)
    }
}

/// Fallback TOC for books compiled without a `.hhc`: the binary topic tables list every page with its title.
/// `#TOPICS` records (16 bytes): tocidx u32, title offset into `#STRINGS` u32, offset into `#URLTBL` u32, flags.
/// `#URLTBL` records (12 bytes): unknown u32, topic index u32, offset into `#URLSTR` u32.
/// `#URLSTR` records: url offset u32, frame offset u32, then the NUL-terminated local path.
enum TopicsTable {
    static func entries(in file: CHMFile, decode: (Data) -> String) -> [SitemapEntry] {
        guard let topics = file.data(at: "/#TOPICS").map([UInt8].init),
              let urlTable = file.data(at: "/#URLTBL").map([UInt8].init),
              let urlStrings = file.data(at: "/#URLSTR").map([UInt8].init) else { return [] }
        let strings = file.data(at: "/#STRINGS").map([UInt8].init) ?? []

        func u32(_ b: [UInt8], _ i: Int) -> Int? {
            guard i >= 0, i + 4 <= b.count else { return nil }
            return Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24
        }
        func cString(_ b: [UInt8], _ i: Int) -> Data? {
            guard i >= 0, i < b.count else { return nil }
            return Data(b[i...].prefix { $0 != 0 })
        }

        var result: [SitemapEntry] = []
        var seen = Set<String>()
        for i in stride(from: 0, to: topics.count - 15, by: 16) {
            guard let urlTableOffset = u32(topics, i + 8),
                  let urlStringOffset = u32(urlTable, urlTableOffset + 8),
                  let localBytes = cString(urlStrings, urlStringOffset + 8), !localBytes.isEmpty else { continue }
            let local = CHMPath.resolve(String(decoding: localBytes, as: UTF8.self), relativeTo: "/")
            let lower = local.lowercased()
            guard lower.hasSuffix(".htm") || lower.hasSuffix(".html"), seen.insert(lower).inserted else { continue }

            var title = ""
            if let titleOffset = u32(topics, i + 4), titleOffset != 0xFFFF_FFFF, let bytes = cString(strings, titleOffset) {
                title = decode(bytes).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if title.isEmpty { title = (local as NSString).lastPathComponent }
            result.append(SitemapEntry(id: result.count + 1, name: title, local: local, children: []))
        }
        return result
    }
}

/// Fields of the `/#SYSTEM` metadata file: a version DWORD then `(code: u16, length: u16, bytes)` records.
struct SystemInfo {
    var contentsFile: Data?
    var indexFile: Data?
    var defaultTopic: Data?
    var title: Data?
    var lcid: UInt32?

    init(data: Data) {
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        var i = 4
        while i + 4 <= bytes.count {
            let code = u16(i), length = u16(i + 2)
            let start = i + 4, end = min(start + length, bytes.count)
            let value = Data(bytes[start..<end]).prefix { $0 != 0 }
            switch code {
            case 0: contentsFile = value
            case 1: indexFile = value
            case 2: defaultTopic = value
            case 3: title = value
            case 4 where end - start >= 4:
                lcid = UInt32(bytes[start]) | UInt32(bytes[start + 1]) << 8
                    | UInt32(bytes[start + 2]) << 16 | UInt32(bytes[start + 3]) << 24
            default: break
            }
            i = start + length
        }
    }
}

/// Stable identity for a book file (size + first 64 KB), so notes survive moving or renaming it.
public enum FileFingerprint {
    public static func key(for url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let head = try handle.read(upToCount: 64 * 1024) ?? Data()
        var hasher = SHA256()
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }
        hasher.update(data: head)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
