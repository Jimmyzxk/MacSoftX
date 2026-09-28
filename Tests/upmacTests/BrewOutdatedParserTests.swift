import XCTest
@testable import upmac

final class BrewOutdatedParserTests: XCTestCase {

    // 1. 合法 v2 JSON 带 formulae + casks 混合
    func testParseMixedFormulaeAndCasks() throws {
        let json = """
        {
          "formulae": [
            {
              "name": "node",
              "installed_versions": ["20.11.0"],
              "current_version": "21.6.2",
              "pinned": false,
              "pinned_version": null
            },
            {
              "name": "git",
              "installed_versions": ["2.43.0"],
              "current_version": "2.44.0",
              "pinned": true,
              "pinned_version": "2.43.0"
            }
          ],
          "casks": [
            {
              "name": "visual-studio-code",
              "installed_versions": ["1.86.0"],
              "current_version": "1.87.0"
            }
          ]
        }
        """

        let items = try BrewOutdatedParser.parse(json)
        XCTAssertEqual(items.count, 3)

        // Formula 1
        XCTAssertEqual(items[0].providerId, "brew")
        XCTAssertEqual(items[0].name, "node")
        XCTAssertEqual(items[0].currentVersion, "20.11.0")
        XCTAssertEqual(items[0].latestVersion, "21.6.2")
        XCTAssertEqual(items[0].kind, .formula)
        XCTAssertFalse(items[0].needsSudo)
        XCTAssertFalse(items[0].requiresLogin)

        // Formula 2
        XCTAssertEqual(items[1].name, "git")
        XCTAssertEqual(items[1].currentVersion, "2.43.0")
        XCTAssertEqual(items[1].latestVersion, "2.44.0")
        XCTAssertEqual(items[1].kind, .formula)

        // Cask 1
        XCTAssertEqual(items[2].providerId, "brew")
        XCTAssertEqual(items[2].name, "visual-studio-code")
        XCTAssertEqual(items[2].currentVersion, "1.86.0")
        XCTAssertEqual(items[2].latestVersion, "1.87.0")
        XCTAssertEqual(items[2].kind, .cask)
        XCTAssertFalse(items[2].needsSudo)
        XCTAssertFalse(items[2].requiresLogin)
    }

    // 2. 仅 casks
    func testParseOnlyCasks() throws {
        let json = """
        {
          "formulae": [],
          "casks": [
            {
              "name": "iterm2",
              "installed_versions": ["3.4.19"],
              "current_version": "3.5.0"
            }
          ]
        }
        """

        let items = try BrewOutdatedParser.parse(json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "iterm2")
        XCTAssertEqual(items[0].currentVersion, "3.4.19")
        XCTAssertEqual(items[0].latestVersion, "3.5.0")
        XCTAssertEqual(items[0].kind, .cask)
        XCTAssertEqual(items[0].providerId, "brew")
    }

    // 3. 空结果
    func testParseEmptyResults() throws {
        let emptyV2 = """
        {
          "formulae": [],
          "casks": []
        }
        """
        let items1 = try BrewOutdatedParser.parse(emptyV2)
        XCTAssertEqual(items1, [])

        let emptyObject = "{}"
        let items2 = try BrewOutdatedParser.parse(emptyObject)
        XCTAssertEqual(items2, [])
    }

    // 4. 坏 JSON → parsingFailed
    func testParseBadJsonThrowsParsingFailed() {
        let badJsonList = [
            "not a json string",
            "{ \"formulae\": [",
            "{\"formulae\": null, \"casks\": invalid}",
            ""
        ]

        for badJson in badJsonList {
            XCTAssertThrowsError(try BrewOutdatedParser.parse(badJson)) { error in
                guard case ProviderError.parsingFailed = error else {
                    XCTFail("Expected .parsingFailed, got \(error)")
                    return
                }
            }
        }
    }

    // 5. 容错测试：installed_versions 为空时取 "?"
    func testInstalledVersionsEmptyDefaultsToQuestionMark() throws {
        let json = """
        {
          "formulae": [
            {
              "name": "orphan-formula",
              "installed_versions": [],
              "current_version": "1.0.0"
            }
          ],
          "casks": []
        }
        """
        let items = try BrewOutdatedParser.parse(json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].currentVersion, "?")
        XCTAssertEqual(items[0].latestVersion, "1.0.0")
    }
}
