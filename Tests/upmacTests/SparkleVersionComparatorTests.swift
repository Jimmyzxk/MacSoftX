import XCTest
@testable import upmac

final class SparkleVersionComparatorTests: XCTestCase {

    func testNumericIncrement() {
        XCTAssertEqual(SparkleVersionComparator.compare("1.2.9", "1.2.10"), .orderedAscending)
        XCTAssertEqual(SparkleVersionComparator.compare("1.2.10", "1.2.9"), .orderedDescending)
    }

    func testPrereleaseVsRelease() {
        // 预发布版本应小于正式发布版本
        XCTAssertEqual(SparkleVersionComparator.compare("1.2b1", "1.2"), .orderedAscending)
        XCTAssertEqual(SparkleVersionComparator.compare("1.2", "1.2b1"), .orderedDescending)
        XCTAssertEqual(SparkleVersionComparator.compare("1.0-alpha", "1.0"), .orderedAscending)
    }

    func testTrailingZeroEquivalence() {
        // 尾随 0 视作相同版本
        XCTAssertEqual(SparkleVersionComparator.compare("1.2.0", "1.2"), .orderedSame)
        XCTAssertEqual(SparkleVersionComparator.compare("1.2", "1.2.0.0"), .orderedSame)
    }

    func testLeadingZeroEquivalence() {
        // 前导 0 视作同一数值
        XCTAssertEqual(SparkleVersionComparator.compare("01.2", "1.2"), .orderedSame)
        XCTAssertEqual(SparkleVersionComparator.compare("1.02", "1.2"), .orderedSame)
    }

    func testPrereleaseOrdering() {
        // dev < alpha < beta < rc < release
        XCTAssertEqual(SparkleVersionComparator.compare("1.0-dev", "1.0-alpha"), .orderedAscending)
        XCTAssertEqual(SparkleVersionComparator.compare("1.0-alpha", "1.0-beta"), .orderedAscending)
        XCTAssertEqual(SparkleVersionComparator.compare("1.0-beta", "1.0-rc"), .orderedAscending)
        XCTAssertEqual(SparkleVersionComparator.compare("1.0-rc", "1.0"), .orderedAscending)
    }

    func testBetaNumbering() {
        // 自然数比较：b1 < b2 < b10
        XCTAssertEqual(SparkleVersionComparator.compare("1.0b1", "1.0b2"), .orderedAscending)
        XCTAssertEqual(SparkleVersionComparator.compare("1.0b2", "1.0b10"), .orderedAscending)
    }

    func testMajorVersionDominance() {
        XCTAssertEqual(SparkleVersionComparator.compare("2.0.0", "1.9.9"), .orderedDescending)
        XCTAssertEqual(SparkleVersionComparator.compare("1.9.9", "2.0.0"), .orderedAscending)
    }

    func testShortAlphaBeta() {
        XCTAssertEqual(SparkleVersionComparator.compare("1.2a1", "1.2b1"), .orderedAscending)
    }

    func testPrefixVStripping() {
        // 支持剥离前缀 v
        XCTAssertEqual(SparkleVersionComparator.compare("v1.2.3", "1.2.3"), .orderedSame)
        XCTAssertEqual(SparkleVersionComparator.compare("V2.0", "2.0"), .orderedSame)
    }

    func testMixedAlphanumeric() {
        // 正式数字段大于同层级预发布字符串
        XCTAssertEqual(SparkleVersionComparator.compare("1.2.1", "1.2-beta"), .orderedDescending)
    }

    func testIsVersionNewerThanHelper() {
        XCTAssertTrue(SparkleVersionComparator.isVersion("2.1.0", newerThan: "2.0.9"))
        XCTAssertFalse(SparkleVersionComparator.isVersion("1.0.0", newerThan: "1.0.0"))
        XCTAssertFalse(SparkleVersionComparator.isVersion("1.0.0", newerThan: "1.0.1"))
    }
}
