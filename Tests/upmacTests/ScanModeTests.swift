import XCTest
@testable import upmac

final class ScanModeTests: XCTestCase {

    private final class MockUnavailableProvider: UpdateProvider, @unchecked Sendable {
        let id: String = "unavailable"
        let displayName: String = "Unavailable Tool"

        func isAvailable() async -> Bool { false }
        func fetchOutdated() async throws -> [UpdateItem] { [] }
        func update(_ item: UpdateItem) async throws -> UpdateResult {
            UpdateResult(ok: false, message: "not available")
        }
    }

    private final class MockFailingProvider: UpdateProvider, @unchecked Sendable {
        let id: String = "failing"
        let displayName: String = "Failing Tool"

        func isAvailable() async -> Bool { true }
        func fetchOutdated() async throws -> [UpdateItem] {
            throw ProviderError.timedOut
        }
        func update(_ item: UpdateItem) async throws -> UpdateResult {
            throw ProviderError.timedOut
        }
    }

    func testScanModeAggregationAndErrorHandling() async {
        let providers: [any UpdateProvider] = [
            MockBrewProvider(),
            MockUnavailableProvider(),
            MockFailingProvider()
        ]

        let report = await ScanMode.execute(providers: providers)

        // MockBrewProvider 提供 4 项，其余 0 项
        XCTAssertEqual(report.totalCount, 4)
        XCTAssertEqual(report.providers.count, 3)

        // 按 providerId 排序: "brew", "failing", "unavailable"
        let brewRep = report.providers.first { $0.providerId == "brew" }
        XCTAssertNotNil(brewRep)
        XCTAssertTrue(brewRep?.isAvailable ?? false)
        XCTAssertEqual(brewRep?.count, 4)
        XCTAssertNil(brewRep?.error)

        let failingRep = report.providers.first { $0.providerId == "failing" }
        XCTAssertNotNil(failingRep)
        XCTAssertTrue(failingRep?.isAvailable ?? false)
        XCTAssertEqual(failingRep?.count, 0)
        XCTAssertEqual(failingRep?.error, ProviderError.timedOut.localizedDescription)

        let unavailRep = report.providers.first { $0.providerId == "unavailable" }
        XCTAssertNotNil(unavailRep)
        XCTAssertFalse(unavailRep?.isAvailable ?? true)
        XCTAssertEqual(unavailRep?.count, 0)
        XCTAssertNil(unavailRep?.error)
    }
}
