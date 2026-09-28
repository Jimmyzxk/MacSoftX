import XCTest
@testable import upmac

final class InventoryParserTests: XCTestCase {

    // MARK: - 1. brew list --json --versions (新版契约测试)

    func testBrewListParserVersionsFlagFormat() throws {
        // 新版 Homebrew brew list --json --versions 实际输出结构
        let json = """
        {
          "formulae": [
            {
              "name": "git",
              "versions": ["2.44.0"],
              "linked_version": "2.44.0",
              "optlinked_version": null,
              "pinned_version": null
            },
            {
              "name": "node",
              "versions": ["21.6.2", "20.11.0"],
              "linked_version": "21.6.2",
              "optlinked_version": null,
              "pinned_version": null
            }
          ],
          "casks": [
            {
              "token": "docker-desktop",
              "versions": ["4.27.1"],
              "pinned_version": null
            }
          ]
        }
        """

        let result = try BrewListParser.parseDetailed(json)
        XCTAssertEqual(result.formulae.count, 2)
        XCTAssertEqual(result.casks.count, 1)
        XCTAssertEqual(result.all.count, 3)

        // Formula 验证
        XCTAssertEqual(result.formulae[0].name, "git")
        XCTAssertEqual(result.formulae[0].version, "2.44.0")
        XCTAssertEqual(result.formulae[0].kind, .cli)
        XCTAssertEqual(result.formulae[0].sourceId, "brew")
        XCTAssertEqual(result.formulae[0].status, .managed)

        XCTAssertEqual(result.formulae[1].name, "node")
        XCTAssertEqual(result.formulae[1].version, "21.6.2")

        // Cask 验证（无 name 字段，以 token 兜底名称，取 versions 首元素）
        XCTAssertEqual(result.casks[0].id, "brew-cask:docker-desktop")
        XCTAssertEqual(result.casks[0].name, "docker-desktop")
        XCTAssertEqual(result.casks[0].version, "4.27.1")
        XCTAssertEqual(result.casks[0].kind, .app)
        XCTAssertEqual(result.casks[0].sourceId, "brew-cask")
        XCTAssertEqual(result.casks[0].status, .managed)
    }

    func testBrewListParserMixedFormulaeAndCasksLegacyFormat() throws {
        let json = """
        {
          "formulae": [
            {
              "name": "git",
              "installed_versions": ["2.44.0"],
              "version": "2.44.0"
            }
          ],
          "casks": [
            {
              "token": "visual-studio-code",
              "name": ["Visual Studio Code"],
              "version": "1.87.0",
              "installed": "1.87.0"
            }
          ]
        }
        """

        let result = try BrewListParser.parseDetailed(json)
        XCTAssertEqual(result.formulae.count, 1)
        XCTAssertEqual(result.casks.count, 1)
        XCTAssertEqual(result.formulae[0].name, "git")
        XCTAssertEqual(result.formulae[0].version, "2.44.0")
        XCTAssertEqual(result.casks[0].name, "Visual Studio Code")
        XCTAssertEqual(result.casks[0].version, "1.87.0")
    }

    /// 测试真实复杂异常 Homebrew 输出格式（包含畸形单条记录，宽容跳过不崩整包）
    func testBrewListParserCorruptEntryTolerance() throws {
        let json = """
        {
          "formulae": [
            {
              "name": "zstd",
              "versions": ["1.5.5"]
            },
            {
              "name": null,
              "versions": ["invalid"]
            }
          ],
          "casks": [
            {
              "token": "docker-desktop",
              "versions": ["4.27.1"]
            },
            {
              "token": null,
              "versions": ["1.0.0"]
            }
          ]
        }
        """

        let result = try BrewListParser.parseDetailed(json)
        XCTAssertEqual(result.formulae.count, 1)
        XCTAssertEqual(result.formulae[0].name, "zstd")
        XCTAssertEqual(result.formulae[0].version, "1.5.5")

        XCTAssertEqual(result.casks.count, 1)
        XCTAssertEqual(result.casks[0].name, "docker-desktop")
        XCTAssertEqual(result.casks[0].version, "4.27.1")
    }

