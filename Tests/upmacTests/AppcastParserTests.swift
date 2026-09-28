import XCTest
@testable import upmac

final class AppcastParserTests: XCTestCase {

    /// 夹具 1：标准 Appcast（包含多个 item，含 sparkle:version、sparkle:shortVersionString 与 enclosure url）
    func testStandardAppcast() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel>
                <title>Sample App Changelog</title>
                <item>
                    <title>Version 2.0.0</title>
                    <enclosure url="https://example.com/downloads/App-2.0.0.zip"
                               sparkle:version="200"
                               sparkle:shortVersionString="2.0.0"
                               length="12345678"
                               type="application/octet-stream" />
                </item>
                <item>
                    <title>Version 2.1.0</title>
                    <enclosure url="https://example.com/downloads/App-2.1.0.zip"
                               sparkle:version="210"
                               sparkle:shortVersionString="2.1.0"
                               length="12345678"
                               type="application/octet-stream" />
                </item>
                <item>
                    <title>Version 1.9.0</title>
                    <enclosure url="https://example.com/downloads/App-1.9.0.zip"
                               sparkle:version="190"
                               sparkle:shortVersionString="1.9.0"
                               length="12345678"
                               type="application/octet-stream" />
                </item>
            </channel>
        </rss>
        """

        let data = Data(xml.utf8)
        let items = AppcastParser.parse(data)

        XCTAssertEqual(items.count, 3)

        let best = AppcastParser.bestItem(from: items)
        XCTAssertNotNil(best)
        XCTAssertEqual(best?.displayVersion, "2.1.0")
        XCTAssertEqual(best?.version, "210")
        XCTAssertEqual(best?.enclosureURL, "https://example.com/downloads/App-2.1.0.zip")
    }

    /// 夹具 2：缺 shortVersionString（仅有 sparkle:version）
    func testMissingShortVersionString() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel>
                <title>App Changelog</title>
                <item>
                    <title>Release 1.5.4</title>
                    <enclosure url="https://example.com/App-1.5.4.dmg"
                               sparkle:version="1.5.4"
                               type="application/octet-stream" />
                </item>
            </channel>
        </rss>
        """

        let data = Data(xml.utf8)
        let items = AppcastParser.parse(data)

        XCTAssertEqual(items.count, 1)
        let item = items.first
        XCTAssertEqual(item?.version, "1.5.4")
        XCTAssertNil(item?.shortVersionString)
        XCTAssertEqual(item?.displayVersion, "1.5.4")
    }

    /// 夹具 3：坏 XML（畸形未闭合标签）
    func testMalformedXML() {
        let badXML = """
        <rss version="2.0"><channel><item><title>Broken XML<enclosure url="bad"
        """

        let data = Data(badXML.utf8)
        let items = AppcastParser.parse(data)

        // 畸形 XML 宽容返回空列表，不抛崩
        XCTAssertTrue(items.isEmpty)
        XCTAssertNil(AppcastParser.bestItem(from: items))
    }

    /// 夹具 4：无 items 的有效 Feed
    func testEmptyFeedNoItems() {
        let emptyXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0">
            <channel>
                <title>Empty Feed</title>
                <description>No releases yet</description>
            </channel>
        </rss>
        """

        let data = Data(emptyXML.utf8)
        let items = AppcastParser.parse(data)

        XCTAssertTrue(items.isEmpty)
        XCTAssertNil(AppcastParser.bestItem(from: items))
    }
}
