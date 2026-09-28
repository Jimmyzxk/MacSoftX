import Foundation

/// Appcast 条目模型
public struct AppcastItem: Sendable, Equatable {
    /// 内部版本号（sparkle:version 或 build number）
    public let version: String
    /// 短版本号（sparkle:shortVersionString 或营销版本号）
    public let shortVersionString: String?
    /// 下载链接
    public let enclosureURL: String?

    public init(version: String, shortVersionString: String? = nil, enclosureURL: String? = nil) {
        self.version = version
        self.shortVersionString = shortVersionString
        self.enclosureURL = enclosureURL
    }

    /// 用户展示或版本比对优先使用的版本号
    public var displayVersion: String {
        if let short = shortVersionString, !short.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return short.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return version.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 纯函数 Appcast XML 解析器
public final class AppcastParser: NSObject, XMLParserDelegate, @unchecked Sendable {

    private var items: [AppcastItem] = []
    private var currentElement: String = ""
    private var currentText: String = ""

    private var inItem: Bool = false
    private var currentItemVersion: String? = nil
    private var currentItemShortVersion: String? = nil
    private var currentItemEnclosureURL: String? = nil

    private var hasError: Bool = false

    /// 解析 XML Data 为 AppcastItem 列表（纯函数，容错处理，畸形 XML 返回空）
    public static func parse(_ xmlData: Data) -> [AppcastItem] {
        let parser = AppcastParser()
        return parser.parseData(xmlData)
    }

    /// 从 Appcast 列表中挑出版本最高者（SUStandardVersionComparator 语义）
    public static func bestItem(from items: [AppcastItem]) -> AppcastItem? {
        guard !items.isEmpty else { return nil }
        return items.max { a, b in
            let cmp = SparkleVersionComparator.compare(a.displayVersion, b.displayVersion)
            if cmp == .orderedSame {
                return SparkleVersionComparator.compare(a.version, b.version) == .orderedAscending
            }
            return cmp == .orderedAscending
        }
    }

    /// 快捷方法：从 XML Data 中直接解析出最高版本的条目
    public static func parseBestItem(from xmlData: Data) -> AppcastItem? {
        let items = parse(xmlData)
        return bestItem(from: items)
    }

    private func parseData(_ data: Data) -> [AppcastItem] {
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = self
        xmlParser.shouldProcessNamespaces = false
        xmlParser.shouldReportNamespacePrefixes = false
        xmlParser.shouldResolveExternalEntities = false

        let success = xmlParser.parse()
        if !success || hasError {
            return []
        }
        return items
    }

    // MARK: - XMLParserDelegate

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""

        if elementName.lowercased() == "item" {
            inItem = true
            currentItemVersion = nil
            currentItemShortVersion = nil
            currentItemEnclosureURL = nil
        } else if inItem && elementName.lowercased() == "enclosure" {
            // 提取 enclosure 标签上的属性
            for (key, val) in attributeDict {
                let lowerKey = key.lowercased()
                if lowerKey == "sparkle:version" || lowerKey == "version" {
                    if currentItemVersion == nil {
                        currentItemVersion = val
                    }
                } else if lowerKey == "sparkle:shortversionstring" || lowerKey == "shortversionstring" {
                    if currentItemShortVersion == nil {
                        currentItemShortVersion = val
                    }
                } else if lowerKey == "url" {
                    if currentItemEnclosureURL == nil {
                        currentItemEnclosureURL = val
                    }
                }
            }
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText.append(string)
    }

    public func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inItem {
            let lowerElement = elementName.lowercased()
            if lowerElement == "sparkle:version" || lowerElement == "version" {
                if currentItemVersion == nil, !trimmedText.isEmpty {
                    currentItemVersion = trimmedText
                }
            } else if lowerElement == "sparkle:shortversionstring" || lowerElement == "shortversionstring" {
                if currentItemShortVersion == nil, !trimmedText.isEmpty {
                    currentItemShortVersion = trimmedText
                }
            }

            if lowerElement == "item" {
                if let version = currentItemVersion ?? currentItemShortVersion, !version.isEmpty {
                    let item = AppcastItem(
                        version: version,
                        shortVersionString: currentItemShortVersion,
                        enclosureURL: currentItemEnclosureURL
                    )
                    items.append(item)
                }
                inItem = false
            }
        }

        currentElement = ""
        currentText = ""
    }

    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        hasError = true
    }
}

/// Appcast 抓取服务
public enum AppcastFetcher {

    /// 抓取指定 feed URL（5秒超时）
    ///
    /// 安全约束：`SUFeedURL` 来自第三方 app 的 Info.plist，属不可信输入。
    /// 生产构建仅接受 HTTPS；`file://` 本地夹具仅在 DEBUG 下保留（供单测使用），
    /// 避免恶意 app 借 `SUFeedURL=file:///...` 诱导本应用读取本地文件。
    public static func fetchLatestItem(from feedURLString: String, timeout: TimeInterval = 5.0) async throws -> AppcastItem? {
        guard let url = URL(string: feedURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }

        let data: Data
        #if DEBUG
        if url.isFileURL || url.scheme == "file" {
            // 本地夹具直接走文件流读取，避免 URLSession 不支持 file:// scheme 报错
            data = try Data(contentsOf: url)
            return AppcastParser.parseBestItem(from: data)
        }
        #endif
        guard url.scheme?.lowercased() == "https" else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.setValue("UpMac/1.0", forHTTPHeaderField: "User-Agent")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        data = responseData

        return AppcastParser.parseBestItem(from: data)
    }
}