    func testBrewListParserEmptyAndEdgeCases() throws {
        let emptyJson = "{}"
        let emptyResult = try BrewListParser.parseDetailed(emptyJson)
        XCTAssertTrue(emptyResult.formulae.isEmpty)
        XCTAssertTrue(emptyResult.casks.isEmpty)

        let formulaOnly = """
        {
          "formulae": [
            { "name": "ripgrep", "versions": [] }
          ]
        }
        """
        let fResult = try BrewListParser.parseDetailed(formulaOnly)
        XCTAssertEqual(fResult.formulae.count, 1)
        XCTAssertEqual(fResult.formulae[0].name, "ripgrep")
        XCTAssertEqual(fResult.formulae[0].version, "?")
    }

    func testBrewListParserInvalidJsonThrows() {
        XCTAssertThrowsError(try BrewListParser.parseDetailed(""))
        XCTAssertThrowsError(try BrewListParser.parseDetailed("{ invalid json"))
    }

    // MARK: - 2. npm ls -g --json (至少 2 例)

    func testNpmListParserStandard() throws {
        let json = """
        {
          "dependencies": {
            "corepack": {
              "version": "0.25.2"
            },
            "npm": {
              "version": "10.4.0"
            }
          }
        }
        """

        let items = try NpmListParser.parse(json)
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(items[0].name, "corepack")
        XCTAssertEqual(items[0].version, "0.25.2")
        XCTAssertEqual(items[0].kind, .cli)
        XCTAssertEqual(items[0].sourceId, "npm")
        XCTAssertEqual(items[0].status, .managed)

        XCTAssertEqual(items[1].name, "npm")
        XCTAssertEqual(items[1].version, "10.4.0")
    }

    func testNpmListParserEmptyOrMissingDependencies() throws {
        let emptyDeps = """
        {
          "dependencies": {}
        }
        """
        let items1 = try NpmListParser.parse(emptyDeps)
        XCTAssertTrue(items1.isEmpty)

        let emptyObject = "{}"
        let items2 = try NpmListParser.parse(emptyObject)
        XCTAssertTrue(items2.isEmpty)

        let emptyString = ""
        let items3 = try NpmListParser.parse(emptyString)
        XCTAssertTrue(items3.isEmpty)
    }

    // MARK: - 3. mas list 文本 (至少 2 例)

    func testMasListParserStandard() {
        let text = """
        497799835 Xcode (15.2)
        111111111 Telegram (10.8.1)
        """

        let items = MasListParser.parse(text)
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(items[0].id, "mas:497799835")
        XCTAssertEqual(items[0].name, "Xcode")
        XCTAssertEqual(items[0].version, "15.2")
        XCTAssertEqual(items[0].kind, .app)
        XCTAssertEqual(items[0].sourceId, "mas")
        XCTAssertEqual(items[0].sourceDisplayName, "Mac App Store")
        XCTAssertEqual(items[0].status, .managed)

        XCTAssertEqual(items[1].id, "mas:111111111")
        XCTAssertEqual(items[1].name, "Telegram")
        XCTAssertEqual(items[1].version, "10.8.1")
    }

    func testMasListParserIrregularAndBlankLines() {
        let text = """

        803453922   Slack for Desktop   (4.36.140)

        Invalid non matching row
        409183694 Keynote (13.2)
        """

        let entries = MasListParser.parseEntries(text)
        XCTAssertEqual(entries.count, 2)

        XCTAssertEqual(entries[0].id, "803453922")
        XCTAssertEqual(entries[0].name, "Slack for Desktop")
        XCTAssertEqual(entries[0].version, "4.36.140")

        XCTAssertEqual(entries[1].id, "409183694")
        XCTAssertEqual(entries[1].name, "Keynote")
        XCTAssertEqual(entries[1].version, "13.2")
    }

    // MARK: - 4. pipx / uv / gem / cargo 解析测试

    func testPipxListParser() throws {
        let json = """
        {
          "venvs": {
            "black": {
              "metadata": {
                "main_package": {
                  "package_version": "24.2.0"
                }
              }
            }
          }
        }
        """

        let items = try PipxListParser.parse(json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "black")
        XCTAssertEqual(items[0].version, "24.2.0")
        XCTAssertEqual(items[0].kind, .cli)
        XCTAssertEqual(items[0].sourceId, "pipx")
    }

