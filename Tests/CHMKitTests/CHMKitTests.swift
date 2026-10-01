import Foundation
import XCTest

@testable import CHMKit

final class SitemapParserTests: XCTestCase {
    func testNestedTOC() {
        let hhc = """
            <HTML><BODY>
            <OBJECT type="text/site properties"><param name="ImageType" value="Folder"></OBJECT>
            <UL>
              <LI> <OBJECT type="text/sitemap">
                <param name="Name" value="卷一">
                <param name="Local" value="html/v1.htm">
              </OBJECT>
              <UL>
                <LI> <OBJECT type="text/sitemap">
                  <param name="Name" value="本地分">
                  <param name="Local" value="html/v1.htm#a1">
                </OBJECT>
              </UL>
              <LI> <OBJECT type="text/sitemap">
                <param name="Name" value="卷二 &amp; 附錄">
                <param name="Local" value="ms-its:book.chm::/html/v2.htm">
              </OBJECT>
            </UL>
            </BODY></HTML>
            """
        let toc = SitemapParser.parse(hhc, basePath: "/book.hhc")
        XCTAssertEqual(toc.map(\.name), ["卷一", "卷二 & 附錄"])
        XCTAssertEqual(toc[0].local, "/html/v1.htm")
        XCTAssertEqual(toc[0].children.map(\.name), ["本地分"])
        XCTAssertEqual(toc[0].children[0].local, "/html/v1.htm#a1")
        XCTAssertEqual(toc[1].local, "/html/v2.htm")
        XCTAssertTrue(toc[1].children.isEmpty)
    }

    func testRelativePathsResolveAgainstSitemapDirectory() {
        XCTAssertEqual(CHMPath.resolve("../img/a.gif", relativeTo: "/html/toc.hhc"), "/img/a.gif")
        XCTAssertEqual(CHMPath.resolve("./a.htm", relativeTo: "/"), "/a.htm")
        XCTAssertEqual(CHMPath.resolve("http://example.com/", relativeTo: "/"), "http://example.com/")
    }
}

final class TextDecodingTests: XCTestCase {
    func testBig5FallbackFromLCID() {
        let text = "瑜伽師地論 繁體中文"
        let big5 = text.data(using: TextDecoding.cp950)!
        XCTAssertEqual(TextDecoding.decode(big5, fallbacks: TextDecoding.encodings(forLCID: 0x0404)), text)
    }

    func testMetaCharsetWinsOverFallback() {
        let html = "<html><head><meta http-equiv=\"Content-Type\" content=\"text/html; charset=big5\"></head><body>經</body></html>"
        let data = html.data(using: TextDecoding.cp950)!
        XCTAssertEqual(TextDecoding.decode(data, fallbacks: [.windowsCP1252]), html)
    }

    func testLossyDecodeKeepsGoodCharacters() {
        var data = "好".data(using: TextDecoding.cp950)!
        data.append(contentsOf: [0xFF, 0xFF])
        data.append("\n書".data(using: TextDecoding.cp950)!)
        let s = TextDecoding.decode(data, fallbacks: [TextDecoding.cp950])
        XCTAssertTrue(s.hasPrefix("好"))
        XCTAssertTrue(s.hasSuffix("\n書"))
    }

    func testForceUTF8Meta() {
        let html = #"<meta http-equiv="Content-Type" content="text/html; charset=big5">"#
        XCTAssertEqual(TextDecoding.forceUTF8MetaCharset(html), #"<meta http-equiv="Content-Type" content="text/html; charset=utf-8">"#)
    }
}

/// Runs only when `CHM_TEST_FILE` points to a real .chm file.
final class RealBookTests: XCTestCase {
    func testOpenRealBook() throws {
        guard let path = ProcessInfo.processInfo.environment["CHM_TEST_FILE"] else {
            throw XCTSkip("Set CHM_TEST_FILE to run")
        }
        let book = try CHMBook(url: URL(fileURLWithPath: path))
        print("title:", book.title, "lcid:", String(book.lcid, radix: 16), "default:", book.defaultTopic)
        print("toc top-level:", book.toc.prefix(5).map(\.name), "count:", book.toc.count, "index:", book.index.count)
        XCTAssertFalse(book.toc.isEmpty)
        let page = try XCTUnwrap(book.file.data(at: CHMPath.stripFragment(book.defaultTopic)))
        let html = book.decodeText(page)
        print("default page sample:", html.prefix(300))
        XCTAssertFalse(html.contains("\u{FFFD}"))
    }
}
