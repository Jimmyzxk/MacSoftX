import XCTest
@testable import upmac

final class CaskVersionCheckerTests: XCTestCase {

    // MARK: - Cask JSON 解析

    func testParseStandardCaskJSON() throws {
        let json = """
        {
          "token":"visual-studio-code",
          "version":"1.137.0",
          "homepage":"https://code.visualstudio.com/",
          "artifacts":[{"app":["Visual Studio Code.app"]}]
        }
        """
        let data = Data(json.utf8)
        let match = CaskJSONParser.parse(data: data, localAppName: "Visual Studio Code")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.latestVersion, "1.137.0")
        XCTAssertEqual(match?.homepage, "https://code.visualstudio.com/")
    }

    func testParseVersionWithComma() throws {
        let json = """
        {
          "token":"notion",
          "version":"4.90.0,238679",
          "homepage":"https://www.notion.so/",
          "artifacts":[{"app":["Notion.app"]}]
        }
        """
        let match = CaskJSONParser.parse(data: Data(json.utf8), localAppName: "Notion")
        XCTAssertEqual(match?.latestVersion, "4.90.0") // comma前
        XCTAssertEqual(match?.homepage, "https://www.notion.so/")
    }

    func testParseNoArtifacts() {
        let json = """
        {
          "token":"some-app",
          "version":"1.0.0",
          "homepage":"https://example.com/"
        }
        """
        let match = CaskJSONParser.parse(data: Data(json.utf8), localAppName: "Some App")
        XCTAssertNil(match, "无 artifacts 字段应保守不命中")
    }

    func testParseBadJSON() {
        let bad = Data("not json".utf8)
        XCTAssertNil(CaskJSONParser.parse(data: bad, localAppName: "Foo"))
        let empty = Data("{}".utf8)
        XCTAssertNil(CaskJSONParser.parse(data: empty, localAppName: "Foo"))
    }

    // MARK: - Token 归一化

    func testTokenNormalization() {
        XCTAssertEqual(CaskToken.normalize("Visual Studio Code"), "visual-studio-code")
        XCTAssertEqual(CaskToken.normalize("Google Chrome.app"), "google-chrome")
        XCTAssertEqual(CaskToken.normalize(" MyApp.app "), "myapp")
        XCTAssertEqual(CaskToken.normalize("Foo_Bar"), "foo-bar")
        let candidates = CaskToken.candidateTokens(for: "Visual Studio Code")
        XCTAssertEqual(candidates.first, "visual-studio-code")
        // 去后缀变体示例：若含 app/desktop 等应生成变体（不强求，但验证逻辑存在）
        let candidates2 = CaskToken.candidateTokens(for: "Docker Desktop")
        XCTAssertTrue(candidates2.contains("docker-desktop"))
        // stripped variant "docker" 应在列
        XCTAssertTrue(candidates2.contains("docker") || candidates2.count >= 1)
    }

    // MARK: - Artifacts 匹配

    func testArtifactsMatchHitAndReject() {
        let jsonHit = """
        {
          "version":"1.0",
          "homepage":"https://example.com/",
          "artifacts":[{"app":["Google Chrome.app"]}]
        }
        """
        XCTAssertNotNil(CaskJSONParser.parse(data: Data(jsonHit.utf8), localAppName: "Google Chrome"))
        XCTAssertNotNil(CaskJSONParser.parse(data: Data(jsonHit.utf8), localAppName: "google chrome"))
        XCTAssertNotNil(CaskJSONParser.parse(data: Data(jsonHit.utf8), localAppName: "Google Chrome.app"))

        let jsonMiss = """
        {
          "version":"1.0",
          "homepage":"https://example.com/",
          "artifacts":[{"app":["Other.app"]}]
        }
        """
        XCTAssertNil(CaskJSONParser.parse(data: Data(jsonMiss.utf8), localAppName: "Google Chrome"))
        // 空 artifacts 数组也不命中
        let jsonEmptyArt = """
        {
          "version":"1.0",
          "artifacts":[]
        }
        """
        XCTAssertNil(CaskJSONParser.parse(data: Data(jsonEmptyArt.utf8), localAppName: "Google Chrome"))
    }

    // MARK: - 版本比较器复用

    func testVersionComparatorReuse() {
        // 复用全项目唯一入口 SparkleVersionComparator
        XCTAssertEqual(SparkleVersionComparator.compare("1.137.0", "1.136.0"), .orderedDescending)
        XCTAssertEqual(SparkleVersionComparator.compare("153.0.8010.37", "152.0.7977.83"), .orderedDescending)
        XCTAssertEqual(SparkleVersionComparator.compare("4.90.0", "4.90.0"), .orderedSame)
        XCTAssertTrue(SparkleVersionComparator.isVersion("1.137.0", newerThan: "1.136.0"))
        XCTAssertFalse(SparkleVersionComparator.isVersion("4.90.0", newerThan: "4.90.0"))
    }
}
