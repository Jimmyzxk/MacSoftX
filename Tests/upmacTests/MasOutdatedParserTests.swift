import XCTest
@testable import upmac

final class MasOutdatedParserTests: XCTestCase {

    // 1. mas 三行标准格式 + 一行缺右括号的宽容处理
    func testParseStandardLinesAndMissingRightParen() {
        let fixture = """
        497799835 Xcode (15.2) (15.3)
        111111111 Telegram (10.8.1) (10.9.0)
        222222222 Slack (4.36.138) (4.36.140)
        333333333 Bitwarden (2024.1.0) (2024.2.0
        """

        let items = MasOutdatedParser.parse(fixture)
        XCTAssertEqual(items.count, 4)

        // Line 1: 标准行 1
        XCTAssertEqual(items[0].providerId, "mas")
        XCTAssertEqual(items[0].name, "Xcode")
        XCTAssertEqual(items[0].currentVersion, "15.2")
        XCTAssertEqual(items[0].latestVersion, "15.3")
        XCTAssertEqual(items[0].kind, .mas)
        XCTAssertEqual(items[0].externalId, "497799835")
        XCTAssertFalse(items[0].needsSudo)
        XCTAssertFalse(items[0].requiresLogin)

        // Line 2: 标准行 2
        XCTAssertEqual(items[1].name, "Telegram")
        XCTAssertEqual(items[1].currentVersion, "10.8.1")
        XCTAssertEqual(items[1].latestVersion, "10.9.0")
        XCTAssertEqual(items[1].externalId, "111111111")

        // Line 3: 标准行 3
        XCTAssertEqual(items[2].name, "Slack")
        XCTAssertEqual(items[2].currentVersion, "4.36.138")
        XCTAssertEqual(items[2].latestVersion, "4.36.140")
        XCTAssertEqual(items[2].externalId, "222222222")

        // Line 4: 缺右括号宽容处理行
        XCTAssertEqual(items[3].name, "Bitwarden")
        XCTAssertEqual(items[3].currentVersion, "2024.1.0")
        XCTAssertEqual(items[3].latestVersion, "2024.2.0")
        XCTAssertEqual(items[3].externalId, "333333333")
    }

    // 2. 空输出
    func testParseEmptyOutput() {
        XCTAssertEqual(MasOutdatedParser.parse(""), [])
        XCTAssertEqual(MasOutdatedParser.parse("   \n\n\t  \n"), [])
    }

    // 3. requiresLogin 标记传递
    func testRequiresLoginFlagPropagates() {
        let fixture = "497799835 Xcode (15.2) (15.3)\n"
        let items = MasOutdatedParser.parse(fixture, requiresLogin: true)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].requiresLogin)
        XCTAssertEqual(items[0].name, "Xcode")
    }

    // 4. 脏数据与异常格式行宽容忽略
    func testCorruptedLinesIgnoredSafely() {
        let fixture = """
        Warning: update check failed for something
        497799835 Xcode (15.2) (15.3)
        Random garbage line without versions
        111111111 Telegram (10.8.1) (10.9.0)
        """

        let items = MasOutdatedParser.parse(fixture)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "Xcode")
        XCTAssertEqual(items[1].name, "Telegram")
    }
}
