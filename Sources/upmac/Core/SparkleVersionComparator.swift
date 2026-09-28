import Foundation

/// Sparkle 版本比较器
/// 严格复刻 Sparkle `SUStandardVersionComparator` 语义：
/// - 数字段与字母段分段比较
/// - alpha < beta < rc < 正式版
/// - 前导零自动忽略（01 == 1）与尾导零对齐（1.2.0 == 1.2）
/// 全项目唯一版本比较入口
public enum SparkleVersionComparator {

    public enum Token: Equatable {
        case number(Int)
        case string(String)
    }

    /// 比较两个版本字符串
    /// - Returns:
    ///   - `.orderedAscending` 表示 v1 < v2（v2 较新）
    ///   - `.orderedSame` 表示 v1 == v2
    ///   - `.orderedDescending` 表示 v1 > v2（v1 较新）
    public static func compare(_ v1: String, _ v2: String) -> ComparisonResult {
        let tokens1 = tokenize(v1)
        let tokens2 = tokenize(v2)

        let maxCount = max(tokens1.count, tokens2.count)

        for i in 0..<maxCount {
            if i < tokens1.count && i < tokens2.count {
                let t1 = tokens1[i]
                let t2 = tokens2[i]

                switch (t1, t2) {
                case let (.number(n1), .number(n2)):
                    if n1 < n2 { return .orderedAscending }
                    if n1 > n2 { return .orderedDescending }

                case let (.string(s1), .string(s2)):
                    let result = compareStringTokens(s1, s2)
                    if result != .orderedSame { return result }

                case (.number, .string):
                    // 正式/数字版本 > 预发布/字符串修饰符（如 1.2.1 > 1.2-beta）
                    return .orderedDescending

                case (.string, .number):
                    // 预发布/字符串修饰符 < 正式/数字版本（如 1.2-beta < 1.2.1）
                    return .orderedAscending
                }
            } else if i >= tokens1.count {
                // v1 提前结束，检查 v2 剩余 tokens
                return evaluateRemainingTokens(tokens2, from: i, isFirstStringLonger: false)
            } else {
                // v2 提前结束，检查 v1 剩余 tokens
                return evaluateRemainingTokens(tokens1, from: i, isFirstStringLonger: true)
            }
        }

        return .orderedSame
    }

    /// 便利方法：判断 v2 是否比 v1 更新
    public static func isVersion(_ v2: String, newerThan v1: String) -> Bool {
        compare(v1, v2) == .orderedAscending
    }

    // MARK: - 内部解析与比较规则

    /// 将版本字符串切分为数字和字母 Token 数组
    public static func tokenize(_ version: String) -> [Token] {
        var clean = version.trimmingCharacters(in: .whitespacesAndNewlines)

        // 剥离可能存在的 "v" 或 "V" 前缀（如 "v1.2.3" -> "1.2.3"）
        if (clean.hasPrefix("v") || clean.hasPrefix("V")), clean.count > 1 {
            let secondChar = clean[clean.index(after: clean.startIndex)]
            if secondChar.isNumber {
                clean = String(clean.dropFirst())
            }
        }

        var tokens: [Token] = []
        var currentNumber: String = ""
        var currentString: String = ""

        func flushNumber() {
            if !currentNumber.isEmpty {
                if let num = Int(currentNumber) {
                    tokens.append(.number(num))
                }
                currentNumber = ""
            }
        }

        func flushString() {
            if !currentString.isEmpty {
                tokens.append(.string(currentString))
                currentString = ""
            }
        }

        for char in clean {
            if char.isNumber {
                flushString()
                currentNumber.append(char)
            } else if char.isLetter {
                flushNumber()
                currentString.append(char)
            } else {
                // 分隔符（. - _ + ~ 等）
                flushNumber()
                flushString()
            }
        }

        flushNumber()
        flushString()

        return tokens
    }

    /// 当一个版本的所有 Token 已经比对完毕，对另一个版本剩余的 Token 进行评估
    /// 核心规则：
    /// 1. 剩余部分全为数字 0 时视为等价（如 1.2.0 == 1.2）
    /// 2. 第一个非 0 Token 如果是预发布字符串（如 b, beta, rc），则该版本是预发布版，弱于基准版（1.2b1 < 1.2）
    /// 3. 第一个非 0 Token 如果是大于 0 的数字，则该版本较新（1.2.1 > 1.2）
    private static func evaluateRemainingTokens(
        _ tokens: [Token],
        from startIndex: Int,
        isFirstStringLonger: Bool
    ) -> ComparisonResult {
        var firstSignificantToken: Token? = nil

        for j in startIndex..<tokens.count {
            let t = tokens[j]
            if case let .number(n) = t, n == 0 {
                continue
            }
            firstSignificantToken = t
            break
        }

        guard let token = firstSignificantToken else {
            // 剩余全是 0，两版本语义相同（如 1.2.0 == 1.2）
            return .orderedSame
        }

        switch token {
        case .string:
            // 包含预发布字符串（如 beta, rc, b），比已发布的基准版更小
            // 1.2b1 比 1.2 更小
            return isFirstStringLonger ? .orderedAscending : .orderedDescending

        case let .number(n):
            if n > 0 {
                // 包含非零数字，比基准版更大
                // 1.2.1 比 1.2 更大
                return isFirstStringLonger ? .orderedDescending : .orderedAscending
            }
            return .orderedSame
        }
    }

    /// 比较预发布字母段（如 alpha < beta < rc）
    private static func compareStringTokens(_ s1: String, _ s2: String) -> ComparisonResult {
        let r1 = prereleaseRank(for: s1)
        let r2 = prereleaseRank(for: s2)

        if let rank1 = r1, let rank2 = r2 {
            if rank1 < rank2 { return .orderedAscending }
            if rank1 > rank2 { return .orderedDescending }
            return .orderedSame
        }

        if r1 != nil && r2 == nil {
            // 已知预发布版本 < 未知修饰符
            return .orderedAscending
        }

        if r1 == nil && r2 != nil {
            return .orderedDescending
        }

        return s1.caseInsensitiveCompare(s2)
    }

    /// 预发布关键字层级映射
    private static func prereleaseRank(for string: String) -> Int? {
        let lower = string.lowercased()
        switch lower {
        case "d", "dev", "development":
            return 10
        case "a", "alpha":
            return 20
        case "b", "beta":
            return 30
        case "rc", "cr", "preview", "pre":
            return 40
        default:
            return nil
        }
    }
}
