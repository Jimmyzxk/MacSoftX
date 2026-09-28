import XCTest
@testable import upmac

final class GemOutdatedParserTests: XCTestCase {

    // 1. 标准 gem outdated 输出 (fixture 1)
    func testParseStandardGemOutdated() {
        let text = """
        cocoapods (1.14.3 < 1.15.2)
        fastlane (2.220.0 < 2.221.1)
        bundler (2.5.6 < 2.5.11)
        """

        let items = GemOutdatedParser.parse(text)
        XCTAssertEqual(items.count, 3)

        // 默认按名称升序：bundler, cocoapods, fastlane
        XCTAssertEqual(items[0].name, "bundler")
        XCTAssertEqual(items[0].providerId, "gem")
        XCTAssertEqual(items[0].currentVersion, "2.5.6")
        XCTAssertEqual(items[0].latestVersion, "2.5.11")
        XCTAssertEqual(items[0].kind, .cli)

        XCTAssertEqual(items[1].name, "cocoapods")
        XCTAssertEqual(items[1].providerId, "gem")
        XCTAssertEqual(items[1].currentVersion, "1.14.3")
        XCTAssertEqual(items[1].latestVersion, "1.15.2")

        XCTAssertEqual(items[2].name, "fastlane")
        XCTAssertEqual(items[2].providerId, "gem")
        XCTAssertEqual(items[2].currentVersion, "2.220.0")
        XCTAssertEqual(items[2].latestVersion, "2.221.1")
    }

    // 2. 多版本已安装与带平台后缀输出 (fixture 2)
    func testParseMultiVersionAndPlatformGemOutdated() {
        let text = """
        rake (13.0.6, 13.1.0 < 13.2.1)
        ffi (1.16.3 arm64-darwin < 1.17.0)
        """

        let items = GemOutdatedParser.parse(text)
        XCTAssertEqual(items.count, 2)

        // ffi: arm64-darwin 架构后缀应被剥离，保留版本 1.16.3
        XCTAssertEqual(items[0].name, "ffi")
        XCTAssertEqual(items[0].currentVersion, "1.16.3")
        XCTAssertEqual(items[0].latestVersion, "1.17.0")

        // rake: 多版本列表取最新已安装版本 13.1.0
        XCTAssertEqual(items[1].name, "rake")
        XCTAssertEqual(items[1].currentVersion, "13.1.0")
        XCTAssertEqual(items[1].latestVersion, "13.2.1")
    }

    // 3. 空白与无关行过滤 (fixture 3)
    func testParseEmptyOrIrrelevantText() {
        let text = """
        
        Updating local specs cache...
        # some comment
        
        """
        let items = GemOutdatedParser.parse(text)
        XCTAssertEqual(items, [])
    }

    // 4. GemDefaultParser 系统自带默认 gem 解析测试 (fixture 1)
    func testParseGemDefaultPackages() {
        let text = """
        *** LOCAL GEMS ***

        bigdecimal (default: 3.1.3)
        bundler (2.4.10, default: 2.3.26)
        cocoapods (1.15.2)
        drb (default: 2.1.1)
        fastlane (2.221.1)
        json (2.6.3, default: 2.6.2)
        rdoc (default: 6.5.0)
        """
        let defaultGems = GemDefaultParser.parse(text)
        XCTAssertEqual(defaultGems, ["bigdecimal", "bundler", "drb", "json", "rdoc"])
        XCTAssertFalse(defaultGems.contains("cocoapods"))
        XCTAssertFalse(defaultGems.contains("fastlane"))
    }

    // 5. GemDefaultParser 多版本及平台后缀解析 (fixture 2)
    func testParseGemDefaultWithPlatformsAndNoise() {
        let text = """
        io-console (default: 0.6.0 arm64-darwin)
        psych (default: 5.0.1, 4.0.4)
        rake (13.0.6)
        stringio (default: 3.0.4 universal-darwin23)
        """
        let defaultGems = GemDefaultParser.parse(text)
        XCTAssertTrue(defaultGems.contains("io-console"))
        XCTAssertTrue(defaultGems.contains("psych"))
        XCTAssertTrue(defaultGems.contains("stringio"))
        XCTAssertFalse(defaultGems.contains("rake"))
    }
}
