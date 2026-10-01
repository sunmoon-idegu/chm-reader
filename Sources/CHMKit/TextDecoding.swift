import Foundation

public enum TextDecoding {
    public static func encoding(_ cf: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
    }

    public static let cp950 = encoding(.dosChineseTrad)
    public static let big5 = encoding(.big5)
    public static let big5HKSCS = encoding(.big5_HKSCS_1999)
    public static let gb18030 = encoding(.GB_18030_2000)
    public static let shiftJIS = encoding(.dosJapanese)
    public static let korean = encoding(.dosKorean)
    public static let windowsLatin1 = String.Encoding.windowsCP1252

    /// Candidate legacy encodings for a Windows LCID, most likely first.
    public static func encodings(forLCID lcid: UInt32) -> [String.Encoding] {
        switch lcid & 0xFFFF {
        case 0x0404, 0x1404: return [cp950, big5HKSCS, big5]
        case 0x0C04: return [big5HKSCS, cp950, big5]
        case 0x0804, 0x1004: return [gb18030]
        case 0x0411: return [shiftJIS]
        case 0x0412: return [korean]
        default: return [windowsLatin1]
        }
    }

    public static func encoding(ianaName name: String) -> String.Encoding? {
        let lower = name.lowercased()
        if lower == "big5" || lower == "x-x-big5" || lower == "cp950" { return cp950 }
        if lower == "big5-hkscs" { return big5HKSCS }
        if lower == "gb2312" || lower == "gbk" || lower == "x-gbk" { return gb18030 }
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cf != kCFStringEncodingInvalidId else { return nil }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }

    public static func ianaName(_ encoding: String.Encoding) -> String? {
        let cf = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
        return CFStringConvertEncodingToIANACharSetName(cf) as String?
    }

    /// Decodes text from a CHM. Never fails: falls back to a lossy decode.
    public static func decode(_ data: Data, fallbacks: [String.Encoding]) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        if data.starts(with: [0xFF, 0xFE]), let s = String(data: data, encoding: .utf16LittleEndian) {
            return String(s.drop(while: { $0 == "\u{FEFF}" }))
        }
        if data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16BigEndian) {
            return String(s.drop(while: { $0 == "\u{FEFF}" }))
        }

        var candidates: [String.Encoding] = []
        if let declared = declaredCharset(in: data), let enc = encoding(ianaName: declared) {
            candidates.append(enc)
            if enc == cp950 { candidates += [big5HKSCS, big5] }
        }
        candidates.append(.utf8)
        candidates += fallbacks

        for enc in candidates {
            if let s = String(data: data, encoding: enc) { return s }
        }
        let lossyEncoding = candidates.first(where: { $0 != .utf8 }) ?? windowsLatin1
        return lossyDecode(data, encoding: lossyEncoding)
    }

    /// Reads `charset=` from a `<meta>` tag near the start of an HTML document.
    static func declaredCharset(in data: Data) -> String? {
        let head = String(decoding: data.prefix(4096).map { $0 < 0x80 ? $0 : 0x20 }, as: UTF8.self)
        let pattern = #"<meta[^>]+charset\s*=\s*["']?\s*([A-Za-z0-9_\-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
              let range = Range(match.range(at: 1), in: head) else { return nil }
        return String(head[range])
    }

    /// Line-by-line decode; lines that fail are decoded per character with U+FFFD for bad bytes.
    /// Safe for double-byte encodings because 0x0A never appears as a trail byte.
    static func lossyDecode(_ data: Data, encoding: String.Encoding) -> String {
        var out = ""
        for (index, line) in data.split(separator: 0x0A, omittingEmptySubsequences: false).enumerated() {
            if index > 0 { out.append("\n") }
            if let s = String(data: Data(line), encoding: encoding) {
                out += s
                continue
            }
            let bytes = Array(line)
            var i = 0
            while i < bytes.count {
                if bytes[i] < 0x80 {
                    out.unicodeScalars.append(Unicode.Scalar(bytes[i]))
                    i += 1
                } else if i + 1 < bytes.count, let s = String(data: Data(bytes[i...i + 1]), encoding: encoding) {
                    out += s
                    i += 2
                } else if let s = String(data: Data([bytes[i]]), encoding: encoding) {
                    out += s
                    i += 1
                } else {
                    out.append("\u{FFFD}")
                    i += 1
                }
            }
        }
        return out
    }

    /// Rewrites any `<meta ... charset=xxx>` so the document agrees with the UTF-8 we serve.
    public static func forceUTF8MetaCharset(_ html: String) -> String {
        let pattern = #"(<meta[^>]+charset\s*=\s*["']?\s*)[A-Za-z0-9_\-]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return html }
        return regex.stringByReplacingMatches(
            in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "$1utf-8")
    }
}
