import XCTest
@testable import upmac

final class GemDetailsParserTests: XCTestCase {

    // 1. 标准多 gem 块解析：含 Installed at (default): 与 Installed at:
    func testParseStandardMultiGemDetails() {
        let text = """
        *** LOCAL GEMS ***

        bigdecimal (1.4.1)
            Authors: Kenta Murata
            Homepage: https://github.com/ruby/bigdecimal
            License: ruby
            Installed at (default): /Library/Ruby/Gems/2.6.0

            Arbitrary-precision decimal

        CFPropertyList (2.3.6)
            Author: Christian Kruse
            Homepage: http://github.com/ckruse/CFPropertyList
            License: MIT
            Installed at: /System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/lib/ruby/gems/2.6.0

            Read property lists

        cocoapods (1.15.2)
            Authors: Test
            Installed at: /Users/testuser/.gem/ruby/2.6.0

            CocoaPods

        rake (12.3.3)
            Authors: Hiroshi SHIBATA
            License: MIT
            Installed at: /Library/Ruby/Gems/2.6.0

            Rake
        """
        let map = GemDetailsParser.parse(text)
        XCTAssertEqual(map.count, 4)
        XCTAssertEqual(map["bigdecimal"], "/Library/Ruby/Gems/2.6.0")
        XCTAssertEqual(map["CFPropertyList"], "/System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/lib/ruby/gems/2.6.0")
        XCTAssertEqual(map["cocoapods"], "/Users/testuser/.gem/ruby/2.6.0")
        XCTAssertEqual(map["rake"], "/Library/Ruby/Gems/2.6.0")
        // 保守：系统路径应可被 GemProvider 过滤
        XCTAssertTrue(map["bigdecimal"]!.hasPrefix("/Library/Ruby/"))
        XCTAssertTrue(map["CFPropertyList"]!.hasPrefix("/System/Library/"))
        XCTAssertFalse(map["cocoapods"]!.hasPrefix("/Library/Ruby/"))
    }

    // 2. 无 Installed at 行：该 gem 不入表，保守保留
    func testParseWithoutInstalledAtLine() {
        let text = """
        bundler (2.4.10, default: 2.3.26)
            Authors: Someone
            Homepage: http://bundler.io
            License: MIT

            The best way to manage

        rake (13.0.6)
            Authors: Test
            Installed at: /Users/testuser/.gem/ruby/3.0.0

            Rake
        """
        let map = GemDetailsParser.parse(text)
        XCTAssertEqual(map.count, 1)
        XCTAssertNil(map["bundler"])
        XCTAssertEqual(map["rake"], "/Users/testuser/.gem/ruby/3.0.0")
    }

    // 3. 空输出
    func testParseEmptyOutput() {
        XCTAssertEqual(GemDetailsParser.parse(""), [:])
        XCTAssertEqual(GemDetailsParser.parse("   \n\n  "), [:])
        XCTAssertEqual(GemDetailsParser.parse("*** LOCAL GEMS ***\n\n"), [:])
    }

    // 4. 混合系统与用户路径（/opt/homebrew/、~/.gem/ 与 /Library/Ruby/ 混排）
    func testParseMixedSystemAndUserPaths() {
        let text = """
        bigdecimal (1.4.1)
            Installed at (default): /Library/Ruby/Gems/2.6.0

        psych (5.0.1, 4.0.4)
            Installed at (default): /Library/Ruby/Gems/2.6.0

        cocoapods (1.15.2)
            Installed at: /Users/testuser/.gem/ruby/2.6.0

        fastlane (2.221.1)
            Installed at: /opt/homebrew/lib/ruby/gems/3.1.0

        nokogiri (1.13.8)
            Installed at: /System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/lib/ruby/gems/2.6.0

        mygem (0.1.0)
            Installed at: /Users/testuser/.gem/ruby/2.6.0
        """
        let map = GemDetailsParser.parse(text)
        XCTAssertEqual(map.count, 6)
        XCTAssertEqual(map["bigdecimal"], "/Library/Ruby/Gems/2.6.0")
        XCTAssertEqual(map["psych"], "/Library/Ruby/Gems/2.6.0")
        XCTAssertEqual(map["cocoapods"], "/Users/testuser/.gem/ruby/2.6.0")
        XCTAssertEqual(map["fastlane"], "/opt/homebrew/lib/ruby/gems/3.1.0")
        XCTAssertEqual(map["nokogiri"], "/System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/lib/ruby/gems/2.6.0")
        XCTAssertEqual(map["mygem"], "/Users/testuser/.gem/ruby/2.6.0")

        // 模拟 GemProvider 过滤规则
        let systemPrefixFiltered = map.filter { $0.value.hasPrefix("/Library/Ruby/") || $0.value.hasPrefix("/System/Library/") }
        XCTAssertEqual(Set(systemPrefixFiltered.keys), ["bigdecimal", "psych", "nokogiri"])
        let userKept = map.filter { !$0.value.hasPrefix("/Library/Ruby/") && !$0.value.hasPrefix("/System/Library/") }
        XCTAssertEqual(Set(userKept.keys), ["cocoapods", "fastlane", "mygem"])
    }
}
