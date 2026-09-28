import XCTest
@testable import upmac

/// ProviderError 的用户可见文案必须为中文，且不泄漏技术黑话（docs/08 §6.6 状态诚实性）
final class ProviderErrorLocalizationTests: XCTestCase {

    func testErrorDescriptionsAreUserFacingChinese() {
        let cases: [ProviderError] = [
            .managerMissing("/opt/homebrew/bin/brew"),
            .sudoRequired,
            .loginRequired,
            .timedOut,
            .parsingFailed("The data couldn’t be read because it isn’t in the correct format.")
        ]

        for error in cases {
            let userFacing = error.errorDescription ?? ""
            XCTAssertFalse(userFacing.isEmpty, "\(error) 缺少用户可见文案")

            // 必须包含中文字符
            let hasChinese = userFacing.contains { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }
            XCTAssertTrue(hasChinese, "\(error) 的用户文案应为中文，实际: \(userFacing)")

            // 不得直接倾泻原始技术报错
            for leak in ["Manager executable", "Sudo privilege", "Login credentials", "Operation timed out", "Parsing failed", "NSError", "The data couldn’t"] {
                XCTAssertFalse(userFacing.contains(leak), "\(error) 的用户文案泄漏技术细节 '\(leak)': \(userFacing)")
            }
        }
    }

    func testDebugDescriptionRetainsTechnicalDetail() {
        // 技术细节必须保留在 debugDescription 里，供日志排查使用
        XCTAssertTrue(ProviderError.managerMissing("/opt/homebrew/bin/brew").debugDescription.contains("/opt/homebrew/bin/brew"))
        XCTAssertTrue(ProviderError.parsingFailed("boom").debugDescription.contains("boom"))
    }

    func testManagerMissingShowsToolNameNotFullPath() {
        let message = ProviderError.managerMissing("/opt/homebrew/bin/brew").errorDescription ?? ""
        XCTAssertTrue(message.contains("brew"), "应展示工具名 brew，实际: \(message)")
        XCTAssertFalse(message.contains("/opt/homebrew/bin/brew"), "不应展示完整路径，实际: \(message)")
    }
}
