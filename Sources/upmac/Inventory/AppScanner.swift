import Foundation

public struct ScannedApp: Sendable, Equatable {
    public let name: String
    public let bundleId: String?
    public let version: String
    public let path: String
    public let isAppStoreReceiptPresent: Bool
    public let feedURL: String?

    public init(
        name: String,
        bundleId: String?,
        version: String,
        path: String,
        isAppStoreReceiptPresent: Bool,
        feedURL: String? = nil
    ) {
        self.name = name
        self.bundleId = bundleId
        self.version = version
        self.path = path
        self.isAppStoreReceiptPresent = isAppStoreReceiptPresent
        self.feedURL = feedURL
    }
}

public enum AppScanner {
    public static var searchDirectories: [String] {
        AppScanService.resolveSearchDirectories()
    }

    public static func scanInstalledApplications(directories: [String]? = nil) -> [ScannedApp] {
        AppScanService.scanInstalledApplications(directories: directories)
    }

    public static func inspectAppBundle(at path: String) -> ScannedApp? {
        AppScanService.inspectAppBundle(at: path)
    }
}
