import XCTest
@testable import upmac

final class CaskDirectUpdateTests: XCTestCase {

    // MARK: - CaskMatch / UpdateItem 新增字段 Codable 往返

    func testUpdateItemCodableWithCaskTokenAndInfoURL() throws {
        let original = UpdateItem(
            providerId: "apps",
            name: "Antigravity",
            currentVersion: "2.12.2",
            latestVersion: "2.13.0",
            kind: .app,
            externalId: "/Applications/Antigravity.app",
            infoURL: "https://antigravity.google/product/antigravity-2",
            caskToken: "antigravity"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UpdateItem.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.caskToken, "antigravity")
        XCTAssertEqual(decoded.infoURL, "https://antigravity.google/product/antigravity-2")
    }

    func testUpdateItemCodableBackwardCompatibilityWithoutNewFields() throws {
        let json = """
        {"providerId":"apps","name":"Foo","currentVersion":"1.0","kind":"app"}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(UpdateItem.self, from: data)
        XCTAssertEqual(decoded.name, "Foo")
        XCTAssertNil(decoded.infoURL)
        XCTAssertNil(decoded.caskToken)
        XCTAssertNil(decoded.latestVersion)
    }

    func testCaskMatchTokenField() throws {
        let json = """
        {"token":"visual-studio-code","version":"1.137.0","homepage":"https://code.visualstudio.com/","artifacts":[{"app":["Visual Studio Code.app"]}]}
        """
        let match = CaskJSONParser.parse(data: Data(json.utf8), localAppName: "Visual Studio Code")
        XCTAssertEqual(match?.token, "visual-studio-code")
        XCTAssertEqual(match?.latestVersion, "1.137.0")
    }

    // MARK: - Brew list --cask --json=v2 解析

    func testBrewCaskManagedParserStandard() {
        let json = """
        {"casks":[{"token":"google-chrome","versions":["153.0.8010.37"]},{"token":"visual-studio-code","versions":["1.137.0"]}]}
        """
        let result = BrewCaskManagedParser.parse(json)
        XCTAssertEqual(result.tokens, ["google-chrome", "visual-studio-code"])
        XCTAssertTrue(result.paths.isEmpty)
    }

    func testBrewCaskManagedParserWithArtifacts() {
        let json = """
        {"casks":[{"token":"foo","artifacts":[{"app":["Foo.app"]}],"versions":["1.0"]}, {"token":"bar","artifacts":[{"app":["Bar.app","Bar Helper.app"]}]}]}
        """
        let result = BrewCaskManagedParser.parse(json)
        XCTAssertEqual(result.tokens, ["foo", "bar"])
        XCTAssertTrue(result.paths.contains("/Applications/Foo.app"))
        XCTAssertTrue(result.paths.contains("/Applications/Bar.app"))
    }

    func testBrewCaskManagedParserEmptyArray() {
        let json = "{\"casks\":[]}"
        let result = BrewCaskManagedParser.parse(json)
        XCTAssertTrue(result.tokens.isEmpty)
        XCTAssertTrue(result.paths.isEmpty)
    }

    func testBrewCaskManagedParserBadJSON() {
        let bad = "not json"
        let r1 = BrewCaskManagedParser.parse(bad)
        XCTAssertTrue(r1.tokens.isEmpty)
        XCTAssertTrue(r1.paths.isEmpty)
        let empty = ""
        let r2 = BrewCaskManagedParser.parse(empty)
        XCTAssertTrue(r2.tokens.isEmpty)
    }

    // MARK: - 路径护栏纯函数

    func testPathGuard() {
        XCTAssertTrue(CaskVersionChecker.isAllowedPath("/Applications/Foo.app"))
        XCTAssertTrue(CaskVersionChecker.isAllowedPath("/Applications"))
        let homeApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications/Foo.app")
        XCTAssertTrue(CaskVersionChecker.isAllowedPath(homeApps))
        XCTAssertTrue(CaskVersionChecker.isAllowedPath((NSHomeDirectory() as NSString).appendingPathComponent("Applications")))
        XCTAssertFalse(CaskVersionChecker.isAllowedPath("/Volumes/External/Applications/Foo.app"))
        XCTAssertFalse(CaskVersionChecker.isAllowedPath("/Volumes/Test/Foo.app"))
        XCTAssertFalse(CaskVersionChecker.isAllowedPath("/tmp/Foo.app"))
        XCTAssertFalse(CaskVersionChecker.isAllowedPath("/usr/local/Applications/Foo.app"))
    }

    // MARK: - 版本跨度校验（主版本差 ≥5 视为可疑）

    func testVersionSpanDiff0_NotSuspicious() {
        XCTAssertFalse(VersionSpanChecker.isSuspicious(current: "2.12.2", latest: "2.13.0"))
    }

    func testVersionSpanDiff1_NotSuspicious() {
        XCTAssertFalse(VersionSpanChecker.isSuspicious(current: "1.0.0", latest: "2.0.0"))
    }

    func testVersionSpanDiff4_NotSuspicious() {
        XCTAssertFalse(VersionSpanChecker.isSuspicious(current: "1.2.9", latest: "5.0.0"))
    }

    func testVersionSpanDiff5_Suspicious() {
        XCTAssertTrue(VersionSpanChecker.isSuspicious(current: "1.2.9", latest: "6.0.0"))
        XCTAssertTrue(VersionSpanChecker.isSuspicious(current: "1.2.9", latest: "12.10"))
    }

    func testVersionSpanDiff6_Suspicious() {
        XCTAssertTrue(VersionSpanChecker.isSuspicious(current: "2.0.0", latest: "8.0.0"))
    }

    func testVersionSpanWithVPrefix() {
        XCTAssertFalse(VersionSpanChecker.isSuspicious(current: "v1.2.3", latest: "v2.0.0"))
        XCTAssertTrue(VersionSpanChecker.isSuspicious(current: "v1.0.0", latest: "v6.0.0"))
    }
}