    func testUvToolListParser() {
        let text = """
        ruff v0.3.0
        - ruff
        black 24.2.0
        - black
        - blackd
        """

        let items = UvToolListParser.parse(text)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "ruff")
        XCTAssertEqual(items[0].version, "0.3.0")
        XCTAssertEqual(items[1].name, "black")
        XCTAssertEqual(items[1].version, "24.2.0")
    }

    func testGemListParser() {
        let text = """
        cocoapods (1.15.2, default: 1.14.3)
        bundler (2.5.6)
        """

        let items = GemListParser.parse(text)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "cocoapods")
        XCTAssertEqual(items[0].version, "1.15.2")
        XCTAssertEqual(items[1].name, "bundler")
        XCTAssertEqual(items[1].version, "2.5.6")
    }

    func testCargoListParser() {
        let text = """
        Package    Installed  Latest  Needs-Update
        ripgrep    v14.1.0    v14.1.0 No
        cargo-tree v0.29.0    v0.29.0 No
        """

        let items = CargoListParser.parse(text)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "ripgrep")
        XCTAssertEqual(items[0].version, "14.1.0")
        XCTAssertEqual(items[1].name, "cargo-tree")
        XCTAssertEqual(items[1].version, "0.29.0")
    }

    func testCargoInstallListFallbackParser() {
        let text = """
        cargo-tree v0.29.0:
            cargo-tree
        ripgrep v14.1.0:
            rg
        """

        let items = CargoListParser.parseInstallList(text)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].name, "cargo-tree")
        XCTAssertEqual(items[0].version, "0.29.0")
        XCTAssertEqual(items[1].name, "ripgrep")
        XCTAssertEqual(items[1].version, "14.1.0")
    }

    // MARK: - 5. InventoryReport 结构与 JSON 序列化

    func testInventoryReportCodableRoundTripWithErrors() throws {
        let item = InventoryItem(
            id: "app:/Applications/Visual Studio Code.app",
            name: "Visual Studio Code",
            version: "1.87.0",
            kind: .app,
            sourceId: "brew-cask",
            sourceDisplayName: "Homebrew Cask",
            status: .managed,
            bundleId: "com.microsoft.VSCode",
            path: "/Applications/Visual Studio Code.app"
        )

        let report = InventoryReport(
            totalCount: 1,
            appCount: 1,
            cliCount: 0,
            orphanCount: 0,
            sourceStats: ["Homebrew Cask": 1],
            items: [item],
            errors: ["cargo": "cargo install --list failed"]
        )

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(InventoryReport.self, from: data)

        XCTAssertEqual(decoded.totalCount, 1)
        XCTAssertEqual(decoded.appCount, 1)
        XCTAssertEqual(decoded.items.first?.name, "Visual Studio Code")
        XCTAssertEqual(decoded.items.first?.status, .managed)
        XCTAssertEqual(decoded.errors["cargo"], "cargo install --list failed")
    }

    func testInventoryReportBackwardsCompatibilityWithoutErrorsField() throws {
        let jsonWithoutErrors = """
        {
          "totalCount": 1,
          "appCount": 1,
          "cliCount": 0,
          "orphanCount": 0,
          "sourceStats": { "App Store": 1 },
          "items": [
            {
              "id": "mas:123",
              "name": "TestApp",
              "version": "1.0.0",
              "kind": "应用",
              "sourceId": "mas",
              "sourceDisplayName": "App Store",
              "status": "受管"
            }
          ],
          "timestamp": "2026-09-13T12:00:00Z"
        }
        """

        let data = jsonWithoutErrors.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(InventoryReport.self, from: data)

        XCTAssertEqual(decoded.totalCount, 1)
        XCTAssertEqual(decoded.errors, [:])
    }

    // MARK: - 6. 名称归一化与 Docker Desktop 匹配算法纯函数测试

    func testAppIconFinderNormalizeName() {
        XCTAssertEqual(AppIconFinder.normalizeName("Visual Studio Code"), "visualstudiocode")
        XCTAssertEqual(AppIconFinder.normalizeName("visual-studio-code"), "visualstudiocode")
        XCTAssertEqual(AppIconFinder.normalizeName("iTerm2.app"), "iterm2app")
        XCTAssertEqual(AppIconFinder.normalizeName("Sublime Text 4"), "sublimetext4")
    }
}
