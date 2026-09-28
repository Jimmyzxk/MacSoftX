import XCTest
@testable import upmac

final class UvOutdatedParserTests: XCTestCase {

    // 1. 标准 uv tool list 树状输出过滤子命令行 (fixture 1)
    func testParseStandardUvToolList() {
        let text = """
        ruff v0.4.8
        - ruff
        black v24.4.2
        - black
        - blackd
        mypy v1.10.0
        - mypy
        - stubgen
        """

        let items = UvOutdatedParser.parse(text)
        XCTAssertEqual(items.count, 3)

        // 默认按名称升序：black, mypy, ruff
        XCTAssertEqual(items[0].name, "black")
        XCTAssertEqual(items[0].providerId, "uv")
        XCTAssertEqual(items[0].currentVersion, "24.4.2")
        XCTAssertNil(items[0].latestVersion)
        XCTAssertEqual(items[0].kind, .cli)

        XCTAssertEqual(items[1].name, "mypy")
        XCTAssertEqual(items[1].currentVersion, "1.10.0")

        XCTAssertEqual(items[2].name, "ruff")
        XCTAssertEqual(items[2].currentVersion, "0.4.8")
    }

    // 2. 带 latest 版本标注输出 (fixture 2)
    func testParseUvToolListWithLatestAnnotation() {
        let text = """
        pytest v8.2.0 (latest: v8.2.2)
        - pytest
        ruff v0.4.8 (latest: 0.5.1)
        - ruff
        """

        let items = UvOutdatedParser.parse(text)
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(items[0].name, "pytest")
        XCTAssertEqual(items[0].currentVersion, "8.2.0")
        XCTAssertEqual(items[0].latestVersion, "8.2.2")

        XCTAssertEqual(items[1].name, "ruff")
        XCTAssertEqual(items[1].currentVersion, "0.4.8")
        XCTAssertEqual(items[1].latestVersion, "0.5.1")
    }

    // 3. 空白与纯子行容错 (fixture 3)
    func testParseEmptyUvToolList() {
        let text = """
        
        - standalone-subcommand
          
        """
        let items = UvOutdatedParser.parse(text)
        XCTAssertEqual(items, [])
    }
}
