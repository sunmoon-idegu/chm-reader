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

final class FullTextSearchTests: XCTestCase {
    func testPlainTextDropsHeadScriptsAndTags() {
        let html = """
            <html><head><title>標題</title><style>p{}</style></head>
            <body><script>var x = "阿賴耶識";</script><p>第一段 &amp; <b>阿賴耶識</b></p><p>第二段</p></body></html>
            """
        XCTAssertEqual(HTMLText.plainText(html), "第一段 & 阿賴耶識\n第二段")
    }

    func testSearchFindsAllOccurrencesWithSnippets() {
        let index = FullTextIndex(pages: [
            .init(id: "/a.htm", title: "A", text: "前言。阿賴耶識是第八識，阿賴耶識又名藏識。"),
            .init(id: "/b.htm", title: "B", text: "沒有這個詞"),
            .init(id: "/c.htm", title: "C", text: "Alaya and ALAYA"),
        ])
        let results = index.search("阿賴耶識", hitsPerPage: 1)
        XCTAssertEqual(results.map(\.pageID), ["/a.htm"])
        XCTAssertEqual(results[0].totalHits, 2)
        XCTAssertEqual(results[0].hits.count, 1)
        XCTAssertEqual(results[0].hits[0].match, "阿賴耶識")
        XCTAssertEqual(results[0].hits[0].before, "前言。")

        let latin = index.search("alaya")
        XCTAssertEqual(latin.first?.totalHits, 2, "case-insensitive")
        XCTAssertEqual(latin.first?.hits.map(\.occurrence), [0, 1])
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(FullTextIndex(pages: [.init(id: "/a", title: "A", text: "abc")]).search("  ").isEmpty)
    }
}

final class RealBookSearchTests: XCTestCase {
    func testSearchRealBook() throws {
        guard let path = ProcessInfo.processInfo.environment["CHM_TEST_FILE"] else {
            throw XCTSkip("Set CHM_TEST_FILE to run")
        }
        let book = try CHMBook(url: URL(fileURLWithPath: path))
        let start = Date()
        let index = FullTextIndex(pages: book.searchablePages())
        let built = Date().timeIntervalSince(start)
        let results = index.search("阿賴耶識")
        let searched = Date().timeIntervalSince(start) - built
        print("pages=\(index.pages.count) chars=\(index.pages.map(\.text.count).reduce(0, +)) index=\(String(format: "%.2f", built))s search=\(String(format: "%.3f", searched))s")
        print("pages with 阿賴耶識:", results.count, "total hits:", results.map(\.totalHits).reduce(0, +))
        if let first = results.first, let hit = first.hits.first {
            print("first:", first.title, "→", hit.before + "【" + hit.match + "】" + hit.after)
        }
        XCTAssertFalse(results.isEmpty)
    }
}
