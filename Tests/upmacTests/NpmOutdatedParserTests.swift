import XCTest
@testable import upmac

final class NpmOutdatedParserTests: XCTestCase {

    // 1. 标准多包 JSON 解析 (fixture 1)
    func testParseStandardOutdatedJson() throws {
        let json = """
        {
          "typescript": {
            "current": "5.3.3",
            "wanted": "5.4.5",
            "latest": "5.4.5",
            "location": "/usr/local/lib/node_modules/typescript"
          },
          "eslint": {
            "current": "8.56.0",
            "wanted": "8.57.0",
            "latest": "9.2.0",
            "location": "/usr/local/lib/node_modules/eslint"
          }
        }
        """

        let items = try NpmOutdatedParser.parse(json)
        XCTAssertEqual(items.count, 2)

        // 默认按名称排序：eslint, typescript
        XCTAssertEqual(items[0].name, "eslint")
        XCTAssertEqual(items[0].providerId, "npm")
        XCTAssertEqual(items[0].currentVersion, "8.56.0")
        XCTAssertEqual(items[0].latestVersion, "9.2.0")
        XCTAssertEqual(items[0].kind, .cli)

        XCTAssertEqual(items[1].name, "typescript")
        XCTAssertEqual(items[1].providerId, "npm")
        XCTAssertEqual(items[1].currentVersion, "5.3.3")
        XCTAssertEqual(items[1].latestVersion, "5.4.5")
    }

    // 2. 边界情况与缺字段兼容 (fixture 2)
    func testParseFallbackFieldsJson() throws {
        let json = """
        {
          "pnpm": {
            "wanted": "9.1.0",
            "latest": "9.1.0"
          },
          "wrangler": {
            "current": "3.50.0",
            "wanted": "3.55.0"
          }
        }
        """

        let items = try NpmOutdatedParser.parse(json)
        XCTAssertEqual(items.count, 2)

        // pnpm: current 缺失 fallback 到 "?"
        XCTAssertEqual(items[0].name, "pnpm")
        XCTAssertEqual(items[0].currentVersion, "?")
        XCTAssertEqual(items[0].latestVersion, "9.1.0")

        // wrangler: latest 缺失 fallback 到 wanted
        XCTAssertEqual(items[1].name, "wrangler")
        XCTAssertEqual(items[1].currentVersion, "3.50.0")
        XCTAssertEqual(items[1].latestVersion, "3.55.0")
    }

    // 3. 空结果与空白字符 (fixture 3)
    func testParseEmptyOutdatedJson() throws {
        let empty1 = try NpmOutdatedParser.parse("{}")
        XCTAssertEqual(empty1, [])

        let empty2 = try NpmOutdatedParser.parse("[]")
        XCTAssertEqual(empty2, [])

        let empty3 = try NpmOutdatedParser.parse("   \n\t  ")
        XCTAssertEqual(empty3, [])
    }
}
